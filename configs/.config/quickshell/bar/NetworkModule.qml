import QtQuick
import Quickshell.Io

/* NetworkModule.qml — Network Status Badge
 * Clicking opens the unified WiFi/BT popup on the Wi-Fi tab.
 */

Badge {
    id: netBadge
    
    // Expose popup control for BluetoothModule to use
    property alias networkPopup: popup

    function formatBytes(bytes) {
        if (bytes === 0) return "0 B/s";
        const k = 1024;
        const sizes = ["B/s", "KB/s", "MB/s", "GB/s"];
        const i = Math.floor(Math.log(bytes) / Math.log(k));
        return parseFloat((bytes / Math.pow(k, i)).toFixed(1)) + " " + sizes[i];
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
        
        var upStr = formatBytes(SysBridge.networkUpBytes);
        var downStr = formatBytes(SysBridge.networkDownBytes);
        tt += "\n⬆ " + upStr + "  ⬇ " + downStr;
        return tt;
    }

    icon: getNetworkIcon()
    label: ""
    showLabel: false
    accentColor: SysBridge.networkConnected ? "#94e2d5" : "#f38ba8"
    iconSize: 14
    implicitWidth: 34
    tooltipText: getTooltip()

    focus: true
    Keys.onEscapePressed: (event) => {
        if (popup.popupVisible) {
            popup.close()
            event.accepted = true
        }
    }

    onClicked: {
        popup.toggle("network")
        if (popup.popupVisible) {
            netBadge.forceActiveFocus()
        }
    }

    NetworkBluetoothPopup {
        id: popup
        anchorItem: netBadge
    }
}
