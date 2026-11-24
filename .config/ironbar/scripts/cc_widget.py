#!/usr/bin/env python3
"""
Single-instance GTK4 + gtk4-layer-shell Control Center widget for Ironbar.
Event-driven backend (pactl subscribe, sysfs FileMonitor, session/system D-Bus)
with coalesced non-blocking slider updates and real-time label/tile synchronization.
"""

from __future__ import annotations

from ctypes import CDLL

# Must be loaded before importing GTK/Gdk/Gtk4LayerShell
CDLL("libgtk4-layer-shell.so")

import getpass
import glob
import os
import re
import signal
import socket
import subprocess
import sys
import threading
import time
from typing import Any, Callable, Optional

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
gi.require_version("Pango", "1.0")
gi.require_version("Graphene", "1.0")
gi.require_version("Gtk4LayerShell", "1.0")
from gi.repository import Gdk, Gio, GLib, Graphene, Gtk, Gtk4LayerShell, Pango  # noqa: E402

try:
    gi.require_version("GLibUnix", "2.0")
    from gi.repository import GLibUnix  # type: ignore
except Exception:
    GLibUnix = None  # type: ignore

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import bt_backend  # noqa: E402

APP_ID = "dev.ironbar.controlcenter"
CSS_PATH = os.path.join(SCRIPT_DIR, "cc_widget.css")
GAMMARELAY_STATE_FILE = "/tmp/gammarelay_last_temp"
VPN_LOCK_FILE = "/tmp/.vpn_control.lock"


class SliderChannel:
    """Manages a GTK4 Scale + icon + live readout with coalesced async system writes."""

    def __init__(
        self,
        icon: str,
        tooltip: str,
        min_val: float,
        max_val: float,
        step: float,
        format_fn: Callable[[int], str],
        apply_fn: Callable[[int], None],
        on_icon_click: Callable[[], None],
        on_live_change: Optional[Callable[[int], None]] = None,
        pace_seconds: float = 0.035,
    ) -> None:
        self.format_fn = format_fn
        self.apply_fn = apply_fn
        self.on_live_change = on_live_change
        self.pace_seconds = pace_seconds

        self._updating_ui = False
        self._suppress_until = 0.0
        self._reconcile_timer_id: Optional[int] = None
        self._pending_sys_value: Optional[tuple[float, bool]] = None
        self._muted = False

        self._cond = threading.Condition()
        self._target: Optional[int] = None
        self._running = True
        self._worker = threading.Thread(target=self._worker_loop, daemon=True)
        self._worker.start()

        self.row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        self.row.set_valign(Gtk.Align.CENTER)

        self.icon_btn = Gtk.Button(label=icon)
        self.icon_btn.add_css_class("cc-slider-icon")
        self.icon_btn.set_valign(Gtk.Align.CENTER)
        self.icon_btn.set_tooltip_text(tooltip)
        self.icon_btn.connect("clicked", lambda _b: on_icon_click())
        self.row.append(self.icon_btn)

        self.scale = Gtk.Scale.new_with_range(
            Gtk.Orientation.HORIZONTAL, min_val, max_val, step
        )
        self.scale.add_css_class("cc-scale")
        self.scale.set_draw_value(False)
        self.scale.set_hexpand(True)
        self.scale.set_valign(Gtk.Align.CENTER)
        self.scale.connect("value-changed", self._on_scale_changed)
        self.row.append(self.scale)

        self.val_lbl = Gtk.Label(label=format_fn(int(min_val)), xalign=1)
        self.val_lbl.add_css_class("cc-slider-pct")
        self.val_lbl.set_valign(Gtk.Align.CENTER)
        self.row.append(self.val_lbl)

    def _on_scale_changed(self, scale: Gtk.Scale) -> None:
        if self._updating_ui:
            return
        val = int(round(scale.get_value()))
        self.val_lbl.set_text(self.format_fn(val))
        if self.on_live_change is not None:
            self.on_live_change(val)
        self._suppress_until = time.monotonic() + 0.35
        self.enqueue(val)

    def enqueue(self, val: int) -> None:
        with self._cond:
            self._target = val
            self._cond.notify()

    def _worker_loop(self) -> None:
        while True:
            with self._cond:
                while self._running and self._target is None:
                    self._cond.wait()
                if not self._running:
                    return
                val = self._target
                self._target = None
            if val is not None:
                try:
                    self.apply_fn(val)
                except Exception:
                    pass
                time.sleep(self.pace_seconds)

    def set_icon(self, glyph: str, muted: bool = False) -> None:
        self.icon_btn.set_label(glyph)
        self._muted = muted
        if muted:
            self.icon_btn.add_css_class("muted")
            self.scale.add_css_class("muted")
        else:
            self.icon_btn.remove_css_class("muted")
            self.scale.remove_css_class("muted")

    def sync_from_system(self, val: float, muted: bool = False) -> None:
        now = time.monotonic()
        if now < self._suppress_until:
            self._pending_sys_value = (val, muted)
            if self._reconcile_timer_id is None:
                delay_ms = max(40, int((self._suppress_until - now) * 1000) + 40)
                self._reconcile_timer_id = GLib.timeout_add(
                    delay_ms, self._reconcile_after_drag
                )
            return

        self._apply_ui_value(val, muted)

    def _reconcile_after_drag(self) -> bool:
        self._reconcile_timer_id = None
        if time.monotonic() < self._suppress_until:
            delay_ms = max(40, int((self._suppress_until - time.monotonic()) * 1000) + 40)
            self._reconcile_timer_id = GLib.timeout_add(
                delay_ms, self._reconcile_after_drag
            )
            return GLib.SOURCE_REMOVE
        pending = self._pending_sys_value
        self._pending_sys_value = None
        if pending is not None:
            self._apply_ui_value(pending[0], pending[1])
        return GLib.SOURCE_REMOVE

    def _apply_ui_value(self, val: float, muted: bool) -> None:
        self._updating_ui = True
        try:
            self.scale.set_value(val)
            self.val_lbl.set_text(self.format_fn(int(round(val))))
        finally:
            self._updating_ui = False

    def stop(self) -> None:
        if self._reconcile_timer_id is not None:
            GLib.source_remove(self._reconcile_timer_id)
            self._reconcile_timer_id = None
        with self._cond:
            self._running = False
            self._cond.notify_all()


