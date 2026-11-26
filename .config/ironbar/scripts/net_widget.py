#!/usr/bin/env python3
"""
Single-instance GTK4 + gtk4-layer-shell NetworkManager widget for Ironbar.
Supports Wi-Fi scanning, saved/new/hidden connections with Show/Hide password,
Ethernet & VPN smart detection and toggling, live bit speeds, and detailed views.
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

try:
    gi.require_version("GLibUnix", "2.0")
    from gi.repository import GLibUnix  # type: ignore
except Exception:
    GLibUnix = None  # type: ignore

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
if SCRIPT_DIR not in sys.path:
    sys.path.insert(0, SCRIPT_DIR)

import net_backend  # noqa: E402

APP_ID = "dev.ironbar.network"
CSS_PATH = os.path.join(SCRIPT_DIR, "net_widget.css")


class NetworkWidgetApp(Gtk.Application):
    def __init__(self) -> None:
        super().__init__(
            application_id=APP_ID,
            flags=Gio.ApplicationFlags.HANDLES_COMMAND_LINE,
        )
        self._held = False
        self._updating_ui = False
        self.backend: Optional[net_backend.NetworkManagerBackend] = None
        self.speed_mon = net_backend.SpeedMonitor()

        self.win: Optional[Gtk.ApplicationWindow] = None
        self.root_box: Optional[Gtk.Box] = None
        self.card: Optional[Gtk.Box] = None

        self._dbus_subs: list[int] = []
        self._refresh_timer_id: Optional[int] = None
        self._speed_timer_id: Optional[int] = None
        self._banner_timer_id: Optional[int] = None

        self._busy = False
        self._scanning = False
        self.search_text = ""
        self.snapshot: dict[str, Any] = {}

        # Active detail/connect context
        self._connect_target: Optional[dict[str, Any]] = None
        self._detail_ctx: Optional[dict[str, Any]] = None
        self._detail_pw_visible = False
        self._detail_pw_cache: Optional[str] = None

        # Flicker-free Wi-Fi row cache keyed by SSID
        self._wifi_row_widgets: dict[str, dict[str, Any]] = {}
        self._wifi_row_order: list[str] = []

    def do_startup(self) -> None:
        Gtk.Application.do_startup(self)
        if not self._held:
            self.hold()
            self._held = True

        self._load_css()
        self.backend = net_backend.NetworkManagerBackend()
        self._build_window()
        self._subscribe_nm()
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
        self._stop_speed_timer()
        if self.backend:
            for sid in self._dbus_subs:
                try:
                    self.backend.bus.signal_unsubscribe(sid)
                except Exception:
                    pass
            self._dbus_subs.clear()
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

    # ── Window & Layout Construction ─────────────────────────────────────────

    def _build_window(self) -> None:
        win = Gtk.ApplicationWindow(application=self)
        win.set_title("Network")
        win.add_css_class("net-window")

        Gtk4LayerShell.init_for_window(win)
        Gtk4LayerShell.set_namespace(win, "ironbar-network")
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
        root.add_css_class("net-backdrop")

        card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        card.set_halign(Gtk.Align.END)
        card.set_valign(Gtk.Align.START)
        card.set_margin_top(40)
        card.set_margin_end(10)
        card.set_size_request(380, -1)
        card.add_css_class("net-popup")

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
        self._build_speed_strip(card)
        self._build_banner(card)
        self._build_stack(card)

    def _build_header(self, parent: Gtk.Box) -> None:
        hdr = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        hdr.add_css_class("net-header-card")

        self.wifi_switch = Gtk.Switch()
        self.wifi_switch.add_css_class("net-switch")
        self.wifi_switch.set_valign(Gtk.Align.CENTER)
        self.wifi_switch.set_tooltip_text("Toggle Wi-Fi radio")
        self.wifi_switch.connect("notify::active", self._on_wifi_radio_toggled)
        hdr.append(self.wifi_switch)

        title_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        title_box.set_hexpand(True)
        title_box.set_valign(Gtk.Align.CENTER)

        self.hdr_title_lbl = Gtk.Label(label="Network", xalign=0)
        self.hdr_title_lbl.add_css_class("net-title")
        self.hdr_title_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        title_box.append(self.hdr_title_lbl)

        self.hdr_sub_lbl = Gtk.Label(label="Checking...", xalign=0)
        self.hdr_sub_lbl.add_css_class("net-subtitle")
        self.hdr_sub_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        title_box.append(self.hdr_sub_lbl)
        hdr.append(title_box)

        actions = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        actions.set_valign(Gtk.Align.CENTER)

        self.scan_btn = Gtk.Button(label="󰑐")
        self.scan_btn.add_css_class("net-icon-btn")
        self.scan_btn.set_tooltip_text("Scan Wi-Fi networks")
        self.scan_btn.connect("clicked", lambda _b: self._trigger_scan())
        actions.append(self.scan_btn)

        hidden_btn = Gtk.Button(label="󰐕")
        hidden_btn.add_css_class("net-icon-btn")
        hidden_btn.set_tooltip_text("Join hidden Wi-Fi network")
        hidden_btn.connect("clicked", lambda _b: self._open_hidden_page())
        actions.append(hidden_btn)

        nmtui_btn = Gtk.Button(label="󰒓")
        nmtui_btn.add_css_class("net-icon-btn")
        nmtui_btn.set_tooltip_text("Open NetworkManager TUI")
        nmtui_btn.connect(
            "clicked",
            lambda _b: self._launch_detached([os.path.join(SCRIPT_DIR, "nmtui-floating.sh")]),
        )
        actions.append(nmtui_btn)

        hdr.append(actions)
        parent.append(hdr)

    def _build_speed_strip(self, parent: Gtk.Box) -> None:
        strip = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        strip.add_css_class("net-speed-card")
        strip.set_valign(Gtk.Align.CENTER)

        self.transport_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=5)
        self.transport_box.set_hexpand(True)
        self.transport_box.set_valign(Gtk.Align.CENTER)
        strip.append(self.transport_box)

        self.speed_down_lbl = Gtk.Label(label="↓ 0 bps", xalign=1)
        self.speed_down_lbl.add_css_class("net-speed-down")
        strip.append(self.speed_down_lbl)

        self.speed_up_lbl = Gtk.Label(label="↑ 0 bps", xalign=1)
        self.speed_up_lbl.add_css_class("net-speed-up")
        strip.append(self.speed_up_lbl)

        parent.append(strip)

    def _build_banner(self, parent: Gtk.Box) -> None:
        rev = Gtk.Revealer()
        rev.set_transition_type(Gtk.RevealerTransitionType.SLIDE_DOWN)
        rev.set_reveal_child(False)

        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        box.add_css_class("net-banner")
        box.add_css_class("info")
        box.set_valign(Gtk.Align.CENTER)

        self.banner_spinner = Gtk.Spinner()
        self.banner_spinner.set_visible(False)
        box.append(self.banner_spinner)

        self.banner_icon = Gtk.Label(label="󰤨")
        self.banner_icon.set_visible(False)
        box.append(self.banner_icon)

        self.banner_lbl = Gtk.Label(label="", xalign=0)
        self.banner_lbl.set_wrap(True)
        self.banner_lbl.set_wrap_mode(Pango.WrapMode.WORD_CHAR)
        self.banner_lbl.set_hexpand(True)
        self.banner_lbl.add_css_class("net-banner-text")
        box.append(self.banner_lbl)

        dismiss_btn = Gtk.Button(label="✕")
        dismiss_btn.add_css_class("net-chip")
        dismiss_btn.connect("clicked", lambda _b: self.banner_revealer.set_reveal_child(False))
        box.append(dismiss_btn)

        rev.set_child(box)
        parent.append(rev)
        self.banner_revealer = rev
        self.banner_box = box

    def _build_stack(self, parent: Gtk.Box) -> None:
        stack = Gtk.Stack()
        stack.set_transition_type(Gtk.StackTransitionType.SLIDE_LEFT_RIGHT)
        stack.set_transition_duration(180)
        stack.set_vhomogeneous(False)
        self.stack = stack

        self._build_main_page(stack)
        self._build_connect_page(stack)
        self._build_hidden_page(stack)
        self._build_details_page(stack)

        parent.append(stack)

    def _build_main_page(self, stack: Gtk.Stack) -> None:
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)

        self.search_entry = Gtk.Entry()
        self.search_entry.set_placeholder_text("Search Wi-Fi networks...")
        self.search_entry.add_css_class("net-entry")
        self.search_entry.connect("changed", self._on_search_changed)
        page.append(self.search_entry)

        scrolled = Gtk.ScrolledWindow()
        scrolled.add_css_class("net-scroll")
        scrolled.set_overlay_scrolling(False)
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scrolled.set_max_content_height(430)
        scrolled.set_propagate_natural_height(True)

        body = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        body.set_margin_bottom(2)

        # Connections (Ethernet + VPN)
        conn_hdr = Gtk.Label(label="CONNECTIONS", xalign=0)
        conn_hdr.add_css_class("net-section-title")
        body.append(conn_hdr)

        self.conn_list_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        body.append(self.conn_list_box)

        # Wi-Fi Off Card
        self.wifi_off_card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        self.wifi_off_card.add_css_class("net-card")
        off_icon = Gtk.Label(label="󰤮")
        off_icon.add_css_class("net-hero-icon")
        off_icon.set_halign(Gtk.Align.CENTER)
        self.wifi_off_card.append(off_icon)
        off_title = Gtk.Label(label="Wi-Fi is turned off")
        off_title.add_css_class("net-title")
        off_title.set_halign(Gtk.Align.CENTER)
        self.wifi_off_card.append(off_title)
        on_btn = Gtk.Button(label="Turn On Wi-Fi")
        on_btn.add_css_class("net-btn-primary")
        on_btn.set_halign(Gtk.Align.CENTER)
        on_btn.connect("clicked", lambda _b: self._set_wifi_radio(True))
        self.wifi_off_card.append(on_btn)
        body.append(self.wifi_off_card)

        # Wi-Fi On Section
        self.wifi_on_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)

        wifi_hdr = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        wifi_hdr.set_valign(Gtk.Align.CENTER)
        wifi_lbl = Gtk.Label(label="WI-FI NETWORKS", xalign=0)
        wifi_lbl.add_css_class("net-section-title")
        wifi_lbl.set_hexpand(True)
        wifi_hdr.append(wifi_lbl)

        self.wifi_scan_chip = Gtk.Button(label="Scan")
        self.wifi_scan_chip.add_css_class("net-chip")
        self.wifi_scan_chip.connect("clicked", lambda _b: self._trigger_scan())
        wifi_hdr.append(self.wifi_scan_chip)
        self.wifi_on_box.append(wifi_hdr)

        self.wifi_list_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.wifi_on_box.append(self.wifi_list_box)

        self.wifi_empty_lbl = Gtk.Label(label="No Wi-Fi networks found", xalign=0)
        self.wifi_empty_lbl.add_css_class("net-muted")
        self.wifi_empty_lbl.set_visible(False)
        self.wifi_on_box.append(self.wifi_empty_lbl)
        body.append(self.wifi_on_box)

        # Out-of-range Saved Wi-Fi
        self.saved_hdr = Gtk.Label(label="SAVED NETWORKS (OUT OF RANGE)", xalign=0)
        self.saved_hdr.add_css_class("net-section-title")
        body.append(self.saved_hdr)

        self.saved_list_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        body.append(self.saved_list_box)

        scrolled.set_child(body)
        page.append(scrolled)
        stack.add_named(page, "main")

    def _build_connect_page(self, stack: Gtk.Stack) -> None:
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)

        top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        top.set_valign(Gtk.Align.CENTER)
        back_btn = Gtk.Button(label="← Back")
        back_btn.add_css_class("net-btn-secondary")
        back_btn.add_css_class("net-btn-small")
        back_btn.connect("clicked", lambda _b: self._go_main())
        top.append(back_btn)
        ttl = Gtk.Label(label="Connect to Wi-Fi", xalign=0)
        ttl.add_css_class("net-title")
        ttl.set_hexpand(True)
        top.append(ttl)
        page.append(top)

        hero = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        hero.add_css_class("net-card")
        self.conn_hero_icon = Gtk.Label(label="󰤨")
        self.conn_hero_icon.add_css_class("net-hero-icon")
        self.conn_hero_icon.set_halign(Gtk.Align.CENTER)
        hero.append(self.conn_hero_icon)

        self.conn_ssid_lbl = Gtk.Label(label="")
        self.conn_ssid_lbl.add_css_class("net-title")
        self.conn_ssid_lbl.set_wrap(True)
        self.conn_ssid_lbl.set_halign(Gtk.Align.CENTER)
        hero.append(self.conn_ssid_lbl)

        self.conn_meta_lbl = Gtk.Label(label="")
        self.conn_meta_lbl.add_css_class("net-subtitle")
        self.conn_meta_lbl.set_halign(Gtk.Align.CENTER)
        hero.append(self.conn_meta_lbl)
        page.append(hero)

        form = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        form.add_css_class("net-card")

        pw_lbl = Gtk.Label(label="Wi-Fi Password", xalign=0)
        pw_lbl.add_css_class("net-muted")
        form.append(pw_lbl)

        pw_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.conn_pw_entry = Gtk.Entry()
        self.conn_pw_entry.set_placeholder_text("Enter network password...")
        self.conn_pw_entry.set_visibility(False)
        self.conn_pw_entry.set_hexpand(True)
        self.conn_pw_entry.add_css_class("net-entry")
        self.conn_pw_entry.connect("activate", lambda _e: self._submit_wifi_password())
        pw_row.append(self.conn_pw_entry)

        self.conn_eye_btn = Gtk.Button(label="󰈈")
        self.conn_eye_btn.add_css_class("net-icon-btn")
        self.conn_eye_btn.set_tooltip_text("Show / Hide password")
        self.conn_eye_btn.connect("clicked", lambda _b: self._toggle_entry_eye(self.conn_pw_entry, self.conn_eye_btn))
        pw_row.append(self.conn_eye_btn)
        form.append(pw_row)

        self.conn_submit_btn = Gtk.Button(label="󰤨  Connect")
        self.conn_submit_btn.add_css_class("net-btn-primary")
        self.conn_submit_btn.connect("clicked", lambda _b: self._submit_wifi_password())
        form.append(self.conn_submit_btn)

        page.append(form)
        stack.add_named(page, "connect")

    def _build_hidden_page(self, stack: Gtk.Stack) -> None:
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)

        top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        top.set_valign(Gtk.Align.CENTER)
        back_btn = Gtk.Button(label="← Back")
        back_btn.add_css_class("net-btn-secondary")
        back_btn.add_css_class("net-btn-small")
        back_btn.connect("clicked", lambda _b: self._go_main())
        top.append(back_btn)
        ttl = Gtk.Label(label="Join Hidden Network", xalign=0)
        ttl.add_css_class("net-title")
        ttl.set_hexpand(True)
        top.append(ttl)
        page.append(top)

        form = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)
        form.add_css_class("net-card")

        form.append(self._make_muted_label("Network Name (SSID)"))
        self.hid_ssid_entry = Gtk.Entry()
        self.hid_ssid_entry.set_placeholder_text("Hidden SSID...")
        self.hid_ssid_entry.add_css_class("net-entry")
        form.append(self.hid_ssid_entry)

        form.append(self._make_muted_label("Security"))
        self.hid_sec_dropdown = Gtk.DropDown(
            model=Gtk.StringList.new(["WPA2 / WPA3 Personal", "Open (None)"])
        )
        self.hid_sec_dropdown.add_css_class("net-dropdown")
        self.hid_sec_dropdown.connect("notify::selected", self._on_hidden_sec_changed)
        form.append(self.hid_sec_dropdown)

        self.hid_pw_box = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.hid_pw_box.append(self._make_muted_label("Password"))
        pw_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        self.hid_pw_entry = Gtk.Entry()
        self.hid_pw_entry.set_placeholder_text("Enter password...")
        self.hid_pw_entry.set_visibility(False)
        self.hid_pw_entry.set_hexpand(True)
        self.hid_pw_entry.add_css_class("net-entry")
        self.hid_pw_entry.connect("activate", lambda _e: self._submit_hidden_network())
        pw_row.append(self.hid_pw_entry)

        self.hid_eye_btn = Gtk.Button(label="󰈈")
        self.hid_eye_btn.add_css_class("net-icon-btn")
        self.hid_eye_btn.set_tooltip_text("Show / Hide password")
        self.hid_eye_btn.connect("clicked", lambda _b: self._toggle_entry_eye(self.hid_pw_entry, self.hid_eye_btn))
        pw_row.append(self.hid_eye_btn)
        self.hid_pw_box.append(pw_row)
        form.append(self.hid_pw_box)

        join_btn = Gtk.Button(label="󰤨  Join Network")
        join_btn.add_css_class("net-btn-primary")
        join_btn.connect("clicked", lambda _b: self._submit_hidden_network())
        form.append(join_btn)

        page.append(form)
        stack.add_named(page, "hidden")

    def _build_details_page(self, stack: Gtk.Stack) -> None:
        page = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)

        top = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        top.set_valign(Gtk.Align.CENTER)
        back_btn = Gtk.Button(label="← Back")
        back_btn.add_css_class("net-btn-secondary")
        back_btn.add_css_class("net-btn-small")
        back_btn.connect("clicked", lambda _b: self._go_main())
        top.append(back_btn)
        ttl = Gtk.Label(label="Network Details", xalign=0)
        ttl.add_css_class("net-title")
        ttl.set_hexpand(True)
        top.append(ttl)
        page.append(top)

        scrolled = Gtk.ScrolledWindow()
        scrolled.add_css_class("net-scroll")
        scrolled.set_overlay_scrolling(False)
        scrolled.set_policy(Gtk.PolicyType.NEVER, Gtk.PolicyType.AUTOMATIC)
        scrolled.set_max_content_height(460)
        scrolled.set_propagate_natural_height(True)

        inner = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=10)

        hero = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        hero.add_css_class("net-card")
        self.det_hero_icon = Gtk.Label(label="󰤨")
        self.det_hero_icon.add_css_class("net-hero-icon")
        self.det_hero_icon.set_halign(Gtk.Align.CENTER)
        hero.append(self.det_hero_icon)

        self.det_name_lbl = Gtk.Label(label="")
        self.det_name_lbl.add_css_class("net-title")
        self.det_name_lbl.set_wrap(True)
        self.det_name_lbl.set_halign(Gtk.Align.CENTER)
        hero.append(self.det_name_lbl)

        self.det_badge_lbl = Gtk.Label(label="")
        self.det_badge_lbl.add_css_class("net-badge")
        self.det_badge_lbl.set_halign(Gtk.Align.CENTER)
        hero.append(self.det_badge_lbl)
        inner.append(hero)

        self.det_info_card = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=8)
        self.det_info_card.add_css_class("net-details-card")
        inner.append(self.det_info_card)

        actions = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=6)
        self.det_reconn_btn = Gtk.Button(label="󰑐  Reconnect")
        self.det_reconn_btn.add_css_class("net-btn-primary")
        self.det_reconn_btn.connect("clicked", lambda _b: self._on_detail_reconnect())
        actions.append(self.det_reconn_btn)

        self.det_forget_btn = Gtk.Button(label="󰆴  Forget Network")
        self.det_forget_btn.add_css_class("net-btn-danger")
        self.det_forget_btn.connect("clicked", lambda _b: self._on_detail_forget())
        actions.append(self.det_forget_btn)
        inner.append(actions)

        scrolled.set_child(inner)
        page.append(scrolled)
        stack.add_named(page, "details")

    def _make_muted_label(self, text: str) -> Gtk.Label:
        lbl = Gtk.Label(label=text, xalign=0)
        lbl.add_css_class("net-muted")
        return lbl

    def _toggle_entry_eye(self, entry: Gtk.Entry, btn: Gtk.Button) -> None:
        vis = not entry.get_visibility()
        entry.set_visibility(vis)
        btn.set_label("󰈉" if vis else "󰈈")
        if vis:
            btn.add_css_class("active")
        else:
            btn.remove_css_class("active")

    # ── Visibility, Speed Timer & Navigation ─────────────────────────────────

    def show_popup(self) -> None:
        if self.win is None:
            return
        self.speed_mon.reset()
        self.refresh_state()
        self._start_speed_timer()
        self.win.present()

    def hide_popup(self) -> None:
        if self.win is None:
            return
        self._stop_speed_timer()
        self._updating_ui = True
        self.search_entry.set_text("")
        self._updating_ui = False
        self.search_text = ""
        self._detail_ctx = None
        self._connect_target = None
        self._detail_pw_visible = False
        self._detail_pw_cache = None
        self.stack.set_visible_child_name("main")
        self.win.set_visible(False)

    def _go_main(self) -> None:
        self._detail_ctx = None
        self._connect_target = None
        self._detail_pw_visible = False
        self._detail_pw_cache = None
        self.stack.set_visible_child_name("main")
        self._render_snapshot()

    def _start_speed_timer(self) -> None:
        if self._speed_timer_id is None:
            self._speed_timer_id = GLib.timeout_add(1000, self._on_speed_tick)

    def _stop_speed_timer(self) -> None:
        if self._speed_timer_id is not None:
            GLib.source_remove(self._speed_timer_id)
            self._speed_timer_id = None

    def _on_speed_tick(self) -> bool:
        if not self.win or not self.win.get_visible():
            self._speed_timer_id = None
            return GLib.SOURCE_REMOVE
        iface = self.snapshot.get("summary", {}).get("primary_iface") or ""
        rx_bps, tx_bps = self.speed_mon.sample(iface)
        self.speed_down_lbl.set_text(f"↓ {net_backend.format_bits(rx_bps)}")
        self.speed_up_lbl.set_text(f"↑ {net_backend.format_bits(tx_bps)}")
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
            if self.stack.get_visible_child_name() != "main":
                self._go_main()
            else:
                self.hide_popup()
            return True
        return False

    def _launch_detached(self, cmd: list[str]) -> None:
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

    # ── D-Bus Subscription & Refresh ─────────────────────────────────────────

    def _subscribe_nm(self) -> None:
        if not self.backend:
            return
        self._dbus_subs.append(
            self.backend.bus.signal_subscribe(
                net_backend.NM_SERVICE,
                None,
                None,
                None,
                None,
                Gio.DBusSignalFlags.NONE,
                self._on_nm_signal,
            )
        )

    def _on_nm_signal(self, *_args: Any) -> None:
        if self._refresh_timer_id is not None:
            return
        self._refresh_timer_id = GLib.timeout_add(180, self._debounced_refresh)

    def _debounced_refresh(self) -> bool:
        self._refresh_timer_id = None
        self.refresh_state()
        return GLib.SOURCE_REMOVE

    def refresh_state(self) -> None:
        if not self.backend:
            return

        def _fetch() -> None:
            snap = self.backend.get_snapshot()
            GLib.idle_add(self._apply_snapshot, snap)

        threading.Thread(target=_fetch, daemon=True).start()

    def _apply_snapshot(self, snap: dict[str, Any]) -> bool:
        self.snapshot = snap
        self._render_snapshot()
        return GLib.SOURCE_REMOVE

    # ── Rendering ────────────────────────────────────────────────────────────

    def _clear_box(self, box: Gtk.Box) -> None:
        child = box.get_first_child()
        while child is not None:
            nxt = child.get_next_sibling()
            box.remove(child)
            child = nxt

    def _render_snapshot(self) -> None:
        if not self.snapshot:
            return
        summary = self.snapshot.get("summary", {})
        wifi_enabled = bool(self.snapshot.get("wifi_enabled", False))

        self._updating_ui = True
        try:
            self.wifi_switch.set_active(wifi_enabled)
            self.hdr_title_lbl.set_text(summary.get("title") or "Network")
            self.hdr_sub_lbl.set_text(summary.get("subtitle") or "Not connected")
            self.scan_btn.set_sensitive(wifi_enabled and not self._scanning)

            self._render_transport_chips(summary)
            self._render_connections()
            self._render_wifi_list(wifi_enabled)
            self._render_saved_out_of_range()
        finally:
            self._updating_ui = False

        if self.stack.get_visible_child_name() == "details" and self._detail_ctx is not None:
            self._render_details_view()

    def _render_transport_chips(self, summary: dict[str, Any]) -> None:
        self._clear_box(self.transport_box)
        mode = summary.get("mode", "offline")
        eth_on = any(d.get("connected") for d in self.snapshot.get("ethernet_devices", []))
        wifi_on = any(d.get("connected") for d in self.snapshot.get("wifi_devices", []))
        vpn_on = bool(self.snapshot.get("vpn", {}).get("connected"))

        if eth_on:
            lbl = Gtk.Label(label="󰈀 Ethernet")
            lbl.add_css_class("net-transport-chip")
            self.transport_box.append(lbl)
        if wifi_on:
            lbl = Gtk.Label(label="󰤨 Wi-Fi")
            lbl.add_css_class("net-transport-chip")
            self.transport_box.append(lbl)
        if vpn_on:
            lbl = Gtk.Label(label="󰖂 VPN")
            lbl.add_css_class("net-transport-chip")
            lbl.add_css_class("vpn")
            self.transport_box.append(lbl)
        if mode == "offline" and not eth_on and not wifi_on and not vpn_on:
            lbl = Gtk.Label(label="󰖪 Offline")
            lbl.add_css_class("net-transport-chip")
            self.transport_box.append(lbl)

    def _render_connections(self) -> None:
        self._clear_box(self.conn_list_box)

        # Ethernet devices
        for eth in self.snapshot.get("ethernet_devices", []):
            connected = bool(eth.get("connected"))
            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            row.add_css_class("net-row")

            btn = Gtk.Button()
            btn.add_css_class("net-row-clickable")
            btn.set_hexpand(True)
            btn.connect("clicked", lambda _b, e=eth: self._open_details({"kind": "ethernet", "device": e["device"]}))

            inner = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
            inner.set_valign(Gtk.Align.CENTER)
            icon = Gtk.Label(label="󰈀")
            icon.add_css_class("net-icon-circle")
            if connected:
                icon.add_css_class("connected")
            inner.append(icon)

            txt = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            txt.set_hexpand(True)
            t_lbl = Gtk.Label(label=eth.get("connection") or eth["device"], xalign=0)
            t_lbl.add_css_class("net-title")
            t_lbl.set_ellipsize(Pango.EllipsizeMode.END)
            txt.append(t_lbl)

            if connected:
                parts = [eth["device"]]
                if eth.get("ip4"):
                    parts.append(eth["ip4"])
                if eth.get("link_speed"):
                    parts.append(eth["link_speed"])
                sub_text = " • ".join(parts)
            else:
                sub_text = f"{eth['device']} • {eth.get('state', 'unavailable')}"
            s_lbl = Gtk.Label(label=sub_text, xalign=0)
            s_lbl.add_css_class("net-subtitle")
            s_lbl.set_ellipsize(Pango.EllipsizeMode.END)
            txt.append(s_lbl)
            inner.append(txt)

            chev = Gtk.Label(label="›")
            chev.add_css_class("net-chevron")
            inner.append(chev)
            btn.set_child(inner)
            row.append(btn)

            sw = Gtk.Switch()
            sw.add_css_class("net-switch")
            sw.set_valign(Gtk.Align.CENTER)
            sw.set_active(connected)
            sw.connect("notify::active", self._on_eth_switch_changed, eth)
            row.append(sw)
            self.conn_list_box.append(row)

        # Proton VPN / Active VPN row
        vpn = self.snapshot.get("vpn", {})
        if vpn.get("has_proton_cli") or vpn.get("connected"):
            vpn_row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            vpn_row.add_css_class("net-row")

            btn = Gtk.Button()
            btn.add_css_class("net-row-clickable")
            btn.set_hexpand(True)
            btn.connect("clicked", lambda _b: self._open_details({"kind": "vpn", "uuid": vpn.get("uuid", "")}))

            inner = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
            inner.set_valign(Gtk.Align.CENTER)
            v_icon = Gtk.Label(label="󰖂" if vpn.get("connected") else "󰦝")
            v_icon.add_css_class("net-icon-circle")
            if vpn.get("connected"):
                v_icon.add_css_class("vpn-active")
            inner.append(v_icon)

            txt = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            txt.set_hexpand(True)
            v_title = Gtk.Label(label="Proton VPN", xalign=0)
            v_title.add_css_class("net-title")
            txt.append(v_title)

            if vpn.get("busy"):
                v_sub_text = vpn.get("busy_text") or "Working..."
            elif vpn.get("connected"):
                v_sub_text = f"Connected • {vpn['name']}"
            else:
                v_sub_text = "Disconnected"
            v_sub = Gtk.Label(label=v_sub_text, xalign=0)
            v_sub.add_css_class("net-subtitle")
            v_sub.set_ellipsize(Pango.EllipsizeMode.END)
            txt.append(v_sub)
            inner.append(txt)

            chev = Gtk.Label(label="›")
            chev.add_css_class("net-chevron")
            inner.append(chev)
            btn.set_child(inner)
            vpn_row.append(btn)

            v_sw = Gtk.Switch()
            v_sw.add_css_class("net-switch")
            v_sw.set_valign(Gtk.Align.CENTER)
            v_sw.set_active(bool(vpn.get("connected")))
            v_sw.set_sensitive(not bool(vpn.get("busy")))
            v_sw.connect("notify::active", self._on_vpn_switch_changed, vpn.get("uuid") or None)
            vpn_row.append(v_sw)
            self.conn_list_box.append(vpn_row)

        # Extra saved NM VPN / WireGuard profiles not already shown as active Proton VPN
        for nv in self.snapshot.get("nm_vpns", []):
            if vpn.get("uuid") and nv["uuid"] == vpn["uuid"]:
                continue
            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            row.add_css_class("net-row")
            ic = Gtk.Label(label="󰖂" if nv["connected"] else "󰦝")
            ic.add_css_class("net-icon-circle")
            if nv["connected"]:
                ic.add_css_class("vpn-active")
            row.append(ic)

            txt = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            txt.set_hexpand(True)
            tl = Gtk.Label(label=nv["name"], xalign=0)
            tl.add_css_class("net-title")
            tl.set_ellipsize(Pango.EllipsizeMode.END)
            txt.append(tl)
            sl = Gtk.Label(label="Connected" if nv["connected"] else f"Saved {nv['type']}", xalign=0)
            sl.add_css_class("net-subtitle")
            txt.append(sl)
            row.append(txt)

            sw = Gtk.Switch()
            sw.add_css_class("net-switch")
            sw.set_valign(Gtk.Align.CENTER)
            sw.set_active(bool(nv["connected"]))
            sw.connect("notify::active", self._on_vpn_switch_changed, nv["uuid"])
            row.append(sw)
            self.conn_list_box.append(row)

    def _render_wifi_list(self, wifi_enabled: bool) -> None:
        self.wifi_off_card.set_visible(not wifi_enabled)
        self.wifi_on_box.set_visible(wifi_enabled)
        if not wifi_enabled:
            return

        q = self.search_text.strip().lower()
        nets = self.snapshot.get("wifi_networks", [])
        if q:
            nets = [n for n in nets if q in n["ssid"].lower() or q in n["security"].lower()]

        new_order = [n["ssid"] for n in nets]
        if new_order != self._wifi_row_order:
            self._clear_box(self.wifi_list_box)
            self._wifi_row_widgets.clear()
            for net in nets:
                w = self._create_wifi_row(net["ssid"])
                self._wifi_row_widgets[net["ssid"]] = w
                self.wifi_list_box.append(w["row"])
            self._wifi_row_order = new_order

        for net in nets:
            self._update_wifi_row(self._wifi_row_widgets[net["ssid"]], net)

        if len(nets) == 0:
            self.wifi_empty_lbl.set_text("No matching Wi-Fi networks" if q else "No Wi-Fi networks found — click Scan")
            self.wifi_empty_lbl.set_visible(True)
        else:
            self.wifi_empty_lbl.set_visible(False)

    def _create_wifi_row(self, ssid: str) -> dict[str, Any]:
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.add_css_class("net-row")

        click_btn = Gtk.Button()
        click_btn.add_css_class("net-row-clickable")
        click_btn.set_hexpand(True)
        click_btn.connect("clicked", lambda _b, s=ssid: self._on_wifi_row_clicked(s))

        inner = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
        inner.set_valign(Gtk.Align.CENTER)

        icon_lbl = Gtk.Label(label="󰤨")
        icon_lbl.add_css_class("net-icon-circle")
        inner.append(icon_lbl)

        txt = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
        txt.set_hexpand(True)
        name_lbl = Gtk.Label(label=ssid, xalign=0)
        name_lbl.add_css_class("net-title")
        name_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        txt.append(name_lbl)

        sub_lbl = Gtk.Label(label="", xalign=0)
        sub_lbl.add_css_class("net-subtitle")
        sub_lbl.set_ellipsize(Pango.EllipsizeMode.END)
        txt.append(sub_lbl)
        inner.append(txt)

        chev = Gtk.Label(label="›")
        chev.add_css_class("net-chevron")
        inner.append(chev)
        click_btn.set_child(inner)
        row.append(click_btn)

        sw = Gtk.Switch()
        sw.add_css_class("net-switch")
        sw.set_valign(Gtk.Align.CENTER)
        sw.connect("notify::active", self._on_wifi_row_switch, ssid)
        row.append(sw)

        conn_btn = Gtk.Button(label="Connect")
        conn_btn.add_css_class("net-btn-primary")
        conn_btn.add_css_class("net-btn-small")
        conn_btn.set_valign(Gtk.Align.CENTER)
        conn_btn.connect("clicked", lambda _b, s=ssid: self._on_wifi_connect_clicked(s))
        row.append(conn_btn)

        return {
            "row": row,
            "icon_lbl": icon_lbl,
            "name_lbl": name_lbl,
            "sub_lbl": sub_lbl,
            "chev": chev,
            "switch": sw,
            "conn_btn": conn_btn,
        }

    def _update_wifi_row(self, w: dict[str, Any], net: dict[str, Any]) -> None:
        in_use = bool(net.get("in_use"))
        saved = bool(net.get("saved"))
        secured = bool(net.get("secured"))

        w["icon_lbl"].set_label(net["glyph"])
        if in_use:
            w["icon_lbl"].add_css_class("connected")
        else:
            w["icon_lbl"].remove_css_class("connected")

        w["name_lbl"].set_text(net["ssid"])
        parts = []
        if in_use:
            parts.append("Connected")
        elif saved:
            parts.append("Saved")
        parts.append(f"{net['signal']}%")
        if net.get("band"):
            parts.append(net["band"])
        if secured:
            parts.append("" if saved or in_use else f"{net['security']} ")
        w["sub_lbl"].set_text(" • ".join(parts))

        w["chev"].set_visible(in_use or saved)
        w["switch"].set_visible(in_use)
        w["conn_btn"].set_visible(not in_use)
        if w["switch"].get_active() != in_use:
            w["switch"].set_active(in_use)

    def _render_saved_out_of_range(self) -> None:
        self._clear_box(self.saved_list_box)
        q = self.search_text.strip().lower()
        saved = self.snapshot.get("saved_out_of_range", [])
        if q:
            saved = [s for s in saved if q in s["name"].lower()]

        show = len(saved) > 0
        self.saved_hdr.set_visible(show)
        self.saved_list_box.set_visible(show)
        for item in saved:
            row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
            row.add_css_class("net-row")

            btn = Gtk.Button()
            btn.add_css_class("net-row-clickable")
            btn.set_hexpand(True)
            btn.connect("clicked", lambda _b, it=item: self._open_details({"kind": "saved_wifi", "uuid": it["uuid"], "ssid": it["name"]}))

            inner = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=10)
            inner.set_valign(Gtk.Align.CENTER)
            ic = Gtk.Label(label="󰤮")
            ic.add_css_class("net-icon-circle")
            inner.append(ic)
            txt = Gtk.Box(orientation=Gtk.Orientation.VERTICAL, spacing=2)
            txt.set_hexpand(True)
            tl = Gtk.Label(label=item["name"], xalign=0)
            tl.add_css_class("net-title")
            tl.set_ellipsize(Pango.EllipsizeMode.END)
            txt.append(tl)
            sl = Gtk.Label(label="Saved • Out of range", xalign=0)
            sl.add_css_class("net-subtitle")
            txt.append(sl)
            inner.append(txt)
            chev = Gtk.Label(label="›")
            chev.add_css_class("net-chevron")
            inner.append(chev)
            btn.set_child(inner)
            row.append(btn)

            f_btn = Gtk.Button(label="󰆴")
            f_btn.add_css_class("net-icon-btn")
            f_btn.set_tooltip_text("Forget saved network")
            f_btn.connect("clicked", lambda _b, u=item["uuid"], n=item["name"]: self._forget_profile(u, n))
            row.append(f_btn)
            self.saved_list_box.append(row)

    # ── Subpages (Connect, Hidden, Details) ──────────────────────────────────

    def _open_connect_page(self, net: dict[str, Any]) -> None:
        self._connect_target = net
        self.conn_hero_icon.set_label(net["glyph"])
        self.conn_ssid_lbl.set_text(net["ssid"])
        meta = [net.get("security") or "Secured", f"{net['signal']}%"]
        if net.get("band"):
            meta.append(net["band"])
        self.conn_meta_lbl.set_text(" • ".join(meta))
        self.conn_pw_entry.set_text("")
        self.conn_pw_entry.set_visibility(False)
        self.conn_eye_btn.set_label("󰈈")
        self.conn_eye_btn.remove_css_class("active")
        self.stack.set_visible_child_name("connect")
        self.conn_pw_entry.grab_focus()

    def _open_hidden_page(self) -> None:
        self.hid_ssid_entry.set_text("")
        self.hid_pw_entry.set_text("")
        self.hid_pw_entry.set_visibility(False)
        self.hid_eye_btn.set_label("󰈈")
        self.hid_eye_btn.remove_css_class("active")
        self.hid_sec_dropdown.set_selected(0)
        self.hid_pw_box.set_visible(True)
        self.stack.set_visible_child_name("hidden")
        self.hid_ssid_entry.grab_focus()

    def _on_hidden_sec_changed(self, dd: Gtk.DropDown, _pspec: Any) -> None:
        self.hid_pw_box.set_visible(dd.get_selected() == 0)

    def _open_details(self, ctx: dict[str, Any]) -> None:
        self._detail_ctx = ctx
        self._detail_pw_visible = False
        self._detail_pw_cache = None
        self._render_details_view()
        self.stack.set_visible_child_name("details")

    def _resolve_detail_entity(self) -> Optional[dict[str, Any]]:
        ctx = self._detail_ctx
        if not ctx:
            return None
        kind = ctx["kind"]
        if kind == "ethernet":
            dev = next((d for d in self.snapshot.get("ethernet_devices", []) if d["device"] == ctx["device"]), None)
            if not dev:
                return None
            return {
                "kind": "ethernet",
                "title": dev.get("connection") or dev["device"],
                "icon": "󰈀",
                "connected": bool(dev.get("connected")),
                "vpn": False,
                "device": dev["device"],
                "uuid": dev.get("uuid", ""),
                "ip4": dev.get("ip4", ""),
                "gateway": dev.get("gateway", ""),
                "dns": ", ".join(dev.get("dns", [])),
                "speed": dev.get("link_speed", ""),
                "hwaddr": dev.get("hwaddr", ""),
                "autoconnect": bool(dev.get("autoconnect", True)),
                "forget_allowed": False,
            }
        if kind == "vpn":
            vpn = self.snapshot.get("vpn", {})
            return {
                "kind": "vpn",
                "title": f"Proton VPN ({vpn.get('name', 'VPN')})" if vpn.get("connected") else "Proton VPN",
                "icon": "󰖂" if vpn.get("connected") else "󰦝",
                "connected": bool(vpn.get("connected")),
                "vpn": True,
                "device": vpn.get("iface", ""),
                "uuid": vpn.get("uuid", ""),
                "ip4": vpn.get("ip4", ""),
                "gateway": "",
                "dns": "",
                "speed": "",
                "hwaddr": "",
                "autoconnect": None,
                "forget_allowed": False,
            }
        if kind == "wifi":
            net = next((n for n in self.snapshot.get("wifi_networks", []) if n["ssid"] == ctx["ssid"]), None)
            if net:
                sig_str = f"{net['signal']}% ({net['quality']})"
                if net.get("band"):
                    sig_str += f" • {net['band']}"
                return {
                    "kind": "wifi",
                    "title": net["ssid"],
                    "icon": net["glyph"],
                    "connected": bool(net.get("in_use")),
                    "vpn": False,
                    "device": net.get("device", ""),
                    "uuid": net.get("uuid") or net.get("saved_uuid", ""),
                    "ip4": net.get("ip4", ""),
                    "gateway": net.get("gateway", ""),
                    "dns": ", ".join(net.get("dns", [])),
                    "speed": net.get("rate", ""),
                    "signal": sig_str,
                    "security": net.get("security", ""),
                    "secured": bool(net.get("secured")),
                    "saved": bool(net.get("saved")),
                    "hwaddr": net.get("hwaddr", ""),
                    "bssid": net.get("bssid", ""),
                    "autoconnect": bool(net.get("autoconnect", False)) if net.get("saved") else None,
                    "forget_allowed": bool(net.get("saved")),
                }
            # Fallback if connected network disappeared briefly or went out of range
            sav = next((s for s in self.snapshot.get("saved_out_of_range", []) if s["name"] == ctx["ssid"]), None)
            if sav:
                ctx = {"kind": "saved_wifi", "uuid": sav["uuid"], "ssid": sav["name"]}
                self._detail_ctx = ctx
                kind = "saved_wifi"
        if kind == "saved_wifi":
            sav = next((s for s in self.snapshot.get("saved_out_of_range", []) if s["uuid"] == ctx["uuid"]), None)
            if not sav:
                return None
            return {
                "kind": "saved_wifi",
                "title": sav["name"],
                "icon": "󰤮",
                "connected": False,
                "vpn": False,
                "device": "",
                "uuid": sav["uuid"],
                "ip4": "",
                "gateway": "",
                "dns": "",
                "speed": "",
                "autoconnect": bool(sav.get("autoconnect", True)),
                "secured": True,
                "saved": True,
                "forget_allowed": True,
            }
        return None

    def _add_detail_row(self, key: str, widget: Gtk.Widget, add_div: bool = True) -> None:
        if add_div and self.det_info_card.get_first_child() is not None:
            div = Gtk.Box()
            div.add_css_class("net-divider")
            self.det_info_card.append(div)
        row = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=8)
        row.set_valign(Gtk.Align.CENTER)
        k_lbl = Gtk.Label(label=key, xalign=0)
        k_lbl.add_css_class("net-detail-key")
        k_lbl.set_hexpand(True)
        row.append(k_lbl)
        row.append(widget)
        self.det_info_card.append(row)

    def _make_copy_val_widget(self, value: str) -> Gtk.Box:
        box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
        lbl = Gtk.Label(label=value, xalign=1)
        lbl.add_css_class("net-detail-val")
        lbl.set_ellipsize(Pango.EllipsizeMode.MIDDLE)
        box.append(lbl)
        btn = Gtk.Button(label="󰆏")
        btn.add_css_class("net-chip")
        btn.set_tooltip_text("Copy to clipboard")
        btn.connect("clicked", lambda _b, v=value: self._copy_text(v))
        box.append(btn)
        return box

    def _render_details_view(self) -> None:
        ent = self._resolve_detail_entity()
        if ent is None:
            self._go_main()
            return

        self._updating_ui = True
        try:
            for cls in ("connected", "vpn-active"):
                self.det_hero_icon.remove_css_class(cls)
                self.det_badge_lbl.remove_css_class(cls)
            self.det_hero_icon.set_label(ent["icon"])
            if ent["connected"]:
                self.det_hero_icon.add_css_class("vpn-active" if ent["vpn"] else "connected")
                self.det_badge_lbl.add_css_class("connected")
                self.det_badge_lbl.set_text("Connected")
            else:
                self.det_badge_lbl.set_text("Out of range" if ent["kind"] == "saved_wifi" else "Disconnected")

            self.det_name_lbl.set_text(ent["title"])
            self._clear_box(self.det_info_card)

            if ent["kind"] != "saved_wifi":
                sw = Gtk.Switch()
                sw.add_css_class("net-switch")
                sw.set_active(ent["connected"])
                sw.connect("notify::active", self._on_detail_conn_switch, ent)
                self._add_detail_row("Connection", sw)

            if ent.get("device"):
                lbl = Gtk.Label(label=ent["device"], xalign=1)
                lbl.add_css_class("net-detail-val")
                self._add_detail_row("Interface", lbl)

            if ent.get("ip4"):
                self._add_detail_row("IP Address", self._make_copy_val_widget(ent["ip4"]))

            if ent.get("gateway"):
                lbl = Gtk.Label(label=ent["gateway"], xalign=1)
                lbl.add_css_class("net-detail-val")
                self._add_detail_row("Gateway", lbl)

            if ent.get("dns"):
                lbl = Gtk.Label(label=ent["dns"], xalign=1)
                lbl.add_css_class("net-detail-val")
                self._add_detail_row("DNS", lbl)

            if ent.get("speed"):
                lbl = Gtk.Label(label=ent["speed"], xalign=1)
                lbl.add_css_class("net-detail-val")
                self._add_detail_row("Link Speed", lbl)

            if ent.get("signal"):
                lbl = Gtk.Label(label=ent["signal"], xalign=1)
                lbl.add_css_class("net-detail-val")
                self._add_detail_row("Signal", lbl)

            if ent.get("security"):
                lbl = Gtk.Label(label=ent["security"], xalign=1)
                lbl.add_css_class("net-detail-val")
                self._add_detail_row("Security", lbl)

            if ent.get("hwaddr"):
                self._add_detail_row("MAC Address", self._make_copy_val_widget(ent["hwaddr"]))

            if ent.get("autoconnect") is not None and ent.get("uuid"):
                asw = Gtk.Switch()
                asw.add_css_class("net-switch")
                asw.set_active(bool(ent["autoconnect"]))
                asw.connect("notify::active", self._on_detail_autoconnect, ent["uuid"])
                self._add_detail_row("Auto-connect", asw)

            if ent.get("saved") and ent.get("secured") and ent.get("uuid"):
                pw_box = Gtk.Box(orientation=Gtk.Orientation.HORIZONTAL, spacing=6)
                pw_text = (self._detail_pw_cache or "(none)") if self._detail_pw_visible else "••••••••"
                pw_lbl = Gtk.Label(label=pw_text, xalign=1)
                pw_lbl.add_css_class("net-detail-val")
                pw_box.append(pw_lbl)

                eye_btn = Gtk.Button(label="󰈉" if self._detail_pw_visible else "󰈈")
                eye_btn.add_css_class("net-chip")
                if self._detail_pw_visible:
                    eye_btn.add_css_class("active")
                eye_btn.set_tooltip_text("Show / Hide saved password")
                eye_btn.connect("clicked", lambda _b, u=ent["uuid"]: self._toggle_detail_password(u))
                pw_box.append(eye_btn)

                cp_btn = Gtk.Button(label="󰆏")
                cp_btn.add_css_class("net-chip")
                cp_btn.set_tooltip_text("Copy password")
                cp_btn.connect("clicked", lambda _b, u=ent["uuid"]: self._copy_detail_password(u))
                pw_box.append(cp_btn)

                self._add_detail_row("Password", pw_box)

            self.det_reconn_btn.set_visible(ent["kind"] != "saved_wifi" and ent["connected"])
            self.det_forget_btn.set_visible(bool(ent.get("forget_allowed") and ent.get("uuid")))
        finally:
            self._updating_ui = False

    def _copy_text(self, value: str) -> None:
        display = Gdk.Display.get_default()
        if display is not None:
            display.get_clipboard().set(value)
            self._show_banner(f"Copied {value}", kind="success", auto_hide=2000)

    def _toggle_detail_password(self, uuid: str) -> None:
        if self._detail_pw_visible:
            self._detail_pw_visible = False
            self._render_details_view()
            return
        if not self.backend:
            return

        def _fetch() -> None:
            pw = self.backend.get_wifi_password(uuid)
            GLib.idle_add(self._on_detail_pw_loaded, pw)

        threading.Thread(target=_fetch, daemon=True).start()

    def _on_detail_pw_loaded(self, pw: Optional[str]) -> bool:
        self._detail_pw_cache = pw or "(not stored)"
        self._detail_pw_visible = True
        self._render_details_view()
        return GLib.SOURCE_REMOVE

    def _copy_detail_password(self, uuid: str) -> None:
        if not self.backend:
            return

        def _fetch() -> None:
            pw = self._detail_pw_cache if self._detail_pw_cache and self._detail_pw_cache != "(not stored)" else self.backend.get_wifi_password(uuid)
            if pw:
                GLib.idle_add(self._copy_text, pw)
            else:
                GLib.idle_add(self._show_banner, "No saved password available", "error", False, 2500)

        threading.Thread(target=_fetch, daemon=True).start()

    # ── Banner & Action Handlers ─────────────────────────────────────────────

    def _show_banner(
        self, text: str, kind: str = "info", spinning: bool = False, auto_hide: int = 0
    ) -> None:
        if self._banner_timer_id is not None:
            GLib.source_remove(self._banner_timer_id)
            self._banner_timer_id = None

        for cls in ("info", "success", "error"):
            self.banner_box.remove_css_class(cls)
        self.banner_box.add_css_class(kind)
        self.banner_lbl.set_text(text)

        self.banner_spinner.set_visible(spinning)
        if spinning:
            self.banner_spinner.start()
            self.banner_icon.set_visible(False)
        else:
            self.banner_spinner.stop()
            self.banner_icon.set_label({"info": "󰤨", "success": "󰄬", "error": "󰅙"}.get(kind, "󰤨"))
            self.banner_icon.set_visible(True)

        self.banner_revealer.set_reveal_child(True)
        if auto_hide > 0:
            self._banner_timer_id = GLib.timeout_add(
                auto_hide,
                lambda: self._auto_hide_banner(),
            )

    def _auto_hide_banner(self) -> bool:
        self._banner_timer_id = None
        if not self._busy:
            self.banner_revealer.set_reveal_child(False)
        return GLib.SOURCE_REMOVE

    def _run_action(
        self,
        msg: str,
        fn: Callable[[], tuple[bool, str]],
        on_ok: Optional[Callable[[], None]] = None,
    ) -> None:
        if self._busy:
            self._show_banner("An operation is already running...", kind="info", auto_hide=2000)
            return
        self._busy = True
        self._show_banner(msg, kind="info", spinning=True)

        def _work() -> None:
            try:
                ok, res_msg = fn()
            except Exception as exc:
                ok, res_msg = False, str(exc)
            GLib.idle_add(self._on_action_done, ok, res_msg, on_ok)

        threading.Thread(target=_work, daemon=True).start()

    def _on_action_done(
        self, ok: bool, msg: str, on_ok: Optional[Callable[[], None]]
    ) -> bool:
        self._busy = False
        self.refresh_state()
        self._show_banner(
            msg,
            kind="success" if ok else "error",
            spinning=False,
            auto_hide=3000 if ok else 4500,
        )
        if ok and on_ok is not None:
            on_ok()
        return GLib.SOURCE_REMOVE

    def _on_search_changed(self, entry: Gtk.Entry) -> None:
        if self._updating_ui:
            return
        self.search_text = entry.get_text()
        self._render_wifi_list(bool(self.snapshot.get("wifi_enabled")))
        self._render_saved_out_of_range()

    def _on_wifi_radio_toggled(self, sw: Gtk.Switch, _pspec: Any) -> None:
        if self._updating_ui:
            return
        self._set_wifi_radio(sw.get_active())

    def _set_wifi_radio(self, on: bool) -> None:
        if not self.backend:
            return
        self._run_action(
            "Turning Wi-Fi on..." if on else "Turning Wi-Fi off...",
            lambda: self.backend.set_wifi_radio(on),
        )

    def _trigger_scan(self) -> None:
        if not self.backend or self._scanning or not self.snapshot.get("wifi_enabled"):
            return
        self._scanning = True
        self.scan_btn.add_css_class("active")
        self.wifi_scan_chip.set_label("Scanning...")
        self.wifi_scan_chip.add_css_class("active")
        self._show_banner("Scanning for nearby Wi-Fi networks...", kind="info", spinning=True)

        def _work() -> None:
            ok, msg = self.backend.rescan_wifi()
            snap = self.backend.get_snapshot()
            GLib.idle_add(self._on_scan_done, ok, msg, snap)

        threading.Thread(target=_work, daemon=True).start()

    def _on_scan_done(self, ok: bool, msg: str, snap: dict[str, Any]) -> bool:
        self._scanning = False
        self.scan_btn.remove_css_class("active")
        self.wifi_scan_chip.set_label("Scan")
        self.wifi_scan_chip.remove_css_class("active")
        self.snapshot = snap
        self._render_snapshot()
        self._show_banner(msg, kind="success" if ok else "error", spinning=False, auto_hide=2200)
        return GLib.SOURCE_REMOVE

    def _on_eth_switch_changed(self, sw: Gtk.Switch, _pspec: Any, eth: dict[str, Any]) -> None:
        if self._updating_ui or not self.backend:
            return
        active = sw.get_active()
        if active:
            self._run_action(
                f"Connecting {eth['device']}...",
                lambda: self.backend.connect_ethernet(eth["device"], eth.get("uuid") or None),
            )
        else:
            self._run_action(
                f"Disconnecting {eth['device']}...",
                lambda: self.backend.disconnect_connection(eth.get("uuid") or None, eth["device"]),
            )

    def _on_vpn_switch_changed(self, sw: Gtk.Switch, _pspec: Any, vpn_uuid: Optional[str]) -> None:
        if self._updating_ui or not self.backend:
            return
        want_on = sw.get_active()
        self._run_action(
            "Connecting VPN..." if want_on else "Disconnecting VPN...",
            lambda: self.backend.toggle_vpn(nm_vpn_uuid=vpn_uuid, active=not want_on),
        )

    def _on_wifi_row_clicked(self, ssid: str) -> None:
        net = next((n for n in self.snapshot.get("wifi_networks", []) if n["ssid"] == ssid), None)
        if not net:
            return
        if net.get("in_use") or net.get("saved"):
            self._open_details({"kind": "wifi", "ssid": ssid})
        elif net.get("secured"):
            self._open_connect_page(net)
        else:
            self._connect_wifi_async(ssid=ssid, password="", hidden=False, saved_uuid=None)

    def _on_wifi_row_switch(self, sw: Gtk.Switch, _pspec: Any, ssid: str) -> None:
        if self._updating_ui or not self.backend:
            return
        if not sw.get_active():
            net = next((n for n in self.snapshot.get("wifi_networks", []) if n["ssid"] == ssid), None)
            if net:
                self._run_action(
                    f"Disconnecting {ssid}...",
                    lambda: self.backend.disconnect_connection(net.get("uuid") or None, net.get("device") or None),
                )

    def _on_wifi_connect_clicked(self, ssid: str) -> None:
        net = next((n for n in self.snapshot.get("wifi_networks", []) if n["ssid"] == ssid), None)
        if not net:
            return
        if net.get("saved"):
            self._connect_wifi_async(
                ssid=ssid,
                password=None,
                hidden=False,
                saved_uuid=net.get("saved_uuid") or None,
                wifi_dev=net.get("device") or None,
                net_obj=net,
            )
        elif net.get("secured"):
            self._open_connect_page(net)
        else:
            self._connect_wifi_async(
                ssid=ssid,
                password="",
                hidden=False,
                saved_uuid=None,
                wifi_dev=net.get("device") or None,
                net_obj=net,
            )

    def _submit_wifi_password(self) -> None:
        if not self._connect_target:
            return
        pw = self.conn_pw_entry.get_text()
        if not pw:
            self._show_banner("Please enter a password", kind="error", auto_hide=2500)
            return
        net = self._connect_target
        self._connect_wifi_async(
            ssid=net["ssid"],
            password=pw,
            hidden=False,
            saved_uuid=net.get("saved_uuid") or None,
            wifi_dev=net.get("device") or None,
            net_obj=net,
            on_success=self._go_main,
        )

    def _submit_hidden_network(self) -> None:
        ssid = self.hid_ssid_entry.get_text().strip()
        if not ssid:
            self._show_banner("Enter a network SSID", kind="error", auto_hide=2500)
            return
        is_open = self.hid_sec_dropdown.get_selected() == 1
        pw = "" if is_open else self.hid_pw_entry.get_text()
        if not is_open and not pw:
            self._show_banner("Enter a password or choose Open security", kind="error", auto_hide=2500)
            return
        wifi_devs = self.snapshot.get("wifi_devices", [])
        wdev = wifi_devs[0]["device"] if wifi_devs else None
        self._connect_wifi_async(
            ssid=ssid,
            password=pw,
            hidden=True,
            saved_uuid=None,
            wifi_dev=wdev,
            on_success=self._go_main,
        )

    def _connect_wifi_async(
        self,
        ssid: str,
        password: Optional[str],
        hidden: bool,
        saved_uuid: Optional[str],
        wifi_dev: Optional[str] = None,
        net_obj: Optional[dict[str, Any]] = None,
        on_success: Optional[Callable[[], None]] = None,
    ) -> None:
        if not self.backend or self._busy:
            return
        self._busy = True
        self._show_banner(f"Connecting to {ssid}...", kind="info", spinning=True)

        def _work() -> None:
            res = self.backend.connect_wifi(
                ssid=ssid,
                password=password,
                hidden=hidden,
                saved_uuid=saved_uuid,
                wifi_dev=wifi_dev,
            )
            GLib.idle_add(self._on_connect_wifi_done, res, net_obj, on_success)

        threading.Thread(target=_work, daemon=True).start()

    def _on_connect_wifi_done(
        self,
        res: dict[str, Any],
        net_obj: Optional[dict[str, Any]],
        on_success: Optional[Callable[[], None]],
    ) -> bool:
        self._busy = False
        self.refresh_state()
        if res.get("ok"):
            self._show_banner(res["message"], kind="success", spinning=False, auto_hide=3000)
            if on_success is not None:
                on_success()
        elif res.get("needs_password") and net_obj is not None:
            self._show_banner("Password required for this network", kind="info", spinning=False, auto_hide=3000)
            self._open_connect_page(net_obj)
        else:
            self._show_banner(res.get("message") or "Connection failed", kind="error", spinning=False, auto_hide=4500)
        return GLib.SOURCE_REMOVE

    def _on_detail_conn_switch(self, sw: Gtk.Switch, _pspec: Any, ent: dict[str, Any]) -> None:
        if self._updating_ui or not self.backend:
            return
        want = sw.get_active()
        if ent["kind"] == "ethernet":
            if want:
                self._run_action(
                    f"Connecting {ent['device']}...",
                    lambda: self.backend.connect_ethernet(ent["device"], ent.get("uuid") or None),
                )
            else:
                self._run_action(
                    f"Disconnecting {ent['device']}...",
                    lambda: self.backend.disconnect_connection(ent.get("uuid") or None, ent["device"]),
                )
        elif ent["kind"] == "vpn":
            self._run_action(
                "Connecting VPN..." if want else "Disconnecting VPN...",
                lambda: self.backend.toggle_vpn(nm_vpn_uuid=ent.get("uuid") or None, active=not want),
            )
        elif ent["kind"] == "wifi":
            if want:
                self._connect_wifi_async(
                    ssid=ent["title"],
                    password=None,
                    hidden=False,
                    saved_uuid=ent.get("uuid") or None,
                    wifi_dev=ent.get("device") or None,
                )
            else:
                self._run_action(
                    f"Disconnecting {ent['title']}...",
                    lambda: self.backend.disconnect_connection(ent.get("uuid") or None, ent.get("device") or None),
                )

    def _on_detail_autoconnect(self, sw: Gtk.Switch, _pspec: Any, uuid: str) -> None:
        if self._updating_ui or not self.backend:
            return
        enabled = sw.get_active()
        threading.Thread(
            target=lambda: self.backend.set_autoconnect(uuid, enabled),
            daemon=True,
        ).start()

    def _on_detail_reconnect(self) -> None:
        ent = self._resolve_detail_entity()
        if not ent or not self.backend:
            return
        self._run_action(
            f"Reconnecting {ent['title']}...",
            lambda: self.backend.reconnect_connection(ent.get("uuid") or "", ent.get("device") or None),
        )

    def _on_detail_forget(self) -> None:
        ent = self._resolve_detail_entity()
        if not ent or not ent.get("uuid"):
            return
        self._forget_profile(ent["uuid"], ent["title"], go_back=True)

    def _forget_profile(self, uuid: str, name: str, go_back: bool = False) -> None:
        if not self.backend:
            return
        self._run_action(
            f"Forgetting {name}...",
            lambda: self.backend.forget_connection(uuid),
            on_ok=self._go_main if go_back else None,
        )


def main(argv: Optional[list[str]] = None) -> int:
    app = NetworkWidgetApp()
    return app.run(argv if argv is not None else sys.argv)


if __name__ == "__main__":
    sys.exit(main())
