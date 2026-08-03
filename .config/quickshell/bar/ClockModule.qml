import QtQuick

/* ClockModule.qml — Dynamic Clock */

Badge {
    id: clockBadge

    property string timeStr: ""
    property string clockIcon: "󱑖"

    function updateClock() {
        var d = new Date();
        var h = d.getHours();
        var h12 = h % 12;
        var ampm = h >= 12 ? "PM" : "AM";
        var hDisp = h12 === 0 ? 12 : h12;
        var m = d.getMinutes().toString().padStart(2, '0');
        var s = d.getSeconds().toString().padStart(2, '0');
        timeStr = hDisp.toString().padStart(2, '0') + ":" + m + ":" + s + " " + ampm;
        
        // Map hours (0-11) to Nerd Font clock icons
        var icons = [
            "󱑖", // 0 (12)
            "󱑋", // 1
            "󱑌", // 2
            "󱑍", // 3
            "󱑎", // 4
            "󱑏", // 5
            "󱑐", // 6
            "󱑑", // 7
            "󱑒", // 8
            "󱑓", // 9
            "󱑔", // 10
            "󱑕"  // 11
        ];
        clockIcon = icons[h12];
    }

    icon: clockIcon
    label: timeStr
    accentColor: "#94e2d5"
    tooltipText:  "Might die soon~"

    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: clockBadge.updateClock()
    }

    Component.onCompleted: updateClock()
}
