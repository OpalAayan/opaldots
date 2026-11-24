# Quickshell Widget Management System

A dynamic widget manager and interactive on-screen editor for [Quickshell](https://quickshell.outfoxxed.me/) desktop widgets running on [Hyprland](https://hyprland.org/).

---

## 1. Overview

The **Quickshell Widget Management System** bridges the gap between lightweight Wayland layer-shell background widgets and interactive window configuration. 

In Wayland desktop environments, desktop widgets traditionally run on the layer-shell protocol (`zwlr_layer_shell_v1`). While layer-shell surfaces provide flicker-free desktop integration beneath application windows, they are inherently non-interactive regarding window management: they cannot be repositioned or resized interactively with the compositor's pointer bindings.

This management system solves this limitation through a dual-mode workflow:
1. **Interactive Edit Mode**: Launches the widget as a standard floating Wayland window (`Window`), enabling intuitive repositioning and resizing via Hyprland's native mouse gestures (`SUPER + Left-Click` to drag, `SUPER + Right-Click` to resize).
2. **Persistent Layer Mode**: Saves the window dimensions and coordinates into a JSON configuration file, recalculates compositor margins accounting for monitor offsets and reserved panels (such as Waybar), and respawns the widget seamlessly on the layer-shell (`WlrLayer.Bottom`).

All controls, positioning, and font scaling are orchestrated through a unified [Fuzzel](https://codeberg.org/dnkl/fuzzel) keyboard-driven menu system bound to `SUPER + ALT + R`.

---

## 2. Architecture

The system operates across three decoupled layers: **QML Presentation**, **Hyprland Compositor IPC**, and **Shell Automation / State Machine**.

```
                           ┌────────────────────────┐
                           │   Fuzzel Menu UI       │
                           │  (widget-manager.sh)   │
                           └───────────┬────────────┘
                                       │ (SUPER+ALT+R)
                   ┌───────────────────┴───────────────────┐
                   ▼                                       ▼
        [Edit Mode Request]                     [Save / Normal Mode]
                   │                                       │
                   ▼                                       ▼
        ┌─────────────────────┐                 ┌─────────────────────┐
        │   start-edit.sh     │                 │    save-edit.sh     │
        └──────────┬──────────┘                 └──────────┬──────────┘
                   │                                       │
        Spawns floating Window                  Queries `hyprctl clients -j`
        (Title: WidgetEdit_*)                   Calculates layer-relative coords
                   │                                       │
                   ▼                                       ▼
    ┌──────────────────────────────┐            ┌──────────────────────────────┐
    │          edit.qml            │            │        geometry.json         │
    │  • Frameless QtQuick Window  │            │  • Inode-preserved JSON      │
    │  • Mauve border indicator    │            │  • Single Source of Truth    │
    │  • Native SUPER+mouse move   │            └──────────────┬───────────────┘
    └──────────────────────────────┘                           │
                                                               ▼
                                                ┌──────────────────────────────┐
                                                │       start-layer.sh         │
                                                └──────────────┬───────────────┘
                                                               │
                                                               ▼
                                                ┌──────────────────────────────┐
                                                │          shell.qml           │
                                                │  • WlrLayer.Bottom           │
                                                │  • PanelWindow (margins)     │
                                                │  • exclusiveZone: 0          │
                                                └──────────────────────────────┘
```

### Key Architectural Pillars

- **Dual Runtime Modes**:
  - **Layer Mode (`shell.qml`)**: Instantiates a Quickshell `PanelWindow` anchored at `top` and `left`, residing on `WlrLayer.Bottom` with `exclusiveZone: 0`. It acts as an unclickable, performant wallpaper overlay that never steals focus or interferes with tiled windows.
  - **Edit Mode (`edit.qml`)**: Instantiates a floating `Window` with `Qt.FramelessWindowHint` matching Hyprland window rule `^(WidgetEdit_.*)$`. It renders with an active Mauve border and translucent backdrop, allowing the user to reposition and resize the widget directly on the canvas.
- **Native Hyprland Gestures**: Moving and resizing do not require custom handle logic in QML. Instead, Hyprland's native bindings handle all geometry mutations:
  - `SUPER + Left-Click Drag`: Move window
  - `SUPER + Right-Click Drag`: Resize window
- **State Persistence Contract (`geometry.json`)**: Geometry (`x`, `y`, `width`, `height`, `scale`) is stored in a clean JSON file per widget. Scripts and QML communicate asynchronously through this file.
- **Fuzzel Menu UI (`widget-manager.sh`)**: A centralized state machine bound to `SUPER + ALT + R`. It inspects whether an edit session is currently open (via `hyprctl clients -j`) and presents context-sensitive menus (Edit/Save/Discard/Scale vs Start/Edit/Reload).

---

## 3. Coordinate Space

Hyprland IPC and Wayland Layer-Shell use two fundamentally different coordinate reference frames. Bridging them accurately requires coordinate transformation.

### Reference Frame Comparison

```
+=============================================================================================+
| Monitor Global Coordinate Space (Absolute Coordinates from `hyprctl`)                       |
| Origin (mon_x, mon_y)                                                                       |
| +-----------------------------------------------------------------------------------------+ |
| | Waybar Exclusive Zone (Reserved Top: RESERVED_TOP px)                                   | |
| +=========================================================================================+ |
| | Post-Reserved Area (Layer-Shell Origin: x=0, y=0)                                       | |
| |                                                                                         | |
| |           margin_x (Layer-relative X)                                                   | |
| |         |<---------------------------->|                                                | |
| |      -  +------------------------------+                                                | |
| |      ^  |                              |                                                | |
| |      |  | Widget Window                |                                                | |
| |  margin_y  (W: width, H: height)       |                                                | |
| |      |  |                              |                                                | |
| |      v  +------------------------------+                                                | |
| |      -                                                                                  | |
| |                                                                                         | |
| +-----------------------------------------------------------------------------------------+ |
+=============================================================================================+
```

### Definitions & Variables

| Variable | Source | Description |
| :--- | :--- | :--- |
| `abs_x`, `abs_y` | `hyprctl clients -j` (`.at[0]`, `.at[1]`) | Absolute compositor pixel coordinates from the virtual desktop origin `(0, 0)`. |
| `mon_x`, `mon_y` | `hyprctl monitors -j` (`.x`, `.y`) | Top-left offset of the monitor containing the widget. |
| `reserved_left`, `reserved_top` | `hyprctl monitors -j` (`.reserved[0]`, `.reserved[1]`) | Exclusive zones reserved by status bars (e.g. Waybar exclusive zone at top). |
| `margin_x`, `margin_y` | `geometry.json` / QML `margins` | Layer-shell margins anchored to `top: true, left: true`. These are relative to the **post-reserved area**. |

### Conversion Formulas

#### 1. Absolute Window Coordinates &rarr; Layer-Shell Margins (`save-edit.sh`)
When saving from Edit Mode, the absolute coordinates reported by Hyprland must be converted to margins relative to the post-reserved area:
```
margin_x = abs_x - mon_x - reserved_left
margin_y = abs_y - mon_y - reserved_top
```
*(Clamped to `margin >= 0` to prevent offscreen placement)*

#### 2. Layer-Shell Margins &rarr; Absolute Window Coordinates (`start-edit.sh`)
When launching Edit Mode, saved layer margins must be translated back to absolute monitor coordinates so Hyprland spawns the floating window exactly where the layer widget was sitting:
```
abs_x = margin_x + mon_x + reserved_left
abs_y = margin_y + mon_y + reserved_top
```

---

## 4. geometry.json Schema

Each widget retains its persistent configuration inside its local `geometry.json` file.

### Schema Definition

```json
{
  "x": 295,
  "y": 101,
  "width": 799,
  "height": 248,
  "scale": 1.30
}
```

### Field Specification

| Field | Type | Unit | Range / Constraints | Description |
| :--- | :--- | :--- | :--- | :--- |
| `x` | `integer` | Pixels | `≥ 0` | Left margin relative to the monitor's post-reserved display area. |
| `y` | `integer` | Pixels | `≥ 0` | Top margin relative to the monitor's post-reserved display area. |
| `width` | `integer` | Pixels | `> 0` | Rendered width of the widget container. |
| `height` | `integer` | Pixels | `> 0` | Rendered height of the widget container. |
| `scale` | `float` | Multiplier | `0.40 – 3.00` | Proportional font and spacing scale factor (`1.0` = 100% baseline). |

> [!IMPORTANT]
> **Inode Preservation via `cat` Redirection**:
> Quickshell watches files using `FileView { watchChanges: true }`, which relies on Linux `inotify` file descriptors. If a script overwrites `geometry.json` using atomic move (`mv tmp.json geometry.json`), the file's inode changes, breaking the active `inotify` watch.
> 
> All write operations must write to a temporary file and stream it into the destination:
> ```bash
> cat "$tmp_file" > "$GEO_FILE"
> ```
> This pattern preserves the existing inode and triggers `FileView.onFileChanged` without restarting Quickshell.

---

## 5. File Structure

```
~/.config/
├── fuzzel/
│   └── scripts/
│       └── widget-manager.sh      # Central Fuzzel menu state machine (SUPER+ALT+R)
│
├── hypr/
│   └── lua/rules/
│       └── windowrules.lua        # Hyprland window rules matching ^(WidgetEdit_.*)$
│
└── quickshell/
    └── widget/
        ├── README.md              # System documentation & developer guide
        ├── lib/
        │   └── widget-helpers.sh  # Shared POSIX/Bash automation library
        └── clock/
            ├── ClockContent.qml   # Reusable typography, clock timer & shadows
            ├── shell.qml          # Layer-Shell entry point (WlrLayer.Bottom)
            ├── edit.qml           # Floating Edit-Mode entry point (WidgetEdit_Clock)
            ├── geometry.json      # Persisted coordinates, dimensions & scale
            └── scripts/
                ├── start-layer.sh   # Spawns background layer-shell instance
                ├── start-edit.sh    # Pre-positions and spawns floating editor window
                ├── save-edit.sh     # Captures live editor geometry & restarts layer
                └── adjust-scale.sh  # Increments/decrements font scale multiplier
```

### Component Roles

| File | Type | Purpose |
| :--- | :--- | :--- |
| [`shell.qml`](file:///home/yogurt/.config/quickshell/widget/clock/shell.qml) | QML | Runs the widget in `WlrLayer.Bottom` mode with zero exclusive zone. Listens to `geometry.json` via `FileView`. |
| [`edit.qml`](file:///home/yogurt/.config/quickshell/widget/clock/edit.qml) | QML | Spawns a frameless floating window titled `WidgetEdit_Clock` with a Catppuccin Mauve bounding box. |
| [`ClockContent.qml`](file:///home/yogurt/.config/quickshell/widget/clock/ClockContent.qml) | QML | Shared visual presentation component. Scales fonts and spacing according to `fontScale`. |
| [`geometry.json`](file:///home/yogurt/.config/quickshell/widget/clock/geometry.json) | JSON | Geometry configuration state file containing coordinates, bounds, and scale multiplier. |
| [`start-layer.sh`](file:///home/yogurt/.config/quickshell/widget/clock/scripts/start-layer.sh) | Shell | Terminates existing widget processes and launches `shell.qml` detached with `qs -p`. |
| [`start-edit.sh`](file:///home/yogurt/.config/quickshell/widget/clock/scripts/start-edit.sh) | Shell | Calculates screen position, registers Hyprland window rules, and launches `edit.qml`. |
| [`save-edit.sh`](file:///home/yogurt/.config/quickshell/widget/clock/scripts/save-edit.sh) | Shell | Inspects Hyprland IPC for the editor window, computes post-reserved margins, writes `geometry.json`, and launches layer mode. |
| [`adjust-scale.sh`](file:///home/yogurt/.config/quickshell/widget/clock/scripts/adjust-scale.sh) | Shell | Adjusts font scale in `geometry.json` (supports `+0.10`, `-0.10`, `+0.05`, `-0.05`, `reset`, or `set <v>`). |
| [`widget-helpers.sh`](file:///home/yogurt/.config/quickshell/widget/lib/widget-helpers.sh) | Shell | Shared library containing dependency checks, process lifecycle tools, coordinate math, and scale calculators. |
| [`widget-manager.sh`](file:///home/yogurt/.config/fuzzel/scripts/widget-manager.sh) | Shell | Fuzzel interactive menu state machine. Displays actions based on whether edit mode is currently active. |

---

## 6. Adding a New Widget

Adding a new desktop widget (for example, `weather` or `system-monitor`) follows a standardized, modular pattern.

### Step 1: Create Directory Hierarchy
Create the widget folder and its internal scripts directory:
```bash
mkdir -p ~/.config/quickshell/widget/mywidget/scripts
```

### Step 2: Implement `<Name>Content.qml`
Create `~/.config/quickshell/widget/mywidget/MyWidgetContent.qml`. Expose a `fontScale` property and use it to scale all font sizes, margins, and layout dimensions:
```qml
import QtQuick
import Quickshell
import QtQuick.Layouts

Item {
    id: root
    anchors.fill: parent

    // Required: font scaling property
    property real fontScale: 1.0

    ColumnLayout {
        anchors.centerIn: parent

        Text {
            text: "Hello Quickshell"
            color: "#ffffff"
            font.pixelSize: Math.max(12, Math.round(32 * root.fontScale))
        }
    }
}
```

### Step 3: Create `shell.qml`
Copy `shell.qml` from the `clock` widget and replace `ClockContent` with your custom content component:
```qml
import QtQuick
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

PanelWindow {
    id: root

    WlrLayershell.layer: WlrLayer.Bottom
    exclusiveZone: 0

    property int geoX: 100
    property int geoY: 100
    property int geoW: 400
    property int geoH: 200
    property real geoScale: 1.0

    anchors {
        top: true
        left: true
    }

    margins {
        top: root.geoY
        left: root.geoX
    }

    implicitWidth: root.geoW
    implicitHeight: root.geoH
    color: "transparent"

    FileView {
        id: geometryFile
        path: Qt.resolvedUrl("geometry.json").toString().replace(/^file:\/\//, "")
        blockLoading: true
        watchChanges: true

        onFileChanged: reload()

        function reload() {
            try {
                var content = geometryFile.text(); // Quickshell 0.3.1: method call!
                if (content && content.length > 0) {
                    var geo = JSON.parse(content);
                    if (geo.x !== undefined) root.geoX = geo.x;
                    if (geo.y !== undefined) root.geoY = geo.y;
                    if (geo.width !== undefined) root.geoW = geo.width;
                    if (geo.height !== undefined) root.geoH = geo.height;
                    if (geo.scale !== undefined) root.geoScale = geo.scale;
                }
            } catch (e) {
                console.warn("mywidget/shell.qml: failed to parse geometry.json:", e);
            }
        }

        Component.onCompleted: reload()
    }

    MyWidgetContent {
        anchors.fill: parent
        fontScale: root.geoScale
    }
}
```

### Step 4: Create `edit.qml`
Copy `edit.qml`, setting `title` to `WidgetEdit_MyWidget` and instantiating your content component:
```qml
import QtQuick
import QtQuick.Window
import Quickshell.Io

Window {
    id: editWindow

    title: "WidgetEdit_MyWidget"
    visible: true
    width: 400
    height: 200
    color: "transparent"
    flags: Qt.FramelessWindowHint

    property real widgetScale: 1.0

    FileView {
        id: geometryFile
        path: Qt.resolvedUrl("geometry.json").toString().replace(/^file:\/\//, "")
        blockLoading: true
        watchChanges: true

        onFileChanged: reload()

        function reload() {
            try {
                var content = geometryFile.text();
                if (content && content.length > 0) {
                    var geo = JSON.parse(content);
                    if (geo.width !== undefined) editWindow.width = geo.width;
                    if (geo.height !== undefined) editWindow.height = geo.height;
                    if (geo.scale !== undefined) editWindow.widgetScale = geo.scale;
                }
            } catch (e) {
                console.warn("mywidget/edit.qml: failed to parse geometry.json:", e);
            }
        }

        Component.onCompleted: reload()
    }

    Rectangle {
        anchors.fill: parent
        color: "#20cba6f7"
        border.color: "#cba6f7"
        border.width: 2
        radius: 6

        MyWidgetContent {
            anchors.fill: parent
            fontScale: editWindow.widgetScale
        }
    }
}
```

### Step 5: Initialize `geometry.json`
Create `~/.config/quickshell/widget/mywidget/geometry.json`:
```json
{
  "x": 100,
  "y": 100,
  "width": 400,
  "height": 200,
  "scale": 1.0
}
```

### Step 6: Populate Helper Scripts
Copy `start-layer.sh`, `start-edit.sh`, `save-edit.sh`, and `adjust-scale.sh` from `clock/scripts/` into `mywidget/scripts/`.
In each script, verify the paths and titles:
- Update `WIDGET_DIR="$HOME/.config/quickshell/widget/mywidget"`
- Update the window title string to `"WidgetEdit_MyWidget"`
- Make scripts executable: `chmod +x mywidget/scripts/*.sh`

### Step 7: Hyprland Window Rules
The Hyprland configuration in [`hypr/lua/rules/windowrules.lua`](file:///home/yogurt/.config/hypr/lua/rules/windowrules.lua) uses the wildcard regex pattern `^(WidgetEdit_.*)$`. Any window title prefixed with `WidgetEdit_` automatically floats, pins, and gains the editor border without requiring manual rule modifications.

### Step 8: Register in `widget-manager.sh`
Add your widget option to the Fuzzel menu list in [`~/.config/fuzzel/scripts/widget-manager.sh`](file:///home/yogurt/.config/fuzzel/scripts/widget-manager.sh):
```bash
widget=$(
    fuzzel_menu "󰍜  Widgets: " \
        "󰥔  Clock" \
        "󰢮  MyWidget"
) || exit 0
```
Add handling for your widget's actions in the corresponding `case` block.

---

## 7. Troubleshooting

### 1. Widget Does Not Appear on Screen
- Run the widget directly from the terminal to inspect Quickshell error output:
  ```bash
  qs -p ~/.config/quickshell/widget/clock/shell.qml
  ```
- Verify whether the process is actively running:
  ```bash
  pgrep -af "quickshell.*clock"
  ```
- Check `geometry.json` values; if `x` or `y` coordinates exceed screen resolution, the widget may be positioned offscreen.

### 2. Widget Position Drifts After Saving Edit
- Ensure that the top reserved area (Waybar exclusive zone) is being accounted for:
  ```bash
  hyprctl monitors -j | jq '.[].reserved'
  ```
- The formula must subtract `reserved[1]` when saving to `geometry.json`, and add `reserved[1]` when launching `edit.qml`.
- Make sure monitor coordinates `mon_x` and `mon_y` are included if using a secondary display.

### 3. FileView Fails to Reload Automatically
- Quickshell 0.3.1 `FileView` requires Linux `inotify` events. If files are edited using `mv` or text editors that perform atomic rename replaces, the file inode changes and breaks the watch descriptor.
- Always use inode-preserving writes:
  ```bash
  cat "$tmp_file" > "$GEO_FILE"
  ```
- **Quickshell 0.3.1 API Gotcha**: Ensure your QML uses `geometryFile.text()` with parentheses as a method call, not `geometryFile.text` as a property.

### 4. Edit Window Does Not Float or Has Standard Window Titlebar
- Verify that `title: "WidgetEdit_<Name>"` matches the regular expression in `windowrules.lua`:
  ```lua
  hl.window_rule({
      match = { title = "^(WidgetEdit_.*)$" },
      float = true,
      pin = true,
      border_color = "rgba(cba6f7ff) rgba(f38ba8ff)",
  })
  ```
- Reload Hyprland window rules or test with:
  ```bash
  hyprctl clients -j | jq '.[] | select(.title | startswith("WidgetEdit"))'
  ```

### 5. `geometry.json` Becomes Corrupt or Invalid
- If `geometry.json` is corrupted or empty, remove the file:
  ```bash
  rm ~/.config/quickshell/widget/clock/geometry.json
  ```
- Running `./start-layer.sh` or any helper script will automatically detect the missing file and regenerate it with safe default values (`x=100, y=100, width=800, height=180, scale=1.0`).
- Previous valid configurations are backed up automatically to `geometry.json.bak` on each write.

---

## 8. Dependencies

The system relies on lightweight system utilities available across modern Wayland / Hyprland Linux distributions:

| Dependency | Purpose | Package Name |
| :--- | :--- | :--- |
| `hyprctl` | Hyprland compositor IPC (queries monitors, client geometry, dispatches window moves) | `hyprland` |
| `qs` | Quickshell reactive QtQuick desktop shell runtime | `quickshell` |
| `fuzzel` | Fast, lightweight Wayland dmenu application launcher for interactive dialogs | `fuzzel` |
| `jq` | Command-line JSON parser for extracting coordinates and updating configurations | `jq` |
| `awk` | High-precision floating-point arithmetic for scale calculations | `gawk` or `mawk` |
| `notify-send` | Desktop notifications confirming scale changes and edit saves | `libnotify` |

All dependencies are verified automatically on launch by `wm_require_deps` in `lib/widget-helpers.sh`.

---

## 9. Shared Library Reference (`lib/widget-helpers.sh`)

The shared library [`lib/widget-helpers.sh`](file:///home/yogurt/.config/quickshell/widget/lib/widget-helpers.sh) encapsulates all core operations. Source this file at the start of any widget script:

```bash
WIDGET_LIB="$(dirname "$(dirname "$(realpath "$0")")")/../lib"
source "$WIDGET_LIB/widget-helpers.sh"
```

### Exported Functions

#### `wm_require_deps`
- **Description**: Verifies that all required binary dependencies (`jq`, `hyprctl`, `qs`, `notify-send`, `awk`) exist on `$PATH`.
- **Exit Code**: Exits immediately with `127` and sends a desktop notification if any tool is missing.

#### `wm_kill_widget NAME`
- **Arguments**: `NAME` — Widget identifier name (e.g. `"clock"`).
- **Description**: Gracefully terminates all running layer and edit processes matching the pattern `NAME/(shell|edit)\.qml` using `SIGTERM`. If processes remain alive after 1.5 seconds (`WM_KILL_TIMEOUT`), escalates to `SIGKILL`.

#### `wm_get_monitor_info ID|"focused"`
- **Arguments**: Numeric monitor ID, `"focused"`, or raw monitor JSON.
- **Description**: Queries `hyprctl monitors -j` and exports monitor dimensions and reserved zones into global environment variables:
  - `MON_X`, `MON_Y`, `MON_W`, `MON_H`
  - `RESERVED_LEFT`, `RESERVED_TOP`, `RESERVED_RIGHT`, `RESERVED_BOTTOM`

#### `wm_abs_to_margin X Y MON_ID`
- **Arguments**: Absolute coordinates `X`, `Y`, and numeric monitor ID `MON_ID`.
- **Description**: Converts absolute compositor screen coordinates to layer-relative margins by subtracting monitor offsets and reserved areas. Clamps results to `>= 0`.
- **Exports**: `MARGIN_X`, `MARGIN_Y`.

#### `wm_margin_to_abs X Y`
- **Arguments**: Layer margins `X`, `Y`.
- **Description**: Converts layer-shell margins to absolute global screen coordinates using the focused monitor's origin and reserved offsets.
- **Exports**: `ABS_X`, `ABS_Y`.

#### `wm_clamp_to_screen MARGIN_X MARGIN_Y WIDTH HEIGHT`
- **Arguments**: Margin coordinates and widget dimensions.
- **Description**: Clamps widget margins to ensure at least 50 pixels of the widget remain visible within the monitor's usable area (excluding reserved panels).
- **Exports**: `MARGIN_X`, `MARGIN_Y` (clamped).

#### `wm_read_geo FILE`
- **Arguments**: Path to `geometry.json`.
- **Description**: Reads and validates geometry configuration. If missing or corrupted, automatically writes default values and recovers.
- **Exports**: `GEO_X`, `GEO_Y`, `GEO_W`, `GEO_H`, `GEO_SCALE`.

#### `wm_write_geo FILE X Y W H SCALE`
- **Arguments**: File path, coordinates, dimensions, and scale multiplier.
- **Description**: Creates a `.bak` backup copy and writes updated geometry to `FILE` while strictly preserving the file inode via temporary file `cat` redirection.

#### `wm_find_edit_window TITLE`
- **Arguments**: Window title string (e.g. `"WidgetEdit_Clock"`).
- **Description**: Queries `hyprctl clients -j` for the specified edit window. Prints the client JSON object to standard output, or returns exit code `1` if not found.

#### `wm_notify TITLE [BODY] [ICON]`
- **Arguments**: Notification title, optional body text, optional icon name.
- **Description**: Sends a styled desktop notification using `notify-send` with Widget Manager branding.

#### `wm_compute_scale CUR ACTION [ARG]`
- **Arguments**: Current scale float, action (`"+0.10"`, `"-0.10"`, `"+"`, `"-"`, `"reset"`, or `"set"`), and optional target value.
- **Description**: Computes scale factor using pure `awk` floating-point math without Python dependencies. Clamps output between `WM_SCALE_MIN` (`0.40`) and `WM_SCALE_MAX` (`3.00`) formatted to 2 decimal places. Prints result to stdout.

#### `wm_scale_to_pct SCALE`
- **Arguments**: Scale multiplier float (e.g. `"1.30"`).
- **Description**: Converts a float scale to an integer percentage string (e.g. `"130"`).

#### `wm_acquire_lock LOCKFILE`
- **Arguments**: Path to lockfile.
- **Description**: Acquires a non-blocking `flock` on file descriptor 9. Prevents concurrent duplicate runs of menu dialogs or script state transitions. Returns `0` on acquisition, `1` if locked.
