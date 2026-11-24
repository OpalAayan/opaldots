#!/usr/bin/env python3
"""
Robust Bluetooth D-Bus + bluetoothctl backend for Ironbar and the GTK4 Bluetooth widget.
"""

from __future__ import annotations

import argparse
import ctypes
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

gi.require_version("Gio", "2.0")
gi.require_version("GLib", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

BLUEZ_SERVICE = "org.bluez"
DBUS_OM_IFACE = "org.freedesktop.DBus.ObjectManager"
DBUS_PROPS_IFACE = "org.freedesktop.DBus.Properties"
ADAPTER_IFACE = "org.bluez.Adapter1"
DEVICE_IFACE = "org.bluez.Device1"
BATTERY_IFACE = "org.bluez.Battery1"
AGENT_MANAGER_IFACE = "org.bluez.AgentManager1"
AGENT_IFACE = "org.bluez.Agent1"
AGENT_PATH = "/dev/ironbar/bt_agent"

_MAC_COLON_RE = re.compile(r"^[0-9A-Fa-f]{2}(?::[0-9A-Fa-f]{2}){5}$")
_MAC_DASH_RE = re.compile(r"^[0-9A-Fa-f]{2}(?:-[0-9A-Fa-f]{2}){5}$")
_MAC_RAW_RE = re.compile(r"^[0-9A-Fa-f]{12}$")

AGENT_XML = """
<node>
  <interface name="org.bluez.Agent1">
    <method name="Release" />
    <method name="RequestPinCode">
      <arg type="o" name="device" direction="in" />
      <arg type="s" name="pincode" direction="out" />
    </method>
    <method name="DisplayPinCode">
      <arg type="o" name="device" direction="in" />
      <arg type="s" name="pincode" direction="in" />
    </method>
    <method name="RequestPasskey">
      <arg type="o" name="device" direction="in" />
      <arg type="u" name="passkey" direction="out" />
    </method>
    <method name="DisplayPasskey">
      <arg type="o" name="device" direction="in" />
      <arg type="u" name="passkey" direction="in" />
      <arg type="q" name="entered" direction="in" />
    </method>
    <method name="RequestConfirmation">
      <arg type="o" name="device" direction="in" />
      <arg type="u" name="passkey" direction="in" />
    </method>
    <method name="RequestAuthorization">
      <arg type="o" name="device" direction="in" />
    </method>
    <method name="AuthorizeService">
      <arg type="o" name="device" direction="in" />
      <arg type="s" name="uuid" direction="in" />
    </method>
    <method name="Cancel" />
  </interface>
</node>
"""


def set_pdeathsig() -> None:
    """Ensure child watch processes exit immediately when parent Ironbar exits/reloads."""
    try:
        libc = ctypes.CDLL("libc.so.6")
        pr_set_pdeathsig = 1
        libc.prctl(pr_set_pdeathsig, signal.SIGTERM)
    except Exception:
        pass


def normalize_mac(raw: str) -> Optional[str]:
    """Normalize MAC addresses (colon, dash, or bare 12-hex) to AA:BB:CC:DD:EE:FF."""
    if not raw:
        return None
    cleaned = raw.strip()
    if _MAC_COLON_RE.match(cleaned):
        return cleaned.upper()
    if _MAC_DASH_RE.match(cleaned):
        return cleaned.replace("-", ":").upper()
    if _MAC_RAW_RE.match(cleaned):
        upper = cleaned.upper()
        return ":".join(upper[i : i + 2] for i in range(0, 12, 2))
    return None


def mac_to_dbus_path(adapter_path: str, mac: str) -> str:
    norm = normalize_mac(mac) or mac.upper()
    return f"{adapter_path.rstrip('/')}/dev_{norm.replace(':', '_')}"


def is_unnamed_device(dev: dict[str, Any]) -> bool:
    """Return True if BlueZ has no real device name and Alias is just the MAC."""
    name = (dev.get("name") or "").strip()
    if name:
        return False
    alias = (dev.get("alias") or "").strip().upper()
    addr = (dev.get("address") or "").strip().upper()
    if not alias:
        return True
    return alias in {addr, addr.replace(":", "-"), addr.replace(":", "")}


def classify_device(icon: str, dev_class: int) -> tuple[str, str]:
    """Map BlueZ Icon name (with Class-of-Device fallback) to (Nerd glyph, label)."""
    icon_l = (icon or "").strip().lower()
    mapping: list[tuple[str, tuple[str, str]]] = [
        ("audio-headset", ("󰋋", "Headset")),
        ("audio-headphones", ("󰋋", "Headphones")),
        ("audio-card", ("󰓃", "Speaker")),
        ("audio-speakers", ("󰓃", "Speaker")),
        ("input-mouse", ("󰍽", "Mouse")),
        ("input-keyboard", ("󰌌", "Keyboard")),
        ("phone", ("󰏲", "Phone")),
        ("input-gaming", ("󰊗", "Controller")),
        ("computer", ("󰌢", "Computer")),
    ]
    for key, val in mapping:
        if icon_l == key:
            return val
    if icon_l.startswith("camera-"):
        return ("󰄀", "Camera")

    if dev_class:
        major = (dev_class >> 8) & 0x1F
        minor = (dev_class >> 2) & 0x3F
        if major == 0x01:
            return ("󰌢", "Computer")
        if major == 0x02:
            return ("󰏲", "Phone")
        if major == 0x04:
            if minor in (0x01, 0x02):
                return ("󰋋", "Headset")
            if minor == 0x06:
                return ("󰋋", "Headphones")
            return ("󰓃", "Audio")
        if major == 0x05:
            if minor & 0x20:
                return ("󰍽", "Mouse")
            if minor & 0x10:
                return ("󰌌", "Keyboard")
            if (minor & 0x0F) in (0x01, 0x02):
                return ("󰊗", "Controller")
        if major == 0x06 and (minor & 0x08):
            return ("󰄀", "Camera")

    return ("󰂯", "Bluetooth Device")


def rssi_quality(rssi: Optional[int]) -> str:
    if rssi is None:
        return "Unknown"
    if rssi >= -55:
        return "Excellent"
    if rssi >= -70:
        return "Good"
    if rssi >= -82:
        return "Fair"
    return "Weak"


def _interruptible_sleep(seconds: float, cancel_event: Optional[threading.Event]) -> bool:
    """Sleep in short slices; returns False if cancelled."""
    if cancel_event is None:
        time.sleep(seconds)
        return True
    deadline = time.monotonic() + seconds
    while time.monotonic() < deadline:
        if cancel_event.is_set():
            return False
        time.sleep(min(0.15, max(0.01, deadline - time.monotonic())))
    return not cancel_event.is_set()


class BluezManager:
    """Thread-safe BlueZ D-Bus + bluetoothctl manager with robust retry logic."""

    def __init__(self, bus: Optional[Gio.DBusConnection] = None) -> None:
        self.bus = bus or Gio.bus_get_sync(Gio.BusType.SYSTEM, None)
        self._op_lock = threading.Lock()
        self.active_pair_macs: set[str] = set()

    def _call(
        self,
        object_path: str,
        interface_name: str,
        method_name: str,
        parameters: Optional[GLib.Variant] = None,
        timeout_ms: int = 10000,
    ) -> Any:
        res = self.bus.call_sync(
            BLUEZ_SERVICE,
            object_path,
            interface_name,
            method_name,
            parameters,
            None,
            Gio.DBusCallFlags.NONE,
            timeout_ms,
            None,
        )
        return res.unpack() if res is not None else None

    def _set_prop(
        self, object_path: str, interface_name: str, prop: str, value: GLib.Variant
    ) -> None:
        self._call(
            object_path,
            DBUS_PROPS_IFACE,
            "Set",
            GLib.Variant("(ssv)", (interface_name, prop, value)),
            timeout_ms=5000,
        )

    def get_snapshot(self) -> dict[str, Any]:
        """Fetch current adapter and all known devices from BlueZ ObjectManager."""
        try:
            raw = self._call("/", DBUS_OM_IFACE, "GetManagedObjects", timeout_ms=4000)
            objects: dict[str, dict[str, dict[str, Any]]] = raw[0] if raw else {}
        except Exception as exc:
            return {"adapter": None, "devices": [], "error": str(exc)}

        adapters: list[dict[str, Any]] = []
        raw_devices: list[tuple[str, dict[str, Any], dict[str, Any]]] = []

        for path, ifaces in sorted(objects.items()):
            if ADAPTER_IFACE in ifaces:
                a = ifaces[ADAPTER_IFACE]
                adapters.append(
                    {
                        "path": path,
                        "address": str(a.get("Address", "")),
                        "name": str(a.get("Name", "")),
                        "alias": str(a.get("Alias", a.get("Name", "Bluetooth"))),
                        "powered": bool(a.get("Powered", False)),
                        "discoverable": bool(a.get("Discoverable", False)),
                        "pairable": bool(a.get("Pairable", False)),
                        "discovering": bool(a.get("Discovering", False)),
                    }
                )
            if DEVICE_IFACE in ifaces:
                raw_devices.append((path, ifaces[DEVICE_IFACE], ifaces.get(BATTERY_IFACE, {})))

        adapter: Optional[dict[str, Any]] = None
        if adapters:
            hci0 = [a for a in adapters if a["path"].endswith("/hci0")]
            adapter = hci0[0] if hci0 else adapters[0]

        adapter_prefix = f"{adapter['path']}/" if adapter else ""
        devices: list[dict[str, Any]] = []

        for path, d, bat in raw_devices:
            if adapter_prefix and not path.startswith(adapter_prefix):
                continue
            addr = str(d.get("Address", "")).upper()
            name = str(d.get("Name", "") or "").strip()
            alias = str(d.get("Alias", "") or "").strip()
            icon_name = str(d.get("Icon", "") or "")
            class_id = int(d.get("Class", 0) or 0)
            glyph, type_label = classify_device(icon_name, class_id)
            rssi_val = d.get("RSSI")
            rssi = int(rssi_val) if rssi_val is not None else None
            bat_val = bat.get("Percentage") if bat else None
            battery = int(bat_val) if bat_val is not None else None
            display_name = name or alias or addr
            dev_info = {
                "path": path,
                "address": addr,
                "name": name,
                "alias": alias,
                "display_name": display_name,
                "icon_name": icon_name,
                "glyph": glyph,
                "type_label": type_label,
                "paired": bool(d.get("Paired", False)),
                "bonded": bool(d.get("Bonded", False)),
                "trusted": bool(d.get("Trusted", False)),
                "blocked": bool(d.get("Blocked", False)),
                "connected": bool(d.get("Connected", False)),
                "rssi": rssi,
                "rssi_quality": rssi_quality(rssi) if rssi is not None else "",
                "battery": battery,
                "class_id": class_id,
            }
            dev_info["unnamed"] = is_unnamed_device(dev_info)
            devices.append(dev_info)

        return {"adapter": adapter, "devices": devices}

    def _get_adapter_path(self) -> Optional[str]:
        snap = self.get_snapshot()
        adapter = snap.get("adapter")
        return adapter["path"] if adapter else None

    def find_device(self, mac: str, snap: Optional[dict[str, Any]] = None) -> Optional[dict[str, Any]]:
        norm = normalize_mac(mac)
        if not norm:
            return None
        current = snap or self.get_snapshot()
        for dev in current.get("devices", []):
            if dev.get("address", "").upper() == norm:
                return dev
        return None

    def set_powered(self, on: bool) -> tuple[bool, str]:
        adapter_path = self._get_adapter_path()
        if not adapter_path:
            return (False, "No Bluetooth adapter found")

        if on:
            subprocess.run(
                ["rfkill", "unblock", "bluetooth"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=3,
                check=False,
            )
            try:
                self._set_prop(adapter_path, ADAPTER_IFACE, "Powered", GLib.Variant("b", True))
            except Exception:
                subprocess.run(
                    ["bluetoothctl", "power", "on"],
                    stdout=subprocess.DEVNULL,
                    stderr=subprocess.DEVNULL,
                    timeout=5,
                    check=False,
                )
            deadline = time.monotonic() + 4.0
            while time.monotonic() < deadline:
                snap = self.get_snapshot()
                ad = snap.get("adapter")
                if ad and ad.get("powered"):
                    return (True, "Bluetooth powered on")
                time.sleep(0.15)
            return (False, "Timed out powering on Bluetooth adapter")

        self.stop_discovery()
        try:
            self._set_prop(adapter_path, ADAPTER_IFACE, "Powered", GLib.Variant("b", False))
            return (True, "Bluetooth powered off")
        except Exception as exc:
            res = subprocess.run(
                ["bluetoothctl", "power", "off"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=5,
                check=False,
            )
            if res.returncode == 0:
                return (True, "Bluetooth powered off")
            return (False, f"Failed to power off Bluetooth: {exc}")

    def toggle_powered(self) -> tuple[bool, str]:
        snap = self.get_snapshot()
        adapter = snap.get("adapter")
        if not adapter:
            return (False, "No Bluetooth adapter found")
        return self.set_powered(not adapter["powered"])

    def set_discoverable(self, on: bool) -> tuple[bool, str]:
        adapter_path = self._get_adapter_path()
        if not adapter_path:
            return (False, "No Bluetooth adapter found")
        try:
            self._set_prop(adapter_path, ADAPTER_IFACE, "Discoverable", GLib.Variant("b", on))
            return (True, "Discoverable enabled" if on else "Discoverable disabled")
        except Exception as exc:
            return (False, f"Failed to update discoverable state: {exc}")

    def set_trusted(self, device_path_or_mac: str, trusted: bool) -> tuple[bool, str]:
        device_path = device_path_or_mac
        if not device_path.startswith("/"):
            dev = self.find_device(device_path_or_mac)
            if not dev:
                return (False, "Device not found")
            device_path = dev["path"]
        try:
            self._set_prop(device_path, DEVICE_IFACE, "Trusted", GLib.Variant("b", trusted))
            return (True, "Trusted updated")
        except Exception as exc:
            return (False, f"Failed to update trusted state: {exc}")

    def start_discovery(self) -> tuple[bool, str]:
        adapter_path = self._get_adapter_path()
        if not adapter_path:
            return (False, "No Bluetooth adapter found")
        try:
            self._call(adapter_path, ADAPTER_IFACE, "StartDiscovery", timeout_ms=5000)
            return (True, "Discovery started")
        except Exception as exc:
            msg = str(exc)
            if "InProgress" in msg:
                return (True, "Discovery already in progress")
            return (False, f"Failed to start scan: {msg}")

    def stop_discovery(self) -> None:
        adapter_path = self._get_adapter_path()
        if adapter_path:
            try:
                self._call(adapter_path, ADAPTER_IFACE, "StopDiscovery", timeout_ms=4000)
            except Exception:
                pass
        snap = self.get_snapshot()
        adapter = snap.get("adapter")
        if adapter and adapter.get("discovering"):
            subprocess.run(
                ["bluetoothctl", "scan", "off"],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                timeout=3,
                check=False,
            )

    def disconnect(self, mac: str) -> tuple[bool, str]:
        norm = normalize_mac(mac)
        if not norm:
            return (False, f"Invalid MAC address: {mac}")
        dev = self.find_device(norm)
        label = dev["display_name"] if dev else norm
        if dev and not dev["connected"]:
            return (True, f"{label} is already disconnected")

        if dev:
            try:
                self._call(dev["path"], DEVICE_IFACE, "Disconnect", timeout_ms=10000)
                time.sleep(0.4)
                after = self.find_device(norm)
                if not after or not after["connected"]:
                    return (True, f"Disconnected from {label}")
            except Exception:
                pass

        res = subprocess.run(
            ["bluetoothctl", "disconnect", norm],
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=10,
            check=False,
        )
        after = self.find_device(norm)
        if not after or not after["connected"]:
            return (True, f"Disconnected from {label}")
        err = (res.stderr or res.stdout or "").strip() or "Disconnect failed"
        return (False, err)

    def remove_device(self, mac: str) -> tuple[bool, str]:
        norm = normalize_mac(mac)
        if not norm:
            return (False, f"Invalid MAC address: {mac}")
        snap = self.get_snapshot()
        adapter = snap.get("adapter")
        if not adapter:
            return (False, "No Bluetooth adapter found")
        dev = self.find_device(norm, snap)
        if not dev:
            return (True, f"{norm} already removed")

        label = dev["display_name"]
        try:
            self._call(
                adapter["path"],
                ADAPTER_IFACE,
                "RemoveDevice",
                GLib.Variant("(o)", (dev["path"],)),
                timeout_ms=8000,
            )
            return (True, f"Removed {label}")
        except Exception:
            res = subprocess.run(
                ["bluetoothctl", "remove", norm],
                stdout=subprocess.PIPE,
                stderr=subprocess.PIPE,
                text=True,
                timeout=8,
                check=False,
            )
            if self.find_device(norm) is None:
                return (True, f"Removed {label}")
            err = (res.stderr or res.stdout or "").strip() or "Failed to remove device"
            return (False, err)

    def _run_btctl(
        self,
        args: list[str],
        timeout: float,
        cancel_event: Optional[threading.Event] = None,
    ) -> tuple[int, str]:
        """Run bluetoothctl with interruptible cancellation and timeout."""
        proc = subprocess.Popen(
            ["bluetoothctl", *args],
            stdout=subprocess.PIPE,
            stderr=subprocess.STDOUT,
            text=True,
        )
        deadline = time.monotonic() + timeout
        try:
            while True:
                rc = proc.poll()
                if rc is not None:
                    out = proc.stdout.read() if proc.stdout else ""
                    return (rc, out.strip())
                if cancel_event is not None and cancel_event.is_set():
                    proc.terminate()
                    try:
                        proc.wait(timeout=1.5)
                    except subprocess.TimeoutExpired:
                        proc.kill()
                    return (-2, "Cancelled")
                if time.monotonic() >= deadline:
                    proc.terminate()
                    try:
                        proc.wait(timeout=1.5)
                    except subprocess.TimeoutExpired:
                        proc.kill()
                    return (-1, "Timed out")
                time.sleep(0.2)
        finally:
            if proc.stdout:
                try:
                    proc.stdout.close()
                except Exception:
                    pass

    def _scan_for_mac(
        self,
        mac: str,
        scan_timeout: int,
        cancel_event: Optional[threading.Event],
        progress_cb: Optional[Callable[[str], None]],
        require_fresh: bool = False,
        label: Optional[str] = None,
    ) -> Optional[dict[str, Any]]:
        """
        Keep BlueZ discovery alive via `bluetoothctl --timeout N scan on` until MAC is found,
        then cleanly stop scanning and settle the radio before pairing/connecting.
        """
        target_label = label or mac
        initial_dev = self.find_device(mac)
        initial_rssi = initial_dev.get("rssi") if initial_dev else None

        scan_proc = subprocess.Popen(
            ["bluetoothctl", "--timeout", str(scan_timeout), "scan", "on"],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
        )
        found_dev: Optional[dict[str, Any]] = None
        start = time.monotonic()
        last_sec_reported = -1

        try:
            while True:
                if cancel_event is not None and cancel_event.is_set():
                    return None
                elapsed = time.monotonic() - start
                remaining = max(0, int(scan_timeout - elapsed))
                if progress_cb and remaining != last_sec_reported:
                    last_sec_reported = remaining
                    progress_cb(f"Scanning for {target_label} ({remaining}s)...")

                dev = self.find_device(mac)
                if dev is not None:
                    if not require_fresh:
                        found_dev = dev
                        break
                    # If the device was already cached before scan started, wait briefly for
                    # fresh inquiry/RSSI or up to 2.5s so bluetoothd finishes probing.
                    if (
                        initial_dev is None
                        or (dev.get("rssi") is not None and dev.get("rssi") != initial_rssi)
                        or elapsed >= 2.5
                    ):
                        found_dev = dev
                        break

                if elapsed >= scan_timeout:
                    found_dev = self.find_device(mac)
                    break
                time.sleep(0.5)
        finally:
            if scan_proc.poll() is None:
                scan_proc.terminate()
                try:
                    scan_proc.wait(timeout=1.5)
                except subprocess.TimeoutExpired:
                    scan_proc.kill()
            self.stop_discovery()

        # Radio settle time so connect/pair doesn't collide with discovery teardown
        if not _interruptible_sleep(0.9, cancel_event):
            return None
        return found_dev

    def _pair_and_trust(
        self,
        mac: str,
        timeout: int,
        cancel_event: Optional[threading.Event],
        progress_cb: Optional[Callable[[str], None]],
        label: str,
    ) -> bool:
        if progress_cb:
            progress_cb(f"Pairing & trusting {label}...")
        dev = self.find_device(mac)
        if dev:
            # Prefer D-Bus Pair() so our registered BluezAgent handles prompts cleanly,
            # falling back to bluetoothctl pair if needed.
            try:
                self._call(dev["path"], DEVICE_IFACE, "Pair", timeout_ms=timeout * 1000)
            except Exception:
                self._run_btctl(["pair", mac], timeout, cancel_event)
        else:
            self._run_btctl(["pair", mac], timeout, cancel_event)

        if cancel_event and cancel_event.is_set():
            return False

        dev = self.find_device(mac)
        if dev:
            self.set_trusted(dev["path"], True)
        self._run_btctl(["trust", mac], 5, cancel_event)
        _interruptible_sleep(0.8, cancel_event)
        dev_after = self.find_device(mac)
        return bool(dev_after and dev_after.get("paired"))

    def _connect_only(
        self,
        mac: str,
        timeout: int,
        cancel_event: Optional[threading.Event],
    ) -> bool:
        dev = self.find_device(mac)
        if dev:
            # Ensure trusted before connecting
            if not dev.get("trusted"):
                self.set_trusted(dev["path"], True)
            res_holder: dict[str, Any] = {}
            done = threading.Event()

            def _on_done(_src: Any, res: Gio.AsyncResult) -> None:
                try:
                    self.bus.call_finish(res)
                    res_holder["ok"] = True
                except Exception as exc:
                    res_holder["err"] = str(exc)
                finally:
                    done.set()

            self.bus.call(
                BLUEZ_SERVICE,
                dev["path"],
                DEVICE_IFACE,
                "Connect",
                None,
                None,
                Gio.DBusCallFlags.NONE,
                timeout * 1000,
                None,
                _on_done,
            )
            deadline = time.monotonic() + timeout + 1.0
            while not done.is_set():
                if cancel_event and cancel_event.is_set():
                    return False
                if time.monotonic() >= deadline:
                    break
                time.sleep(0.2)
            if not res_holder.get("ok"):
                self._run_btctl(["connect", mac], timeout, cancel_event)
        else:
            self._run_btctl(["connect", mac], timeout, cancel_event)

        if not _interruptible_sleep(1.5, cancel_event):
            return False
        after = self.find_device(mac)
        return bool(after and after.get("connected"))

    def smart_connect(
        self,
        mac: str,
        progress_cb: Optional[Callable[[str], None]] = None,
        cancel_event: Optional[threading.Event] = None,
    ) -> tuple[bool, str]:
        """Fast connect for known/paired devices with automatic scan + pair + trust fallback."""
        norm = normalize_mac(mac)
        if not norm:
            return (False, f"Invalid MAC address: {mac}")

        with self._op_lock:
            self.active_pair_macs.add(norm)
            try:
                snap = self.get_snapshot()
                adapter = snap.get("adapter")
                if not adapter:
                    return (False, "No Bluetooth adapter found")

                if not adapter["powered"]:
                    if progress_cb:
                        progress_cb("Powering on Bluetooth...")
                    ok, msg = self.set_powered(True)
                    if not ok:
                        return (False, msg)

                dev = self.find_device(norm)
                label = dev["display_name"] if dev else norm
                if dev and dev.get("connected"):
                    return (True, f"{label} is already connected")

                # Always stop discovery before connecting so the radio isn't busy
                self.stop_discovery()
                if not _interruptible_sleep(0.7, cancel_event):
                    return (False, "Cancelled")

                # Fast path if already paired
                if dev and dev.get("paired"):
                    if progress_cb:
                        progress_cb(f"Connecting to {label}...")
                    if self._connect_only(norm, 12, cancel_event):
                        after = self.find_device(norm)
                        final_name = after["display_name"] if after else label
                        return (True, f"Connected to {final_name}")

                if cancel_event and cancel_event.is_set():
                    return (False, "Cancelled")

                # Fallback: scan for device, stop scan, pair/trust if needed, connect
                found = self._scan_for_mac(
                    norm,
                    scan_timeout=12,
                    cancel_event=cancel_event,
                    progress_cb=progress_cb,
                    require_fresh=bool(dev is not None),
                    label=label,
                )
                if cancel_event and cancel_event.is_set():
                    return (False, "Cancelled")
                if not found:
                    return (False, f"{label} not found — try Force Reconnect")

                label = found["display_name"]
                if not found.get("paired"):
                    self._pair_and_trust(norm, 15, cancel_event, progress_cb, label)
                    if cancel_event and cancel_event.is_set():
                        return (False, "Cancelled")
                elif not found.get("trusted"):
                    self.set_trusted(found["path"], True)

                if progress_cb:
                    progress_cb(f"Connecting to {label}...")
                if self._connect_only(norm, 15, cancel_event):
                    after = self.find_device(norm)
                    final_name = after["display_name"] if after else label
                    return (True, f"Connected to {final_name}")

                return (False, f"Could not connect to {label} — try Force Reconnect")
            finally:
                self.active_pair_macs.discard(norm)
                self.stop_discovery()

    def force_reconnect(
        self,
        mac: str,
        max_retries: int = 2,
        scan_timeout: int = 15,
        connect_timeout: int = 15,
        reset_on_retry: bool = True,
        progress_cb: Optional[Callable[[str], None]] = None,
        cancel_event: Optional[threading.Event] = None,
    ) -> tuple[bool, str]:
        """
        Full robust reconnect state machine (from reconnect_headset.sh):
        Power on -> Scan -> Stop Scan -> Pair & Trust -> Connect -> Verify -> Remove & Retry.
        """
        norm = normalize_mac(mac)
        if not norm:
            return (False, f"Invalid MAC address: {mac}")

        with self._op_lock:
            self.active_pair_macs.add(norm)
            try:
                snap = self.get_snapshot()
                adapter = snap.get("adapter")
                if not adapter:
                    return (False, "No Bluetooth adapter found")

                if not adapter["powered"]:
                    if progress_cb:
                        progress_cb("Powering on Bluetooth...")
                    ok, msg = self.set_powered(True)
                    if not ok:
                        return (False, msg)
                    if not _interruptible_sleep(1.2, cancel_event):
                        return (False, "Cancelled")

                dev = self.find_device(norm)
                label = dev["display_name"] if dev else norm
                if dev and dev.get("connected"):
                    return (True, f"{label} is already connected")

                self.stop_discovery()

                for attempt in range(1, max_retries + 1):
                    if cancel_event and cancel_event.is_set():
                        return (False, "Cancelled")

                    if progress_cb:
                        progress_cb(f"Attempt {attempt}/{max_retries}: Scanning for {label}...")

                    existing = self.find_device(norm)
                    found = self._scan_for_mac(
                        norm,
                        scan_timeout=scan_timeout,
                        cancel_event=cancel_event,
                        progress_cb=progress_cb,
                        require_fresh=(attempt == 1 and existing is not None),
                        label=label,
                    )
                    if cancel_event and cancel_event.is_set():
                        return (False, "Cancelled")

                    if not found:
                        if progress_cb:
                            progress_cb(f"Attempt {attempt}/{max_retries}: {label} not found during scan.")
                    else:
                        label = found["display_name"]
                        if not found.get("paired"):
                            self._pair_and_trust(norm, connect_timeout, cancel_event, progress_cb, label)
                            if cancel_event and cancel_event.is_set():
                                return (False, "Cancelled")
                        elif not found.get("trusted"):
                            self.set_trusted(found["path"], True)

                        if progress_cb:
                            progress_cb(f"Attempt {attempt}/{max_retries}: Connecting to {label}...")
                        if self._connect_only(norm, connect_timeout, cancel_event):
                            after = self.find_device(norm)
                            final_name = after["display_name"] if after else label
                            return (True, f"Connected to {final_name}")

                        if progress_cb:
                            progress_cb(f"Attempt {attempt}/{max_retries}: Connection failed or timed out.")

                    if attempt < max_retries and reset_on_retry:
                        if cancel_event and cancel_event.is_set():
                            return (False, "Cancelled")
                        if progress_cb:
                            progress_cb(f"Resetting {label} before retry...")
                        self.remove_device(norm)
                        self.stop_discovery()
                        if not _interruptible_sleep(2.0, cancel_event):
                            return (False, "Cancelled")

                return (False, f"Could not connect to {label} after {max_retries} attempts")
            finally:
                self.active_pair_macs.discard(norm)
                self.stop_discovery()


class BluezAgent:
    """Lightweight org.bluez.Agent1 implementation for seamless pairing."""

    def __init__(
        self,
        bus: Gio.DBusConnection,
        manager: BluezManager,
        on_confirm: Optional[Callable[[str, str, Callable[[bool], None]], None]] = None,
        on_display_code: Optional[Callable[[str, str], None]] = None,
    ) -> None:
        self.bus = bus
        self.manager = manager
        self.on_confirm = on_confirm
        self.on_display_code = on_display_code
        self._reg_id: int = 0
        self._registered_with_bluez = False

    def register(self) -> bool:
        try:
            node_info = Gio.DBusNodeInfo.new_for_xml(AGENT_XML)
            iface_info = node_info.lookup_interface(AGENT_IFACE)
            self._reg_id = self.bus.register_object(
                AGENT_PATH,
                iface_info,
                self._on_method_call,
                None,
                None,
            )
            self.bus.call_sync(
                BLUEZ_SERVICE,
                "/org/bluez",
                AGENT_MANAGER_IFACE,
                "RegisterAgent",
                GLib.Variant("(os)", (AGENT_PATH, "DisplayYesNo")),
                None,
                Gio.DBusCallFlags.NONE,
                3000,
                None,
            )
            self._registered_with_bluez = True
            try:
                self.bus.call_sync(
                    BLUEZ_SERVICE,
                    "/org/bluez",
                    AGENT_MANAGER_IFACE,
                    "RequestDefaultAgent",
                    GLib.Variant("(o)", (AGENT_PATH,)),
                    None,
                    Gio.DBusCallFlags.NONE,
                    3000,
                    None,
                )
            except Exception:
                pass
            return True
        except Exception:
            return False

    def unregister(self) -> None:
        if self._registered_with_bluez:
            try:
                self.bus.call_sync(
                    BLUEZ_SERVICE,
                    "/org/bluez",
                    AGENT_MANAGER_IFACE,
                    "UnregisterAgent",
                    GLib.Variant("(o)", (AGENT_PATH,)),
                    None,
                    Gio.DBusCallFlags.NONE,
                    2000,
                    None,
                )
            except Exception:
                pass
            self._registered_with_bluez = False
        if self._reg_id:
            try:
                self.bus.unregister_object(self._reg_id)
            except Exception:
                pass
            self._reg_id = 0

    def _device_mac_from_path(self, device_path: str) -> str:
        tail = device_path.rsplit("/", 1)[-1]
        if tail.startswith("dev_"):
            return tail[4:].replace("_", ":").upper()
        return ""

    def _on_method_call(
        self,
        _connection: Gio.DBusConnection,
        _sender: str,
        _object_path: str,
        _interface_name: str,
        method_name: str,
        parameters: GLib.Variant,
        invocation: Gio.DBusMethodInvocation,
    ) -> None:
        args = parameters.unpack() if parameters is not None else ()

        if method_name in ("Release", "Cancel"):
            invocation.return_value(None)
            return

        if method_name == "RequestPinCode":
            invocation.return_value(GLib.Variant("(s)", ("0000",)))
            return

        if method_name == "RequestPasskey":
            invocation.return_value(GLib.Variant("(u)", (0,)))
            return

        if method_name == "DisplayPinCode":
            dev_path, pincode = args
            if self.on_display_code:
                self.on_display_code(dev_path, str(pincode))
            invocation.return_value(None)
            return

        if method_name == "DisplayPasskey":
            dev_path, passkey, _entered = args
            if self.on_display_code:
                self.on_display_code(dev_path, f"{int(passkey):06d}")
            invocation.return_value(None)
            return

        if method_name == "RequestConfirmation":
            dev_path, passkey = args
            code_str = f"{int(passkey):06d}"
            if self.on_confirm:
                resolved = {"done": False}

                def respond(accepted: bool) -> None:
                    if resolved["done"]:
                        return
                    resolved["done"] = True
                    if accepted:
                        invocation.return_value(None)
                    else:
                        invocation.return_dbus_error(
                            "org.bluez.Error.Rejected", "Passkey rejected by user"
                        )

                self.on_confirm(dev_path, code_str, respond)
            else:
                invocation.return_value(None)
            return

        if method_name in ("RequestAuthorization", "AuthorizeService"):
            dev_path = args[0]
            mac = self._device_mac_from_path(dev_path)
            dev = self.manager.find_device(mac) if mac else None
            if mac in self.manager.active_pair_macs or (dev and (dev.get("paired") or dev.get("trusted"))):
                invocation.return_value(None)
            else:
                invocation.return_value(None)
            return

        invocation.return_dbus_error(
            "org.bluez.Error.Rejected", f"Unsupported method {method_name}"
        )


def format_bar_icon(snap: dict[str, Any]) -> str:
    adapter = snap.get("adapter")
    if not adapter or not adapter.get("powered"):
        return "<span color='#6c7086'>󰂲</span>"
    connected = [d for d in snap.get("devices", []) if d.get("connected")]
    if connected:
        return "<span color='#89b4fa'>󰂱</span>"
    return "<span color='#89b4fa'>󰂯</span>"


def format_bar_tooltip(snap: dict[str, Any]) -> str:
    adapter = snap.get("adapter")
    if not adapter:
        return "Bluetooth: No adapter found"
    if not adapter.get("powered"):
        return "Bluetooth: Off (Click to open • Middle-click to toggle)"
    connected = [d for d in snap.get("devices", []) if d.get("connected")]
    if connected:
        parts = []
        for dev in connected:
            bat = dev.get("battery")
            if bat is not None:
                parts.append(f"{dev['display_name']} ({bat}%)")
            else:
                parts.append(dev["display_name"])
        return "Bluetooth: " + ", ".join(parts)
    return "Bluetooth: On • No devices connected"


def format_cc_subtitle(snap: dict[str, Any]) -> str:
    adapter = snap.get("adapter")
    if not adapter:
        return "Unavailable"
    if not adapter.get("powered"):
        return "Off"
    connected = [d for d in snap.get("devices", []) if d.get("connected")]
    if len(connected) == 1:
        dev = connected[0]
        name = dev["display_name"]
        bat = dev.get("battery")
        if bat is not None:
            short = name if len(name) <= 15 else name[:14] + "…"
            return f"{short} • {bat}%"
        return name if len(name) <= 22 else name[:21] + "…"
    if len(connected) > 1:
        return f"{len(connected)} connected"
    return "On • Ready"


def format_by_mode(mode: str, snap: dict[str, Any]) -> str:
    if mode == "icon":
        return format_bar_icon(snap)
    if mode == "tooltip":
        return format_bar_tooltip(snap)
    if mode == "cc-subtitle":
        return format_cc_subtitle(snap)
    raise ValueError(f"Unknown format mode: {mode}")


def _reap_stale_watchers(mode: str) -> None:
    """Terminate older watch processes for the same mode spawned by an earlier bar reload."""
    my_pid = os.getpid()
    my_ppid = os.getppid()
    now = time.time()
    script_name = os.path.basename(__file__)
    try:
        entries = os.listdir("/proc")
    except Exception:
        return
    for entry in entries:
        if not entry.isdigit():
            continue
        pid = int(entry)
        if pid == my_pid:
            continue
        try:
            proc_dir = f"/proc/{pid}"
            if now - os.stat(proc_dir).st_mtime < 1.5:
                continue
            with open(f"{proc_dir}/stat", "r", encoding="utf-8", errors="ignore") as f:
                stat_txt = f.read()
            rparen = stat_txt.rfind(")")
            if rparen < 0:
                continue
            ppid = int(stat_txt[rparen + 2 :].split()[1])
            if ppid != my_ppid:
                continue
            with open(f"{proc_dir}/cmdline", "rb") as f:
                parts = [p.decode("utf-8", errors="ignore") for p in f.read().split(b"\x00") if p]
            if any(p.endswith(script_name) for p in parts) and "watch" in parts and mode in parts:
                os.kill(pid, signal.SIGTERM)
        except Exception:
            continue


def run_watch(mode: str) -> int:
    """Zero-CPU D-Bus watcher for Ironbar `watch:` scripts."""
    set_pdeathsig()
    _reap_stale_watchers(mode)
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)

    manager = BluezManager()
    last_output: Optional[str] = None
    pending_timer: dict[str, Optional[int]] = {"id": None}

    def emit_now() -> bool:
        nonlocal last_output
        pending_timer["id"] = None
        snap = manager.get_snapshot()
        text = format_by_mode(mode, snap)
        if text != last_output:
            last_output = text
            try:
                sys.stdout.write(text + "\n")
                sys.stdout.flush()
            except BrokenPipeError:
                sys.exit(0)
        return False

    def schedule_emit(*_args: Any) -> None:
        if pending_timer["id"] is not None:
            return
        pending_timer["id"] = GLib.timeout_add(100, emit_now)

    emit_now()

    sub_ids = [
        manager.bus.signal_subscribe(
            BLUEZ_SERVICE,
            DBUS_PROPS_IFACE,
            "PropertiesChanged",
            None,
            None,
            Gio.DBusSignalFlags.NONE,
            schedule_emit,
        ),
        manager.bus.signal_subscribe(
            BLUEZ_SERVICE,
            DBUS_OM_IFACE,
            "InterfacesAdded",
            None,
            None,
            Gio.DBusSignalFlags.NONE,
            schedule_emit,
        ),
        manager.bus.signal_subscribe(
            BLUEZ_SERVICE,
            DBUS_OM_IFACE,
            "InterfacesRemoved",
            None,
            None,
            Gio.DBusSignalFlags.NONE,
            schedule_emit,
        ),
    ]

    loop = GLib.MainLoop()
    pipe_watch_id: Optional[int] = None

    def _on_pipe_closed(_fd: int, _cond: GLib.IOCondition) -> bool:
        loop.quit()
        return False

    try:
        pipe_watch_id = GLib.io_add_watch(
            sys.stdout.fileno(),
            GLib.PRIORITY_DEFAULT,
            GLib.IOCondition.ERR | GLib.IOCondition.HUP | GLib.IOCondition.NVAL,
            _on_pipe_closed,
        )
    except Exception:
        pipe_watch_id = None

    def _quit(*_args: Any) -> None:
        loop.quit()

    signal.signal(signal.SIGTERM, _quit)
    signal.signal(signal.SIGINT, _quit)

    try:
        loop.run()
    except (KeyboardInterrupt, BrokenPipeError):
        pass
    finally:
        if pipe_watch_id is not None:
            try:
                GLib.source_remove(pipe_watch_id)
            except Exception:
                pass
        for sid in sub_ids:
            try:
                manager.bus.signal_unsubscribe(sid)
            except Exception:
                pass
    return 0


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Ironbar BlueZ Bluetooth Backend")
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("icon")
    sub.add_parser("tooltip")
    sub.add_parser("cc-subtitle")
    sub.add_parser("status-json")

    p_watch = sub.add_parser("watch")
    p_watch.add_argument("mode", choices=["icon", "tooltip", "cc-subtitle"])

    p_power = sub.add_parser("power")
    p_power.add_argument("state", choices=["on", "off", "toggle"])

    p_connect = sub.add_parser("connect")
    p_connect.add_argument("mac")

    p_reconn = sub.add_parser("reconnect")
    p_reconn.add_argument("mac")
    p_reconn.add_argument("--retries", type=int, default=2)
    p_reconn.add_argument("--scan-timeout", type=int, default=15)
    p_reconn.add_argument("--connect-timeout", type=int, default=15)
    p_reconn.add_argument("--no-reset", action="store_true")

    p_disc = sub.add_parser("disconnect")
    p_disc.add_argument("mac")

    p_rem = sub.add_parser("remove")
    p_rem.add_argument("mac")

    args = parser.parse_args(argv)

    if args.cmd == "watch":
        return run_watch(args.mode)

    manager = BluezManager()

    if args.cmd in ("icon", "tooltip", "cc-subtitle"):
        snap = manager.get_snapshot()
        print(format_by_mode(args.cmd, snap))
        return 0

    if args.cmd == "status-json":
        print(json.dumps(manager.get_snapshot(), indent=2))
        return 0

    if args.cmd == "power":
        if args.state == "toggle":
            ok, msg = manager.toggle_powered()
        else:
            ok, msg = manager.set_powered(args.state == "on")
        print(msg)
        return 0 if ok else 1

    if args.cmd == "disconnect":
        ok, msg = manager.disconnect(args.mac)
        print(msg)
        return 0 if ok else 1

    if args.cmd == "remove":
        ok, msg = manager.remove_device(args.mac)
        print(msg)
        return 0 if ok else 1

    if args.cmd in ("connect", "reconnect"):
        agent = BluezAgent(manager.bus, manager)
        agent.register()
        try:
            def log_cb(msg: str) -> None:
                print(msg, flush=True)

            if args.cmd == "connect":
                ok, msg = manager.smart_connect(args.mac, progress_cb=log_cb)
            else:
                ok, msg = manager.force_reconnect(
                    args.mac,
                    max_retries=args.retries,
                    scan_timeout=args.scan_timeout,
                    connect_timeout=args.connect_timeout,
                    reset_on_retry=not args.no_reset,
                    progress_cb=log_cb,
                )
            print(msg)
            return 0 if ok else 1
        finally:
            agent.unregister()

    return 1


if __name__ == "__main__":
    sys.exit(main())
