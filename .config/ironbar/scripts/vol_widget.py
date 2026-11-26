#!/usr/bin/env python3
"""
Single-instance GTK4 + gtk4-layer-shell Volume Mixer widget for Ironbar.
Event-driven via `pactl subscribe` + `pactl -f json` with live percentages,
output sink switching, per-app stream mixing, and coalesced slider writes.
"""

from __future__ import annotations

from ctypes import CDLL

# Must be loaded before importing GTK/Gdk/Gtk4LayerShell
CDLL("libgtk4-layer-shell.so")

import json
import os
import re
import signal
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
APP_ID = "dev.ironbar.volume"
CSS_PATH = os.path.join(SCRIPT_DIR, "vol_widget.css")


def _vol_glyph(pct: int, muted: bool) -> str:
    if muted:
        return "󰖁"
    if pct >= 60:
        return ""
    if pct >= 25:
        return ""
    return ""


def _extract_pct(volume_map: dict[str, Any]) -> int:
    if not volume_map:
        return 0
    vals: list[int] = []
    for ch in volume_map.values():
        vp = str(ch.get("value_percent", ""))
        m = re.search(r"(\d+)%", vp)
        if m:
            vals.append(int(m.group(1)))
        elif "value" in ch:
            vals.append(int(round(float(ch["value"]) * 100.0 / 65536.0)))
    return int(round(sum(vals) / len(vals))) if vals else 0


class MixerChannel:
    """Coalesced slider + inline mute button + live percentage readout."""

    def __init__(
        self,
        apply_fn: Callable[[int], None],
        on_mute_click: Callable[[], None],
        on_live_change: Optional[Callable[[int, bool], None]] = None,
        pace_seconds: float = 0.035,
    ) -> None:
        self.apply_fn = apply_fn
        self.on_live_change = on_live_change
        self.pace_seconds = pace_seconds

        self._updating_ui = False
        self._suppress_until = 0.0
        self._reconcile_timer_id: Optional[int] = None
        self._pending_sys_value: Optional[tuple[int, bool]] = None
        self._muted = False

        self._cond = threading.Condition()
        self._target: Optional[int] = None
        self._running = True
        self._worker = threading.Thread(target=self._worker_loop, daemon=True)
        self._worker.start()

        self.row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        self.row.set_valign(Gtk.Align.CENTER)

        self.mute_btn = Gtk.Button(label="")
        self.mute_btn.add_css_class("vol-mute-btn")
        self.mute_btn.set_valign(Gtk.Align.CENTER)
        self.mute_btn.set_tooltip_text("Toggle mute")
        self.mute_btn.connect("clicked", lambda _b: on_mute_click())
        self.row.append(self.mute_btn)

        self.scale = Gtk.Scale.new_with_range(Gtk.Orientation.HORIZONTAL, 0, 150, 2)
        self.scale.add_css_class("vol-scale")
        self.scale.set_draw_value(False)
        self.scale.set_hexpand(True)
        self.scale.set_valign(Gtk.Align.CENTER)
        self.scale.connect("value-changed", self._on_scale_changed)
        self.row.append(self.scale)

        self.pct_lbl = Gtk.Label(label="0%", xalign=1)
        self.pct_lbl.add_css_class("vol-pct")
        self.pct_lbl.set_valign(Gtk.Align.CENTER)
        self.row.append(self.pct_lbl)

    def _on_scale_changed(self, scale: Gtk.Scale) -> None:
        if self._updating_ui:
            return
        val = int(round(scale.get_value()))
        self.pct_lbl.set_text(f"{val}%")
        self.mute_btn.set_label(_vol_glyph(val, self._muted))
        if self.on_live_change is not None:
            self.on_live_change(val, self._muted)
        self._suppress_until = time.monotonic() + 0.35
        self._enqueue(val)

    def _enqueue(self, val: int) -> None:
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

    def sync_from_system(self, pct: int, muted: bool) -> None:
        self._apply_mute_style(pct, muted)
        now = time.monotonic()
        if now < self._suppress_until:
            self._pending_sys_value = (pct, muted)
            if self._reconcile_timer_id is None:
                delay_ms = max(40, int((self._suppress_until - now) * 1000) + 40)
                self._reconcile_timer_id = GLib.timeout_add(
                    delay_ms, self._reconcile_after_drag
                )
            return
        self._apply_slider_value(pct, muted)

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
            self._apply_slider_value(pending[0], pending[1])
        return GLib.SOURCE_REMOVE

    def _apply_mute_style(self, pct: int, muted: bool) -> None:
        self._muted = muted
        self.mute_btn.set_label(_vol_glyph(pct, muted))
        for w in (self.mute_btn, self.scale, self.pct_lbl):
            if muted:
                w.add_css_class("muted")
            else:
                w.remove_css_class("muted")

    def _apply_slider_value(self, pct: int, muted: bool) -> None:
        self._updating_ui = True
        try:
            clamped = max(0, min(150, int(pct)))
            self.scale.set_value(clamped)
            self.pct_lbl.set_text(f"{clamped}%")
            self._apply_mute_style(clamped, muted)
        finally:
            self._updating_ui = False

    def stop(self) -> None:
        if self._reconcile_timer_id is not None:
            GLib.source_remove(self._reconcile_timer_id)
            self._reconcile_timer_id = None
        with self._cond:
            self._running = False
            self._cond.notify_all()