class ControlCenterApp(Gtk.Application):
    def __init__(self) -> None:
        super().__init__(
            application_id=APP_ID,
            flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE,
        )
        self._held = False
        self.win: Optional[Gtk.ApplicationWindow] = None
        self.root_box: Optional[Gtk.Box] = None
        self.card: Optional[Gtk.Box] = None

        self.sys_bus: Optional[Gio.DBusConnection] = None
        self.sess_bus: Optional[Gio.DBusConnection] = None
        self.bt_manager: Optional[bt_backend.BluezManager] = None

        self._sys_subs: list[int] = []
        self._sess_subs: list[int] = []
        self._backlight_dir: Optional[str] = None
        self._backlight_max: int = 100
        self._backlight_monitors: list[Gio.FileMonitor] = []

        self._pactl_proc: Optional[subprocess.Popen[str]] = None
        self._pactl_stop = threading.Event()

        self._audio_timer_id: Optional[int] = None
        self._bright_timer_id: Optional[int] = None
        self._bt_timer_id: Optional[int] = None
        self._net_timer_id: Optional[int] = None
        self._bat_timer_id: Optional[int] = None
        self._uptime_timer_id: Optional[int] = None

        self._sink_muted = False
        self._source_muted = False
        self._night_temp = 6500
        self._pp_bus_name: Optional[str] = None
        self._pp_obj_path: Optional[str] = None
        self._pp_iface: Optional[str] = None
        self._current_profile = "balanced"
        self._vpn_busy = False

        self._userhost = self._read_userhost()
        self._wm = (os.environ.get("XDG_CURRENT_DESKTOP") or "hyprland").lower()

    def do_startup(self) -> None:
        Gtk.Application.do_startup(self)
        if not self._held:
            self.hold()
            self._held = True

        self._load_css()
        self.sys_bus = Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        self.sess_bus = Gio.bus_get_sync(Gio.BusType.SESSION, None)
        self.bt_manager = bt_backend.BluezManager(self.sys_bus)

        self._detect_backlight()
        self._detect_power_profiles()
        self._build_window()
        self._setup_monitors()
        self.sync_all()

        if GLibUnix is not None:
            GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, self._on_unix_signal)
            GLibUnix.signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, self._on_unix_signal)
        else:
            GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGTERM, self._on_unix_signal)
            GLib.unix_signal_add(GLib.PRIORITY_DEFAULT, signal.SIGINT, self._on_unix_signal)

    def do_activate(self) -> None:
        if self.win is None:
            self._build_window()
        self.show_popup()

    def do_command_line(self, command_line: Gio.ApplicationCommandLine) -> int:
        args = command_line.get_arguments()[1:]
        action = "toggle"
        if "--quit" in args:
            action = "quit"
        elif "--daemon" in args:
            action = "daemon"
        elif "--show" in args:
            action = "show"
        elif "--hide" in args:
            action = "hide"
        elif "--toggle" in args:
            action = "toggle"

        if self.win is None:
            self._build_window()

        if action == "quit":
            self._cleanup_and_quit()
        elif action == "daemon":
            pass
        elif action == "show":
            self.show_popup()
        elif action == "hide":
            self.hide_popup()
        elif action == "toggle":
            if self.win and self.win.get_visible():
                self.hide_popup()
            else:
                self.show_popup()
        return 0

    def _on_unix_signal(self) -> bool:
        self._cleanup_and_quit()
        return GLib.SOURCE_REMOVE

    def _cleanup_and_quit(self) -> None:
        self._stop_uptime_timer()
        self._pactl_stop.set()
        if self._pactl_proc is not None and self._pactl_proc.poll() is None:
            self._pactl_proc.terminate()
            try:
                self._pactl_proc.wait(timeout=1.0)
            except subprocess.TimeoutExpired:
                self._pactl_proc.kill()

        for mon in self._backlight_monitors:
            try:
                mon.cancel()
            except Exception:
                pass
        self._backlight_monitors.clear()

        if self.sys_bus:
            for sid in self._sys_subs:
                try:
                    self.sys_bus.signal_unsubscribe(sid)
                except Exception:
                    pass
            self._sys_subs.clear()

        if self.sess_bus:
            for sid in self._sess_subs:
                try:
                    self.sess_bus.signal_unsubscribe(sid)
                except Exception:
                    pass
            self._sess_subs.clear()

        for ch in (
            getattr(self, "bright_ch", None),
            getattr(self, "vol_ch", None),
            getattr(self, "mic_ch", None),
            getattr(self, "night_ch", None),
        ):
            if ch is not None:
                ch.stop()

        self.quit()

    def _load_css(self) -> None:
        if not os.path.exists(CSS_PATH):
            return
        provider = Gtk.CssProvider()
        provider.load_from_path(CSS_PATH)
        display = Gdk.Display.get_default()
        if display is not None:
            Gtk.StyleContext.add_provider_for_display(
                display, provider, Gtk.STYLE_PROVIDER_PRIORITY_USER
            )

    # ── UI Construction ──────────────────────────────────────────────────────

    def _build_window(self) -> None:
        win = Gtk.ApplicationWindow(application=self)
        win.set_title("Control Center")
        win.add_css_class("cc-window")

        Gtk4LayerShell.init_for_window(win)
        Gtk4LayerShell.set_namespace(win, "ironbar-control-center")
        Gtk4LayerShell.set_layer(win, Gtk4LayerShell.Layer.OVERLAY)
        Gtk4LayerShell.set_exclusive_zone(win, -1)
        Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.TOP, True)
        Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.BOTTOM, True)
        Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.LEFT, True)
        Gtk4LayerShell.set_anchor(win, Gtk4LayerShell.Edge.RIGHT, True)
        Gtk4LayerShell.set_keyboard_mode(win, Gtk4LayerShell.KeyboardMode.ON_DEMAND)

        root = Gtk.Box(orientation=Gtk.Orientation.VERTICAL)
        root.set_hexpand(True)
        root.set_vexpand(True)
        root.add_css_class("cc-backdrop")

        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=14)
        card.set_halign(Gtk.Align.END)
        card.set_valign(Gtk.Align.START)
        card.set_margin_top(40)
        card.set_margin_end(10)
        card.set_size_request(496, -1)
        card.add_css_class("cc-popup")

        root.append(card)
        win.set_child(root)

        click = Gtk.GestureClick.new()
        click.set_button(0)
        click.connect("pressed", self._on_backdrop_click)
        root.add_controller(click)

        key_ctrl = Gtk.EventControllerKey.new()
        key_ctrl.connect("key-pressed", self._on_key_pressed)
        win.add_controller(key_ctrl)

        self.win = win
        self.root_box = root
        self.card = card

        self._build_header(card)
        self._build_sliders(card)
        self._build_tiles(card)

    def _build_header(self, parent: Gtk.Box) -> None:
        hdr = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        hdr.set_valign(Gtk.Align.CENTER)

        avatar = Gtk.Label(label="󰣇")
        avatar.add_css_class("cc-avatar")
        avatar.set_valign(Gtk.Align.CENTER)
        hdr.append(avatar)

        user_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        user_box.set_hexpand(True)
        user_box.set_valign(Gtk.Align.CENTER)

        self.user_title_lbl = Gtk.Label(label=self._userhost, xalign=0)
        self.user_title_lbl.add_css_class("cc-user-title")
        self.user_title_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        user_box.append(self.user_title_lbl)

        self.user_sub_lbl = Gtk.Label(label="", xalign=0)
        self.user_sub_lbl.add_css_class("cc-user-sub")
        self.user_sub_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        user_box.append(self.user_sub_lbl)
        hdr.append(user_box)

        sess_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        sess_box.set_valign(Gtk.Align.CENTER)

        session_actions = [
            ("", "Lock", "cc-session-btn", lambda: self._run_session(["sh", "-c", "sleep 0.1 && hyprlock"])),
            ("󰤄", "Suspend", "cc-session-btn", lambda: self._run_session(["systemctl", "suspend"])),
            ("󰍃", "Logout", "cc-session-btn", lambda: self._run_session(["hyprctl", "dispatch", "exit"])),
            ("", "Reboot", "cc-session-btn", lambda: self._run_session(["systemctl", "reboot"])),
            ("", "Shutdown", "cc-session-danger", lambda: self._run_session(["systemctl", "poweroff"])),
        ]
        for glyph, tip, css_cls, cb in session_actions:
            btn = Gtk.Button(label=glyph)
            btn.add_css_class(css_cls)
            btn.set_tooltip_text(tip)
            btn.connect("clicked", lambda _b, fn=cb: fn())
            sess_box.append(btn)

        hdr.append(sess_box)
        parent.append(hdr)

    def _build_sliders(self, parent: Gtk.Box) -> None:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)

        self.bright_ch = SliderChannel(
            icon="󰃠",
            tooltip="Show current brightness",
            min_val=1,
            max_val=100,
            step=3,
            format_fn=lambda v: f"{v}%",
            apply_fn=self._apply_brightness,
            on_icon_click=lambda: self._spawn_detached(
                [os.path.join(SCRIPT_DIR, "brightness_ironbar.sh"), "get"], hide=False
            ),
        )
        box.append(self.bright_ch.row)

        self.vol_ch = SliderChannel(
            icon="",
            tooltip="Toggle audio mute",
            min_val=0,
            max_val=150,
            step=2,
            format_fn=lambda v: f"{v}%",
            apply_fn=self._apply_volume,
            on_icon_click=self._toggle_sink_mute,
        )
        box.append(self.vol_ch.row)

        self.mic_ch = SliderChannel(
            icon="",
            tooltip="Toggle microphone mute",
            min_val=0,
            max_val=100,
            step=2,
            format_fn=lambda v: f"{v}%",
            apply_fn=self._apply_mic,
            on_icon_click=self._toggle_source_mute,
        )
        box.append(self.mic_ch.row)

        self.night_ch = SliderChannel(
            icon="󰖔",
            tooltip="Toggle Night Light",
            min_val=2500,
            max_val=6500,
            step=50,
            format_fn=lambda v: f"{v}K",
            apply_fn=self._apply_nightlight,
            on_icon_click=self._toggle_nightlight,
            on_live_change=self._update_nightlight_tile_ui,
        )
        box.append(self.night_ch.row)

        parent.append(box)

    def _make_tile(
        self, icon: str, title: str, subtitle: str, active: bool, on_click: Callable[[], None]
    ) -> tuple[Gtk.Button, Gtk.Label, Gtk.Label]:
        btn = Gtk.Button()
        btn.add_css_class("cc-tile")
        btn.set_hexpand(True)
        btn.connect("clicked", lambda _b: on_click())

        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=12)
        row.set_valign(Gtk.Align.CENTER)

        icon_lbl = Gtk.Label(label=icon)
        icon_lbl.add_css_class("cc-icon-active" if active else "cc-icon-inactive")
        icon_lbl.set_valign(Gtk.Align.CENTER)
        row.append(icon_lbl)

        txt = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        txt.set_valign(Gtk.Align.CENTER)
        txt.set_hexpand(True)

        t_lbl = Gtk.Label(label=title, xalign=0)
        t_lbl.add_css_class("cc-tile-title")
        t_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        txt.append(t_lbl)

        s_lbl = Gtk.Label(label=subtitle, xalign=0)
        s_lbl.add_css_class("cc-tile-sub")
        s_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        txt.append(s_lbl)

        row.append(txt)
        btn.set_child(row)
        return btn, icon_lbl, s_lbl

    def _set_tile_state(
        self, icon_lbl: Gtk.Label, sub_lbl: Gtk.Label, glyph: str, subtitle: str, active: bool
    ) -> None:
        icon_lbl.set_label(glyph)
        sub_lbl.set_text(subtitle)
        if active:
            icon_lbl.remove_css_class("cc-icon-inactive")
            icon_lbl.add_css_class("cc-icon-active")
        else:
            icon_lbl.remove_css_class("cc-icon-active")
            icon_lbl.add_css_class("cc-icon-inactive")

    def _build_tiles(self, parent: Gtk.Box) -> None:
        grid = Gtk.Grid()
        grid.set_column_spacing(8)
        grid.set_row_spacing(8)
        grid.set_column_homogeneous(True)

        _, self.net_icon, self.net_sub = self._make_tile(
            "󰤨", "Network", "Checking...", True,
            lambda: self._spawn_detached([os.path.join(SCRIPT_DIR, "nmtui-floating.sh")], hide=True),
        )
        net_btn = self.net_icon.get_ancestor(Gtk.Button)

        _, self.bt_icon, self.bt_sub = self._make_tile(
            "󰂯", "Bluetooth", "Checking...", True,
            lambda: self._spawn_detached([os.path.join(SCRIPT_DIR, "bt_widget.py"), "--show"], hide=True),
        )
        bt_btn = self.bt_icon.get_ancestor(Gtk.Button)

        _, self.vpn_icon, self.vpn_sub = self._make_tile(
            "󰦝", "Proton VPN", "Disconnected", False,
            self._on_vpn_clicked,
        )
        vpn_btn = self.vpn_icon.get_ancestor(Gtk.Button)

        _, self.pp_icon, self.pp_sub = self._make_tile(
            "", "Power Profile", "Balanced", True,
            self._cycle_power_profile,
        )
        pp_btn = self.pp_icon.get_ancestor(Gtk.Button)

        picker_btn, _, _ = self._make_tile(
            "󰃉", "Color Picker", "Choose color", False,
            self._on_picker_clicked,
        )

        _, self.nl_icon, self.nl_sub = self._make_tile(
            "󰖔", "Night Light", "6500K", False,
            self._toggle_nightlight,
        )
        nl_btn = self.nl_icon.get_ancestor(Gtk.Button)

        grid.attach(net_btn, 0, 0, 1, 1)
        grid.attach(bt_btn, 1, 0, 1, 1)
        grid.attach(vpn_btn, 0, 1, 1, 1)
        grid.attach(pp_btn, 1, 1, 1, 1)
        grid.attach(picker_btn, 0, 2, 1, 1)
        grid.attach(nl_btn, 1, 2, 1, 1)

        parent.append(grid)

    # ── Popup Visibility & Events ────────────────────────────────────────────

    def show_popup(self) -> None:
        if self.win is None:
            return
        self.sync_all()
        self._start_uptime_timer()
        self.win.present()

    def hide_popup(self) -> None:
        if self.win is None:
            return
        self._stop_uptime_timer()
        self.win.set_visible(False)

    def _start_uptime_timer(self) -> None:
        if self._uptime_timer_id is None:
            self._uptime_timer_id = GLib.timeout_add_seconds(30, self._on_uptime_tick)

    def _stop_uptime_timer(self) -> None:
        if self._uptime_timer_id is not None:
            GLib.source_remove(self._uptime_timer_id)
            self._uptime_timer_id = None

    def _on_uptime_tick(self) -> bool:
        self._sync_header_info()
        return GLib.SOURCE_CONTINUE

    def _on_backdrop_click(
        self, _gesture: Gtk.GestureClick, _n_press: int, x: float, y: float
    ) -> None:
        if self.card is None or self.root_box is None:
            return
        ok, bounds = self.card.compute_bounds(self.root_box)
        if ok:
            pt = Graphene.Point()
            pt.init(x, y)
            if not bounds.contains_point(pt):
                self.hide_popup()

    def _on_key_pressed(
        self,
        _ctrl: Gtk.EventControllerKey,
        keyval: int,
        _keycode: int,
        _state: Gdk.ModifierType,
    ) -> bool:
        if keyval == Gdk.KEY_Escape:
            self.hide_popup()
            return True
        return False

    def _run_session(self, cmd: list[str]) -> None:
        self.hide_popup()
        self._spawn_detached(cmd, hide=False)

    def _spawn_detached(self, cmd: list[str], hide: bool) -> None:
        if hide:
            self.hide_popup()
        try:
            subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except Exception:
            pass

    def _on_picker_clicked(self) -> None:
        self.hide_popup()
        GLib.timeout_add(
            120,
            lambda: self._spawn_detached([os.path.join(SCRIPT_DIR, "picker.sh")], hide=False)
            or GLib.SOURCE_REMOVE,
        )

    # ── Event Monitors ───────────────────────────────────────────────────────

    def _setup_monitors(self) -> None:
        # 1. Backlight sysfs FileMonitor
        if self._backlight_dir:
            for fname in ("actual_brightness", "brightness"):
                fpath = os.path.join(self._backlight_dir, fname)
                if os.path.exists(fpath):
                    try:
                        mon = Gio.File.new_for_path(fpath).monitor_file(
                            Gio.FileMonitorFlags.NONE, None
                        )
                        mon.connect("changed", self._on_backlight_changed)
                        self._backlight_monitors.append(mon)
                    except Exception:
                        pass

        # 2. Audio pactl subscribe thread
        threading.Thread(target=self._pactl_loop, daemon=True).start()

        # 3. Night Light session D-Bus PropertiesChanged
        if self.sess_bus:
            self._sess_subs.append(
                self.sess_bus.signal_subscribe(
                    "rs.wl-gammarelay",
                    "org.freedesktop.DBus.Properties",
                    "PropertiesChanged",
                    "/",
                    None,
                    Gio.DBusSignalFlags.NONE,
                    lambda *_a: self._sync_nightlight(),
                )
            )

        # 4. System D-Bus signals: BlueZ, UPower (Battery), PowerProfiles, NetworkManager
        if self.sys_bus:
            self._sys_subs.extend(
                [
                    self.sys_bus.signal_subscribe(
                        bt_backend.BLUEZ_SERVICE,
                        bt_backend.DBUS_PROPS_IFACE,
                        "PropertiesChanged",
                        None,
                        None,
                        Gio.DBusSignalFlags.NONE,
                        self._schedule_bt_sync,
                    ),
                    self.sys_bus.signal_subscribe(
                        bt_backend.BLUEZ_SERVICE,
                        bt_backend.DBUS_OM_IFACE,
                        "InterfacesAdded",
                        None,
                        None,
                        Gio.DBusSignalFlags.NONE,
                        self._schedule_bt_sync,
                    ),
                    self.sys_bus.signal_subscribe(
                        bt_backend.BLUEZ_SERVICE,
                        bt_backend.DBUS_OM_IFACE,
                        "InterfacesRemoved",
                        None,
                        None,
                        Gio.DBusSignalFlags.NONE,
                        self._schedule_bt_sync,
                    ),
                    self.sys_bus.signal_subscribe(
                        "org.freedesktop.UPower",
                        "org.freedesktop.DBus.Properties",
                        "PropertiesChanged",
                        None,
                        None,
                        Gio.DBusSignalFlags.NONE,
                        self._schedule_bat_sync,
                    ),
                    self.sys_bus.signal_subscribe(
                        "org.freedesktop.NetworkManager",
                        None,
                        None,
                        None,
                        None,
                        Gio.DBusSignalFlags.NONE,
                        self._schedule_net_sync,
                    ),
                ]
            )
            if self._pp_bus_name and self._pp_obj_path:
                self._sys_subs.append(
                    self.sys_bus.signal_subscribe(
                        self._pp_bus_name,
                        "org.freedesktop.DBus.Properties",
                        "PropertiesChanged",
                        self._pp_obj_path,
                        None,
                        Gio.DBusSignalFlags.NONE,
                        lambda *_a: self._sync_power_profile(),
                    )
                )

    def _pactl_loop(self) -> None:
        while not self._pactl_stop.is_set():
            try:
                proc = subprocess.Popen(
                    ["pactl", "subscribe"],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.DEVNULL,
                    text=True,
                )
                self._pactl_proc = proc
                if proc.stdout is None:
                    break
                for line in proc.stdout:
                    if self._pactl_stop.is_set():
                        break
                    low = line.lower()
                    if " on sink" in low or " on source" in low or " on server" in low:
                        GLib.idle_add(self._schedule_audio_sync)
                proc.wait()
            except Exception:
                pass
            if not self._pactl_stop.is_set():
                time.sleep(1.0)

    def _schedule_audio_sync(self) -> bool:
        if self._audio_timer_id is None:
            self._audio_timer_id = GLib.timeout_add(60, self._do_audio_sync)
        return GLib.SOURCE_REMOVE

    def _do_audio_sync(self) -> bool:
        self._audio_timer_id = None
        self._sync_audio()
        return GLib.SOURCE_REMOVE

    def _on_backlight_changed(self, *_args: Any) -> None:
        if self._bright_timer_id is None:
            self._bright_timer_id = GLib.timeout_add(50, self._do_bright_sync)

    def _do_bright_sync(self) -> bool:
        self._bright_timer_id = None
        self._sync_brightness()
        return GLib.SOURCE_REMOVE

    def _schedule_bt_sync(self, *_args: Any) -> None:
        if self._bt_timer_id is None:
            self._bt_timer_id = GLib.timeout_add(150, self._do_bt_sync)

    def _do_bt_sync(self) -> bool:
        self._bt_timer_id = None
        self._sync_bluetooth()
        return GLib.SOURCE_REMOVE

    def _schedule_bat_sync(self, *_args: Any) -> None:
        if self._bat_timer_id is None:
            self._bat_timer_id = GLib.timeout_add(200, self._do_bat_sync)

    def _do_bat_sync(self) -> bool:
        self._bat_timer_id = None
        self._sync_header_info()
        return GLib.SOURCE_REMOVE

    def _schedule_net_sync(self, *_args: Any) -> None:
        if self._net_timer_id is None:
            self._net_timer_id = GLib.timeout_add(180, self._do_net_sync)

    def _do_net_sync(self) -> bool:
        self._net_timer_id = None
        self._sync_network_and_vpn()
        return GLib.SOURCE_REMOVE

    # ── Sync All & Subsystem Backends ────────────────────────────────────────

    def sync_all(self) -> None:
        self._sync_header_info()
        self._sync_brightness()
        self._sync_audio()
        self._sync_nightlight()
        self._sync_bluetooth()
        self._sync_power_profile()
        self._sync_network_and_vpn()

    def _read_userhost(self) -> str:
        user = getpass.getuser() or os.environ.get("USER", "user")
        host = socket.gethostname()
        if not host and os.path.exists("/etc/hostname"):
            try:
                with open("/etc/hostname", "r", encoding="utf-8") as f:
                    host = f.read().strip()
            except Exception:
                pass
        return f"{user}@{host or 'localhost'}"

    def _read_uptime(self) -> str:
        try:
            with open("/proc/uptime", "r", encoding="utf-8") as f:
                secs = int(float(f.read().split()[0]))
            days, rem = divmod(secs, 86400)
            hours, rem = divmod(rem, 3600)
            mins = rem // 60
            parts = []
            if days:
                parts.append(f"{days}d")
            if hours:
                parts.append(f"{hours}h")
            if mins or not parts:
                parts.append(f"{mins}m")
            return " ".join(parts)
        except Exception:
            return "0m"

    def _read_battery(self) -> Optional[tuple[str, int]]:
        bats = sorted(glob.glob("/sys/class/power_supply/BAT*"))
        if not bats:
            return None
        bat_dir = bats[0]
        try:
            with open(os.path.join(bat_dir, "capacity"), "r", encoding="utf-8") as f:
                cap = int(f.read().strip())
        except Exception:
            return None
        status = ""
        try:
            with open(os.path.join(bat_dir, "status"), "r", encoding="utf-8") as f:
                status = f.read().strip().lower()
        except Exception:
            pass
        if status == "charging":
            glyph = "󰂄"
        elif cap >= 90:
            glyph = "󰁹"
        elif cap >= 70:
            glyph = "󰂀"
        elif cap >= 45:
            glyph = "󰁾"
        elif cap >= 20:
            glyph = "󰁼"
        else:
            glyph = "󰁺"
        return (glyph, cap)

    def _sync_header_info(self) -> None:
        up = self._read_uptime()
        bat = self._read_battery()
        text = f"󰖯 {self._wm}    up {up}"
        if bat is not None:
            glyph, cap = bat
            text += f"   {glyph} {cap}%"
        self.user_sub_lbl.set_text(text)

    # Brightness
    def _detect_backlight(self) -> None:
        dirs = sorted(glob.glob("/sys/class/backlight/*"))
        if not dirs:
            return
        self._backlight_dir = dirs[0]
        try:
            with open(os.path.join(self._backlight_dir, "max_brightness"), "r", encoding="utf-8") as f:
                self._backlight_max = max(1, int(f.read().strip()))
        except Exception:
            self._backlight_max = 100

    def _sync_brightness(self) -> None:
        if not self._backlight_dir:
            return
        pct = 100
        for fname in ("actual_brightness", "brightness"):
            fpath = os.path.join(self._backlight_dir, fname)
            if os.path.exists(fpath):
                try:
                    with open(fpath, "r", encoding="utf-8") as f:
                        cur = int(f.read().strip())
                    pct = max(1, min(100, round((cur * 100) / self._backlight_max)))
                    break
                except Exception:
                    pass
        self.bright_ch.sync_from_system(pct)

    def _apply_brightness(self, pct: int) -> None:
        clamped = max(1, min(100, int(pct)))
        subprocess.run(
            ["brightnessctl", "set", f"{clamped}%", "-q"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )

    # Audio (wpctl)
    def _read_wpctl(self, target: str) -> tuple[int, bool]:
        try:
            out = subprocess.check_output(
                ["wpctl", "get-volume", target],
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=1.5,
            )
            muted = "[MUTED]" in out
            m = re.search(r"Volume:\s*([0-9]+(?:\.[0-9]+)?)", out)
            pct = int(round(float(m.group(1)) * 100)) if m else 0
            return (pct, muted)
        except Exception:
            return (0, False)

    def _sync_audio(self) -> None:
        def _fetch() -> None:
            sink_pct, sink_muted = self._read_wpctl("@DEFAULT_AUDIO_SINK@")
            src_pct, src_muted = self._read_wpctl("@DEFAULT_AUDIO_SOURCE@")

            def _apply() -> bool:
                self._sink_muted = sink_muted
                self._source_muted = src_muted
                if sink_muted:
                    s_icon = "󰖁"
                elif sink_pct >= 60:
                    s_icon = ""
                elif sink_pct >= 25:
                    s_icon = ""
                else:
                    s_icon = ""
                self.vol_ch.set_icon(s_icon, muted=sink_muted)
                self.vol_ch.sync_from_system(min(150, max(0, sink_pct)), muted=sink_muted)

                m_icon = "" if src_muted else ""
                self.mic_ch.set_icon(m_icon, muted=src_muted)
                self.mic_ch.sync_from_system(min(100, max(0, src_pct)), muted=src_muted)
                return GLib.SOURCE_REMOVE

            GLib.idle_add(_apply)

        threading.Thread(target=_fetch, daemon=True).start()

    def _apply_volume(self, pct: int) -> None:
        clamped = max(0, min(150, int(pct)))
        if self._sink_muted and clamped > 0:
            subprocess.run(
                ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "0"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
        subprocess.run(
            ["wpctl", "set-volume", "-l", "1.5", "@DEFAULT_AUDIO_SINK@", f"{clamped}%"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )

    def _apply_mic(self, pct: int) -> None:
        clamped = max(0, min(100, int(pct)))
        subprocess.run(
            ["wpctl", "set-volume", "-l", "1.0", "@DEFAULT_AUDIO_SOURCE@", f"{clamped}%"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )

    def _toggle_sink_mute(self) -> None:
        def _work() -> None:
            subprocess.run(
                ["wpctl", "set-mute", "@DEFAULT_AUDIO_SINK@", "toggle"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            GLib.idle_add(self._sync_audio)

        threading.Thread(target=_work, daemon=True).start()

    def _toggle_source_mute(self) -> None:
        def _work() -> None:
            subprocess.run(
                ["wpctl", "set-mute", "@DEFAULT_AUDIO_SOURCE@", "toggle"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            GLib.idle_add(self._sync_audio)

        threading.Thread(target=_work, daemon=True).start()

    # Night Light (rs.wl-gammarelay)
    def _read_nightlight_temp(self) -> int:
        if not self.sess_bus:
            return 6500
        try:
            res = self.sess_bus.call_sync(
                "rs.wl-gammarelay",
                "/",
                "org.freedesktop.DBus.Properties",
                "Get",
                GLib.Variant("(ss)", ("rs.wl.gammarelay", "Temperature")),
                None,
                Gio.DBusCallFlags.NONE,
                1500,
                None,
            )
            val = int(res.unpack()[0])
            return max(2500, min(6500, val))
        except Exception:
            return 6500

    def _update_nightlight_tile_ui(self, temp: int) -> None:
        self._night_temp = temp
        if temp >= 6500:
            self._set_tile_state(self.nl_icon, self.nl_sub, "󰖔", "Off • 6500K", False)
        else:
            self._set_tile_state(self.nl_icon, self.nl_sub, "󰖔", f"On • {temp}K", True)

    def _sync_nightlight(self) -> None:
        temp = self._read_nightlight_temp()
        self.night_ch.sync_from_system(temp)
        if time.monotonic() >= self.night_ch._suppress_until:
            self._update_nightlight_tile_ui(temp)

    def _apply_nightlight(self, temp: int) -> None:
        if not self.sess_bus:
            return
        clamped = max(2500, min(6500, int(temp)))
        try:
            self.sess_bus.call_sync(
                "rs.wl-gammarelay",
                "/",
                "org.freedesktop.DBus.Properties",
                "Set",
                GLib.Variant("(ssv)", ("rs.wl.gammarelay", "Temperature", GLib.Variant("q", clamped))),
                None,
                Gio.DBusCallFlags.NONE,
                1500,
                None,
            )
        except Exception:
            pass

    def _toggle_nightlight(self) -> None:
        cur = self._read_nightlight_temp()
        if cur >= 6500:
            target = 4500
            if os.path.exists(GAMMARELAY_STATE_FILE):
                try:
                    with open(GAMMARELAY_STATE_FILE, "r", encoding="utf-8") as f:
                        saved = int(f.read().strip())
                    if 2500 <= saved < 6500:
                        target = saved
                except Exception:
                    pass
        else:
            try:
                with open(GAMMARELAY_STATE_FILE, "w", encoding="utf-8") as f:
                    f.write(f"{cur}\n")
            except Exception:
                pass
            target = 6500
        self.night_ch.sync_from_system(target)
        self._update_nightlight_tile_ui(target)
        self.night_ch.enqueue(target)

    # Bluetooth
    def _sync_bluetooth(self) -> None:
        if not self.bt_manager:
            return
        snap = self.bt_manager.get_snapshot()
        adapter = snap.get("adapter")
        powered = bool(adapter and adapter.get("powered"))
        sub = bt_backend.format_cc_subtitle(snap)
        glyph = "󰂯" if powered else "󰂲"
        self._set_tile_state(self.bt_icon, self.bt_sub, glyph, sub, powered)

    # Power Profiles
    def _detect_power_profiles(self) -> None:
        if not self.sys_bus:
            return
        candidates = [
            ("org.freedesktop.UPower.PowerProfiles", "/org/freedesktop/UPower/PowerProfiles", "org.freedesktop.UPower.PowerProfiles"),
            ("net.hadess.PowerProfiles", "/net/hadess/PowerProfiles", "net.hadess.PowerProfiles"),
        ]
        for bus_name, obj_path, iface in candidates:
            try:
                self.sys_bus.call_sync(
                    bus_name,
                    obj_path,
                    "org.freedesktop.DBus.Properties",
                    "Get",
                    GLib.Variant("(ss)", (iface, "ActiveProfile")),
                    None,
                    Gio.DBusCallFlags.NONE,
                    1500,
                    None,
                )
                self._pp_bus_name = bus_name
                self._pp_obj_path = obj_path
                self._pp_iface = iface
                return
            except Exception:
                continue

    def _sync_power_profile(self) -> None:
        prof = "balanced"
        if self.sys_bus and self._pp_bus_name and self._pp_obj_path and self._pp_iface:
            try:
                res = self.sys_bus.call_sync(
                    self._pp_bus_name,
                    self._pp_obj_path,
                    "org.freedesktop.DBus.Properties",
                    "Get",
                    GLib.Variant("(ss)", (self._pp_iface, "ActiveProfile")),
                    None,
                    Gio.DBusCallFlags.NONE,
                    1500,
                    None,
                )
                prof = str(res.unpack()[0])
            except Exception:
                pass
        self._current_profile = prof
        meta = {
            "power-saver": ("󰌪", "Power Saver"),
            "balanced": ("", "Balanced"),
            "performance": ("󰓅", "Performance"),
        }
        glyph, label = meta.get(prof, ("", "Balanced"))
        self._set_tile_state(self.pp_icon, self.pp_sub, glyph, label, True)

    def _cycle_power_profile(self) -> None:
        order = {"performance": "balanced", "balanced": "power-saver", "power-saver": "performance"}
        nxt = order.get(self._current_profile, "balanced")
        if self.sys_bus and self._pp_bus_name and self._pp_obj_path and self._pp_iface:
            try:
                self.sys_bus.call_sync(
                    self._pp_bus_name,
                    self._pp_obj_path,
                    "org.freedesktop.DBus.Properties",
                    "Set",
                    GLib.Variant("(ssv)", (self._pp_iface, "ActiveProfile", GLib.Variant("s", nxt))),
                    None,
                    Gio.DBusCallFlags.NONE,
                    1500,
                    None,
                )
                self._sync_power_profile()
                meta = {
                    "power-saver": ("󰌪", "Power Saver", "power-profile-power-saver-symbolic"),
                    "balanced": ("", "Balanced", "power-profile-balanced-symbolic"),
                    "performance": ("󰓅", "Performance", "power-profile-performance-symbolic"),
                }
                glyph, title, sys_icon = meta[nxt]
                self._spawn_detached(
                    [
                        "notify-send", "-t", "2000",
                        "-h", "string:x-canonical-private-synchronous:powerprofile",
                        f"{glyph} {title}", "-i", sys_icon,
                    ],
                    hide=False,
                )
                return
            except Exception:
                pass
        self._spawn_detached([os.path.join(SCRIPT_DIR, "power-profile.sh"), "cycle"], hide=False)

    # Network & VPN
    def _sync_network_and_vpn(self) -> None:
        def _fetch() -> None:
            net_glyph, net_name = self._read_network_state()
            vpn_glyph, vpn_sub, vpn_active = self._read_vpn_state()

            def _apply() -> bool:
                self._set_tile_state(
                    self.net_icon,
                    self.net_sub,
                    net_glyph,
                    net_name,
                    net_name != "Disconnected",
                )
                self._set_tile_state(
                    self.vpn_icon,
                    self.vpn_sub,
                    vpn_glyph,
                    vpn_sub,
                    vpn_active,
                )
                return GLib.SOURCE_REMOVE

            GLib.idle_add(_apply)

        threading.Thread(target=_fetch, daemon=True).start()

    def _read_network_state(self) -> tuple[str, str]:
        try:
            out = subprocess.check_output(
                ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"],
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=2.0,
            )
            for line in out.splitlines():
                parts = line.split(":", 3)
                if len(parts) == 4 and parts[1] in ("wifi", "ethernet") and parts[2] == "connected":
                    ntype, cname = parts[1], parts[3][:18]
                    glyph = "󰤨" if ntype == "wifi" else "󰈀"
                    return (glyph, cname or ntype.title())
        except Exception:
            pass
        return ("󰖪", "Disconnected")

    def _read_vpn_state(self) -> tuple[str, str, bool]:
        if self._vpn_busy or os.path.exists(VPN_LOCK_FILE):
            try:
                if os.path.exists(VPN_LOCK_FILE):
                    with open(VPN_LOCK_FILE, "r", encoding="utf-8") as f:
                        msg = f.read().strip() or "Working..."
                    return ("󰦝", msg, False)
            except Exception:
                pass
            return ("󰦝", "Working...", False)
        try:
            out = subprocess.check_output(
                ["nmcli", "-t", "-f", "NAME,TYPE", "connection", "show", "--active"],
                stderr=subprocess.DEVNULL,
                text=True,
                timeout=2.0,
            )
            for line in out.splitlines():
                low = line.lower()
                if any(k in low for k in ("proton", "pvpn", ":vpn:", ":wireguard:", ":tun:")):
                    cname = line.split(":", 1)[0]
                    for prefix in ("ProtonVPN ", "Proton VPN ", "pvpn-"):
                        if cname.startswith(prefix):
                            cname = cname[len(prefix):]
                    if cname and len(cname) <= 18:
                        return ("󰖂", f"Connected • {cname}", True)
                    return ("󰖂", "Connected", True)
        except Exception:
            pass
        return ("󰦝", "Disconnected", False)

    def _on_vpn_clicked(self) -> None:
        if self._vpn_busy:
            return
        self._vpn_busy = True
        self._set_tile_state(self.vpn_icon, self.vpn_sub, "󰦝", "Working...", False)

        def _work() -> None:
            try:
                subprocess.run(
                    [os.path.join(SCRIPT_DIR, "vpn_control.sh"), "toggle"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=35,
                    check=False,
                )
            except Exception:
                pass
            finally:
                self._vpn_busy = False
                GLib.idle_add(self._sync_network_and_vpn)

        threading.Thread(target=_work, daemon=True).start()


def main(argv: Optional[list[str]] = None) -> int:
    app = ControlCenterApp()
    return app.run(argv if argv is not None else sys.argv)


if __name__ == "__main__":
    sys.exit(main())
