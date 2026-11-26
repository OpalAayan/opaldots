#!/usr/bin/env python3
"""
Robust NetworkManager D-Bus + nmcli + /proc/net/dev backend for Ironbar and net_widget.py.
Supports smart Ethernet/Wi-Fi/VPN detection, live bit-rate monitoring, Wi-Fi scanning,
password/hidden connections, saved profile management, and zero-CPU D-Bus watchers.
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
import time
from typing import Any, Optional

import gi

gi.require_version("Gio", "2.0")
gi.require_version("GLib", "2.0")
from gi.repository import Gio, GLib  # noqa: E402

NM_SERVICE = "org.freedesktop.NetworkManager"
VPN_LOCK_FILE = "/tmp/.vpn_control.lock"
SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
VPN_SCRIPT = os.path.join(SCRIPT_DIR, "vpn_control.sh")


def set_pdeathsig() -> None:
    """Ensure child watch processes exit immediately when parent Ironbar exits/reloads."""
    try:
        libc = ctypes.CDLL("libc.so.6")
        libc.prctl(1, signal.SIGTERM)
    except Exception:
        pass


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


def split_nmcli_line(line: str) -> list[str]:
    """Split an `nmcli -t` line on unescaped colons and unescape `\\:` / `\\\\`."""
    fields: list[str] = []
    buf: list[str] = []
    escaped = False
    for ch in line.rstrip("\r\n"):
        if escaped:
            buf.append(ch)
            escaped = False
        elif ch == "\\":
            escaped = True
        elif ch == ":":
            fields.append("".join(buf))
            buf.clear()
        else:
            buf.append(ch)
    if escaped:
        buf.append("\\")
    fields.append("".join(buf))
    return fields


def wifi_signal_glyph(sig: int) -> str:
    if sig >= 80:
        return "󰤨"
    if sig >= 60:
        return "󰤥"
    if sig >= 40:
        return "󰤢"
    if sig >= 20:
        return "󰤟"
    return "󰤯"


def signal_quality(sig: int) -> str:
    if sig >= 80:
        return "Excellent"
    if sig >= 60:
        return "Good"
    if sig >= 40:
        return "Fair"
    if sig >= 20:
        return "Weak"
    return "Very Weak"


def parse_band(freq_str: str) -> str:
    m = re.search(r"(\d+)", freq_str or "")
    if not m:
        return ""
    mhz = int(m.group(1))
    if mhz >= 5900:
        return "6 GHz"
    if mhz >= 4900:
        return "5 GHz"
    if mhz > 0:
        return "2.4 GHz"
    return ""


def format_bits(bps: float) -> str:
    """Format bit/s cleanly using SI bit units (bps, Kbps, Mbps, Gbps)."""
    bps = max(0.0, float(bps))
    if bps < 1000.0:
        return f"{int(round(bps))} bps"
    if bps < 1_000_000.0:
        kbps = bps / 1000.0
        return f"{kbps:.0f} Kbps" if kbps >= 100.0 else f"{kbps:.1f} Kbps"
    if bps < 1_000_000_000.0:
        mbps = bps / 1_000_000.0
        return f"{mbps:.2f} Mbps" if mbps < 10.0 else f"{mbps:.1f} Mbps"
    return f"{bps / 1_000_000_000.0:.2f} Gbps"


class SpeedMonitor:
    """Computes live interface RX/TX speeds in bits/sec from `/proc/net/dev`."""

    def __init__(self) -> None:
        self._last_iface: Optional[str] = None
        self._last_rx: int = 0
        self._last_tx: int = 0
        self._last_ts: float = 0.0

    def _read_iface_bytes(self, iface: str) -> Optional[tuple[int, int]]:
        try:
            with open("/proc/net/dev", "r", encoding="utf-8") as f:
                lines = f.readlines()[2:]
            for line in lines:
                if ":" not in line:
                    continue
                name, rest = line.split(":", 1)
                if name.strip() == iface:
                    cols = rest.split()
                    if len(cols) >= 9:
                        return (int(cols[0]), int(cols[8]))
        except Exception:
            pass
        return None

    def reset(self) -> None:
        self._last_iface = None
        self._last_ts = 0.0

    def sample(self, iface: Optional[str]) -> tuple[float, float]:
        if not iface:
            self.reset()
            return (0.0, 0.0)
        counts = self._read_iface_bytes(iface)
        now = time.monotonic()
        if counts is None:
            self.reset()
            return (0.0, 0.0)
        rx, tx = counts
        if self._last_iface != iface or self._last_ts <= 0.0:
            self._last_iface = iface
            self._last_rx = rx
            self._last_tx = tx
            self._last_ts = now
            return (0.0, 0.0)
        dt = now - self._last_ts
        if dt <= 0.05:
            return (0.0, 0.0)
        rx_bps = max(0, rx - self._last_rx) * 8.0 / dt
        tx_bps = max(0, tx - self._last_tx) * 8.0 / dt
        self._last_rx = rx
        self._last_tx = tx
        self._last_ts = now
        return (rx_bps, tx_bps)


def _run_cmd(args: list[str], timeout: float = 5.0) -> tuple[int, str, str]:
    try:
        res = subprocess.run(
            args,
            stdout=subprocess.PIPE,
            stderr=subprocess.PIPE,
            text=True,
            timeout=timeout,
            check=False,
        )
        return (res.returncode, res.stdout.strip(), res.stderr.strip())
    except subprocess.TimeoutExpired:
        return (-1, "", "Command timed out")
    except Exception as exc:
        return (-1, "", str(exc))


class NetworkManagerBackend:
    """Thread-safe NetworkManager + iproute2 backend."""

    def __init__(self, bus: Optional[Gio.DBusConnection] = None) -> None:
        self.bus = bus or Gio.bus_get_sync(Gio.BusType.SYSTEM, None)

    def _get_default_route_iface(self) -> Optional[str]:
        rc, out, _ = _run_cmd(["ip", "-4", "route", "show", "default"], timeout=2.0)
        if rc != 0 or not out:
            return None
        best_iface: Optional[str] = None
        best_metric = 1 << 30
        for line in out.splitlines():
            m_dev = re.search(r"\bdev\s+(\S+)", line)
            if not m_dev:
                continue
            dev = m_dev.group(1)
            m_met = re.search(r"\bmetric\s+(\d+)", line)
            metric = int(m_met.group(1)) if m_met else 0
            if metric < best_metric:
                best_metric = metric
                best_iface = dev
        return best_iface

    def _get_device_details(self, device: str) -> dict[str, Any]:
        rc, out, _ = _run_cmd(
            [
                "nmcli",
                "-t",
                "-f",
                "GENERAL.DEVICE,GENERAL.HWADDR,IP4.ADDRESS,IP4.GATEWAY,IP4.DNS,CAPABILITIES.SPEED",
                "device",
                "show",
                device,
            ],
            timeout=2.5,
        )
        info: dict[str, Any] = {
            "hwaddr": "",
            "ip4": "",
            "gateway": "",
            "dns": [],
            "link_speed": "",
        }
        if rc == 0 and out:
            for line in out.splitlines():
                parts = split_nmcli_line(line)
                if len(parts) < 2:
                    continue
                key = re.sub(r"\[\d+\]$", "", parts[0].strip())
                val = ":".join(parts[1:]).strip()
                if not val or val == "--":
                    continue
                if key == "GENERAL.HWADDR":
                    info["hwaddr"] = val
                elif key == "IP4.ADDRESS" and not info["ip4"]:
                    info["ip4"] = val.split("/", 1)[0]
                elif key == "IP4.GATEWAY" and not info["gateway"]:
                    info["gateway"] = val
                elif key == "IP4.DNS":
                    info["dns"].append(val)
                elif key == "CAPABILITIES.SPEED":
                    info["link_speed"] = val

        if not info["ip4"]:
            rc_ip, out_ip, _ = _run_cmd(
                ["ip", "-4", "-o", "addr", "show", "dev", device], timeout=1.5
            )
            if rc_ip == 0 and out_ip:
                m = re.search(r"\binet\s+(\d+\.\d+\.\d+\.\d+)", out_ip)
                if m:
                    info["ip4"] = m.group(1)

        if not info["link_speed"]:
            speed_path = f"/sys/class/net/{device}/speed"
            if os.path.exists(speed_path):
                try:
                    with open(speed_path, "r", encoding="utf-8") as f:
                        spd = int(f.read().strip())
                    if spd > 0:
                        info["link_speed"] = f"{spd} Mb/s"
                except Exception:
                    pass
        return info

    def _detect_vpn(
        self, active_conns: list[dict[str, str]]
    ) -> tuple[dict[str, Any], list[dict[str, Any]]]:
        busy_msg = ""
        if os.path.exists(VPN_LOCK_FILE):
            try:
                with open(VPN_LOCK_FILE, "r", encoding="utf-8") as f:
                    busy_msg = f.read().strip() or "Working..."
            except Exception:
                busy_msg = "Working..."

        proton_cli = any(
            subprocess.run(
                ["which", cmd],
                stdout=subprocess.DEVNULL,
                stderr=subprocess.DEVNULL,
                check=False,
            ).returncode
            == 0
            for cmd in ("protonvpn", "protonvpn-cli")
        )

        active_vpn_conn: Optional[dict[str, str]] = None
        for c in active_conns:
            ctype = c["type"].lower()
            cname = c["name"].lower()
            if ctype in ("vpn", "wireguard") or "proton" in cname or "pvpn" in cname:
                active_vpn_conn = c
                break

        vpn_iface = ""
        rc_link, out_link, _ = _run_cmd(["ip", "-br", "link"], timeout=1.5)
        if rc_link == 0 and out_link:
            for line in out_link.splitlines():
                cols = line.split()
                if not cols:
                    continue
                ifname = cols[0].split("@", 1)[0]
                if re.search(r"proton|pvpn|protun|wg-proton|^tun\d*|^wg\d*", ifname, re.I):
                    vpn_iface = ifname
                    break

        connected = bool(active_vpn_conn or vpn_iface)
        label = ""
        vpn_uuid = ""
        if active_vpn_conn:
            label = active_vpn_conn["name"]
            vpn_uuid = active_vpn_conn["uuid"]
            if not vpn_iface:
                vpn_iface = active_vpn_conn.get("device", "")
            for prefix in ("ProtonVPN ", "Proton VPN ", "pvpn-"):
                if label.startswith(prefix):
                    label = label[len(prefix) :]
        elif vpn_iface:
            label = vpn_iface

        vpn_ip = ""
        if vpn_iface:
            rc_ip, out_ip, _ = _run_cmd(
                ["ip", "-4", "-o", "addr", "show", "dev", vpn_iface], timeout=1.5
            )
            if rc_ip == 0 and out_ip:
                m = re.search(r"\binet\s+(\d+\.\d+\.\d+\.\d+)", out_ip)
                if m:
                    vpn_ip = m.group(1)

        vpn_info = {
            "connected": connected,
            "busy": bool(busy_msg),
            "busy_text": busy_msg,
            "name": label or ("Proton VPN" if proton_cli else "VPN"),
            "iface": vpn_iface,
            "ip4": vpn_ip,
            "uuid": vpn_uuid,
            "has_proton_cli": proton_cli,
        }
        return vpn_info, []

    def get_snapshot(self) -> dict[str, Any]:
        """Collect complete NetworkManager, Ethernet, Wi-Fi, and VPN state."""
        _, radio_out, _ = _run_cmd(["nmcli", "radio", "wifi"], timeout=2.0)
        wifi_enabled = radio_out.strip().lower() == "enabled"

        primary_route_iface = self._get_default_route_iface()

        # Active connections
        active_conns: list[dict[str, str]] = []
        rc_act, out_act, _ = _run_cmd(
            ["nmcli", "-t", "-f", "NAME,UUID,TYPE,DEVICE", "connection", "show", "--active"],
            timeout=2.5,
        )
        if rc_act == 0 and out_act:
            for line in out_act.splitlines():
                p = split_nmcli_line(line)
                if len(p) >= 4:
                    active_conns.append(
                        {"name": p[0], "uuid": p[1], "type": p[2], "device": p[3]}
                    )
        active_by_device = {c["device"]: c for c in active_conns if c["device"]}

        # Saved connections
        saved_wifi: dict[str, dict[str, Any]] = {}
        saved_eth: list[dict[str, Any]] = []
        saved_vpns: list[dict[str, Any]] = []
        rc_sav, out_sav, _ = _run_cmd(
            ["nmcli", "-t", "-f", "NAME,UUID,TYPE,AUTOCONNECT", "connection", "show"],
            timeout=2.5,
        )
        if rc_sav == 0 and out_sav:
            for line in out_sav.splitlines():
                p = split_nmcli_line(line)
                if len(p) < 4:
                    continue
                cname, cuuid, ctype, autoc = p[0], p[1], p[2], p[3].lower() == "yes"
                entry = {"name": cname, "uuid": cuuid, "type": ctype, "autoconnect": autoc}
                if ctype == "802-11-wireless":
                    if cname not in saved_wifi:
                        saved_wifi[cname] = entry
                elif ctype == "802-3-ethernet":
                    saved_eth.append(entry)
                elif ctype in ("vpn", "wireguard"):
                    is_active = any(a["uuid"] == cuuid for a in active_conns)
                    saved_vpns.append({**entry, "connected": is_active})

        # Devices
        ethernet_devices: list[dict[str, Any]] = []
        wifi_devices: list[dict[str, Any]] = []
        rc_dev, out_dev, _ = _run_cmd(
            ["nmcli", "-t", "-f", "DEVICE,TYPE,STATE,CONNECTION", "device", "status"],
            timeout=2.5,
        )
        if rc_dev == 0 and out_dev:
            for line in out_dev.splitlines():
                p = split_nmcli_line(line)
                if len(p) < 4:
                    continue
                dev, dtype, state, conn = p[0], p[1], p[2], p[3]
                if dtype not in ("ethernet", "wifi"):
                    continue
                connected = state == "connected"
                act = active_by_device.get(dev, {})
                details = self._get_device_details(dev) if connected else {
                    "hwaddr": "",
                    "ip4": "",
                    "gateway": "",
                    "dns": [],
                    "link_speed": "",
                }
                if not details["hwaddr"] and os.path.exists(f"/sys/class/net/{dev}/address"):
                    try:
                        with open(f"/sys/class/net/{dev}/address", "r", encoding="utf-8") as f:
                            details["hwaddr"] = f.read().strip().upper()
                    except Exception:
                        pass

                dev_obj: dict[str, Any] = {
                    "device": dev,
                    "type": dtype,
                    "state": state,
                    "connected": connected,
                    "connection": conn or (saved_eth[0]["name"] if dtype == "ethernet" and saved_eth else dev),
                    "uuid": act.get("uuid") or (saved_eth[0]["uuid"] if dtype == "ethernet" and saved_eth else ""),
                    "autoconnect": saved_eth[0]["autoconnect"] if dtype == "ethernet" and saved_eth else True,
                    **details,
                }
                if dtype == "ethernet":
                    ethernet_devices.append(dev_obj)
                else:
                    wifi_devices.append(dev_obj)

        active_wifi_dev = next((d for d in wifi_devices if d["connected"]), None)
        primary_wifi_dev = active_wifi_dev or (wifi_devices[0] if wifi_devices else None)

        # Wi-Fi networks
        wifi_networks: list[dict[str, Any]] = []
        if wifi_enabled and wifi_devices:
            rc_w, out_w, _ = _run_cmd(
                [
                    "nmcli",
                    "-t",
                    "-f",
                    "IN-USE,SSID,BSSID,SIGNAL,SECURITY,FREQ,RATE",
                    "device",
                    "wifi",
                    "list",
                    "--rescan",
                    "no",
                ],
                timeout=3.0,
            )
            by_ssid: dict[str, dict[str, Any]] = {}
            if rc_w == 0 and out_w:
                for line in out_w.splitlines():
                    p = split_nmcli_line(line)
                    if len(p) < 7:
                        continue
                    in_use_raw, ssid, bssid, sig_s, sec, freq, rate = p[:7]
                    ssid = ssid.strip()
                    if not ssid:
                        continue
                    in_use = in_use_raw.strip() == "*"
                    try:
                        sig = int(sig_s.strip())
                    except ValueError:
                        sig = 0
                    sec_clean = "" if sec.strip() in ("", "--") else sec.strip()
                    cand = {
                        "ssid": ssid,
                        "bssid": bssid.strip(),
                        "signal": sig,
                        "glyph": wifi_signal_glyph(sig),
                        "quality": signal_quality(sig),
                        "security": sec_clean or "Open",
                        "secured": bool(sec_clean),
                        "freq": freq.strip(),
                        "band": parse_band(freq),
                        "rate": rate.strip(),
                        "in_use": in_use,
                    }
                    prev = by_ssid.get(ssid)
                    if prev is None:
                        by_ssid[ssid] = cand
                    elif cand["in_use"] and not prev["in_use"]:
                        by_ssid[ssid] = cand
                    elif not prev["in_use"] and cand["signal"] > prev["signal"]:
                        by_ssid[ssid] = cand

            for ssid, net in by_ssid.items():
                sav = saved_wifi.get(ssid)
                net["saved"] = sav is not None
                net["saved_uuid"] = sav["uuid"] if sav else ""
                net["autoconnect"] = sav["autoconnect"] if sav else False
                if net["in_use"] and active_wifi_dev:
                    net["device"] = active_wifi_dev["device"]
                    net["ip4"] = active_wifi_dev["ip4"]
                    net["gateway"] = active_wifi_dev["gateway"]
                    net["dns"] = active_wifi_dev["dns"]
                    net["hwaddr"] = active_wifi_dev["hwaddr"]
                    net["uuid"] = active_wifi_dev["uuid"] or net["saved_uuid"]
                else:
                    net["device"] = primary_wifi_dev["device"] if primary_wifi_dev else ""
                    net["ip4"] = ""
                    net["gateway"] = ""
                    net["dns"] = []
                    net["hwaddr"] = primary_wifi_dev["hwaddr"] if primary_wifi_dev else ""
                    net["uuid"] = net["saved_uuid"]
                wifi_networks.append(net)

            wifi_networks.sort(
                key=lambda n: (
                    not n["in_use"],
                    not n["saved"],
                    -n["signal"],
                    n["ssid"].lower(),
                )
            )

        visible_ssids = {n["ssid"] for n in wifi_networks}
        saved_out_of_range = sorted(
            [v for name, v in saved_wifi.items() if name not in visible_ssids],
            key=lambda v: v["name"].lower(),
        )

        vpn_info, _ = self._detect_vpn(active_conns)

        # Smart transport summary
        connected_eth = [d for d in ethernet_devices if d["connected"]]
        connected_wifi = [d for d in wifi_devices if d["connected"]]
        active_wifi_net = next((n for n in wifi_networks if n["in_use"]), None)

        primary_transport = "offline"
        primary_iface: Optional[str] = None
        if primary_route_iface and any(d["device"] == primary_route_iface for d in connected_eth):
            primary_transport = "ethernet"
            primary_iface = primary_route_iface
        elif primary_route_iface and any(d["device"] == primary_route_iface for d in connected_wifi):
            primary_transport = "wifi"
            primary_iface = primary_route_iface
        elif connected_eth:
            primary_transport = "ethernet"
            primary_iface = connected_eth[0]["device"]
        elif connected_wifi:
            primary_transport = "wifi"
            primary_iface = connected_wifi[0]["device"]
        elif vpn_info["connected"] and vpn_info["iface"]:
            primary_iface = vpn_info["iface"]

        if vpn_info["connected"]:
            mode = f"{primary_transport}+vpn" if primary_transport != "offline" else "vpn"
        else:
            mode = primary_transport

        if mode == "ethernet+vpn":
            eth_name = connected_eth[0]["connection"] if connected_eth else "Ethernet"
            title = "Ethernet + VPN"
            subtitle = f"{eth_name} • VPN: {vpn_info['name']}"
            bar_icon = "<span color='#cba6f7'>󰖂</span>"
            bar_tooltip = f"Network: Ethernet ({eth_name}) • VPN: {vpn_info['name']}"
        elif mode == "wifi+vpn":
            ssid_name = active_wifi_net["ssid"] if active_wifi_net else (connected_wifi[0]["connection"] if connected_wifi else "Wi-Fi")
            title = "Wi-Fi + VPN"
            subtitle = f"{ssid_name} • VPN: {vpn_info['name']}"
            bar_icon = "<span color='#cba6f7'>󰖂</span>"
            bar_tooltip = f"Network: {ssid_name} • VPN: {vpn_info['name']}"
        elif mode == "vpn":
            title = "VPN Connected"
            subtitle = vpn_info["name"]
            bar_icon = "<span color='#cba6f7'>󰖂</span>"
            bar_tooltip = f"Network: VPN ({vpn_info['name']})"
        elif mode == "ethernet":
            eth0 = connected_eth[0]
            title = "Ethernet"
            subtitle = f"{eth0['connection']} • {eth0['ip4'] or eth0['device']}"
            bar_icon = "<span color='#94e2d5'>󰈀</span>"
            bar_tooltip = f"Ethernet: {eth0['connection']} ({eth0['ip4'] or eth0['device']})"
        elif mode == "wifi":
            w0 = connected_wifi[0]
            sig = active_wifi_net["signal"] if active_wifi_net else 75
            glyph = active_wifi_net["glyph"] if active_wifi_net else wifi_signal_glyph(sig)
            ssid_name = active_wifi_net["ssid"] if active_wifi_net else w0["connection"]
            title = "Wi-Fi"
            subtitle = f"{ssid_name} • {sig}%"
            bar_icon = f"<span color='#94e2d5'>{glyph}</span>"
            bar_tooltip = f"Wi-Fi: {ssid_name} ({sig}%)"
        else:
            title = "Offline"
            subtitle = "Wi-Fi off" if not wifi_enabled else "Not connected"
            bar_icon = "<span color='#6c7086'>󰖪</span>"
            bar_tooltip = "Network: Disconnected"

        return {
            "wifi_enabled": wifi_enabled,
            "ethernet_devices": ethernet_devices,
            "wifi_devices": wifi_devices,
            "wifi_networks": wifi_networks,
            "saved_out_of_range": saved_out_of_range,
            "vpn": vpn_info,
            "nm_vpns": saved_vpns,
            "summary": {
                "mode": mode,
                "primary_transport": primary_transport,
                "primary_iface": primary_iface or "",
                "title": title,
                "subtitle": subtitle,
                "bar_icon": bar_icon,
                "bar_tooltip": bar_tooltip,
            },
        }

    # ── Network Actions ──────────────────────────────────────────────────────

    def rescan_wifi(self, wifi_dev: Optional[str] = None) -> tuple[bool, str]:
        args = ["nmcli", "device", "wifi", "rescan"]
        if wifi_dev:
            args.extend(["ifname", wifi_dev])
        rc, _, err = _run_cmd(args, timeout=8.0)
        if rc == 0 or "immediately following" in err.lower():
            return (True, "Wi-Fi scan completed")
        return (False, err or "Failed to scan Wi-Fi")

    def set_wifi_radio(self, on: bool) -> tuple[bool, str]:
        if on:
            _run_cmd(["rfkill", "unblock", "wifi"], timeout=2.0)
        rc, _, err = _run_cmd(["nmcli", "radio", "wifi", "on" if on else "off"], timeout=5.0)
        if rc == 0:
            return (True, "Wi-Fi enabled" if on else "Wi-Fi disabled")
        return (False, err or "Failed to toggle Wi-Fi radio")

    def toggle_wifi_radio(self) -> tuple[bool, str]:
        _, out, _ = _run_cmd(["nmcli", "radio", "wifi"], timeout=2.0)
        return self.set_wifi_radio(out.strip().lower() != "enabled")

    def _friendly_nm_error(self, err: str) -> str:
        low = (err or "").lower()
        if any(k in low for k in ("secrets were required", "no suitable secrets", "bad password", "802-11-wireless-security")):
            return "Incorrect password or authentication failed"
        if "no network with ssid" in low or "cannot find" in low:
            return "Network not found in range"
        if "timeout" in low or "timed out" in low:
            return "Connection timed out"
        return (err or "Connection failed").splitlines()[-1]

    def connect_wifi(
        self,
        ssid: str,
        password: Optional[str] = None,
        hidden: bool = False,
        saved_uuid: Optional[str] = None,
        wifi_dev: Optional[str] = None,
    ) -> dict[str, Any]:
        ssid = (ssid or "").strip()
        if not ssid:
            return {"ok": False, "message": "Network SSID cannot be empty", "needs_password": False}

        # Saved network quick connect when no explicit password given
        if saved_uuid and password is None and not hidden:
            rc, _, err = _run_cmd(["nmcli", "--wait", "18", "connection", "up", "uuid", saved_uuid], timeout=20.0)
            if rc == 0:
                return {"ok": True, "message": f"Connected to {ssid}", "needs_password": False}
            low = err.lower()
            if any(k in low for k in ("secrets were required", "no suitable secrets", "psk", "password")):
                return {"ok": False, "message": "Password required", "needs_password": True}
            return {"ok": False, "message": self._friendly_nm_error(err), "needs_password": False}

        # If replacing credentials for an existing saved profile, remove the old profile cleanly
        if saved_uuid and password is not None:
            _run_cmd(["nmcli", "connection", "delete", "uuid", saved_uuid], timeout=5.0)

        args = ["nmcli", "--wait", "20", "device", "wifi", "connect", ssid]
        if password is not None and password != "":
            args.extend(["password", password])
        if hidden:
            args.extend(["hidden", "yes"])
        if wifi_dev:
            args.extend(["ifname", wifi_dev])

        rc, _, err = _run_cmd(args, timeout=22.0)
        if rc == 0:
            return {"ok": True, "message": f"Connected to {ssid}", "needs_password": False}
        low = err.lower()
        needs_pw = any(k in low for k in ("secrets were required", "no suitable secrets", "psk", "password"))
        return {"ok": False, "message": self._friendly_nm_error(err), "needs_password": needs_pw}

    def disconnect_connection(
        self, uuid: Optional[str] = None, device: Optional[str] = None
    ) -> tuple[bool, str]:
        if uuid:
            rc, _, err = _run_cmd(["nmcli", "connection", "down", "uuid", uuid], timeout=8.0)
            if rc == 0:
                return (True, "Disconnected")
        if device:
            rc, _, err = _run_cmd(["nmcli", "device", "disconnect", device], timeout=8.0)
            if rc == 0:
                return (True, f"Disconnected {device}")
            return (False, err or f"Failed to disconnect {device}")
        return (False, "No connection or device specified")

    def connect_ethernet(self, device: str, conn_uuid: Optional[str] = None) -> tuple[bool, str]:
        if conn_uuid:
            rc, _, err = _run_cmd(["nmcli", "--wait", "12", "connection", "up", "uuid", conn_uuid], timeout=14.0)
            if rc == 0:
                return (True, f"Connected {device}")
        rc, _, err = _run_cmd(["nmcli", "--wait", "12", "device", "connect", device], timeout=14.0)
        if rc == 0:
            return (True, f"Connected {device}")
        return (False, err or f"Failed to connect {device}")

    def reconnect_connection(self, uuid: str, device: Optional[str] = None) -> tuple[bool, str]:
        if uuid:
            _run_cmd(["nmcli", "connection", "down", "uuid", uuid], timeout=6.0)
            time.sleep(0.4)
            rc, _, err = _run_cmd(["nmcli", "--wait", "18", "connection", "up", "uuid", uuid], timeout=20.0)
            if rc == 0:
                return (True, "Reconnected")
            return (False, self._friendly_nm_error(err))
        if device:
            _run_cmd(["nmcli", "device", "disconnect", device], timeout=6.0)
            time.sleep(0.4)
            return self.connect_ethernet(device)
        return (False, "No connection specified")

    def forget_connection(self, uuid: str) -> tuple[bool, str]:
        if not uuid:
            return (False, "No saved profile UUID")
        rc, _, err = _run_cmd(["nmcli", "connection", "delete", "uuid", uuid], timeout=6.0)
        if rc == 0:
            return (True, "Forgot saved network")
        return (False, err or "Failed to forget network")

    def set_autoconnect(self, uuid: str, enabled: bool) -> tuple[bool, str]:
        if not uuid:
            return (False, "No saved profile UUID")
        rc, _, err = _run_cmd(
            ["nmcli", "connection", "modify", "uuid", uuid, "connection.autoconnect", "yes" if enabled else "no"],
            timeout=5.0,
        )
        if rc == 0:
            return (True, "Auto-connect updated")
        return (False, err or "Failed to update auto-connect")

    def get_wifi_password(self, uuid: str) -> Optional[str]:
        if not uuid:
            return None
        rc, out, _ = _run_cmd(
            ["nmcli", "-s", "-g", "802-11-wireless-security.psk", "connection", "show", "uuid", uuid],
            timeout=3.0,
        )
        if rc == 0 and out:
            return out
        return None

    def toggle_vpn(self, nm_vpn_uuid: Optional[str] = None, active: bool = False) -> tuple[bool, str]:
        if nm_vpn_uuid:
            cmd = ["nmcli", "--wait", "20", "connection", "down" if active else "up", "uuid", nm_vpn_uuid]
            rc, _, err = _run_cmd(cmd, timeout=22.0)
            if rc == 0:
                return (True, "VPN disconnected" if active else "VPN connected")
            return (False, err or "VPN operation failed")
        if os.path.exists(VPN_SCRIPT):
            rc, _, err = _run_cmd([VPN_SCRIPT, "toggle"], timeout=35.0)
            if rc == 0:
                return (True, "VPN toggled")
            return (False, err or "VPN toggle failed")
        return (False, "VPN control script not found")


def run_watch(mode: str) -> int:
    """Zero-CPU NetworkManager D-Bus watcher for Ironbar `watch:` scripts."""
    set_pdeathsig()
    _reap_stale_watchers(mode)
    signal.signal(signal.SIGPIPE, signal.SIG_DFL)

    backend = NetworkManagerBackend()
    last_output: Optional[str] = None
    pending_timer: dict[str, Optional[int]] = {"id": None}

    def emit_now() -> bool:
        nonlocal last_output
        pending_timer["id"] = None
        snap = backend.get_snapshot()
        text = snap["summary"]["bar_icon"] if mode == "icon" else snap["summary"]["bar_tooltip"]
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
        pending_timer["id"] = GLib.timeout_add(150, emit_now)

    emit_now()

    sub_ids = [
        backend.bus.signal_subscribe(
            NM_SERVICE,
            None,
            None,
            None,
            None,
            Gio.DBusSignalFlags.NONE,
            schedule_emit,
        )
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
                backend.bus.signal_unsubscribe(sid)
            except Exception:
                pass
    return 0


def main(argv: Optional[list[str]] = None) -> int:
    parser = argparse.ArgumentParser(description="Ironbar NetworkManager Backend")
    sub = parser.add_subparsers(dest="cmd", required=True)

    sub.add_parser("icon")
    sub.add_parser("tooltip")
    sub.add_parser("status-json")

    p_watch = sub.add_parser("watch")
    p_watch.add_argument("mode", choices=["icon", "tooltip"])

    sub.add_parser("toggle-wifi")
    sub.add_parser("rescan")

    p_conn = sub.add_parser("connect-wifi")
    p_conn.add_argument("ssid")
    p_conn.add_argument("--password", default=None)
    p_conn.add_argument("--hidden", action="store_true")

    p_disc = sub.add_parser("disconnect")
    p_disc.add_argument("device")

    p_forget = sub.add_parser("forget")
    p_forget.add_argument("uuid")

    args = parser.parse_args(argv)
    if args.cmd == "watch":
        return run_watch(args.mode)

    backend = NetworkManagerBackend()
    if args.cmd == "status-json":
        print(json.dumps(backend.get_snapshot(), indent=2))
        return 0
    if args.cmd == "icon":
        print(backend.get_snapshot()["summary"]["bar_icon"])
        return 0
    if args.cmd == "tooltip":
        print(backend.get_snapshot()["summary"]["bar_tooltip"])
        return 0
    if args.cmd == "toggle-wifi":
        ok, msg = backend.toggle_wifi_radio()
        print(msg)
        return 0 if ok else 1
    if args.cmd == "rescan":
        ok, msg = backend.rescan_wifi()
        print(msg)
        return 0 if ok else 1
    if args.cmd == "connect-wifi":
        res = backend.connect_wifi(args.ssid, password=args.password, hidden=args.hidden)
        print(res["message"])
        return 0 if res["ok"] else 1
    if args.cmd == "disconnect":
        ok, msg = backend.disconnect_connection(device=args.device)
        print(msg)
        return 0 if ok else 1
    if args.cmd == "forget":
        ok, msg = backend.forget_connection(args.uuid)
        print(msg)
        return 0 if ok else 1
    return 1


if __name__ == "__main__":
    sys.exit(main())
