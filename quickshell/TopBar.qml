import QtQuick
import QtQuick.Layouts
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import Quickshell.Services.SystemTray

PanelWindow {
    id: barWindow

    anchors {
        top: true
        left: true
        right: true
    }

    implicitHeight: 36
    margins { top: 8; bottom: 0; left: 4; right: 4 }
    exclusiveZone: 38
    color: "transparent"

    // Dynamic Matugen Palette (Catppuccin Mocha fallback)
    MatugenColors {
        id: mocha
    }

    // ==========================================
    // STATE VARIABLES
    // ==========================================

    // Startup animation triggers
    property bool isStartupReady: false
    Timer { interval: 10; running: true; onTriggered: barWindow.isStartupReady = true }

    property bool startupCascadeFinished: false
    Timer { interval: 1000; running: true; onTriggered: barWindow.startupCascadeFinished = true }

    // Time & Date
    property string timeStr: ""
    property string fullDateStr: ""
    property int typeInIndex: 0
    property string dateStr: fullDateStr.substring(0, typeInIndex)

    // WiFi (icon only in bar — SSID goes in dropdown later)
    property string wifiStatus: "Off"
    property string wifiIcon: "󰤮"
    property string wifiSsid: ""           // fetched but not shown in bar, reserved for dropdown

    // Volume
    property string volPercent: "0%"
    property string volIcon: "󰕾"
    property bool isMuted: false

    // Workspaces
    property var workspacesData: []

    // Music (ncspot via playerctl)
    property var musicData: { "status": "Stopped", "title": "", "artUrl": "", "timeStr": "" }

    // Derived
    property bool isMediaActive: barWindow.musicData.status !== "Stopped" && barWindow.musicData.title !== ""
    property bool isWifiOn: barWindow.wifiStatus.toLowerCase() === "enabled" || barWindow.wifiStatus.toLowerCase() === "on"

    // ==========================================
    // DATA FETCHING
    // ==========================================

    // Workspaces daemon — writes JSON to /tmp
    Process {
        id: wsDaemon
        command: ["bash", "-c", "~/.config/quickshell/workspaces.sh > /tmp/qs_workspaces.json"]
        running: true
    }

    // Workspaces poller — reads that JSON every 100ms
    Process {
        id: wsPoller
        command: ["bash", "-c", "tail -n 1 /tmp/qs_workspaces.json 2>/dev/null"]
        stdout: StdioCollector {
            onStreamFinished: {
                let txt = this.text.trim();
                if (txt !== "") {
                    try { barWindow.workspacesData = JSON.parse(txt); } catch(e) {}
                }
            }
        }
    }
    Timer { interval: 100; running: true; repeat: true; onTriggered: wsPoller.running = true }

    // Music poller — ncspot → playerctl → JSON every 500ms
    Process {
        id: musicPoller
        command: ["bash", "-c", "cat /tmp/music_info.json 2>/dev/null || bash ~/.config/scripts/quickshell/music/music_info.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                let txt = this.text.trim();
                if (txt !== "") {
                    try { barWindow.musicData = JSON.parse(txt); } catch(e) {}
                }
            }
        }
    }
    Timer { interval: 500; running: true; repeat: true; onTriggered: musicPoller.running = true }

    // Slow poller — WiFi only (BT and Battery removed)
    Process {
        id: slowSysPoller
        command: ["bash", "-c", `
            echo "$(~/.config/quickshell/sys_info.sh --wifi-status)"
            echo "$(~/.config/quickshell/sys_info.sh --wifi-icon)"
            echo "$(~/.config/quickshell/sys_info.sh --wifi-ssid)"
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.trim().split("\n");
                if (lines.length >= 3) {
                    barWindow.wifiStatus = lines[0];
                    barWindow.wifiIcon   = lines[1];
                    barWindow.wifiSsid   = lines[2]; // reserved for dropdown
                }
            }
        }
    }
    Timer { interval: 1500; running: true; repeat: true; triggeredOnStart: true; onTriggered: slowSysPoller.running = true }

    // Fast poller — Volume only (KB layout removed)
    Process {
        id: fastSysPoller
        command: ["bash", "-c", `
            echo "$(~/.config/quickshell/sys_info.sh --volume)"
            echo "$(~/.config/quickshell/sys_info.sh --volume-icon)"
            echo "$(~/.config/quickshell/sys_info.sh --is-muted)"
        `]
        stdout: StdioCollector {
            onStreamFinished: {
                let lines = this.text.trim().split("\n");
                if (lines.length >= 3) {
                    barWindow.volPercent = lines[0];
                    barWindow.volIcon    = lines[1];
                    barWindow.isMuted    = (lines[2].toLowerCase() === "true");
                }
            }
        }
    }
    Timer { interval: 150; running: true; repeat: true; triggeredOnStart: true; onTriggered: fastSysPoller.running = true }

    // REMOVED POLLERS (kept as reference comments):
    // weatherPoller         — weather removed from bar
    // batPercent/batIcon    — desktop, no battery
    // btStatus/btIcon       — bluetooth removed
    // kbLayout              — single layout, not needed

    // ==========================================
    // TIME & TYPEWRITER
    // ==========================================

    // Updates every second, but typewriter only triggers when the MINUTE changes
    Timer {
        interval: 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: {
            let d = new Date();
            // 24hr, no seconds
            let newTimeStr = Qt.formatDateTime(d, "HH:mm");
            let newDateStr = Qt.formatDateTime(d, "dddd, MMMM dd");

            barWindow.fullDateStr = newDateStr;
            barWindow.timeStr = newTimeStr;
        }
    }

    // Typewriter timer — runs whenever typeInIndex is behind fullDateStr length
    Timer {
        id: typewriterTimer
        interval: 150
        running: barWindow.isStartupReady && barWindow.typeInIndex < barWindow.fullDateStr.length
        repeat: true
        onTriggered: barWindow.typeInIndex += 1
    }

    // ==========================================
    // UI LAYOUT
    // ==========================================
    Item {
        anchors.fill: parent

        // ───────────────── LEFT ─────────────────
        RowLayout {
            id: leftLayout
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            property bool showLayout: false
            opacity: leftLayout.showLayout ? 1 : 0
            transform: Translate {
                x: leftLayout.showLayout ? 0 : -20
                Behavior on x { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
            }
            Timer {
                running: barWindow.isStartupReady
                interval: 10
                onTriggered: leftLayout.showLayout = true
            }
            Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

            property int moduleHeight: 36

            // ── Search / App Launcher ──
            // COMMENTED OUT — uncomment when Quickshell launcher ported from end4 dotfiles
            /*
            Rectangle {
                property bool isHovered: searchMouse.containsMouse
                color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.95) : Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75)
                radius: 14; border.width: 1; border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, isHovered ? 0.15 : 0.05)
                Layout.preferredHeight: parent.moduleHeight; Layout.preferredWidth: 36
                scale: isHovered ? 1.05 : 1.0
                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                Behavior on color { ColorAnimation { duration: 200 } }
                Text {
                    anchors.centerIn: parent
                    text: "󰍉"
                    font.family: "Iosevka Nerd Font"; font.pixelSize: 24
                    color: parent.isHovered ? mocha.blue : mocha.text
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
                MouseArea {
                    id: searchMouse
                    anchors.fill: parent
                    hoverEnabled: true
                    // TODO: replace with QML-native launcher call once end4 launcher is ported
                    onClicked: Quickshell.execDetached(["bash", "-c", "wofi --show drun"])
                }
            }
            */

            // ── Notifications Bell ──
            // Shows on DP-1 always; moves to HDMI-A-1 when DP-1 has a fullscreen window
            // Monitor-aware behavior is configured in swaync config, not here
            Rectangle {
                property bool isHovered: notifMouse.containsMouse
                color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.95) : Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75)
                radius: 14; border.width: 1; border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, isHovered ? 0.15 : 0.05)
                Layout.preferredHeight: parent.moduleHeight; Layout.preferredWidth: 36
                scale: isHovered ? 1.05 : 1.0
                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                Behavior on color { ColorAnimation { duration: 200 } }
                Text {
                    anchors.centerIn: parent
                    text: ""
                    font.family: "Iosevka Nerd Font"; font.pixelSize: 18
                    color: parent.isHovered ? mocha.yellow : mocha.text
                    Behavior on color { ColorAnimation { duration: 200 } }
                }
                MouseArea {
                    id: notifMouse
                    anchors.fill: parent
                    acceptedButtons: Qt.LeftButton | Qt.RightButton
                    hoverEnabled: true
                    onClicked: (mouse) => {
                        if (mouse.button === Qt.LeftButton)  Quickshell.execDetached(["swaync-client", "-t", "-sw"]);
                        if (mouse.button === Qt.RightButton) Quickshell.execDetached(["swaync-client", "-d"]);
                    }
                }
            }

            // ── Workspace Dots ──
            Rectangle {
                color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75)
                radius: 14; border.width: 1; border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                Layout.preferredHeight: parent.moduleHeight
                clip: true

                property real targetWidth: barWindow.workspacesData.length > 0 ? wsLayout.implicitWidth + 20 : 0
                Layout.preferredWidth: targetWidth
                visible: targetWidth > 0
                opacity: barWindow.workspacesData.length > 0 ? 1 : 0
                Behavior on opacity  { NumberAnimation { duration: 300 } }
                Behavior on targetWidth { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }

                RowLayout {
                    id: wsLayout
                    anchors.centerIn: parent
                    spacing: 6

                    Repeater {
                        model: barWindow.workspacesData
                        delegate: Rectangle {
                            id: wsPill
                            property bool isHovered: wsPillMouse.containsMouse

                            property real targetWidth: modelData.state === "active" ? 36 : 32
                            Layout.preferredWidth: targetWidth
                            Behavior on targetWidth { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                            Layout.preferredHeight: 32; radius: 10

                            color: modelData.state === "active"
                                    ? mocha.mauve
                                    : (isHovered
                                        ? Qt.rgba(mocha.surface2.r, mocha.surface2.g, mocha.surface2.b, 0.9)
                                        : (modelData.state === "occupied"
                                            ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.9)
                                            : "transparent"))

                            scale: isHovered && modelData.state !== "active" ? 1.08 : 1.0
                            Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                            // Staggered startup cascade
                            property bool initAnimTrigger: barWindow.startupCascadeFinished
                            opacity: initAnimTrigger ? 1 : 0
                            transform: Translate {
                                y: wsPill.initAnimTrigger ? 0 : 15
                                Behavior on y { NumberAnimation { duration: 500; easing.type: Easing.OutBack } }
                            }
                            Component.onCompleted: {
                                if (!barWindow.startupCascadeFinished) {
                                    animTimer.interval = index * 60;
                                    animTimer.start();
                                }
                            }
                            Timer {
                                id: animTimer
                                running: false; repeat: false
                                onTriggered: wsPill.initAnimTrigger = true
                            }
                            Behavior on opacity { NumberAnimation { duration: 500; easing.type: Easing.OutCubic } }
                            Behavior on color   { ColorAnimation  { duration: 250 } }

                            Text {
                                anchors.centerIn: parent
                                text: modelData.id
                                font.family: "JetBrains Mono"
                                font.pixelSize: 14
                                font.weight: modelData.state === "active" ? Font.Black : (modelData.state === "occupied" ? Font.Bold : Font.Medium)
                                color: modelData.state === "active"
                                        ? mocha.crust
                                        : (isHovered
                                            ? mocha.text
                                            : (modelData.state === "occupied" ? mocha.text : mocha.overlay0))
                                Behavior on color { ColorAnimation { duration: 250 } }
                            }

                            MouseArea {
                                id: wsPillMouse
                                hoverEnabled: true
                                anchors.fill: parent
                                // Direct hyprctl dispatch — no qs_manager.sh dependency
                                onClicked: Quickshell.execDetached(["hyprctl", "dispatch", "workspace", String(modelData.id)])
                            }
                        }
                    }
                }
            }

            // ── Media Player (ncspot via playerctl) ──
            Rectangle {
                id: mediaBox
                color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75)
                radius: 14; border.width: 1; border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.05)
                Layout.preferredHeight: parent.moduleHeight
                clip: true

                property real targetWidth: barWindow.isMediaActive ? mediaLayoutContainer.width + 24 : 0
                Layout.preferredWidth: targetWidth
                visible: Layout.preferredWidth > 0
                Behavior on targetWidth { NumberAnimation { duration: 1400; easing.type: Easing.OutExpo } }

                Item {
                    id: mediaLayoutContainer
                    anchors.verticalCenter: parent.verticalCenter
                    anchors.left: parent.left
                    anchors.leftMargin: 12
                    implicitHeight: parent.height
                    width: innerMediaLayout.implicitWidth

                    RowLayout {
                        id: innerMediaLayout
                        anchors.verticalCenter: parent.verticalCenter
                        spacing: 16

                        MouseArea {
                            id: mediaInfoMouse
                            Layout.preferredWidth: infoLayout.implicitWidth
                            Layout.fillHeight: true
                            hoverEnabled: true
                            // TODO: uncomment when QS music panel is built
                            // onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/quickshellqs_manager.sh toggle music"])

                            RowLayout {
                                id: infoLayout
                                anchors.verticalCenter: parent.verticalCenter
                                spacing: 10
                                scale: mediaInfoMouse.containsMouse ? 1.02 : 1.0
                                Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }

                                Rectangle {
                                    Layout.preferredWidth: 32; Layout.preferredHeight: 32; radius: 8; color: mocha.surface1
                                    border.width: barWindow.musicData.status === "Playing" ? 1 : 0
                                    border.color: mocha.mauve
                                    clip: true
                                    Image {
                                        anchors.fill: parent
                                        source: barWindow.musicData.artUrl || ""
                                        fillMode: Image.PreserveAspectCrop
                                    }
                                    Rectangle {
                                        anchors.fill: parent
                                        color: Qt.rgba(mocha.mauve.r, mocha.mauve.g, mocha.mauve.b, 0.2)
                                    }
                                }

                                ColumnLayout {
                                    spacing: -2
                                    Layout.preferredWidth: 180
                                    Text {
                                        text: barWindow.musicData.title
                                        font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: 13
                                        color: mocha.text
                                        elide: Text.ElideRight; Layout.fillWidth: true
                                    }
                                    Text {
                                        text: barWindow.musicData.timeStr
                                        font.family: "JetBrains Mono"; font.weight: Font.Black; font.pixelSize: 10
                                        color: mocha.subtext0
                                        elide: Text.ElideRight; Layout.fillWidth: true
                                    }
                                }
                            }
                        }

                        // Playback controls
                        RowLayout {
                            spacing: 8
                            Item {
                                Layout.preferredWidth: 24; Layout.preferredHeight: 24
                                Text {
                                    anchors.centerIn: parent; text: "󰒮"
                                    font.family: "Iosevka Nerd Font"; font.pixelSize: 26
                                    color: prevMouse.containsMouse ? mocha.text : mocha.overlay2
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    scale: prevMouse.containsMouse ? 1.1 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                }
                                MouseArea { id: prevMouse; hoverEnabled: true; anchors.fill: parent; onClicked: Quickshell.execDetached(["playerctl", "previous"]) }
                            }
                            Item {
                                Layout.preferredWidth: 28; Layout.preferredHeight: 28
                                Text {
                                    anchors.centerIn: parent
                                    text: barWindow.musicData.status === "Playing" ? "󰏤" : "󰐊"
                                    font.family: "Iosevka Nerd Font"; font.pixelSize: 30
                                    color: playMouse.containsMouse ? mocha.green : mocha.text
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    scale: playMouse.containsMouse ? 1.15 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                }
                                MouseArea { id: playMouse; hoverEnabled: true; anchors.fill: parent; onClicked: Quickshell.execDetached(["playerctl", "play-pause"]) }
                            }
                            Item {
                                Layout.preferredWidth: 24; Layout.preferredHeight: 24
                                Text {
                                    anchors.centerIn: parent; text: "󰒭"
                                    font.family: "Iosevka Nerd Font"; font.pixelSize: 26
                                    color: nextMouse.containsMouse ? mocha.text : mocha.overlay2
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    scale: nextMouse.containsMouse ? 1.1 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }
                                }
                                MouseArea { id: nextMouse; hoverEnabled: true; anchors.fill: parent; onClicked: Quickshell.execDetached(["playerctl", "next"]) }
                            }
                        }
                    }
                }
            }
        }

        // ───────────────── CENTER ─────────────────
        Row {
            id: centerRow
            anchors.centerIn: parent
            spacing: 4

            // Startup animation shared across both pills
            property bool showLayout: false
            opacity: centerRow.showLayout ? 1 : 0
            transform: Translate {
                y: centerRow.showLayout ? 0 : -20
                Behavior on y { NumberAnimation { duration: 600; easing.type: Easing.OutBack } }
                }
                Timer {
                    running: barWindow.isStartupReady
                    interval: 10
                    onTriggered: centerRow.showLayout = true
                }
                Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

            // ── Time Pill ──
            Rectangle {
                property bool isHovered: timeMouse.containsMouse
                color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.95) : Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75)
                radius: 14; border.width: 1; border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, isHovered ? 0.15 : 0.05)
                implicitHeight: 36
                width: timeText.implicitWidth + 36
                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
                scale: isHovered ? 1.03 : 1.0
                Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }
                Behavior on color { ColorAnimation { duration: 250 } }

                Text {
                    id: timeText
                    anchors.centerIn: parent
                    text: barWindow.timeStr
                    font.family: "JetBrains Mono"; font.pixelSize: 16; font.weight: Font.Black
                    color: mocha.blue
                }
                MouseArea { id: timeMouse; anchors.fill: parent; hoverEnabled: true }
            }

            // ── Date Pill ──
            Rectangle {
                property bool isHovered: dateMouse.containsMouse
                color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.95) : Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75)
                radius: 14; border.width: 1; border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, isHovered ? 0.15 : 0.05)
                implicitHeight: 36
                width: dateText.implicitWidth + 36
                Behavior on width { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
                scale: isHovered ? 1.03 : 1.0
                Behavior on scale { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }
                Behavior on color { ColorAnimation { duration: 250 } }

                Text {
                    id: dateText
                    anchors.centerIn: parent
                    text: barWindow.dateStr    // typewriter animated, resets every minute
                    font.family: "JetBrains Mono"; font.pixelSize: 13; font.weight: Font.Bold
                    color: mocha.subtext0
                }
                MouseArea {
                    id: dateMouse; anchors.fill: parent; hoverEnabled: true
                    // TODO: uncomment when QS calendar panel is built
                    // onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/quickshell/qs_manager.sh toggle calendar"])
                }
            }
        }

        // ───────────────── RIGHT ─────────────────
        RowLayout {
            id: rightLayout
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: 4

            property bool showLayout: false
            opacity: rightLayout.showLayout ? 1 : 0
            transform: Translate {
                x: rightLayout.showLayout ? 0 : 20
                Behavior on x { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }
            }
            Timer {
                running: barWindow.isStartupReady
                interval: 10
                onTriggered: rightLayout.showLayout = true
            }
            Behavior on opacity { NumberAnimation { duration: 600; easing.type: Easing.OutCubic } }

            // ── System Tray ──
            Rectangle {
                implicitHeight: 36; radius: 24
                border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.08); border.width: 1
                color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75)

                property real targetWidth: trayRepeater.count > 0 ? trayLayout.implicitWidth + 24 : 0
                Layout.preferredWidth: targetWidth
                Behavior on targetWidth { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }
                visible: targetWidth > 0
                opacity: targetWidth > 0 ? 1 : 0
                Behavior on opacity { NumberAnimation { duration: 300 } }

                RowLayout {
                    id: trayLayout
                    anchors.centerIn: parent
                    spacing: 10

                    Repeater {
                        id: trayRepeater
                        model: SystemTray.items
                        delegate: Image {
                            id: trayIcon
                            source: modelData.icon || ""
                            fillMode: Image.PreserveAspectFit
                            sourceSize: Qt.size(18, 18)
                            Layout.preferredWidth: 18; Layout.preferredHeight: 18
                            Layout.alignment: Qt.AlignVCenter

                            property bool isHovered: trayMouse.containsMouse
                            property bool initAnimTrigger: barWindow.startupCascadeFinished
                            opacity: initAnimTrigger ? (isHovered ? 1.0 : 0.8) : 0.0
                            scale:   initAnimTrigger ? (isHovered ? 1.15 : 1.0) : 0.0

                            Component.onCompleted: {
                                if (!barWindow.startupCascadeFinished) {
                                    trayAnimTimer.interval = index * 50;
                                    trayAnimTimer.start();
                                }
                            }
                            Timer { id: trayAnimTimer; running: false; repeat: false; onTriggered: trayIcon.initAnimTrigger = true }
                            Behavior on opacity { NumberAnimation { duration: 250; easing.type: Easing.OutCubic } }
                            Behavior on scale   { NumberAnimation { duration: 250; easing.type: Easing.OutBack } }

                            QsMenuAnchor {
                                id: menuAnchor
                                anchor.window: barWindow
                                anchor.item: trayIcon
                                menu: modelData.menu
                            }
                            MouseArea {
                                id: trayMouse
                                anchors.fill: parent; hoverEnabled: true
                                acceptedButtons: Qt.LeftButton | Qt.RightButton | Qt.MiddleButton
                                onClicked: mouse => {
                                    if (mouse.button === Qt.LeftButton)        modelData.activate();
                                    else if (mouse.button === Qt.MiddleButton) modelData.secondaryActivate();
                                    else if (mouse.button === Qt.RightButton) {
                                        if (modelData.menu) menuAnchor.open();
                                        else if (typeof modelData.contextMenu === "function") modelData.contextMenu(mouse.x, mouse.y);
                                    }
                                }
                            }
                        }
                    }
                }
            }

            // ── System Elements Pill ──
            Rectangle {
                implicitHeight: 36; radius: 24
                border.color: Qt.rgba(mocha.text.r, mocha.text.g, mocha.text.b, 0.08); border.width: 1
                color: Qt.rgba(mocha.base.r, mocha.base.g, mocha.base.b, 0.75)

                property real targetWidth: sysLayout.implicitWidth + 20
                Layout.preferredWidth: targetWidth
                Behavior on targetWidth { NumberAnimation { duration: 400; easing.type: Easing.OutExpo } }

                RowLayout {
                    id: sysLayout
                    anchors.centerIn: parent
                    spacing: 8
                    property int pillHeight: 34

                    // KB Layout removed — single layout, not needed
                    // Bluetooth removed — not in stack
                    // Battery removed — desktop

                    // ── WiFi (icon only — SSID in dropdown) ──
                    Rectangle {
                        id: wifiPill
                        property bool isHovered: wifiMouse.containsMouse
                        radius: 17; Layout.preferredHeight: sysLayout.pillHeight
                        color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4)

                        Rectangle {
                            anchors.fill: parent; radius: 17
                            opacity: barWindow.isWifiOn ? 1.0 : 0.0
                            Behavior on opacity { NumberAnimation { duration: 300 } }
                            gradient: Gradient {
                                orientation: Gradient.Horizontal
                                GradientStop { position: 0.0; color: mocha.blue }
                                GradientStop { position: 1.0; color: Qt.lighter(mocha.blue, 1.3) }
                            }
                        }

                        property real targetWidth: wifiLayoutRow.implicitWidth + 24
                        Layout.preferredWidth: targetWidth
                        Behavior on targetWidth { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }
                        scale: isHovered ? 1.05 : 1.0
                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                        Behavior on color { ColorAnimation { duration: 200 } }

                        RowLayout {
                            id: wifiLayoutRow; anchors.centerIn: parent; spacing: 8
                            // Icon only — no SSID text in bar, reserved for dropdown
                            Text {
                                text: barWindow.wifiIcon
                                font.family: "Iosevka Nerd Font"; font.pixelSize: 16
                                color: barWindow.isWifiOn ? mocha.base : mocha.subtext0
                            }
                        }
                        MouseArea {
                            id: wifiMouse; hoverEnabled: true; anchors.fill: parent
                            // TODO: uncomment when network dropdown is built
                            // onClicked: Quickshell.execDetached(["bash", "-c", "~/.config/quickshell/qs_manager.sh toggle network wifi"])
                        }
                    }

                    // ── Volume ──
                    Rectangle {
                        property bool isHovered: volMouse.containsMouse
                        color: isHovered ? Qt.rgba(mocha.surface1.r, mocha.surface1.g, mocha.surface1.b, 0.6) : (barWindow.isMuted ? Qt.rgba(0, 0, 0, 0.2) : Qt.rgba(mocha.surface0.r, mocha.surface0.g, mocha.surface0.b, 0.4))
                        radius: 17; Layout.preferredHeight: sysLayout.pillHeight

                        property real targetWidth: volLayoutRow.implicitWidth + 24
                        Layout.preferredWidth: targetWidth
                        Behavior on targetWidth { NumberAnimation { duration: 300; easing.type: Easing.OutExpo } }
                        scale: isHovered ? 1.05 : 1.0
                        Behavior on scale { NumberAnimation { duration: 250; easing.type: Easing.OutExpo } }
                        Behavior on color { ColorAnimation { duration: 200 } }

                        RowLayout {
                            id: volLayoutRow; anchors.centerIn: parent; spacing: 8
                            Text {
                                text: barWindow.volIcon
                                font.family: "Iosevka Nerd Font"; font.pixelSize: 16
                                color: barWindow.isMuted ? mocha.overlay0 : mocha.peach
                            }
                            Text {
                                text: barWindow.volPercent
                                font.family: "JetBrains Mono"; font.pixelSize: 13; font.weight: Font.Black
                                color: barWindow.isMuted ? mocha.overlay0 : mocha.text
                                font.strikeout: barWindow.isMuted
                            }
                        }
                        MouseArea {
                            id: volMouse; hoverEnabled: true; anchors.fill: parent
                            onClicked: Quickshell.execDetached(["pavucontrol"])
                        }
                    }
                }
            }
        }
    }
}
