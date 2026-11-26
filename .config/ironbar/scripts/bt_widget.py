#!/usr/bin/env python3
"""
Single-instance GTK4 + gtk4-layer-shell Bluetooth popup widget for Ironbar.
Inspired by Blueberry and styled in Ironbar's Android M3 Purplish palette.
"""

from __future__ import annotations

from ctypes import CDLL

# Must be loaded before importing GTK/Gdk/Gtk4LayerShell
CDLL("libgtk4-layer-shell.so")

import os
import signal
import subprocess
import sys
import threading
from typing import Any, Callable, Optional

import gi

gi.require_version("Gtk", "4.0")
gi.require_version("Gdk", "4.0")
gi.require_version("Pango", "1.0")
gi.require_version("Graphene", "1.0")
gi.require_version("Gtk4LayerShell", "1.0")
from gi.repository import Gdk, Gio, GLib, Graphene, Gtk, Gtk4LayerShell, Pango  # noqa: E402

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import bt_backend  # noqa: E402

APP_ID = "dev.ironbar.bluetooth"
CSS_PATH = os.path.join(SCRIPT_DIR, "bt_widget.css")
SCAN_DURATION_SECONDS = 20


class BluetoothWidgetApp(Gtk.Application):
    def __init__(self) -> None:
        super().__init__(
            application_id=APP_ID,
            flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE,
        )
        self.manager: Optional[bt_backend.BluezManager] = None
        self.agent: Optional[bt_backend.BluezAgent] = None
        self.win: Optional[Gtk.ApplicationWindow] = None
        self.root_box: Optional[Gtk.Box] = None
        self.card: Optional[Gtk.Box] = None

        self._held = False
        self._updating_ui = False
        self._dbus_subs: list[int] = []
        self._refresh_timer_id: Optional[int] = None
        self._scan_timer_id: Optional[int] = None
        self._scan_remaining: int = 0
        self._ui_scan_active: bool = False
        self._banner_hide_timer_id: Optional[int] = None

        self._worker_lock = threading.Lock()
        self._worker_running = False
        self._worker_cancel: Optional[threading.Event] = None
        self._pending_confirm_cb: Optional[Callable[[bool], None]] = None

        self.snapshot: dict[str, Any] = {"adapter": None, "devices": []}
        self.selected_mac: Optional[str] = None
        self.show_unnamed: bool = False
        self.search_text: str = ""

        # Row caches for flicker-free updates
        self._my_row_widgets: dict[str, dict[str, Any]] = {}
        self._my_row_order: list[str] = []
        self._nearby_row_widgets: dict[str, dict[str, Any]] = {}
        self._nearby_row_order: list[str] = []

    def do_startup(self) -> None:
        Gtk.Application.do_startup(self)
        if not self._held:
            self.hold()
            self._held = True

        self._load_css()
        self.manager = bt_backend.BluezManager()
        self.agent = bt_backend.BluezAgent(
            self.manager.bus,
            self.manager,
            on_confirm=self._on_agent_confirm,
            on_display_code=self._on_agent_display_code,
        )
        self.agent.register()

        self._build_window()
        self._subscribe_bluez()
        self.refresh_state()

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
        if self._worker_cancel is not None:
            self._worker_cancel.set()
        if self._ui_scan_active:
            self._stop_ui_scan(quiet=True)
        if self.manager:
            for sid in self._dbus_subs:
                try:
                    self.manager.bus.signal_unsubscribe(sid)
                except Exception:
                    pass
            self._dbus_subs.clear()
        if self.agent:
            self.agent.unregister()
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
        win.set_title("Bluetooth")
        win.add_css_class("bt-window")

        Gtk4LayerShell.init_for_window(win)
        Gtk4LayerShell.set_namespace(win, "ironbar-bluetooth")
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
        root.add_css_class("bt-backdrop")

        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        card.set_halign(Gtk.Align.END)
        card.set_valign(Gtk.Align.START)
        card.set_margin_top(40)
        card.set_margin_end(10)
        card.set_size_request(368, -1)
        card.add_css_class("bt-popup")

        root.append(card)
        win.set_child(root)

        # Click outside card dismisses popup
        click = Gtk.GestureClick.new()
        click.set_button(0)
        click.connect("pressed", self._on_backdrop_click)
        root.add_controller(click)

        # Escape navigates back or hides popup
        key_ctrl = Gtk.EventControllerKey.new()
        key_ctrl.connect("key-pressed", self._on_key_pressed)
        win.add_controller(key_ctrl)

        self.win = win
        self.root_box = root
        self.card = card

        self._build_header(card)
        self._build_banner(card)
        self._build_stack(card)

    def _build_header(self, parent: Gtk.Box) -> None:
        header = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        header.add_css_class("bt-header-card")

        self.power_switch = Gtk.Switch()
        self.power_switch.add_css_class("bt-switch")
        self.power_switch.set_valign(Gtk.Align.CENTER)
        self.power_switch.set_tooltip_text("Toggle Bluetooth power")
        self.power_switch.connect("notify::active", self._on_power_switch_changed)
        header.append(self.power_switch)

        title_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        title_box.set_hexpand(True)
        title_box.set_valign(Gtk.Align.CENTER)

        title_lbl = Gtk.Label(label="Bluetooth", xalign=0)
        title_lbl.add_css_class("bt-title")
        title_box.append(title_lbl)

        self.header_sub_lbl = Gtk.Label(label="", xalign=0)
        self.header_sub_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        self.header_sub_lbl.add_css_class("bt-subtitle")
        title_box.append(self.header_sub_lbl)
        header.append(title_box)

        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        actions.set_valign(Gtk.Align.CENTER)

        self.scan_btn = Gtk.Button(label="󰑐")
        self.scan_btn.add_css_class("bt-icon-btn")
        self.scan_btn.set_tooltip_text("Scan for nearby devices")
        self.scan_btn.connect("clicked", lambda _b: self._toggle_scan())
        actions.append(self.scan_btn)

        self.add_mac_btn = Gtk.Button(label="󰐕")
        self.add_mac_btn.add_css_class("bt-icon-btn")
        self.add_mac_btn.set_tooltip_text("Connect new device by MAC address")
        self.add_mac_btn.connect("clicked", lambda _b: self._open_add_mac_page())
        actions.append(self.add_mac_btn)

        self.vis_btn = Gtk.Button(label="󰂰")
        self.vis_btn.add_css_class("bt-icon-btn")
        self.vis_btn.set_tooltip_text("Toggle device visibility")
        self.vis_btn.connect("clicked", lambda _b: self._toggle_discoverable())
        actions.append(self.vis_btn)

        blueberry_btn = Gtk.Button(label="󰒓")
        blueberry_btn.add_css_class("bt-icon-btn")
        blueberry_btn.set_tooltip_text("Open Blueberry")
        blueberry_btn.connect("clicked", lambda _b: self._launch_detached(["blueberry"]))
        actions.append(blueberry_btn)

        header.append(actions)
        parent.append(header)

    def _build_banner(self, parent: Gtk.Box) -> None:
        revealer = Gtk.Revealer()
        revealer.set_transition_type(Gtk.RevealerTransitionType.SLIDE_DOWN)
        revealer.set_reveal_child(False)

        banner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        banner.add_css_class("bt-banner")
        banner.add_css_class("info")

        top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        top.set_valign(Gtk.Align.CENTER)

        self.banner_spinner = Gtk.Spinner()
        self.banner_spinner.set_visible(False)
        top.append(self.banner_spinner)

        self.banner_icon = Gtk.Label(label="󰂯")
        self.banner_icon.set_visible(False)
        top.append(self.banner_icon)

        self.banner_label = Gtk.Label(label="", xalign=0)
        self.banner_label.set_wrap(True)
        self.banner_label.set_wrap_mode(Pango.WrapMode.WORD_CHAR)
        self.banner_label.set_hexpand(True)
        self.banner_label.add_css_class("bt-banner-text")
        top.append(self.banner_label)

        self.banner_cancel_btn = Gtk.Button(label="✕")
        self.banner_cancel_btn.add_css_class("bt-chip")
        self.banner_cancel_btn.set_tooltip_text("Cancel / Dismiss")
        self.banner_cancel_btn.connect("clicked", self._on_banner_cancel)
        top.append(self.banner_cancel_btn)
        banner.append(top)

        self.confirm_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.confirm_box.set_halign(Gtk.Align.END)
        self.confirm_box.set_visible(False)

        reject_btn = Gtk.Button(label="Reject")
        reject_btn.add_css_class("bt-btn-danger")
        reject_btn.add_css_class("bt-btn-small")
        reject_btn.connect("clicked", lambda _b: self._resolve_confirm(False))
        self.confirm_box.append(reject_btn)

        accept_btn = Gtk.Button(label="Confirm")
        accept_btn.add_css_class("bt-btn-primary")
        accept_btn.add_css_class("bt-btn-small")
        accept_btn.connect("clicked", lambda _b: self._resolve_confirm(True))
        self.confirm_box.append(accept_btn)
        banner.append(self.confirm_box)

        revealer.set_child(banner)
        parent.append(revealer)

        self.banner_revealer = revealer
        self.banner_box = banner

    def _build_stack(self, parent: Gtk.Box) -> None:
        stack = Gtk.Stack()
        stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        stack.set_transition_duration(180)
        stack.set_vhomogeneous(False)

        self.stack = stack
        self._build_list_page(stack)
        self._build_details_page(stack)
        self._build_add_mac_page(stack)
        parent.append(stack)

    def _build_list_page(self, stack: Gtk.Stack) -> None:
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)

        # Off-state card
        off_card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        off_card.add_css_class("bt-card")
        off_card.set_halign(Gtk.Align.FILL)

        off_icon = Gtk.Label(label="󰂲")
        off_icon.add_css_class("bt-hero-icon")
        off_icon.set_halign(Gtk.Align.CENTER)
        off_icon.set_margin_top(6)
        off_card.append(off_icon)

        off_title = Gtk.Label(label="Bluetooth is off")
        off_title.add_css_class("bt-title")
        off_title.set_halign(Gtk.Align.CENTER)
        off_card.append(off_title)

        off_desc = Gtk.Label(
            label="Turn on Bluetooth to connect headsets, keyboards, and nearby devices."
        )
        off_desc.add_css_class("bt-muted")
        off_desc.set_wrap(True)
        off_desc.set_justify(Gtk.Justification.CENTER)
        off_desc.set_halign(Gtk.Align.CENTER)
        off_card.append(off_desc)

        turn_on_btn = Gtk.Button(label="Turn On Bluetooth")
        turn_on_btn.add_css_class("bt-btn-primary")
        turn_on_btn.set_halign(Gtk.Align.CENTER)
        turn_on_btn.set_margin_top(4)
        turn_on_btn.set_margin_bottom(6)
        turn_on_btn.connect("clicked", lambda _b: self._set_power(True))
        off_card.append(turn_on_btn)

        self.off_card = off_card
        page.append(off_card)

        # On-state container
        on_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.on_box = on_box

        self.search_entry = Gtk.Entry()
        self.search_entry.set_placeholder_text("Search devices or paste MAC...")
        self.search_entry.add_css_class("bt-entry")
        self.search_entry.connect("changed", self._on_search_changed)
        self.search_entry.connect("activate", self._on_search_activate)
        on_box.append(self.search_entry)

        self.quick_mac_btn = Gtk.Button(label="")
        self.quick_mac_btn.add_css_class("bt-btn-primary")
        self.quick_mac_btn.set_visible(False)
        self.quick_mac_btn.connect("clicked", self._on_quick_mac_clicked)
        on_box.append(self.quick_mac_btn)

        scrolled = Gtk.ScrolledWindow()
        scrolled.add_css_class("bt-scroll")
        scrolled.set_overlay_scrolling(False)
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scrolled.set_max_content_height(420)
        scrolled.set_propagate_natural_height(True)

        lists_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        lists_box.set_margin_bottom(2)

        # My Devices
        self.my_section_lbl = Gtk.Label(label="MY DEVICES", xalign=0)
        self.my_section_lbl.add_css_class("bt-section-title")
        lists_box.append(self.my_section_lbl)

        self.my_list_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        lists_box.append(self.my_list_box)

        self.my_empty_lbl = Gtk.Label(label="No paired devices yet", xalign=0)
        self.my_empty_lbl.add_css_class("bt-muted")
        self.my_empty_lbl.set_visible(False)
        lists_box.append(self.my_empty_lbl)

        # Nearby Devices Header
        nearby_hdr = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        nearby_hdr.set_valign(Gtk.Align.CENTER)
        nearby_hdr.set_margin_top(2)

        nearby_lbl = Gtk.Label(label="NEARBY DEVICES", xalign=0)
        nearby_lbl.add_css_class("bt-section-title")
        nearby_lbl.set_hexpand(True)
        nearby_hdr.append(nearby_lbl)

        self.unnamed_toggle = Gtk.ToggleButton(label="Show unnamed")
        self.unnamed_toggle.add_css_class("bt-chip")
        self.unnamed_toggle.set_active(False)
        self.unnamed_toggle.connect("toggled", self._on_unnamed_toggled)
        nearby_hdr.append(self.unnamed_toggle)

        self.nearby_scan_btn = Gtk.Button(label="Scan")
        self.nearby_scan_btn.add_css_class("bt-chip")
        self.nearby_scan_btn.connect("clicked", lambda _b: self._toggle_scan())
        nearby_hdr.append(self.nearby_scan_btn)

        lists_box.append(nearby_hdr)

        self.nearby_list_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        lists_box.append(self.nearby_list_box)

        self.nearby_empty_lbl = Gtk.Label(
            label="Click Scan or + to find new devices", xalign=0
        )
        self.nearby_empty_lbl.add_css_class("bt-muted")
        self.nearby_empty_lbl.set_wrap(True)
        lists_box.append(self.nearby_empty_lbl)

        scrolled.set_child(lists_box)
        on_box.append(scrolled)
        page.append(on_box)

        stack.add_named(page, "list")

    def _build_details_page(self, stack: Gtk.Stack) -> None:
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)

        top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        top.set_valign(Gtk.Align.CENTER)

        back_btn = Gtk.Button(label="← Back")
        back_btn.add_css_class("bt-btn-secondary")
        back_btn.add_css_class("bt-btn-small")
        back_btn.connect("clicked", lambda _b: self._go_to_list())
        top.append(back_btn)

        title = Gtk.Label(label="Device Details", xalign=0)
        title.add_css_class("bt-title")
        title.set_hexpand(True)
        top.append(title)
        page.append(top)

        # Hero Card
        hero = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        hero.add_css_class("bt-card")

        self.detail_hero_icon = Gtk.Label(label="󰂯")
        self.detail_hero_icon.add_css_class("bt-hero-icon")
        self.detail_hero_icon.set_halign(Gtk.Align.CENTER)
        hero.append(self.detail_hero_icon)

        self.detail_name_lbl = Gtk.Label(label="")
        self.detail_name_lbl.add_css_class("bt-title")
        self.detail_name_lbl.set_wrap(True)
        self.detail_name_lbl.set_justify(Gtk.Justification.CENTER)
        self.detail_name_lbl.set_halign(Gtk.Align.CENTER)
        hero.append(self.detail_name_lbl)

        self.detail_bat_lbl = Gtk.Label(label="")
        self.detail_bat_lbl.add_css_class("bt-badge")
        self.detail_bat_lbl.set_halign(Gtk.Align.CENTER)
        self.detail_bat_lbl.set_visible(False)
        hero.append(self.detail_bat_lbl)
        page.append(hero)

        # Info Table Card
        info = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        info.add_css_class("bt-details-card")

        # Connection row
        conn_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        conn_key = Gtk.Label(label="Connection", xalign=0)
        conn_key.add_css_class("bt-detail-key")
        conn_key.set_hexpand(True)
        conn_row.append(conn_key)
        self.detail_conn_switch = Gtk.Switch()
        self.detail_conn_switch.add_css_class("bt-switch")
        self.detail_conn_switch.connect("notify::active", self._on_detail_conn_changed)
        conn_row.append(self.detail_conn_switch)
        info.append(conn_row)

        info.append(self._make_divider())

        # Paired row
        paired_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        p_key = Gtk.Label(label="Paired", xalign=0)
        p_key.add_css_class("bt-detail-key")
        p_key.set_hexpand(True)
        paired_row.append(p_key)
        self.detail_paired_lbl = Gtk.Label(label="No", xalign=1)
        self.detail_paired_lbl.add_css_class("bt-detail-val")
        paired_row.append(self.detail_paired_lbl)
        info.append(paired_row)

        info.append(self._make_divider())

        # Trusted row
        trust_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        t_key = Gtk.Label(label="Trusted", xalign=0)
        t_key.add_css_class("bt-detail-key")
        t_key.set_hexpand(True)
        trust_row.append(t_key)
        self.detail_trust_switch = Gtk.Switch()
        self.detail_trust_switch.add_css_class("bt-switch")
        self.detail_trust_switch.connect("notify::active", self._on_detail_trust_changed)
        trust_row.append(self.detail_trust_switch)
        info.append(trust_row)

        info.append(self._make_divider())

        # Type row
        type_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        ty_key = Gtk.Label(label="Type", xalign=0)
        ty_key.add_css_class("bt-detail-key")
        ty_key.set_hexpand(True)
        type_row.append(ty_key)
        self.detail_type_lbl = Gtk.Label(label="Bluetooth Device", xalign=1)
        self.detail_type_lbl.add_css_class("bt-detail-val")
        type_row.append(self.detail_type_lbl)
        info.append(type_row)

        info.append(self._make_divider())

        # Address row
        addr_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        a_key = Gtk.Label(label="Address", xalign=0)
        a_key.add_css_class("bt-detail-key")
        a_key.set_hexpand(True)
        addr_row.append(a_key)
        self.detail_addr_lbl = Gtk.Label(label="", xalign=1)
        self.detail_addr_lbl.add_css_class("bt-detail-val")
        addr_row.append(self.detail_addr_lbl)
        copy_btn = Gtk.Button(label="󰆏")
        copy_btn.add_css_class("bt-chip")
        copy_btn.set_tooltip_text("Copy MAC address")
        copy_btn.connect("clicked", self._on_copy_detail_mac)
        addr_row.append(copy_btn)
        info.append(addr_row)

        # Signal row (hidden when RSSI unavailable)
        self.detail_rssi_div = self._make_divider()
        info.append(self.detail_rssi_div)

        self.detail_rssi_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        r_key = Gtk.Label(label="Signal", xalign=0)
        r_key.add_css_class("bt-detail-key")
        r_key.set_hexpand(True)
        self.detail_rssi_row.append(r_key)
        self.detail_rssi_lbl = Gtk.Label(label="", xalign=1)
        self.detail_rssi_lbl.add_css_class("bt-detail-val")
        self.detail_rssi_row.append(self.detail_rssi_lbl)
        info.append(self.detail_rssi_row)

        page.append(info)

        # Actions
        actions = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)

        force_btn = Gtk.Button(label="󰑐  Force Reconnect (Reset & Re-pair)")
        force_btn.add_css_class("bt-btn-primary")
        force_btn.connect("clicked", self._on_detail_force_reconnect)
        actions.append(force_btn)

        sound_btn = Gtk.Button(label="󰕾  Sound Settings")
        sound_btn.add_css_class("bt-btn-secondary")
        sound_btn.connect("clicked", lambda _b: self._launch_detached(["pavucontrol"]))
        actions.append(sound_btn)

        remove_btn = Gtk.Button(label="󰆴  Remove Device")
        remove_btn.add_css_class("bt-btn-danger")
        remove_btn.connect("clicked", self._on_detail_remove)
        actions.append(remove_btn)

        page.append(actions)
        stack.add_named(page, "details")

    def _build_add_mac_page(self, stack: Gtk.Stack) -> None:
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)

        top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        top.set_valign(Gtk.Align.CENTER)

        back_btn = Gtk.Button(label="← Back")
        back_btn.add_css_class("bt-btn-secondary")
        back_btn.add_css_class("bt-btn-small")
        back_btn.connect("clicked", lambda _b: self._go_to_list())
        top.append(back_btn)

        title = Gtk.Label(label="Add Device by MAC", xalign=0)
        title.add_css_class("bt-title")
        title.set_hexpand(True)
        top.append(title)
        page.append(top)

        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        card.add_css_class("bt-card")

        desc = Gtk.Label(
            label="Enter a Bluetooth MAC address to scan, pair, trust, and connect directly.",
            xalign=0,
        )
        desc.add_css_class("bt-muted")
        desc.set_wrap(True)
        card.append(desc)

        self.mac_entry = Gtk.Entry()
        self.mac_entry.set_placeholder_text("E3:5F:23:22:BF:DD")
        self.mac_entry.add_css_class("bt-entry")
        self.mac_entry.connect("changed", self._on_mac_entry_changed)
        self.mac_entry.connect("activate", lambda _e: self._on_mac_connect_clicked())
        card.append(self.mac_entry)

        self.mac_status_lbl = Gtk.Label(
            label="Formats: AA:BB:CC:DD:EE:FF, AA-BB-..., or 12 hex chars",
            xalign=0,
        )
        self.mac_status_lbl.add_css_class("bt-subtitle")
        card.append(self.mac_status_lbl)

        retry_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        retry_row.set_valign(Gtk.Align.CENTER)
        retry_lbl = Gtk.Label(
            label="Forget & retry on failure (2 attempts)", xalign=0
        )
        retry_lbl.add_css_class("bt-muted")
        retry_lbl.set_wrap(True)
        retry_lbl.set_hexpand(True)
        retry_row.append(retry_lbl)

        self.mac_retry_switch = Gtk.Switch()
        self.mac_retry_switch.add_css_class("bt-switch")
        self.mac_retry_switch.set_active(True)
        retry_row.append(self.mac_retry_switch)
        card.append(retry_row)

        self.mac_connect_btn = Gtk.Button(label="󰂯  Scan & Connect")
        self.mac_connect_btn.add_css_class("bt-btn-primary")
        self.mac_connect_btn.set_sensitive(False)
        self.mac_connect_btn.connect("clicked", lambda _b: self._on_mac_connect_clicked())
        card.append(self.mac_connect_btn)

        page.append(card)

        self.recent_title_lbl = Gtk.Label(label="RECENTLY SEEN NEARBY", xalign=0)
        self.recent_title_lbl.add_css_class("bt-section-title")
        page.append(self.recent_title_lbl)

        self.recent_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        page.append(self.recent_box)

        stack.add_named(page, "add_mac")

    def _make_divider(self) -> Gtk.Box:
        div = Gtk.Box()
        div.add_css_class("bt-divider")
        return div

    # ── Popup Visibility & Navigation ────────────────────────────────────────

    def show_popup(self) -> None:
        if self.win is None:
            return
        self.refresh_state()
        self.win.present()

    def hide_popup(self) -> None:
        if self.win is None:
            return
        if self._ui_scan_active:
            self._stop_ui_scan(quiet=True)
        self._updating_ui = True
        self.search_entry.set_text("")
        self._updating_ui = False
        self.search_text = ""
        self.quick_mac_btn.set_visible(False)
        self.selected_mac = None
        self.stack.set_visible_child_name("list")
        self.win.set_visible(False)

    def _go_to_list(self) -> None:
        self.selected_mac = None
        self.stack.set_visible_child_name("list")
        self._render_snapshot()

    def _open_details(self, mac: str) -> None:
        self.selected_mac = mac
        self._render_details_page()
        self.stack.set_visible_child_name("details")

    def _open_add_mac_page(self, prefill: str = "") -> None:
        self._render_recent_nearby()
        if prefill:
            self.mac_entry.set_text(prefill)
        else:
            self._on_mac_entry_changed(self.mac_entry)
        self.stack.set_visible_child_name("add_mac")
        self.mac_entry.grab_focus()

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
            cur = self.stack.get_visible_child_name()
            if cur in ("details", "add_mac"):
                self._go_to_list()
            else:
                self.hide_popup()
            return True
        return False

    def _launch_detached(self, cmd: list[str]) -> None:
        try:
            subprocess.Popen(
                cmd,
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                start_new_session=True,
            )
            self.hide_popup()
        except Exception as exc:
            self._show_banner(f"Failed to launch {cmd[0]}: {exc}", kind="error", auto_hide=4000)

    # ── BlueZ D-Bus Live Subscription ────────────────────────────────────────

    def _subscribe_bluez(self) -> None:
        if self.manager is None:
            return
        bus = self.manager.bus
        self._dbus_subs.extend(
            [
                bus.signal_subscribe(
                    bt_backend.BLUEZ_SERVICE,
                    bt_backend.DBUS_PROPS_IFACE,
                    "PropertiesChanged",
                    None,
                    None,
                    Gio.DBusSignalFlags.NONE,
                    self._on_bluez_signal,
                ),
                bus.signal_subscribe(
                    bt_backend.BLUEZ_SERVICE,
                    bt_backend.DBUS_OM_IFACE,
                    "InterfacesAdded",
                    None,
                    None,
                    Gio.DBusSignalFlags.NONE,
                    self._on_bluez_signal,
                ),
                bus.signal_subscribe(
                    bt_backend.BLUEZ_SERVICE,
                    bt_backend.DBUS_OM_IFACE,
                    "InterfacesRemoved",
                    None,
                    None,
                    Gio.DBusSignalFlags.NONE,
                    self._on_bluez_signal,
                ),
            ]
        )

    def _on_bluez_signal(self, *_args: Any) -> None:
        if self._refresh_timer_id is not None:
            return
        self._refresh_timer_id = GLib.timeout_add(150, self._debounced_refresh)

    def _debounced_refresh(self) -> bool:
        self._refresh_timer_id = None
        self.refresh_state()
        return GLib.SOURCE_REMOVE

    def refresh_state(self) -> None:
        if self.manager is None:
            return
        self.snapshot = self.manager.get_snapshot()
        self._render_snapshot()

    # ── Rendering ────────────────────────────────────────────────────────────

    def _render_snapshot(self) -> None:
        adapter = self.snapshot.get("adapter")
        devices: list[dict[str, Any]] = self.snapshot.get("devices", [])

        self._updating_ui = True
        try:
            if not adapter:
                self.power_switch.set_active(False)
                self.power_switch.set_sensitive(False)
                self.header_sub_lbl.set_text("No Bluetooth adapter found")
                self.scan_btn.set_sensitive(False)
                self.add_mac_btn.set_sensitive(False)
                self.vis_btn.set_sensitive(False)
                self.off_card.set_visible(True)
                self.on_box.set_visible(False)
                return

            powered = bool(adapter.get("powered"))
            discoverable = bool(adapter.get("discoverable"))
            alias = adapter.get("alias") or "Bluetooth"

            self.power_switch.set_sensitive(True)
            self.power_switch.set_active(powered)

            if not powered:
                self.header_sub_lbl.set_text("Bluetooth is off")
            elif discoverable:
                self.header_sub_lbl.set_text(f'Visible as "{alias}"')
            else:
                self.header_sub_lbl.set_text(f"Hidden • {alias}")

            self.scan_btn.set_sensitive(powered)
            self.add_mac_btn.set_sensitive(True)
            self.vis_btn.set_sensitive(powered)

            if powered and discoverable:
                self.vis_btn.add_css_class("active")
            else:
                self.vis_btn.remove_css_class("active")

            self._update_scan_buttons()

            self.off_card.set_visible(not powered)
            self.on_box.set_visible(powered)

            if powered:
                self._render_device_lists(devices)
        finally:
            self._updating_ui = False

        cur_page = self.stack.get_visible_child_name()
        if cur_page == "details":
            self._render_details_page()
        elif cur_page == "add_mac":
            self._render_recent_nearby()

    def _update_scan_buttons(self) -> None:
        if self._ui_scan_active:
            self.scan_btn.set_label("󰓛")
            self.scan_btn.add_css_class("active")
            self.scan_btn.set_tooltip_text(f"Stop scan ({self._scan_remaining}s)")
            self.nearby_scan_btn.set_label(f"Stop ({self._scan_remaining}s)")
            self.nearby_scan_btn.add_css_class("active")
        else:
            self.scan_btn.set_label("󰑐")
            self.scan_btn.remove_css_class("active")
            self.scan_btn.set_tooltip_text("Scan for nearby devices")
            self.nearby_scan_btn.set_label("Scan")
            self.nearby_scan_btn.remove_css_class("active")

    def _matches_filter(self, dev: dict[str, Any], query: str) -> bool:
        if not query:
            return True
        q = query.strip().lower()
        name = (dev.get("display_name") or "").lower()
        addr = (dev.get("address") or "").lower()
        dtype = (dev.get("type_label") or "").lower()
        norm_q = bt_backend.normalize_mac(q)
        if norm_q and norm_q.lower() == addr:
            return True
        return q in name or q in addr or q in dtype

    def _render_device_lists(self, devices: list[dict[str, Any]]) -> None:
        query = self.search_text.strip()

        my_devs = [d for d in devices if d.get("paired") or d.get("connected")]
        my_devs.sort(key=lambda d: (not d.get("connected", False), d["display_name"].lower()))
        my_filtered = [d for d in my_devs if self._matches_filter(d, query)]

        nearby_devs = [
            d for d in devices if not d.get("paired") and not d.get("connected")
        ]
        if not self.show_unnamed and not query:
            nearby_devs = [d for d in nearby_devs if not d.get("unnamed")]
        nearby_devs = [d for d in nearby_devs if self._matches_filter(d, query)]
        nearby_devs.sort(
            key=lambda d: (
                d.get("unnamed", False),
                -(d["rssi"] if d.get("rssi") is not None else -999),
                d["display_name"].lower(),
            )
        )

        self._sync_my_devices(my_filtered)
        self.my_empty_lbl.set_visible(len(my_filtered) == 0)

        self._sync_nearby_devices(nearby_filtered := nearby_devs)
        if len(nearby_filtered) == 0:
            if self._ui_scan_active:
                self.nearby_empty_lbl.set_text("Scanning for nearby devices...")
            elif query:
                self.nearby_empty_lbl.set_text("No matching nearby devices")
            else:
                self.nearby_empty_lbl.set_text("Click Scan or + to find new devices")
            self.nearby_empty_lbl.set_visible(True)
        else:
            self.nearby_empty_lbl.set_visible(False)

    def _clear_box(self, box: Gtk.Box) -> None:
        child = box.get_first_child()
        while child is not None:
            nxt = child.get_next_sibling()
            box.remove(child)
            child = nxt

    def _sync_my_devices(self, devs: list[dict[str, Any]]) -> None:
        new_order = [d["address"] for d in devs]
        if new_order != self._my_row_order:
            self._clear_box(self.my_list_box)
            self._my_row_widgets.clear()
            for dev in devs:
                w = self._create_my_row(dev["address"])
                self._my_row_widgets[dev["address"]] = w
                self.my_list_box.append(w["row"])
            self._my_row_order = new_order

        for dev in devs:
            self._update_my_row(self._my_row_widgets[dev["address"]], dev)

    def _create_my_row(self, mac: str) -> dict[str, Any]:
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.add_css_class("bt-device-row")

        click_btn = Gtk.Button()
        click_btn.add_css_class("bt-row-clickable")
        click_btn.set_hexpand(True)
        click_btn.set_tooltip_text("View device details")
        click_btn.connect("clicked", lambda _b, m=mac: self._open_details(m))

        inner = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        inner.set_valign(Gtk.Align.CENTER)

        icon_lbl = Gtk.Label(label="󰂯")
        icon_lbl.add_css_class("bt-device-icon")
        icon_lbl.set_valign(Gtk.Align.CENTER)
        inner.append(icon_lbl)

        text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        text_box.set_hexpand(True)
        text_box.set_valign(Gtk.Align.CENTER)

        name_lbl = Gtk.Label(label="", xalign=0)
        name_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        name_lbl.add_css_class("bt-title")
        text_box.append(name_lbl)

        sub_lbl = Gtk.Label(label="", xalign=0)
        sub_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        sub_lbl.add_css_class("bt-subtitle")
        text_box.append(sub_lbl)

        inner.append(text_box)

        chev = Gtk.Label(label="›")
        chev.add_css_class("bt-chevron")
        inner.append(chev)

        click_btn.set_child(inner)
        row.append(click_btn)

        sw = Gtk.Switch()
        sw.add_css_class("bt-switch")
        sw.set_valign(Gtk.Align.CENTER)
        sw.connect("notify::active", self._on_my_row_switch, mac)
        row.append(sw)

        return {
            "row": row,
            "icon_lbl": icon_lbl,
            "name_lbl": name_lbl,
            "sub_lbl": sub_lbl,
            "switch": sw,
        }

    def _update_my_row(self, w: dict[str, Any], dev: dict[str, Any]) -> None:
        connected = bool(dev.get("connected"))
        w["icon_lbl"].set_label(dev["glyph"])
        if connected:
            w["icon_lbl"].add_css_class("connected")
        else:
            w["icon_lbl"].remove_css_class("connected")

        w["name_lbl"].set_text(dev["display_name"])
        bat = dev.get("battery")
        if connected:
            sub = f"Connected • {bat}%" if bat is not None else "Connected"
        else:
            sub = "Disconnected"
        w["sub_lbl"].set_text(sub)

        if w["switch"].get_active() != connected:
            w["switch"].set_active(connected)

    def _sync_nearby_devices(self, devs: list[dict[str, Any]]) -> None:
        new_order = [d["address"] for d in devs]
        if new_order != self._nearby_row_order:
            self._clear_box(self.nearby_list_box)
            self._nearby_row_widgets.clear()
            for dev in devs:
                w = self._create_nearby_row(dev["address"])
                self._nearby_row_widgets[dev["address"]] = w
                self.nearby_list_box.append(w["row"])
            self._nearby_row_order = new_order

        for dev in devs:
            self._update_nearby_row(self._nearby_row_widgets[dev["address"]], dev)

    def _create_nearby_row(self, mac: str) -> dict[str, Any]:
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        row.add_css_class("bt-device-row")

        icon_lbl = Gtk.Label(label="󰂯")
        icon_lbl.add_css_class("bt-device-icon")
        icon_lbl.set_valign(Gtk.Align.CENTER)
        row.append(icon_lbl)

        text_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        text_box.set_hexpand(True)
        text_box.set_valign(Gtk.Align.CENTER)

        name_lbl = Gtk.Label(label="", xalign=0)
        name_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        name_lbl.add_css_class("bt-title")
        text_box.append(name_lbl)

        sub_lbl = Gtk.Label(label="", xalign=0)
        sub_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        sub_lbl.add_css_class("bt-subtitle")
        text_box.append(sub_lbl)

        row.append(text_box)

        pair_btn = Gtk.Button(label="Pair")
        pair_btn.add_css_class("bt-btn-primary")
        pair_btn.add_css_class("bt-btn-small")
        pair_btn.set_valign(Gtk.Align.CENTER)
        pair_btn.connect("clicked", lambda _b, m=mac: self._start_smart_connect(m))
        row.append(pair_btn)

        return {
            "row": row,
            "icon_lbl": icon_lbl,
            "name_lbl": name_lbl,
            "sub_lbl": sub_lbl,
            "pair_btn": pair_btn,
        }

    def _update_nearby_row(self, w: dict[str, Any], dev: dict[str, Any]) -> None:
        w["icon_lbl"].set_label(dev["glyph"])
        w["name_lbl"].set_text(dev["display_name"])
        rssi = dev.get("rssi")
        if rssi is not None:
            sub = f"{dev['address']} • {rssi} dBm ({dev['rssi_quality']})"
        else:
            sub = dev["address"]
        w["sub_lbl"].set_text(sub)

    def _render_details_page(self) -> None:
        if not self.selected_mac:
            return
        dev = None
        for d in self.snapshot.get("devices", []):
            if d["address"] == self.selected_mac:
                dev = d
                break
        if dev is None:
            self._go_to_list()
            return

        self._updating_ui = True
        try:
            connected = bool(dev.get("connected"))
            self.detail_hero_icon.set_label(dev["glyph"])
            if connected:
                self.detail_hero_icon.add_css_class("connected")
            else:
                self.detail_hero_icon.remove_css_class("connected")

            self.detail_name_lbl.set_text(dev["display_name"])

            bat = dev.get("battery")
            for cls in ("bt-bat-good", "bt-bat-mid", "bt-bat-low"):
                self.detail_bat_lbl.remove_css_class(cls)
            if bat is not None:
                self.detail_bat_lbl.set_text(f"󰥈  Battery {bat}%")
                if bat >= 60:
                    self.detail_bat_lbl.add_css_class("bt-bat-good")
                elif bat >= 25:
                    self.detail_bat_lbl.add_css_class("bt-bat-mid")
                else:
                    self.detail_bat_lbl.add_css_class("bt-bat-low")
                self.detail_bat_lbl.set_visible(True)
            else:
                self.detail_bat_lbl.set_visible(False)

            self.detail_conn_switch.set_active(connected)
            self.detail_paired_lbl.set_text("Yes" if dev.get("paired") else "No")
            self.detail_trust_switch.set_active(bool(dev.get("trusted")))
            self.detail_type_lbl.set_text(dev["type_label"])
            self.detail_addr_lbl.set_text(dev["address"])

            rssi = dev.get("rssi")
            if rssi is not None:
                self.detail_rssi_lbl.set_text(f"{rssi} dBm ({dev['rssi_quality']})")
                self.detail_rssi_div.set_visible(True)
                self.detail_rssi_row.set_visible(True)
            else:
                self.detail_rssi_div.set_visible(False)
                self.detail_rssi_row.set_visible(False)
        finally:
            self._updating_ui = False

    def _render_recent_nearby(self) -> None:
        self._clear_box(self.recent_box)
        nearby = [
            d
            for d in self.snapshot.get("devices", [])
            if not d.get("connected") and not d.get("unnamed")
        ]
        nearby.sort(key=lambda d: (-(d["rssi"] if d.get("rssi") is not None else -999), d["display_name"].lower()))
        nearby = nearby[:4]
        if not nearby:
            self.recent_title_lbl.set_visible(False)
            self.recent_box.set_visible(False)
            return

        self.recent_title_lbl.set_visible(True)
        self.recent_box.set_visible(True)
        for dev in nearby:
            btn = Gtk.Button()
            btn.add_css_class("bt-device-row")
            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            lbl = Gtk.Label(label=f"{dev['glyph']}  {dev['display_name']}", xalign=0)
            lbl.set_ellipsize(Pango.EllipsizeMode.END)
            lbl.set_hexpand(True)
            row.append(lbl)
            mac_lbl = Gtk.Label(label=dev["address"], xalign=1)
            mac_lbl.add_css_class("bt-subtitle")
            row.append(mac_lbl)
            btn.set_child(row)
            btn.connect("clicked", lambda _b, m=dev["address"]: self.mac_entry.set_text(m))
            self.recent_box.append(btn)

    # ── Banner & Pairing Agent Prompts ───────────────────────────────────────

    def _show_banner(
        self,
        text: str,
        kind: str = "info",
        spinning: bool = False,
        auto_hide: int = 0,
        show_confirm: bool = False,
    ) -> None:
        if self._banner_hide_timer_id is not None:
            GLib.source_remove(self._banner_hide_timer_id)
            self._banner_hide_timer_id = None

        for cls in ("info", "success", "error"):
            self.banner_box.remove_css_class(cls)
        self.banner_box.add_css_class(kind)

        self.banner_label.set_text(text)
        self.banner_spinner.set_visible(spinning)
        if spinning:
            self.banner_spinner.start()
            self.banner_icon.set_visible(False)
        else:
            self.banner_spinner.stop()
            icon_map = {"info": "󰂯", "success": "󰄬", "error": "󰅙"}
            self.banner_icon.set_label(icon_map.get(kind, "󰂯"))
            self.banner_icon.set_visible(True)

        self.confirm_box.set_visible(show_confirm)
        self.banner_cancel_btn.set_visible(not show_confirm)
        self.banner_revealer.set_reveal_child(True)

        if auto_hide > 0:
            self._banner_hide_timer_id = GLib.timeout_add(auto_hide, self._auto_hide_banner)

    def _auto_hide_banner(self) -> bool:
        self._banner_hide_timer_id = None
        if not self._worker_running and self._pending_confirm_cb is None:
            self.banner_revealer.set_reveal_child(False)
        return GLib.SOURCE_REMOVE

    def _on_banner_cancel(self, _btn: Gtk.Button) -> None:
        if self._worker_running and self._worker_cancel is not None:
            self._worker_cancel.set()
            self.banner_label.set_text("Cancelling...")
        else:
            self.banner_revealer.set_reveal_child(False)

    def _on_agent_confirm(
        self, dev_path: str, passkey: str, respond: Callable[[bool], None]
    ) -> None:
        def _show() -> bool:
            if self._pending_confirm_cb is not None:
                try:
                    self._pending_confirm_cb(False)
                except Exception:
                    pass
            self._pending_confirm_cb = respond
            mac = dev_path.rsplit("/", 1)[-1].replace("dev_", "").replace("_", ":")
            dev = self.manager.find_device(mac, self.snapshot) if self.manager else None
            label = dev["display_name"] if dev else mac
            self._show_banner(
                f"Confirm pairing with {label} — Passkey: {passkey}",
                kind="info",
                spinning=False,
                show_confirm=True,
            )
            return GLib.SOURCE_REMOVE

        GLib.idle_add(_show)

    def _on_agent_display_code(self, dev_path: str, code: str) -> None:
        def _show() -> bool:
            mac = dev_path.rsplit("/", 1)[-1].replace("dev_", "").replace("_", ":")
            dev = self.manager.find_device(mac, self.snapshot) if self.manager else None
            label = dev["display_name"] if dev else mac
            self._show_banner(
                f"Enter passkey {code} on {label}",
                kind="info",
                spinning=True,
            )
            return GLib.SOURCE_REMOVE

        GLib.idle_add(_show)

    def _resolve_confirm(self, accepted: bool) -> None:
        cb = self._pending_confirm_cb
        self._pending_confirm_cb = None
        self.confirm_box.set_visible(False)
        if cb is not None:
            cb(accepted)
        if accepted:
            self._show_banner("Passkey confirmed — finishing pairing...", kind="info", spinning=True)
        else:
            self._show_banner("Pairing rejected", kind="error", auto_hide=3000)

    # ── Event Handlers & Workers ─────────────────────────────────────────────

    def _on_power_switch_changed(self, sw: Gtk.Switch, _pspec: Any) -> None:
        if self._updating_ui:
            return
        self._set_power(sw.get_active())

    def _set_power(self, on: bool) -> None:
        if self.manager is None:
            return
        if not on and self._ui_scan_active:
            self._stop_ui_scan(quiet=True)

        def _work() -> None:
            ok, msg = self.manager.set_powered(on)
            GLib.idle_add(self._on_quick_action_done, ok, msg)

        threading.Thread(target=_work, daemon=True).start()

    def _toggle_discoverable(self) -> None:
        if self.manager is None:
            return
        adapter = self.snapshot.get("adapter")
        if not adapter or not adapter.get("powered"):
            return
        target = not bool(adapter.get("discoverable"))

        def _work() -> None:
            ok, msg = self.manager.set_discoverable(target)
            GLib.idle_add(self._on_quick_action_done, ok, msg)

        threading.Thread(target=_work, daemon=True).start()

    def _on_quick_action_done(self, ok: bool, msg: str) -> bool:
        self.refresh_state()
        if not ok:
            self._show_banner(msg, kind="error", auto_hide=3500)
        return GLib.SOURCE_REMOVE

    def _toggle_scan(self) -> None:
        if self._ui_scan_active:
            self._stop_ui_scan(quiet=False)
        else:
            self._start_ui_scan()

    def _start_ui_scan(self) -> None:
        if self.manager is None:
            return
        adapter = self.snapshot.get("adapter")
        if not adapter or not adapter.get("powered"):
            return
        if self._worker_running:
            self._show_banner("Wait for current connection attempt to finish", kind="info", auto_hide=2500)
            return

        ok, msg = self.manager.start_discovery()
        if not ok:
            self._show_banner(msg, kind="error", auto_hide=3500)
            return

        self._ui_scan_active = True
        self._scan_remaining = SCAN_DURATION_SECONDS
        self._update_scan_buttons()
        if self._scan_timer_id is not None:
            GLib.source_remove(self._scan_timer_id)
        self._scan_timer_id = GLib.timeout_add(1000, self._on_scan_tick)
        self.refresh_state()

    def _on_scan_tick(self) -> bool:
        if not self._ui_scan_active:
            self._scan_timer_id = None
            return GLib.SOURCE_REMOVE
        self._scan_remaining -= 1
        if self._scan_remaining <= 0:
            self._scan_timer_id = None
            self._stop_ui_scan(quiet=True)
            return GLib.SOURCE_REMOVE
        self._update_scan_buttons()
        return GLib.SOURCE_CONTINUE

    def _stop_ui_scan(self, quiet: bool = False) -> None:
        self._ui_scan_active = False
        if self._scan_timer_id is not None:
            GLib.source_remove(self._scan_timer_id)
            self._scan_timer_id = None
        if self.manager is not None:
            threading.Thread(target=self.manager.stop_discovery, daemon=True).start()
        self._update_scan_buttons()
        if not quiet:
            self.refresh_state()

    def _on_search_changed(self, entry: Gtk.Entry) -> None:
        if self._updating_ui:
            return
        text = entry.get_text()
        self.search_text = text
        norm = bt_backend.normalize_mac(text)
        if norm:
            self.quick_mac_btn.set_label(f"󰂯  Scan & Connect {norm}")
            self.quick_mac_btn.set_visible(True)
        else:
            self.quick_mac_btn.set_visible(False)
        self._render_device_lists(self.snapshot.get("devices", []))

    def _on_search_activate(self, entry: Gtk.Entry) -> None:
        norm = bt_backend.normalize_mac(entry.get_text())
        if norm:
            self._start_force_reconnect(norm)

    def _on_quick_mac_clicked(self, _btn: Gtk.Button) -> None:
        norm = bt_backend.normalize_mac(self.search_entry.get_text())
        if norm:
            self._start_force_reconnect(norm)

    def _on_unnamed_toggled(self, btn: Gtk.ToggleButton) -> None:
        self.show_unnamed = btn.get_active()
        self._render_device_lists(self.snapshot.get("devices", []))

    def _on_my_row_switch(self, sw: Gtk.Switch, _pspec: Any, mac: str) -> None:
        if self._updating_ui:
            return
        if sw.get_active():
            self._start_smart_connect(mac)
        else:
            self._start_disconnect(mac)

    def _on_detail_conn_changed(self, sw: Gtk.Switch, _pspec: Any) -> None:
        if self._updating_ui or not self.selected_mac:
            return
        if sw.get_active():
            self._start_smart_connect(self.selected_mac)
        else:
            self._start_disconnect(self.selected_mac)

    def _on_detail_trust_changed(self, sw: Gtk.Switch, _pspec: Any) -> None:
        if self._updating_ui or not self.selected_mac or self.manager is None:
            return
        mac = self.selected_mac
        trusted = sw.get_active()

        def _work() -> None:
            ok, msg = self.manager.set_trusted(mac, trusted)
            GLib.idle_add(self._on_quick_action_done, ok, msg)

        threading.Thread(target=_work, daemon=True).start()

    def _on_copy_detail_mac(self, _btn: Gtk.Button) -> None:
        if not self.selected_mac:
            return
        display = Gdk.Display.get_default()
        if display is not None:
            display.get_clipboard().set(self.selected_mac)
            self._show_banner(f"Copied {self.selected_mac}", kind="success", auto_hide=2000)

    def _on_detail_force_reconnect(self, _btn: Gtk.Button) -> None:
        if self.selected_mac:
            self._start_force_reconnect(self.selected_mac)

    def _on_detail_remove(self, _btn: Gtk.Button) -> None:
        if not self.selected_mac or self.manager is None:
            return
        mac = self.selected_mac
        self._run_worker(
            f"Removing {mac}...",
            lambda _cb, _cancel: self.manager.remove_device(mac),
            on_success=lambda: self._go_to_list(),
        )

    def _on_mac_entry_changed(self, entry: Gtk.Entry) -> None:
        raw = entry.get_text()
        norm = bt_backend.normalize_mac(raw)
        if not raw.strip():
            self.mac_status_lbl.set_text("Formats: AA:BB:CC:DD:EE:FF, AA-BB-..., or 12 hex chars")
            self.mac_connect_btn.set_sensitive(False)
        elif norm:
            self.mac_status_lbl.set_text(f"✓ Valid MAC: {norm}")
            self.mac_connect_btn.set_sensitive(True)
        else:
            self.mac_status_lbl.set_text("Enter 12 hex digits (e.g. E3:5F:23:22:BF:DD)")
            self.mac_connect_btn.set_sensitive(False)

    def _on_mac_connect_clicked(self) -> None:
        norm = bt_backend.normalize_mac(self.mac_entry.get_text())
        if not norm:
            return
        if self.mac_retry_switch.get_active():
            self._start_force_reconnect(norm)
        else:
            self._start_smart_connect(norm)

    def _start_smart_connect(self, mac: str) -> None:
        if self.manager is None:
            return
        self._run_worker(
            f"Connecting to {mac}...",
            lambda cb, cancel: self.manager.smart_connect(
                mac, progress_cb=cb, cancel_event=cancel
            ),
        )

    def _start_force_reconnect(self, mac: str) -> None:
        if self.manager is None:
            return
        self._run_worker(
            f"Force reconnecting {mac}...",
            lambda cb, cancel: self.manager.force_reconnect(
                mac,
                max_retries=2,
                scan_timeout=15,
                connect_timeout=15,
                reset_on_retry=True,
                progress_cb=cb,
                cancel_event=cancel,
            ),
        )

    def _start_disconnect(self, mac: str) -> None:
        if self.manager is None:
            return
        self._run_worker(
            f"Disconnecting {mac}...",
            lambda _cb, _cancel: self.manager.disconnect(mac),
        )

    def _run_worker(
        self,
        initial_msg: str,
        fn: Callable[[Callable[[str], None], threading.Event], tuple[bool, str]],
        on_success: Optional[Callable[[], None]] = None,
    ) -> None:
        if self._ui_scan_active:
            self._stop_ui_scan(quiet=True)

        with self._worker_lock:
            if self._worker_running:
                if self._worker_cancel is not None:
                    self._worker_cancel.set()
                self._show_banner(
                    "Cancelled previous action — please click again",
                    kind="info",
                    auto_hide=2500,
                )
                return
            self._worker_running = True
            cancel_event = threading.Event()
            self._worker_cancel = cancel_event

        self._show_banner(initial_msg, kind="info", spinning=True)

        def progress_cb(msg: str) -> None:
            GLib.idle_add(self._update_worker_progress, msg)

        def _thread() -> None:
            try:
                ok, msg = fn(progress_cb, cancel_event)
            except Exception as exc:
                ok, msg = False, str(exc)
            GLib.idle_add(self._on_worker_finished, ok, msg, cancel_event, on_success)

        threading.Thread(target=_thread, daemon=True).start()

    def _update_worker_progress(self, msg: str) -> bool:
        if self._worker_running and self._pending_confirm_cb is None:
            self.banner_label.set_text(msg)
        return GLib.SOURCE_REMOVE

    def _on_worker_finished(
        self,
        ok: bool,
        msg: str,
        cancel_event: threading.Event,
        on_success: Optional[Callable[[], None]],
    ) -> bool:
        with self._worker_lock:
            self._worker_running = False
            if self._worker_cancel is cancel_event:
                self._worker_cancel = None

        if self._pending_confirm_cb is not None:
            try:
                self._pending_confirm_cb(False)
            except Exception:
                pass
            self._pending_confirm_cb = None

        self.refresh_state()
        if ok:
            self._show_banner(msg, kind="success", spinning=False, auto_hide=3500)
            if on_success is not None:
                on_success()
        else:
            kind = "info" if msg == "Cancelled" else "error"
            self._show_banner(msg, kind=kind, spinning=False, auto_hide=4500)
        return GLib.SOURCE_REMOVE


def main(argv: Optional[list[str]] = None) -> int:
    app = BluetoothWidgetApp()
    return app.run(argv if argv is not None else sys.argv)


if __name__ == "__main__":
    sys.exit(main())
