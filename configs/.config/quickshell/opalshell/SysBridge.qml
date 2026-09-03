pragma Singleton

import QtQuick
import Quickshell
import Quickshell.Io

/* =============================================================================
 * SysBridge.qml — System Metrics Data Provider
 * Polls the compiled C bridge binary once per second, parses the JSON
 * response, and exposes reactive properties to all bar modules.
 *
 * Uses the "all" command for a single process spawn per tick.
 * ============================================================================= */

Singleton {
    id: bridge

    /* — Settings — */
    property bool showDecimals: false // Set to false to hide decimals

    /* — Exposed reactive properties — */
    property string cpuUsage: "0"
    property string memoryUsage: "0"
    property string diskUsage: "0"
    property string temperature: "0"
    property int batteryCapacity: -1
    property string batteryStatus: "Unknown"
    property int brightness: 100
    property string networkSsid: ""
    property int networkSignal: 0
    property bool networkConnected: false
    property string networkType: "disconnected"
    property string networkIfname: ""
    property string networkIp: ""
    property double networkUpBytes: 0
    property double networkDownBytes: 0
    property string bluetoothStatus: "off"
    property int bluetoothConnected: 0
    property int audioVolume: 0
    property bool audioMuted: false

    /* — Action Methods — */
    function forceUpdate() {
        sysProcess.running = true;
    }

    /* — Derived states — */
    property bool hasBattery: batteryCapacity >= 0
    property bool isCriticalTemp: temperature >= 80
    property bool isBatteryCharging: batteryStatus === "Charging"
    property bool isBatteryLow: batteryCapacity >= 0 && batteryCapacity <= 15
    property bool isBatteryWarning: batteryCapacity > 15 && batteryCapacity <= 30

    /* — Path to the compiled bridge binary — */
    property string bridgePath: Qt.resolvedUrl("./sysbridge").toString().replace("file://", "")

    /* — Polling timer — */
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            sysProcess.running = true;
        }
    }

    /* — Process to call sysbridge — */
    Process {
        id: sysProcess
        command: [bridge.bridgePath, "all"]
        running: false

        stdout: SplitParser {
            onRead: data => {
                try {
                    var obj = JSON.parse(data);
                    
                    function formatVal(val) {
                        return bridge.showDecimals ? parseFloat(val).toFixed(1) : Math.round(val).toString();
                    }

                    bridge.cpuUsage        = formatVal(obj.cpu       ?? 0);
                    bridge.memoryUsage     = formatVal(obj.memory    ?? 0);
                    bridge.diskUsage       = formatVal(obj.disk      ?? 0);
                    bridge.temperature     = formatVal(obj.temp      ?? 0);
                    bridge.batteryCapacity = obj.battery   ?? -1;
                    bridge.batteryStatus   = obj.batteryStatus ?? "Unknown";
                    bridge.brightness      = obj.brightness ?? 100;

                    if (obj.network) {
                        bridge.networkSsid      = obj.network.ssid      ?? "";
                        bridge.networkSignal    = obj.network.signal    ?? 0;
                        bridge.networkConnected = obj.network.connected ?? false;
                        bridge.networkType      = obj.network.type      ?? "disconnected";
                        bridge.networkIfname    = obj.network.ifname    ?? "";
                        bridge.networkIp        = obj.network.ip        ?? "";
                        bridge.networkUpBytes   = obj.network.upBytes   ?? 0;
                        bridge.networkDownBytes = obj.network.downBytes ?? 0;
                    }

                    if (obj.bluetooth) {
                        bridge.bluetoothStatus    = obj.bluetooth.status    ?? "off";
                        bridge.bluetoothConnected = obj.bluetooth.connected ?? 0;
                    }
                    
                    if (obj.audio) {
                        bridge.audioVolume = obj.audio.volume ?? 0;
                        bridge.audioMuted  = obj.audio.muted  ?? false;
                    }
                } catch(e) {
                    console.warn("SysBridge: Failed to parse JSON:", data, e);
                }
            }
        }
    }
}