class VolumeWidgetApp(Gtk.Application):
    def __init__(self) -> None:
        super().__init__(
            application_id=APP_ID,
            flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE,
        )
        self._held = False
        self._updating_ui = False
        self.win: Optional[Gtk.ApplicationWindow] = None
        self.root_box: Optional[Gtk.Box] = None
        self.card: Optional[Gtk.Box] = None

        self._pactl_proc: Optional[subprocess.Popen[str]] = None
        self._pactl_stop = threading.Event()
        self._sync_timer_id: Optional[int] = None

        self._sink_names: list[str] = []
        self._sink_signature: list[tuple[str, str]] = []
        self._default_sink_name: str = ""
        self._app_rows: dict[int, dict[str, Any]] = {}
        self._app_order: list[int] = []

    def do_startup(self) -> None:
        Gtk.Application.do_startup(self)
        if not self._held:
            self.hold()
            self._held = True

        self._load_css()
        self._build_window()
        threading.Thread(target=self._pactl_loop, daemon=True).start()
        self.refresh_state()

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
        self._pactl_stop.set()
        if self._pactl_proc is not None and self._pactl_proc.poll() is None:
            self._pactl_proc.terminate()
            try:
                self._pactl_proc.wait(timeout=1.0)
            except subprocess.TimeoutExpired:
                self._pactl_proc.kill()
        if hasattr(self, "output_ch"):
            self.output_ch.stop()
        for item in self._app_rows.values():
            item["channel"].stop()
        self._app_rows.clear()
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

    def _build_window(self) -> None:
        win = Gtk.ApplicationWindow(application=self)
        win.set_title("Volume")
        win.add_css_class("vol-window")

        Gtk4LayerShell.init_for_window(win)
        Gtk4LayerShell.set_namespace(win, "ironbar-volume")
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
        root.add_css_class("vol-backdrop")

        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        card.set_halign(Gtk.Align.END)
        card.set_valign(Gtk.Align.START)
        card.set_margin_top(40)
        card.set_margin_end(10)
        card.set_size_request(360, -1)
        card.add_css_class("vol-popup")

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

        # Output Device Card
        out_card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        out_card.add_css_class("vol-card")

        out_hdr = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        out_hdr.set_valign(Gtk.Align.CENTER)

        out_title = Gtk.Label(label="󰕾  Output", xalign=0)
        out_title.add_css_class("vol-title")
        out_title.set_hexpand(True)
        out_hdr.append(out_title)

        self.out_badge_lbl = Gtk.Label(label="0%", xalign=1)
        self.out_badge_lbl.add_css_class("vol-pct")
        out_hdr.append(self.out_badge_lbl)

        mixer_btn = Gtk.Button(label="󰒓")
        mixer_btn.add_css_class("vol-icon-btn")
        mixer_btn.set_tooltip_text("Open Sound Settings (pavucontrol)")
        mixer_btn.connect("clicked", lambda _b: self._open_pavucontrol())
        out_hdr.append(mixer_btn)
        out_card.append(out_hdr)

        self.sink_model = Gtk.StringList()
        self.sink_dropdown = Gtk.DropDown(model=self.sink_model)
        self.sink_dropdown.add_css_class("vol-dropdown")
        self.sink_dropdown.connect("notify::selected", self._on_sink_selected)
        out_card.append(self.sink_dropdown)

        self.output_ch = MixerChannel(
            apply_fn=self._apply_default_sink_volume,
            on_mute_click=self._toggle_default_sink_mute,
            on_live_change=self._on_output_live_change,
        )
        out_card.append(self.output_ch.row)
        card.append(out_card)

        # Applications Card
        self.apps_card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.apps_card.add_css_class("vol-card")
        self.apps_card.set_visible(False)

        apps_hdr = Gtk.Label(label="APPLICATIONS", xalign=0)
        apps_hdr.add_css_class("vol-section-title")
        self.apps_card.append(apps_hdr)

        scrolled = Gtk.ScrolledWindow()
        scrolled.add_css_class("vol-scroll")
        scrolled.set_overlay_scrolling(False)
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scrolled.set_max_content_height(260)
        scrolled.set_propagate_natural_height(True)

        self.apps_list_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=12)
        scrolled.set_child(self.apps_list_box)
        self.apps_card.append(scrolled)
        card.append(self.apps_card)

    # ── Popup Lifecycle ──────────────────────────────────────────────────────

    def show_popup(self) -> None:
        if self.win is None:
            return
        self.refresh_state()
        self.win.present()

    def hide_popup(self) -> None:
        if self.win is None:
            return
        self.win.set_visible(False)

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

    def _open_pavucontrol(self) -> None:
        self.hide_popup()
        try:
            subprocess.Popen(
                ["pavucontrol"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
        except Exception:
            pass

    # ── PipeWire / Pulse Event Stream ────────────────────────────────────────

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
                    if " on sink" in low or " on server" in low:
                        GLib.idle_add(self._schedule_refresh)
                proc.wait()
            except Exception:
                pass
            if not self._pactl_stop.is_set():
                time.sleep(1.0)

    def _schedule_refresh(self) -> bool:
        if self._sync_timer_id is None:
            self._sync_timer_id = GLib.timeout_add(60, self._debounced_refresh)
        return GLib.SOURCE_REMOVE

    def _debounced_refresh(self) -> bool:
        self._sync_timer_id = None
        self.refresh_state()
        return GLib.SOURCE_REMOVE

    def refresh_state(self) -> None:
        def _fetch() -> None:
            default_sink = ""
            sinks: list[dict[str, Any]] = []
            inputs: list[dict[str, Any]] = []
            try:
                default_sink = subprocess.check_output(
                    ["pactl", "get-default-sink"],
                    stderr=subprocess.DEVNULL,
                    text=True,
                    timeout=1.5,
                ).strip()
            except Exception:
                pass
            try:
                sinks_raw = subprocess.check_output(
                    ["pactl", "-f", "json", "list", "sinks"],
                    stderr=subprocess.DEVNULL,
                    text=True,
                    timeout=2.0,
                )
                sinks = json.loads(sinks_raw)
            except Exception:
                pass
            try:
                inputs_raw = subprocess.check_output(
                    ["pactl", "-f", "json", "list", "sink-inputs"],
                    stderr=subprocess.DEVNULL,
                    text=True,
                    timeout=2.0,
                )
                inputs = json.loads(inputs_raw)
            except Exception:
                pass

            GLib.idle_add(self._apply_state, default_sink, sinks, inputs)

        threading.Thread(target=_fetch, daemon=True).start()

    def _apply_state(
        self,
        default_sink: str,
        sinks: list[dict[str, Any]],
        inputs: list[dict[str, Any]],
    ) -> bool:
        self._default_sink_name = default_sink

        # Update Sink Dropdown
        sig = [(str(s.get("name", "")), str(s.get("description") or s.get("name", ""))) for s in sinks]
        self._updating_ui = True
        try:
            if sig != self._sink_signature:
                self._sink_signature = sig
                self._sink_names = [n for n, _d in sig]
                while self.sink_model.get_n_items() > 0:
                    self.sink_model.remove(0)
                for _n, desc in sig:
                    self.sink_model.append(desc)
            if default_sink in self._sink_names:
                idx = self._sink_names.index(default_sink)
                if self.sink_dropdown.get_selected() != idx:
                    self.sink_dropdown.set_selected(idx)
        finally:
            self._updating_ui = False

        # Update Output Slider
        active_sink = next((s for s in sinks if s.get("name") == default_sink), None)
        if active_sink is None and sinks:
            active_sink = sinks[0]
        if active_sink is not None:
            pct = _extract_pct(active_sink.get("volume", {}))
            muted = bool(active_sink.get("mute", False))
            self.output_ch.sync_from_system(pct, muted)
            if time.monotonic() >= self.output_ch._suppress_until:
                self._on_output_live_change(pct, muted)

        # Update Application Streams
        self._sync_app_rows(inputs)
        return GLib.SOURCE_REMOVE

    def _on_output_live_change(self, pct: int, muted: bool) -> None:
        if muted:
            self.out_badge_lbl.set_text(f"Muted • {pct}%")
            self.out_badge_lbl.add_css_class("muted")
        else:
            self.out_badge_lbl.set_text(f"{pct}%")
            self.out_badge_lbl.remove_css_class("muted")

    def _sync_app_rows(self, inputs: list[dict[str, Any]]) -> None:
        new_order = [int(item["index"]) for item in inputs if "index" in item]
        if new_order != self._app_order:
            for item in self._app_rows.values():
                item["channel"].stop()
            self._app_rows.clear()
            child = self.apps_list_box.get_first_child()
            while child is not None:
                nxt = child.get_next_sibling()
                self.apps_list_box.remove(child)
                child = nxt

            for inp in inputs:
                if "index" not in inp:
                    continue
                idx = int(inp["index"])
                row_data = self._create_app_row(idx)
                self._app_rows[idx] = row_data
                self.apps_list_box.append(row_data["box"])
            self._app_order = new_order

        for inp in inputs:
            if "index" not in inp:
                continue
            idx = int(inp["index"])
            row_data = self._app_rows.get(idx)
            if row_data is None:
                continue
            props = inp.get("properties", {}) or {}
            app_name = str(props.get("application.name") or "Application").strip()
            media_name = str(props.get("media.name") or "").strip()
            if media_name and media_name.lower() != app_name.lower():
                title = media_name
                sub = app_name
            else:
                title = app_name
                sub = ""
            row_data["title_lbl"].set_text(title)
            row_data["sub_lbl"].set_text(sub)
            row_data["sub_lbl"].set_visible(bool(sub))

            pct = _extract_pct(inp.get("volume", {}))
            muted = bool(inp.get("mute", False))
            row_data["channel"].sync_from_system(pct, muted)

        self.apps_card.set_visible(len(self._app_order) > 0)

    def _create_app_row(self, stream_idx: int) -> dict[str, Any]:
        box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)

        hdr = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        hdr.set_valign(Gtk.Align.CENTER)

        title_lbl = Gtk.Label(label="", xalign=0)
        title_lbl.add_css_class("vol-title")
        title_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        title_lbl.set_hexpand(True)
        hdr.append(title_lbl)

        sub_lbl = Gtk.Label(label="", xalign=1)
        sub_lbl.add_css_class("vol-sub")
        sub_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        hdr.append(sub_lbl)
        box.append(hdr)

        ch = MixerChannel(
            apply_fn=lambda pct, i=stream_idx: self._apply_stream_volume(i, pct),
            on_mute_click=lambda i=stream_idx: self._toggle_stream_mute(i),
        )
        box.append(ch.row)

        return {
            "box": box,
            "title_lbl": title_lbl,
            "sub_lbl": sub_lbl,
            "channel": ch,
        }

    # ── Audio Control Actions ────────────────────────────────────────────────

    def _on_sink_selected(self, dropdown: Gtk.DropDown, _pspec: Any) -> None:
        if self._updating_ui:
            return
        idx = int(dropdown.get_selected())
        if 0 <= idx < len(self._sink_names):
            sink_name = self._sink_names[idx]
            threading.Thread(
                target=lambda: subprocess.run(
                    ["pactl", "set-default-sink", sink_name],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    check=False,
                ),
                daemon=True,
            ).start()

    def _apply_default_sink_volume(self, pct: int) -> None:
        clamped = max(0, min(150, int(pct)))
        if clamped > 0 and self.output_ch._muted:
            subprocess.run(
                ["pactl", "set-sink-mute", "@DEFAULT_SINK@", "0"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
        subprocess.run(
            ["pactl", "set-sink-volume", "@DEFAULT_SINK@", f"{clamped}%"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )

    def _toggle_default_sink_mute(self) -> None:
        def _work() -> None:
            subprocess.run(
                ["pactl", "set-sink-mute", "@DEFAULT_SINK@", "toggle"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            GLib.idle_add(self.refresh_state)

        threading.Thread(target=_work, daemon=True).start()

    def _apply_stream_volume(self, idx: int, pct: int) -> None:
        clamped = max(0, min(150, int(pct)))
        subprocess.run(
            ["pactl", "set-sink-input-volume", str(idx), f"{clamped}%"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            check=False,
        )

    def _toggle_stream_mute(self, idx: int) -> None:
        def _work() -> None:
            subprocess.run(
                ["pactl", "set-sink-input-mute", str(idx), "toggle"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            )
            GLib.idle_add(self.refresh_state)

        threading.Thread(target=_work, daemon=True).start()


def main(argv: Optional[list[str]] = None) -> int:
    app = VolumeWidgetApp()
    return app.run(argv if argv is not None else sys.argv)


if __name__ == "__main__":
    sys.exit(main())
