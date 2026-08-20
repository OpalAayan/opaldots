import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland
import Quickshell.Io

/*  NetworkBluetoothPopup.qml
 *  Unified Wi-Fi / Bluetooth / Ethernet popup for the quickshell bar.
 *  Backend: nmcli + bluetoothctl via standalone shell scripts.
 *  Colors: hardcoded Catppuccin Mocha.
 */

Item {
    id: root

    /* ═══════════════════════════════════════════
     * PUBLIC API
     * ═══════════════════════════════════════════ */
    property bool popupVisible: false
    property string activeMode: "wifi"   // "wifi" | "bt" | "eth"
    property Item anchorItem: parent

    function open(mode)   { activeMode = mode || "wifi"; popupVisible = true }
    function close()      { popupVisible = false; pendingWifiId = ""; pendingWifiSsid = "" }
    function toggle(mode) {
        if (popupVisible && activeMode === mode) { close(); return }
        open(mode)
    }

    onPopupVisibleChanged: {
        if (popupVisible) {
            pollNow();
            pollTimer.start();
            if (activeMode === "wifi") savedNetworksFetcher.running = true
        } else {
            pollTimer.stop()
        }
    }
    onActiveModeChanged: {
        pendingWifiId = ""; pendingWifiSsid = ""
        if (popupVisible) {
            pollNow()
            if (activeMode === "wifi") savedNetworksFetcher.running = true
        }
    }

    /* ═══════════════════════════════════════════
     * THEME — Catppuccin Mocha (hardcoded)
     * ═══════════════════════════════════════════ */
    readonly property color cBase:     "#1e1e2e"
    readonly property color cMantle:   "#181825"
    readonly property color cCrust:    "#11111b"
    readonly property color cText:     "#cdd6f4"
    readonly property color cSubtext0: "#a6adc8"
    readonly property color cSubtext1: "#bac2de"
    readonly property color cOverlay0: "#6c7086"
    readonly property color cOverlay1: "#7f849c"
    readonly property color cSurface0: "#313244"
    readonly property color cSurface1: "#45475a"
    readonly property color cSurface2: "#585b70"
    readonly property color cMauve:    "#cba6f7"
    readonly property color cSapphire: "#74c7ec"
    readonly property color cBlue:     "#89b4fa"
    readonly property color cRed:      "#f38ba8"
    readonly property color cMaroon:   "#eba0ac"
    readonly property color cPeach:    "#fab387"
    readonly property color cTeal:     "#94e2d5"
    readonly property color cGreen:    "#a6e3a1"
    readonly property color cYellow:   "#f9e2af"

    property color activeAccent: activeMode === "bt" ? cMauve
                                        : activeMode === "eth" ? cTeal : cSapphire
    Behavior on activeAccent { ColorAnimation { duration: 350 } }

    readonly property string fontMain: "JetBrainsMono Nerd Font"
    readonly property string fontAlt:  "Rubik"

    /* ═══════════════════════════════════════════
     * PATHS
     * ═══════════════════════════════════════════ */
    readonly property string scriptsDir: {
        let raw = Qt.resolvedUrl("./scripts").toString()
        if (raw.indexOf("file://") === 0) raw = raw.substring(7)
        return raw
    }

    /* ═══════════════════════════════════════════
     * BACKEND STATE
     * ═══════════════════════════════════════════ */
    property bool ethPresent:  false
    property bool wifiPresent: false
    property bool btPresent:   false

    property string ethPower:  "off"
    property string wifiPower: "off"
    property string btPower:   "off"

    property var ethConnected:  null
    property var wifiConnected: null
    property var btConnected:   []
    property var wifiList:      []
    property var btList:        []
    property string ethDeviceName: ""

    // Connection busy state
    property string connectingId: ""
    property string failedId:     ""
    property var busyTasks:             ({})
    property var disconnectingDevices:  ({})

    // WiFi password prompt
    property string pendingWifiSsid: ""
    property string pendingWifiId:   ""
    property var savedWifiNetworks:  []

    // Power-toggle pending
    property bool   ethPowerPending:  false
    property bool   wifiPowerPending: false
    property bool   btPowerPending:   false
    property string expectedEthPower:  ""
    property string expectedWifiPower: ""
    property string expectedBtPower:   ""

    // Derived
    readonly property bool currentPower:
        activeMode === "eth"  ? ethPower  === "on"
      : activeMode === "wifi" ? wifiPower === "on"
      :                         btPower   === "on"
    readonly property bool isEthConn:  !!ethConnected
    readonly property bool isWifiConn: !!wifiConnected && wifiConnected.ssid !== undefined
    readonly property bool isBtConn:   btConnected.length > 0
    readonly property bool currentConn:
        activeMode === "eth" ? isEthConn : activeMode === "wifi" ? isWifiConn : isBtConn
    readonly property bool currentPowerPending:
        activeMode === "eth" ? ethPowerPending : activeMode === "wifi" ? wifiPowerPending : btPowerPending

    /* ═══════════════════════════════════════════
     * TIMERS
     * ═══════════════════════════════════════════ */
    Timer {
        id: pollTimer
        interval: (Object.keys(root.busyTasks).length > 0 ||
                   Object.keys(root.disconnectingDevices).length > 0) ? 1500 : 4000
        running: false; repeat: true
        onTriggered: root.pollNow()
    }
    Timer { id: busyTimeout; interval: 15000
        onTriggered: { root.busyTasks=({}); root.disconnectingDevices=({}); root.connectingId="" }
    }
    Timer { id: failClearTimer; interval: 4000; onTriggered: root.failedId = "" }
    Timer { id: ethPendingReset;  interval: 8000; onTriggered: { root.ethPowerPending=false;  root.expectedEthPower=""  } }
    Timer { id: wifiPendingReset; interval: 8000; onTriggered: { root.wifiPowerPending=false; root.expectedWifiPower="" } }
    Timer { id: btPendingReset;   interval: 8000; onTriggered: { root.btPowerPending=false;   root.expectedBtPower=""   } }

    /* ═══════════════════════════════════════════
     * PROCESSES
     * ═══════════════════════════════════════════ */
    function pollNow() {
        if (!ethPoller.running)  ethPoller.running  = true
        if (!wifiPoller.running) wifiPoller.running = true
        if (!btPoller.running)   btPoller.running   = true
    }

    Process {
        id: ethPoller; running: false
        command: ["bash", root.scriptsDir + "/eth_panel_logic.sh"]
        stdout: StdioCollector { onStreamFinished: root.processEthJson(this.text.trim()) }
    }
    Process {
        id: wifiPoller; running: false
        command: ["bash", root.scriptsDir + "/wifi_panel_logic.sh"]
        stdout: StdioCollector { onStreamFinished: root.processWifiJson(this.text.trim()) }
    }
    Process {
        id: btPoller; running: false
        command: ["bash", root.scriptsDir + "/bluetooth_panel_logic.sh", "--status"]
        stdout: StdioCollector { onStreamFinished: root.processBtJson(this.text.trim()) }
    }
    Process {
        id: connectProcess
        property string targetId: ""
        property string targetSsid: ""
        onExited: {
            let bt = root.busyTasks; delete bt[targetId]
            root.busyTasks = Object.assign({}, bt)
            if (exitCode !== 0) {
                root.failedId = targetId; failClearTimer.restart()
                if (root.activeMode === "wifi" && targetSsid !== "") {
                    Quickshell.execDetached(["bash","-c","nmcli connection delete '"+targetSsid+"' 2>/dev/null"])
                    root.savedWifiNetworks = root.savedWifiNetworks.filter(n => n !== targetSsid)
                }
            }
            root.connectingId = ""; root.pollNow()
        }
    }
    Process {
        id: savedNetworksFetcher; running: false
        command: ["bash","-c","nmcli -t -f NAME connection show | grep -v 'lo'"]
        stdout: StdioCollector {
            onStreamFinished: {
                let t = this.text.trim()
                root.savedWifiNetworks = t ? t.split('\n') : []
            }
        }
    }
    Process {
        id: btScanProcess; running: false
        command: ["bash","-c","timeout 10 bluetoothctl scan on 2>/dev/null || true"]
    }

    /* ═══════════════════════════════════════════
     * DATA PROCESSING
     * ═══════════════════════════════════════════ */
    function processEthJson(txt) {
        if (!txt) return
        try {
            let d = JSON.parse(txt)
            root.ethPresent = d.present === true
            if (d.device) root.ethDeviceName = d.device
            let fp = d.power || "off"
            if (root.ethPowerPending) {
                root.ethPower = root.expectedEthPower
                if (fp === root.expectedEthPower) { root.ethPowerPending = false; ethPendingReset.stop() }
            } else root.ethPower = fp
            let nc = d.connected
            if (JSON.stringify(root.ethConnected) !== JSON.stringify(nc)) root.ethConnected = nc
        } catch(e) {}
    }

    function processWifiJson(txt) {
        if (!txt) return
        try {
            let d = JSON.parse(txt)
            root.wifiPresent = d.present === true
            let fp = d.power || "off"
            if (root.wifiPowerPending) {
                root.wifiPower = root.expectedWifiPower
                if (fp === root.expectedWifiPower) { root.wifiPowerPending = false; wifiPendingReset.stop() }
            } else root.wifiPower = fp
            let nc = d.connected; let nn = d.networks || []
            if (JSON.stringify(root.wifiConnected) !== JSON.stringify(nc)) root.wifiConnected = nc
            nn.sort((a,b) => (a.id||"").localeCompare(b.id||""))
            if (JSON.stringify(root.wifiList) !== JSON.stringify(nn))
                { root.syncModel(wifiListModel, nn); root.wifiList = nn }
            // clear busy for newly connected
            if (root.isWifiConn && nc && root.busyTasks[nc.ssid]) {
                let bt=root.busyTasks; delete bt[nc.ssid]; root.connectingId=""
                root.busyTasks=Object.assign({},bt)
            }
            let dd=root.disconnectingDevices; let ch=false
            for (let s in dd) { if (!root.isWifiConn||(nc&&nc.ssid!==s)){delete dd[s];ch=true} }
            if (ch) root.disconnectingDevices=Object.assign({},dd)
        } catch(e) {}
    }

    function processBtJson(txt) {
        if (!txt) return
        try {
            let d = JSON.parse(txt)
            root.btPresent = d.present === true
            let fp = d.power || "off"
            if (root.btPowerPending) {
                root.btPower = root.expectedBtPower
                if (fp === root.expectedBtPower) { root.btPowerPending = false; btPendingReset.stop() }
            } else root.btPower = fp
            let nc = d.connected || []; if (!Array.isArray(nc)) nc=[nc]
            let nd = d.devices || []; nd.sort((a,b)=>(a.id||"").localeCompare(b.id||""))
            if (JSON.stringify(root.btConnected)!==JSON.stringify(nc)) root.btConnected=nc
            if (JSON.stringify(root.btList)!==JSON.stringify(nd))
                { root.syncModel(btListModel,nd); root.btList=nd }
            let bt=root.busyTasks; let ch=false
            for (let i=0;i<nc.length;i++){if(bt[nc[i].mac]){delete bt[nc[i].mac];root.connectingId="";ch=true}}
            if(ch) root.busyTasks=Object.assign({},bt)
            let dd=root.disconnectingDevices
            for(let m in dd){if(!nc.some(x=>x.mac===m)) delete dd[m]}
            root.disconnectingDevices=Object.assign({},dd)
        } catch(e) {}
    }

    function connectDevice(mode, id, target, password) {
        root.connectingId = id; root.failedId = ""
        let bt = root.busyTasks; bt[id] = true
        root.busyTasks = Object.assign({}, bt); busyTimeout.restart()
        connectProcess.targetId = id
        connectProcess.targetSsid = (mode === "wifi") ? target : ""
        if (mode === "eth")
            connectProcess.command = ["bash","-c","nmcli device connect '"+target+"'"]
        else if (mode === "wifi") {
            if (password)
                connectProcess.command = ["bash","-c","nmcli device wifi connect '"+target+"' password '"+password+"'"]
            else
                connectProcess.command = ["bash","-c","nmcli device wifi connect '"+target+"'"]
        } else
            connectProcess.command = ["bash",root.scriptsDir+"/bluetooth_panel_logic.sh","--connect",target]
        connectProcess.running = true
    }

    function disconnectDevice(mode, id) {
        let dd=root.disconnectingDevices; dd[id]=true
        root.disconnectingDevices=Object.assign({},dd); busyTimeout.restart()
        if (mode==="eth") Quickshell.execDetached(["nmcli","device","disconnect",id])
        else if (mode==="wifi") Quickshell.execDetached(["bash","-c",
            "nmcli device disconnect $(nmcli -t -f DEVICE,TYPE d | grep wifi | cut -d: -f1 | head -n1)"])
        else Quickshell.execDetached(["bash",root.scriptsDir+"/bluetooth_panel_logic.sh","--disconnect",id])
        root.pollNow()
    }

    function togglePower() {
        if (root.activeMode === "eth") {
            if (root.ethPowerPending) return
            root.expectedEthPower = root.ethPower==="on"?"off":"on"
            root.ethPowerPending = true; ethPendingReset.restart()
            root.ethPower = root.expectedEthPower
            let dev = root.ethDeviceName
            if (dev) {
                if (root.expectedEthPower==="on") Quickshell.execDetached(["nmcli","device","connect",dev])
                else Quickshell.execDetached(["nmcli","device","disconnect",dev])
            }
        } else if (root.activeMode === "wifi") {
            if (root.wifiPowerPending) return
            root.expectedWifiPower = root.wifiPower==="on"?"off":"on"
            root.wifiPowerPending = true; wifiPendingReset.restart()
            root.wifiPower = root.expectedWifiPower
            Quickshell.execDetached(["nmcli","radio","wifi",root.wifiPower])
        } else {
            if (root.btPowerPending) return
            root.expectedBtPower = root.btPower==="on"?"off":"on"
            root.btPowerPending = true; btPendingReset.restart()
            root.btPower = root.expectedBtPower
            Quickshell.execDetached(["bash",root.scriptsDir+"/bluetooth_panel_logic.sh","--toggle"])
        }
        root.pollNow()
    }

    /* ═══════════════════════════════════════════
     * LIST MODELS
     * ═══════════════════════════════════════════ */
    ListModel { id: wifiListModel }
    ListModel { id: btListModel }

    function syncModel(lm, arr) {
        for (let i=lm.count-1;i>=0;i--) {
            if (!arr.some(d=>d.id===lm.get(i).id)) lm.remove(i)
        }
        for (let i=0;i<arr.length&&i<30;i++) {
            let d=arr[i]; let fi=-1
            for(let j=i;j<lm.count;j++){if(lm.get(j).id===d.id){fi=j;break}}
            let o={id:d.id||"",ssid:d.ssid||"",mac:d.mac||"",name:d.name||d.ssid||"",
                   icon:d.icon||"",security:d.security||"",action:d.action||""}
            if(fi===-1) lm.insert(i,o)
            else{if(fi!==i)lm.move(fi,i,1);for(let k in o){if(lm.get(i)[k]!==o[k])lm.setProperty(i,k,o[k])}}
        }
    }

    /* ═══════════════════════════════════════════
     * INLINE COMPONENTS
     * ═══════════════════════════════════════════ */
    component InfoPair : RowLayout {
        property string label: ""
        property string value: ""
        spacing: 8
        Text { font.family:root.fontMain; font.pixelSize:10; color:root.cOverlay1; text:parent.label }
        Text { font.family:root.fontMain; font.pixelSize:10; color:root.cSubtext1; text:parent.value; elide:Text.ElideRight; Layout.fillWidth:true }
    }

    /* ═══════════════════════════════════════════
     * POPUP WINDOW
     * ═══════════════════════════════════════════ */
    PopupWindow {
        id: popupWindow
        visible: root.popupVisible
        anchor.item: root.anchorItem
        anchor.edges: Edges.Bottom
        anchor.gravity: Edges.Bottom
        anchor.margins.top: 8
        color: "transparent"
        implicitWidth: 380
        implicitHeight: 540
        
        Shortcut {
            sequence: "Escape"
            onActivated: root.close()
        }

        Rectangle {
            id: bg
            anchors.fill: parent
            radius: 14
            color: root.cBase
            border.color: Qt.rgba(1,1,1,0.06)
            border.width: 1
            clip: true

            /* Subtle accent glow at top of popup */
            Rectangle {
                width: parent.width * 0.5; height: 60
                x: (parent.width - width) / 2; y: -30
                radius: 30; color: root.activeAccent
                opacity: root.currentPower ? 0.07 : 0.02
                Behavior on color   { ColorAnimation { duration: 350 } }
                Behavior on opacity { NumberAnimation { duration: 350 } }
            }

            ColumnLayout {
                anchors.fill: parent
                spacing: 0

                /* ─── HEADER ─── */
                Item {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 50

                    RowLayout {
                        anchors.fill: parent
                        anchors.leftMargin: 16; anchors.rightMargin: 12
                        spacing: 10

                        Text {
                            font.family: root.fontMain; font.pixelSize: 20
                            color: root.activeAccent
                            text: root.activeMode==="eth"?"󰈀":root.activeMode==="wifi"?"󰤨":"󰂯"
                            Behavior on color { ColorAnimation { duration: 300 } }
                        }
                        Text {
                            Layout.fillWidth: true
                            font.family: root.fontAlt; font.pixelSize: 15; font.weight: Font.Bold
                            color: root.cText
                            text: root.activeMode==="eth"?"Ethernet":root.activeMode==="wifi"?"Wi-Fi":"Bluetooth"
                        }
                        /* BT scan button */
                        Rectangle {
                            visible: root.activeMode==="bt" && root.btPower==="on"
                            width: 30; height: 30; radius: 8
                            color: scanMa.containsMouse ? root.cSurface1 : root.cSurface0
                            Behavior on color { ColorAnimation { duration: 150 } }
                            Text {
                                anchors.centerIn: parent
                                font.family: root.fontMain; font.pixelSize: 14
                                color: btScanProcess.running ? root.activeAccent : root.cText
                                text: "󰍉"
                                RotationAnimation on rotation {
                                    running: btScanProcess.running
                                    from:0; to:360; duration:2000; loops:Animation.Infinite
                                }
                            }
                            MouseArea { id:scanMa; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor
                                onClicked: if(!btScanProcess.running) btScanProcess.running=true
                            }
                        }
                        /* Power button */
                        Rectangle {
                            width: 34; height: 34; radius: width/2
                            color: root.currentPower ? root.activeAccent : root.cSurface0
                            border.color: root.currentPowerPending ? root.cYellow
                                        : root.currentPower ? Qt.lighter(root.activeAccent,1.2) : root.cSurface2
                            border.width: 1.5
                            Behavior on color        { ColorAnimation { duration: 300 } }
                            Behavior on border.color { ColorAnimation { duration: 300 } }
                            scale: pwrMa.pressed ? 0.88 : pwrMa.containsMouse ? 1.06 : 1.0
                            Behavior on scale { NumberAnimation { duration: 150 } }
                            Text {
                                anchors.centerIn: parent
                                font.family: root.fontMain; font.pixelSize: 15
                                color: root.currentPower ? root.cCrust : root.cText
                                text: root.currentPowerPending ? "󰑮" : ""
                                Behavior on color { ColorAnimation { duration: 300 } }
                                RotationAnimation on rotation {
                                    running: root.currentPowerPending
                                    from:0;to:360;duration:800;loops:Animation.Infinite
                                    onRunningChanged: if(!running) target.rotation=0
                                }
                            }
                            MouseArea { id:pwrMa; anchors.fill:parent; hoverEnabled:true; cursorShape:Qt.PointingHandCursor
                                onClicked: root.togglePower()
                            }
                        }
                    }
                    /* separator */
                    Rectangle {
                        anchors.bottom:parent.bottom; anchors.left:parent.left; anchors.right:parent.right
                        anchors.leftMargin:14; anchors.rightMargin:14
                        height:1; color: root.cSurface0
                    }
                }

                /* ─── CONTENT ─── */
                Item {
                    Layout.fillWidth: true
                    Layout.fillHeight: true

                    /* Power-off placeholder */
                    ColumnLayout {
                        anchors.centerIn: parent; spacing: 12
                        visible: !root.currentPower
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            font.family: root.fontMain; font.pixelSize: 44; color: root.cOverlay0
                            text: root.activeMode==="eth"?"󰈂":root.activeMode==="wifi"?"󰤮":"󰂲"
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            font.family: root.fontAlt; font.pixelSize: 13; font.weight: Font.Medium; color: root.cOverlay0
                            text: (root.activeMode==="eth"?"Ethernet":root.activeMode==="wifi"?"Wi-Fi":"Bluetooth") + " is off"
                        }
                        Text {
                            Layout.alignment: Qt.AlignHCenter
                            font.family: root.fontAlt; font.pixelSize: 11; color: root.cSurface2
                            text: "Click the power button to enable"
                        }
                    }

                    /* Active content */
                    ColumnLayout {
                        anchors.fill: parent
                        anchors.margins: 12; anchors.topMargin: 6
                        spacing: 6
                        visible: root.currentPower

                        /* ─── WIFI CONNECTED CARD ─── */
                        Rectangle {
                            id: wifiCard
                            Layout.fillWidth: true
                            visible: root.activeMode==="wifi" && root.isWifiConn && root.pendingWifiId===""
                            implicitHeight: wifiCol.implicitHeight + 20
                            radius: 10; color: root.cSurface0
                            Behavior on color { ColorAnimation { duration: 200 } }
                            property real dcFill: 0
                            property bool dcTriggered: false

                            Rectangle {
                                width: 3; radius: 2; color: root.activeAccent
                                anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.left: parent.left
                                anchors.topMargin: 6; anchors.bottomMargin: 6; anchors.leftMargin: 4
                            }
                            Rectangle {
                                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                width: parent.width * wifiCard.dcFill; radius: parent.radius; color: root.cRed; opacity: 0.12
                            }
                            ColumnLayout {
                                id: wifiCol
                                anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 14; anchors.rightMargin: 14
                                spacing: 4
                                RowLayout {
                                    spacing: 10
                                    Text { font.family:root.fontMain; font.pixelSize:22; color:root.activeAccent; text:root.wifiConnected?(root.wifiConnected.icon||"󰤨"):"󰤨" }
                                    ColumnLayout {
                                        spacing: 1
                                        Text { font.family:root.fontMain; font.pixelSize:13; font.weight:Font.Bold; color:root.cText; text:root.wifiConnected?root.wifiConnected.ssid:""; elide:Text.ElideRight; Layout.maximumWidth:250 }
                                        Text {
                                            font.family:root.fontAlt; font.pixelSize:10; color: wifiCardMa.containsMouse?root.cRed:root.cSubtext0
                                            text: root.disconnectingDevices[root.wifiConnected?root.wifiConnected.ssid:""] ? "Disconnecting..." : wifiCardMa.containsMouse ? "Hold to disconnect" : "Connected"
                                            Behavior on color { ColorAnimation{duration:200} }
                                        }
                                    }
                                }
                                GridLayout { columns:2; columnSpacing:12; rowSpacing:1; Layout.leftMargin:32
                                    InfoPair { label:"Signal"; value:root.wifiConnected?(root.wifiConnected.signal+"%"):"" }
                                    InfoPair { label:"IP";     value:root.wifiConnected?(root.wifiConnected.ip||"..."):"" }
                                    InfoPair { label:"Security"; value:root.wifiConnected?(root.wifiConnected.security||"Open"):"" }
                                    InfoPair { label:"Band";   value:root.wifiConnected?(root.wifiConnected.freq||""):""; visible:root.wifiConnected&&root.wifiConnected.freq }
                                }
                            }
                            MouseArea { id:wifiCardMa; anchors.fill:parent; hoverEnabled:true
                                onPressed:  { wifiDrain.stop(); wifiFill.start() }
                                onReleased: { if(!wifiCard.dcTriggered){wifiFill.stop();wifiDrain.start()} }
                            }
                            NumberAnimation { id:wifiFill; target:wifiCard; property:"dcFill"; to:1; duration:700*(1-wifiCard.dcFill); easing.type:Easing.InSine
                                onFinished: { if(!wifiCardMa.pressed){wifiCard.dcFill=0;return}; wifiCard.dcTriggered=true; root.disconnectDevice("wifi",root.wifiConnected?root.wifiConnected.ssid:""); wifiCard.dcFill=0; wifiCard.dcTriggered=false }
                            }
                            NumberAnimation { id:wifiDrain; target:wifiCard; property:"dcFill"; to:0; duration:500*wifiCard.dcFill; easing.type:Easing.OutQuad }
                        }

                        /* ─── ETH CONNECTED CARD ─── */
                        Rectangle {
                            id: ethCard
                            Layout.fillWidth: true
                            visible: root.activeMode==="eth" && root.isEthConn
                            implicitHeight: ethCol.implicitHeight + 20
                            radius: 10; color: root.cSurface0
                            property real dcFill: 0; property bool dcTriggered: false
                            Rectangle {
                                width: 3; radius: 2; color: root.activeAccent
                                anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.left: parent.left
                                anchors.topMargin: 6; anchors.bottomMargin: 6; anchors.leftMargin: 4
                            }
                            Rectangle {
                                anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                width: parent.width * ethCard.dcFill; radius: parent.radius; color: root.cRed; opacity: 0.12
                            }
                            ColumnLayout {
                                id: ethCol
                                anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                anchors.leftMargin: 14; anchors.rightMargin: 14
                                spacing: 4
                                RowLayout {
                                    spacing: 10
                                    Text { font.family:root.fontMain; font.pixelSize:22; color:root.activeAccent; text:"󰈀" }
                                    ColumnLayout { spacing:1
                                        Text { font.family:root.fontMain; font.pixelSize:13; font.weight:Font.Bold; color:root.cText; text:root.ethConnected?root.ethConnected.name:"" }
                                        Text { font.family:root.fontAlt; font.pixelSize:10; color:ethCardMa.containsMouse?root.cRed:root.cSubtext0; text:ethCardMa.containsMouse?"Hold to disconnect":"Connected"; Behavior on color{ColorAnimation{duration:200}} }
                                    }
                                }
                                GridLayout { columns:2; columnSpacing:12; rowSpacing:1; Layout.leftMargin:32
                                    InfoPair { label:"IP"; value:root.ethConnected?(root.ethConnected.ip||"..."):"" }
                                    InfoPair { label:"Speed"; value:root.ethConnected?(root.ethConnected.speed||""):"" }
                                    InfoPair { label:"MAC"; value:root.ethConnected?(root.ethConnected.mac||""):"" }
                                }
                            }
                            MouseArea { id:ethCardMa; anchors.fill:parent; hoverEnabled:true
                                onPressed:{ethDrain.stop();ethFill.start()}
                                onReleased:{if(!ethCard.dcTriggered){ethFill.stop();ethDrain.start()}}
                            }
                            NumberAnimation{id:ethFill;target:ethCard;property:"dcFill";to:1;duration:700*(1-ethCard.dcFill);easing.type:Easing.InSine
                                onFinished:{if(!ethCardMa.pressed){ethCard.dcFill=0;return};ethCard.dcTriggered=true;root.disconnectDevice("eth",root.ethConnected?root.ethConnected.id:"");ethCard.dcFill=0;ethCard.dcTriggered=false}}
                            NumberAnimation{id:ethDrain;target:ethCard;property:"dcFill";to:0;duration:500*ethCard.dcFill;easing.type:Easing.OutQuad}
                        }

                        /* ─── BT CONNECTED CARDS ─── */
                        Repeater {
                            model: root.activeMode==="bt" ? root.btConnected : []
                            delegate: Rectangle {
                                id: btCard
                                Layout.fillWidth: true
                                implicitHeight: btCardCol.implicitHeight + 20
                                radius: 10; color: root.cSurface0
                                property real dcFill: 0; property bool dcTriggered: false
                                property string myMac: modelData.mac || ""
                                property bool isDisconnecting: !!root.disconnectingDevices[myMac]
                                Rectangle {
                                    width: 3; radius: 2; color: root.activeAccent
                                    anchors.top: parent.top; anchors.bottom: parent.bottom; anchors.left: parent.left
                                    anchors.topMargin: 6; anchors.bottomMargin: 6; anchors.leftMargin: 4
                                }
                                Rectangle {
                                    anchors.left: parent.left; anchors.top: parent.top; anchors.bottom: parent.bottom
                                    width: parent.width * btCard.dcFill; radius: parent.radius; color: root.cRed; opacity: 0.12
                                }
                                ColumnLayout {
                                    id: btCardCol
                                    anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                    anchors.leftMargin: 14; anchors.rightMargin: 14
                                    spacing: 4
                                    RowLayout {
                                        spacing: 10
                                        Text { font.family:root.fontMain; font.pixelSize:22; color:root.activeAccent; text:modelData.icon||"󰂯" }
                                        ColumnLayout { spacing:1
                                            Text { font.family:root.fontMain; font.pixelSize:13; font.weight:Font.Bold; color:root.cText; text:modelData.name||"Unknown"; elide:Text.ElideRight; Layout.maximumWidth:220 }
                                            Text { font.family:root.fontAlt; font.pixelSize:10
                                                color: btCard.isDisconnecting ? root.cOverlay0 : btCardMa.containsMouse ? root.cRed : root.cSubtext0
                                                text: btCard.isDisconnecting ? "Disconnecting..." : btCardMa.containsMouse ? "Hold to disconnect" : "Connected"
                                                Behavior on color{ColorAnimation{duration:200}}
                                            }
                                        }
                                    }
                                    GridLayout { columns:2; columnSpacing:12; rowSpacing:1; Layout.leftMargin:32
                                        InfoPair { label:"Battery"; value:(modelData.battery||"0")+"%" }
                                        InfoPair { label:"Profile"; value:modelData.profile||"None" }
                                        InfoPair { label:"MAC"; value:modelData.mac||"" }
                                    }
                                }
                                MouseArea { id:btCardMa; anchors.fill:parent; hoverEnabled:true
                                    enabled: !btCard.isDisconnecting
                                    onPressed:{btDrainAnim.stop();btFillAnim.start()}
                                    onReleased:{if(!btCard.dcTriggered){btFillAnim.stop();btDrainAnim.start()}}
                                }
                                NumberAnimation{id:btFillAnim;target:btCard;property:"dcFill";to:1;duration:700*(1-btCard.dcFill);easing.type:Easing.InSine
                                    onFinished:{if(!btCardMa.pressed){btCard.dcFill=0;return};btCard.dcTriggered=true;root.disconnectDevice("bt",btCard.myMac);btCard.dcFill=0;btCard.dcTriggered=false}}
                                NumberAnimation{id:btDrainAnim;target:btCard;property:"dcFill";to:0;duration:500*btCard.dcFill;easing.type:Easing.OutQuad}
                            }
                        }

                        /* ─── WIFI PASSWORD PROMPT ─── */
                        Rectangle {
                            id: pwdCard
                            Layout.fillWidth: true
                            visible: root.pendingWifiId !== "" && root.activeMode === "wifi"
                            implicitHeight: pwdCol.implicitHeight + 24
                            radius: 10; color: root.cSurface0
                            border.color: root.activeAccent; border.width: 1

                            ColumnLayout {
                                id: pwdCol
                                anchors.left: parent.left; anchors.right: parent.right; anchors.verticalCenter: parent.verticalCenter
                                anchors.margins: 14
                                spacing: 8
                                Text { font.family:root.fontMain; font.pixelSize:14; color:root.activeAccent; text:"󰤨  " + root.pendingWifiSsid; elide:Text.ElideRight; Layout.maximumWidth:300 }
                                Text { font.family:root.fontAlt; font.pixelSize:10; color:root.cOverlay1; text:"Enter password to connect" }
                                Rectangle {
                                    Layout.fillWidth: true; height: 34; radius: 8
                                    color: root.cMantle; border.color: pwdField.activeFocus?root.activeAccent:root.cSurface1; border.width:1
                                    Behavior on border.color { ColorAnimation{duration:200} }
                                    TextInput {
                                        id: pwdField
                                        anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                                        verticalAlignment: TextInput.AlignVCenter
                                        font.family: root.fontMain; font.pixelSize: 12; color: root.cText
                                        echoMode: TextInput.Password; clip: true
                                        onAccepted: {
                                            if(text.trim()!==""){
                                                root.connectDevice("wifi",root.pendingWifiId,root.pendingWifiSsid,text)
                                                root.pendingWifiId=""; root.pendingWifiSsid=""; text=""
                                            }
                                        }
                                        Keys.onEscapePressed: { root.pendingWifiId=""; root.pendingWifiSsid=""; text="" }
                                    }
                                }
                                RowLayout {
                                    spacing: 8
                                    Rectangle {
                                        width: cancelTxt.implicitWidth+20; height:28; radius:6; color:root.cSurface1
                                        Text { id:cancelTxt; anchors.centerIn:parent; font.family:root.fontAlt; font.pixelSize:11; color:root.cText; text:"Cancel" }
                                        MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor
                                            onClicked:{ root.pendingWifiId=""; root.pendingWifiSsid="" }
                                        }
                                    }
                                    Rectangle {
                                        width: connTxt.implicitWidth+20; height:28; radius:6; color:root.activeAccent
                                        Text { id:connTxt; anchors.centerIn:parent; font.family:root.fontAlt; font.pixelSize:11; font.weight:Font.Bold; color:root.cCrust; text:"Connect" }
                                        MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor
                                            onClicked:{
                                                if(pwdField.text.trim()!==""){
                                                    root.connectDevice("wifi",root.pendingWifiId,root.pendingWifiSsid,pwdField.text)
                                                    root.pendingWifiId=""; root.pendingWifiSsid=""; pwdField.text=""
                                                }
                                            }
                                        }
                                    }
                                }
                            }
                            Timer { id:focusTimer; interval:80; running:pwdCard.visible; onTriggered:pwdField.forceActiveFocus() }
                        }

                        /* ─── NOT CONNECTED (WiFi/BT) ─── */
                        ColumnLayout {
                            visible: root.currentPower && !root.currentConn && root.pendingWifiId==="" && root.activeMode!=="eth"
                            Layout.alignment: Qt.AlignHCenter
                            Layout.topMargin: 8; spacing: 6
                            Text {
                                Layout.alignment: Qt.AlignHCenter
                                font.family:root.fontMain; font.pixelSize:30; color:root.cOverlay0
                                text: root.activeMode==="wifi"?"󰤭":"󰂲"
                                SequentialAnimation on opacity { loops:Animation.Infinite; running:parent.visible
                                    NumberAnimation{to:0.4;duration:1200;easing.type:Easing.InOutSine}
                                    NumberAnimation{to:1.0;duration:1200;easing.type:Easing.InOutSine}
                                }
                            }
                            Text { Layout.alignment:Qt.AlignHCenter; font.family:root.fontAlt; font.pixelSize:12; color:root.cOverlay0; text:"Not connected" }
                        }

                        /* ─── ETH DISCONNECTED ─── */
                        ColumnLayout {
                            visible: root.activeMode==="eth" && root.currentPower && !root.isEthConn
                            Layout.alignment: Qt.AlignHCenter; Layout.topMargin:20; spacing:8
                            Text { Layout.alignment:Qt.AlignHCenter; font.family:root.fontMain; font.pixelSize:40; color:root.cOverlay0; text:"󰈂" }
                            Text { Layout.alignment:Qt.AlignHCenter; font.family:root.fontAlt; font.pixelSize:12; color:root.cOverlay0; text:"No cable connected" }
                        }

                        /* ─── SECTION HEADER ─── */
                        Text {
                            visible: root.currentPower && root.activeMode !== "eth"
                            font.family:root.fontAlt; font.pixelSize:11; font.weight:Font.Medium
                            color: root.cOverlay0; Layout.topMargin: 2
                            text: root.activeMode==="wifi" ? "Available Networks" : "Devices"
                        }

                        /* ─── DEVICE LIST ─── */
                        ListView {
                            id: deviceList
                            Layout.fillWidth: true; Layout.fillHeight: true
                            visible: root.currentPower && root.activeMode !== "eth"
                            model: root.activeMode==="wifi" ? wifiListModel : btListModel
                            clip: true; spacing: 3
                            boundsBehavior: Flickable.StopAtBounds

                            delegate: Rectangle {
                                id: devCard
                                width: deviceList.width; height: 44
                                radius: 8
                                property string devId: model.id || ""
                                property string devName: model.name || model.ssid || ""
                                property string devIcon: model.icon || ""
                                property string devAction: model.action || ""
                                property string devSecurity: model.security || ""
                                property string devSsid: model.ssid || ""
                                property string devMac: model.mac || ""
                                property bool isBusy: root.connectingId===devId || !!root.busyTasks[devId]
                                property bool isFailed: root.failedId===devId

                                color: devMa.containsMouse ? Qt.rgba(1,1,1,0.06) : Qt.rgba(1,1,1,0.02)
                                border.color: isFailed ? root.cRed : devMa.containsMouse ? root.cSurface2 : Qt.rgba(1,1,1,0.03)
                                border.width: 1
                                Behavior on color { ColorAnimation{duration:150} }
                                Behavior on border.color { ColorAnimation{duration:150} }

                                RowLayout {
                                    anchors.fill: parent; anchors.leftMargin: 12; anchors.rightMargin: 12
                                    spacing: 10
                                    Text { font.family:root.fontMain; font.pixelSize:16; color:isFailed?root.cRed:root.activeAccent; text:devIcon }
                                    ColumnLayout { Layout.fillWidth:true; spacing:0
                                        Text { font.family:root.fontMain; font.pixelSize:12; font.weight:Font.Bold
                                            color: isFailed?root.cRed:root.cText; text:devName; elide:Text.ElideRight; Layout.maximumWidth:200 }
                                        Text { font.family:root.fontAlt; font.pixelSize:9
                                            color: isFailed?root.cMaroon : isBusy?root.activeAccent : root.cOverlay1
                                            text: isFailed ? "Failed" : isBusy ? "Connecting..." : (root.activeMode==="wifi" ? devSecurity : devAction)
                                        }
                                    }
                                    /* Signal strength (wifi) or action label */
                                    Text {
                                        visible: root.activeMode==="wifi" && !isBusy && !isFailed
                                        font.family:root.fontMain; font.pixelSize:10; color:root.cOverlay1
                                        text: model.signal ? model.signal+"%" : ""
                                    }
                                    /* Loading dots for busy */
                                    Row {
                                        visible: isBusy; spacing:3
                                        Repeater { model:3; Rectangle { width:4;height:4;radius:2;color:root.activeAccent
                                            SequentialAnimation on y { loops:Animation.Infinite
                                                PauseAnimation{duration:index*100}
                                                NumberAnimation{from:0;to:-4;duration:200;easing.type:Easing.OutSine}
                                                NumberAnimation{from:-4;to:0;duration:200;easing.type:Easing.InSine}
                                                PauseAnimation{duration:(2-index)*100}
                                            }
                                        }}
                                    }
                                }
                                MouseArea {
                                    id: devMa; anchors.fill:parent; hoverEnabled:true
                                    cursorShape: isBusy ? Qt.ArrowCursor : Qt.PointingHandCursor
                                    onClicked: {
                                        if(isBusy) return
                                        if(root.activeMode==="wifi") {
                                            let sec=(devSecurity||"").trim().toLowerCase()
                                            let isSecure = sec!=="" && sec!=="open" && sec!=="--" && sec!=="none"
                                            let isSaved = root.savedWifiNetworks.indexOf(devSsid) !== -1
                                            if(isSecure && !isSaved) {
                                                root.pendingWifiSsid = devSsid
                                                root.pendingWifiId = devId
                                            } else {
                                                root.connectDevice("wifi",devId,devSsid,"")
                                            }
                                        } else {
                                            root.connectDevice("bt",devId,devMac,"")
                                        }
                                    }
                                }
                            }

                            /* Empty state */
                            Text {
                                anchors.centerIn: parent
                                visible: deviceList.count === 0 && root.currentPower
                                font.family: root.fontAlt; font.pixelSize: 11; color: root.cOverlay0
                                text: root.activeMode==="wifi" ? "Scanning..." : (btScanProcess.running ? "Scanning..." : "No devices found")
                            }
                        }
                    }
                }

                /* ─── TAB BAR ─── */
                Rectangle {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 44
                    Layout.leftMargin: 10; Layout.rightMargin: 10
                    Layout.bottomMargin: 10; Layout.topMargin: 2
                    radius: 12; color: root.cSurface0
                    visible: true

                    /* Animated pill highlight */
                    Rectangle {
                        id: pill
                        y: 5; height: parent.height - 10; radius: 9
                        gradient: Gradient {
                            orientation: Gradient.Horizontal
                            GradientStop { position:0; color:Qt.lighter(root.activeAccent,1.15) }
                            GradientStop { position:1; color:root.activeAccent }
                        }
                        property Item target: root.activeMode==="eth"?ethTab : root.activeMode==="wifi"?wifiTab : btTab
                        x: 5 + (target ? target.x : 0)
                        width: target ? target.width : 0
                        Behavior on x     { NumberAnimation{duration:280;easing.type:Easing.OutExpo} }
                        Behavior on width { NumberAnimation{duration:280;easing.type:Easing.OutExpo} }
                    }

                    RowLayout {
                        anchors.fill: parent; anchors.margins: 5
                        spacing: 4

                        Rectangle {
                            id: ethTab; Layout.fillWidth:true; Layout.fillHeight:true
                            visible: root.ethPresent; radius:9; color:"transparent"
                            RowLayout { anchors.centerIn:parent; spacing:6
                                Text { font.family:root.fontMain; font.pixelSize:14; color:root.activeMode==="eth"?root.cCrust:root.cText; text:"󰈀"; Behavior on color{ColorAnimation{duration:200}} }
                                Text { font.family:root.fontAlt; font.pixelSize:11; font.weight:Font.Bold; color:root.activeMode==="eth"?root.cCrust:root.cText; text:"Ethernet"; Behavior on color{ColorAnimation{duration:200}} }
                            }
                            MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor
                                onClicked: if(root.activeMode!=="eth") root.activeMode="eth"
                            }
                        }
                        Rectangle { visible:root.ethPresent&&(root.wifiPresent||root.btPresent); width:1; Layout.fillHeight:true; Layout.topMargin:6; Layout.bottomMargin:6; color:"#33ffffff" }

                        Rectangle {
                            id: wifiTab; Layout.fillWidth:true; Layout.fillHeight:true
                            visible: root.wifiPresent || !root.ethPresent; radius:9; color:"transparent"
                            RowLayout { anchors.centerIn:parent; spacing:6
                                Text { font.family:root.fontMain; font.pixelSize:14; color:root.activeMode==="wifi"?root.cCrust:root.cText; text:"󰤨"; Behavior on color{ColorAnimation{duration:200}} }
                                Text { font.family:root.fontAlt; font.pixelSize:11; font.weight:Font.Bold; color:root.activeMode==="wifi"?root.cCrust:root.cText; text:"Wi-Fi"; Behavior on color{ColorAnimation{duration:200}} }
                            }
                            MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor
                                onClicked: if(root.activeMode!=="wifi") root.activeMode="wifi"
                            }
                        }
                        Rectangle { visible:(root.wifiPresent||!root.ethPresent)&&root.btPresent; width:1; Layout.fillHeight:true; Layout.topMargin:6; Layout.bottomMargin:6; color:"#33ffffff" }

                        Rectangle {
                            id: btTab; Layout.fillWidth:true; Layout.fillHeight:true
                            visible: root.btPresent || !root.wifiPresent; radius:9; color:"transparent"
                            RowLayout { anchors.centerIn:parent; spacing:6
                                Text { font.family:root.fontMain; font.pixelSize:14; color:root.activeMode==="bt"?root.cCrust:root.cText; text:"󰂯"; Behavior on color{ColorAnimation{duration:200}} }
                                Text { font.family:root.fontAlt; font.pixelSize:11; font.weight:Font.Bold; color:root.activeMode==="bt"?root.cCrust:root.cText; text:"Bluetooth"; Behavior on color{ColorAnimation{duration:200}} }
                            }
                            MouseArea { anchors.fill:parent; cursorShape:Qt.PointingHandCursor
                                onClicked: if(root.activeMode!=="bt") root.activeMode="bt"
                            }
                        }
                    }
                }
            }
        }
    }
}
