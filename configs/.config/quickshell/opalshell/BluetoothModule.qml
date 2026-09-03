import QtQuick
import Quickshell.Io

/* BluetoothModule.qml — Bluetooth Status Badge
 * Clicking opens the unified WiFi/BT popup on the Bluetooth tab.
 * References the NetworkModule's popup instance via the 'networkModuleRef' property.
 */

Badge {
    id: btBadge
    property string btStatus: SysBridge.bluetoothStatus
    property int connectedDevices: SysBridge.bluetoothConnected

    // Set this from shell.qml to reference NetworkModule's popup
    property var networkModuleRef: null

    function getBtIcon() {
        if (btStatus === "off") return "󰂲"; // bluetooth off
        if (connectedDevices > 0) return "󰂱"; // bluetooth connected
        return "󰂯"; // bluetooth on
    }

    icon: getBtIcon()
    label: connectedDevices > 0 ? connectedDevices.toString() : ""
    showLabel: connectedDevices > 0
    accentColor: btStatus === "off" ? "#6c7086" : "#89b4fa"
    iconSize: 14
    tooltipText: "Bluetooth: " + (btStatus === "on" ? (connectedDevices > 0 ? (connectedDevices + " device(s) connected") : "On") : "Off")

    onClicked: {
        if (networkModuleRef && networkModuleRef.networkPopup) {
            // Use the NetworkModule's shared popup, switch to BT tab
            let popup = networkModuleRef.networkPopup
            popup.anchorItem = btBadge
            popup.toggle("bt")
        }
    }
}
