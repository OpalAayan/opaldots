import QtQuick
import Quickshell.Io

/* NetworkModule.qml — Network Status Badge
 * Clicking opens the unified WiFi/BT popup on the Wi-Fi tab.
 */

Badge {
    id: netBadge
    
    // Expose popup control for BluetoothModule to use
    property alias networkPopup: popup

    function formatSpeed(bytesPerSec) {
        if (!bytesPerSec || bytesPerSec <= 0) return "0 bps";
        let bits = bytesPerSec * 8;
        if (bits >= 1000000000) return (bits / 1000000000).toFixed(1) + " Gbps";
        if (bits >= 1000000)    return (bits / 1000000).toFixed(1) + " Mbps";
        if (bits >= 1000)       return (bits / 1000).toFixed(0) + " Kbps";
        return bits.toFixed(0) + " bps";
    }

    function getNetworkIcon() {
        if (!SysBridge.networkConnected) return "󰤮";
        if (SysBridge.networkType === "ethernet") return "󰈀";
        if (SysBridge.networkType === "vpn") return "󰈀";
        
        // WiFi signal tiers
        if (SysBridge.networkSignal >= 80) return "󰤨";
        if (SysBridge.networkSignal >= 60) return "󰤥";
        if (SysBridge.networkSignal >= 40) return "󰤢";
        if (SysBridge.networkSignal >= 20) return "󰤟";
        return "󰤯";
    }

    function getTooltip() {
        if (!SysBridge.networkConnected) return "Network: Disconnected";
        
        var tt = SysBridge.networkIfname + ": " + SysBridge.networkIp;
        if (SysBridge.networkType === "wifi" && SysBridge.networkSsid !== "") {
            tt += "\n" + SysBridge.networkSsid + " (" + SysBridge.networkSignal + "%)";
        }
        
        var upStr = formatSpeed(SysBridge.networkUpBytes);
        var downStr = formatSpeed(SysBridge.networkDownBytes);
        tt += "\n↓ " + downStr + "  ↑ " + upStr;
        return tt;
    }

    icon: getNetworkIcon()
    label: ""
    showLabel: false
    accentColor: SysBridge.networkConnected ? "#94e2d5" : "#f38ba8"
    iconSize: 14
    implicitWidth: 34
    tooltipText: getTooltip()

    onClicked: {
        popup.toggle("network")
    }

    NetworkBluetoothPopup {
        id: popup
        anchorItem: netBadge
    }
}
