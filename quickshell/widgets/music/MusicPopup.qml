import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import QtQuick.Effects
import Quickshell
import Quickshell.Io
import "../../"

Item {
    id: root

    MatugenColors { id: _theme }

    readonly property color base:     _theme.base
    readonly property color surface0: _theme.surface0
    readonly property color surface1: _theme.surface1
    readonly property color surface2: _theme.surface2
    readonly property color overlay0: _theme.overlay0
    readonly property color overlay1: _theme.overlay1
    readonly property color overlay2: _theme.overlay2
    readonly property color text:     _theme.text
    readonly property color subtext0: _theme.subtext0
    readonly property color subtext1: _theme.subtext1
    readonly property color blue:     _theme.blue
    readonly property color sapphire: _theme.sapphire
    readonly property color lavender: _theme.blue
    readonly property color mauve:    _theme.mauve
    readonly property color pink:     _theme.pink
    readonly property color red:      _theme.red
    readonly property color yellow:   _theme.yellow

    // ─────────────────────────────────────────────
    // DATA STATE
    // ─────────────────────────────────────────────
    property var musicData: {
        "title": "Loading...", "artist": "", "status": "Stopped", "percent": 0,
        "lengthStr": "00:00", "positionStr": "00:00", "timeStr": "--:-- / --:--",
        "source": "Offline", "playerName": "", "blur": "", "grad": "",
        "textColor": "#cdd6f4", "deviceIcon": "󰓃", "deviceName": "Speaker",
        "artUrl": ""
    }

    property var eqData: {
        "b1": 0, "b2": 0, "b3": 0, "b4": 0, "b5": 0,
        "b6": 0, "b7": 0, "b8": 0, "b9": 0, "b10": 0,
        "preset": "Flat", "pending": false
    }

    property bool userIsSeeking:   false
    property bool userToggledPlay: false
    property real lastEqUpdate:    0

    // Flowing progress bar gradient animation
    property real catppuccinFlowOffset: 0
    NumberAnimation on catppuccinFlowOffset {
        from: 0; to: 1.0; duration: 8000
        loops: Animation.Infinite; running: true
    }

    // ─────────────────────────────────────────────
    // PLAY/PAUSE EVENT LISTENER
    // ─────────────────────────────────────────────
    property string lastMusicStatus: "Stopped"
    onMusicDataChanged: {
        if (musicData && musicData.status && musicData.status !== lastMusicStatus) {
            if (musicData.status === "Playing") playPulse.trigger();
            lastMusicStatus = musicData.status;
        }
    }

    // ─────────────────────────────────────────────
    // STARTUP ANIMATIONS
    // ─────────────────────────────────────────────
    property real introMain:  0
    property real introCover: 0
    property real introText:  0
    property real introEq:    0

    ParallelAnimation {
        running: true
        NumberAnimation { target: root; property: "introMain";  from: 0; to: 1.0; duration: 700;  easing.type: Easing.OutQuart }
        NumberAnimation { target: root; property: "introCover"; from: 0; to: 1.0; duration: 800;  easing.type: Easing.OutExpo }
        NumberAnimation { target: root; property: "introText";  from: 0; to: 1.0; duration: 900;  easing.type: Easing.OutExpo }
        NumberAnimation { target: root; property: "introEq";    from: 0; to: 1.0; duration: 1000; easing.type: Easing.OutExpo }
    }

    // ─────────────────────────────────────────────
    // COLOR EXTRACTION FROM ALBUM ART GRADIENT
    // ─────────────────────────────────────────────
    property var borderColors: {
        var defaults = [root.mauve, root.blue, root.red, root.mauve];
        if (!root.musicData || !root.musicData.grad) return defaults;
        var matches = root.musicData.grad.match(/#[0-9a-fA-F]{6}/g);
        if (matches && matches.length >= 3) return [matches[0], matches[1], matches[2], matches[0]];
        return defaults;
    }

    property color bc1: borderColors[0] || root.mauve
    property color bc2: borderColors[1] || root.blue
    property color bc3: borderColors[2] || root.red
    property color bc4: borderColors[3] || root.mauve

    property color dynamicTextColor: {
        if (root.musicData && root.musicData.textColor) {
            var c = String(root.musicData.textColor).trim();
            var match = c.match(/^(#[0-9a-fA-F]{6})/);
            if (match) return match[1];
        }
        return root.text;
    }

    // ─────────────────────────────────────────────
    // UTILITIES
    // ─────────────────────────────────────────────
    function execCmd(cmdStr) {
        var p = Qt.createQmlObject(
            'import Quickshell.Io; Process { command: ["bash", "-c", "' +
            cmdStr.replace(/\\/g, '\\\\').replace(/"/g, '\\"') +
            '"]; running: true; onExited: (exitCode) => destroy() }',
            root
        );
    }

    function applyPresetOptimistically(presetName) {
        var presets = {
            "Flat":    [0,  0,  0,  0,  0,  0,  0,  0,  0,  0],
            "Bass":    [5,  7,  5,  2,  1,  0,  0,  0,  1,  2],
            "Treble":  [-2,-1,  0,  1,  2,  3,  4,  5,  6,  6],
            "Vocal":   [-2,-1,  1,  3,  5,  5,  4,  2,  1,  0],
            "Pop":     [2,  4,  2,  0,  1,  2,  4,  2,  1,  2],
            "Rock":    [5,  4,  2, -1, -2, -1,  2,  4,  5,  6],
            "Jazz":    [3,  3,  1,  1,  1,  1,  2,  1,  2,  3],
            "Classic": [0,  1,  2,  2,  2,  2,  1,  2,  3,  4]
        };
        if (presets[presetName]) {
            var temp = Object.assign({}, root.eqData);
            for (var i = 0; i < 10; i++) temp["b" + (i + 1)] = presets[presetName][i];
            temp.preset  = presetName;
            temp.pending = false;
            root.eqData  = temp;
            root.lastEqUpdate = Date.now();
            execCmd("$HOME/.config/quickshell/widgets/music/equalizer.sh preset " + presetName);
        }
    }

    // ─────────────────────────────────────────────
    // DATA POLLING
    // ─────────────────────────────────────────────
    Timer { id: seekDebounceTimer;  interval: 2500; onTriggered: root.userIsSeeking   = false }
    Timer { id: playDebounceTimer;  interval: 1500; onTriggered: root.userToggledPlay = false }

    Timer {
        interval: 500; running: true; repeat: true; triggeredOnStart: true
        onTriggered: {
            if (!musicProc.running) musicProc.running = true;
            if (!eqProc.running)    eqProc.running    = true;
        }
    }

    Process {
        id: musicProc
        running: true
        command: ["bash", "-c", "$HOME/.config/quickshell/widgets/music/music_info.sh"]
        stdout: StdioCollector {
            onStreamFinished: {
                var outStr = this.text ? this.text.trim() : "";
                if (outStr.length > 0) {
                    try {
                        var newData = JSON.parse(outStr);
                        if (root.userToggledPlay) newData.status = root.musicData.status;
                        root.musicData = newData;
                    } catch(e) {}
                }
            }
        }
    }

    Process {
        id: eqProc
        running: true
        command: ["bash", "-c", "$HOME/.config/quickshell/widgets/music/equalizer.sh get"]
        stdout: StdioCollector {
            onStreamFinished: {
                if (Date.now() - root.lastEqUpdate < 2000) return;
                var outStr = this.text ? this.text.trim() : "";
                if (outStr.length > 0) {
                    try { root.eqData = JSON.parse(outStr); } catch(e) {}
                }
            }
        }
    }

    // ─────────────────────────────────────────────
    // UI
    // ─────────────────────────────────────────────
    Item {
        id: mainWrapper
        anchors.fill: parent
        scale: 0.95 + (0.05 * root.introMain)
        opacity: root.introMain

        // Border — color from album art extraction
        Rectangle {
            anchors.fill: parent; radius: 16; color: "transparent"
            border.width: 3; border.color: root.bc1
            Behavior on border.color { ColorAnimation { duration: 800 } }
            z: 2
        }

        // Solid dark background
        Rectangle {
            id: innerBg
            anchors.fill: parent
            anchors.margins: 3
            color: root.base
            radius: 12
            layer.enabled: true

            Rectangle {
                id: innerBgMask
                anchors.fill: parent
                radius: 12
                visible: false
                layer.enabled: true
            }

            Item {
                id: bgEffectsLayer
                anchors.fill: parent
                layer.enabled: true
                layer.effect: MultiEffect {
                    maskEnabled: true
                    maskSource: innerBgMask
                }

                // Blurred album art background (subtle)
                Image {
                    anchors.fill: parent
                    source: root.musicData.blur ? "file://" + root.musicData.blur : ""
                    fillMode: Image.PreserveAspectCrop
                    opacity: status === Image.Ready ? 0.3 : 0.0
                    Behavior on opacity { NumberAnimation { duration: 800; easing.type: Easing.InOutQuad } }
                }
            }

            ColumnLayout {
                anchors.fill: parent
                anchors.margins: 20
                spacing: 0

                // ══════════════════════════════════════
                // TOP — Cover art + track info
                // ══════════════════════════════════════
                RowLayout {
                    Layout.fillWidth: true
                    Layout.preferredHeight: 220
                    spacing: 25

                    // ── Cover Art ──
                    Item {
                        Layout.preferredWidth: 220
                        Layout.preferredHeight: 220
                        Layout.alignment: Qt.AlignVCenter
                        opacity: root.introCover
                        transform: Translate { x: -30 * (1 - root.introCover) }

                        scale: root.musicData.status === "Playing" ? 1.0 : 0.90
                        Behavior on scale { NumberAnimation { duration: 800; easing.type: Easing.OutElastic; easing.overshoot: 1.2 } }

                        Rectangle {
                            anchors.fill: parent
                            radius: 110
                            color: root.surface1
                            border.width: 4
                            border.color: root.musicData.status === "Playing" ? root.mauve : root.overlay0
                            Behavior on border.color { ColorAnimation { duration: 500 } }

                            Rectangle {
                                z: -1
                                anchors.centerIn: parent
                                width: parent.width + 20; height: parent.height + 20
                                radius: width / 2
                                color: root.mauve
                                opacity: root.musicData.status === "Playing" ? 0.5 : 0.0
                                Behavior on opacity { NumberAnimation { duration: 500 } }
                                layer.enabled: true
                                layer.effect: MultiEffect { blurEnabled: true; blurMax: 32; blur: 1.0 }
                            }

                            Item {
                                anchors.fill: parent
                                anchors.margins: 4

                                Image {
                                    id: artImg
                                    anchors.fill: parent
                                    source: root.musicData.artUrl ? "file://" + root.musicData.artUrl : ""
                                    fillMode: Image.PreserveAspectCrop
                                    visible: false
                                }

                                Rectangle {
                                    id: maskRect
                                    anchors.fill: parent
                                    radius: width / 2
                                    visible: false
                                    layer.enabled: true
                                }

                                MultiEffect {
                                    anchors.fill: parent
                                    source: artImg
                                    maskEnabled: true
                                    maskSource: maskRect
                                    opacity: artImg.status === Image.Ready ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 800 } }
                                }

                                // Mauve tint overlay
                                Rectangle {
                                    anchors.fill: parent
                                    radius: width / 2
                                    color: Qt.rgba(root.mauve.r, root.mauve.g, root.mauve.b, 0.2)
                                    opacity: artImg.status === Image.Ready ? 1.0 : 0.0
                                    Behavior on opacity { NumberAnimation { duration: 800 } }
                                }

                                // Center hole
                                Rectangle {
                                    width: 40; height: 40; radius: 20
                                    color: "#000000"; opacity: 0.8
                                    anchors.centerIn: parent
                                }
                            }

                            NumberAnimation on rotation {
                                from: 0; to: 360; duration: 8000
                                loops: Animation.Infinite; running: true
                                paused: root.musicData.status !== "Playing"
                            }
                        }
                    }

                    // ── Track Info ──
                    ColumnLayout {
                        Layout.fillWidth: true
                        Layout.alignment: Qt.AlignVCenter
                        spacing: 15
                        opacity: root.introText
                        transform: Translate { x: 30 * (1 - root.introText) }

                        ColumnLayout {
                            spacing: 6

                            Text {
                                text: root.musicData.title
                                color: root.dynamicTextColor
                                font.family: "JetBrains Mono"; font.pixelSize: 20; font.bold: true
                                elide: Text.ElideRight; maximumLineCount: 2; wrapMode: Text.Wrap
                                Layout.fillWidth: true
                                Behavior on color { ColorAnimation { duration: 600 } }
                            }
                            Text {
                                text: root.musicData.artist ? "BY " + root.musicData.artist : ""
                                color: root.subtext0
                                font.family: "JetBrains Mono"; font.pixelSize: 14; font.bold: true
                                elide: Text.ElideRight; Layout.fillWidth: true
                            }
                            RowLayout {
                                spacing: 10
                                Rectangle {
                                    color: "#1AFFFFFF"; radius: 4
                                    Layout.preferredHeight: 24
                                    Layout.preferredWidth: pillContent.width + 20
                                    RowLayout {
                                        id: pillContent; anchors.centerIn: parent; spacing: 6
                                        Text { text: root.musicData.deviceIcon || "󰓃"; color: root.mauve; font.family: "Iosevka Nerd Font"; font.pixelSize: 14 }
                                        Text { text: root.musicData.deviceName || "Speaker"; color: root.overlay2; font.family: "JetBrains Mono"; font.pixelSize: 12; font.bold: true }
                                    }
                                }
                                Text {
                                    text: "VIA " + (root.musicData.source || "Offline")
                                    color: root.overlay2
                                    font.family: "JetBrains Mono"; font.pixelSize: 12; font.bold: true; font.italic: true
                                }
                            }
                        }

                        // ── Progress Bar ──
                        ColumnLayout {
                            Layout.fillWidth: true
                            spacing: 5

                            Slider {
                                id: progBar
                                Layout.fillWidth: true
                                Layout.preferredHeight: 20
                                from: 0; to: 100

                                Connections {
                                    target: root
                                    function onMusicDataChanged() {
                                        if (!progBar.pressed && !root.userIsSeeking) {
                                            if (root.musicData && root.musicData.percent !== undefined) {
                                                var p = Number(root.musicData.percent);
                                                if (!isNaN(p)) progBar.value = p;
                                            }
                                        }
                                    }
                                }

                                Behavior on value {
                                    enabled: !progBar.pressed && !root.userIsSeeking
                                    NumberAnimation { duration: 400; easing.type: Easing.OutSine }
                                }

                                onPressedChanged: {
                                    if (pressed) {
                                        root.userIsSeeking = true;
                                        seekDebounceTimer.stop();
                                    } else {
                                        var temp = Object.assign({}, root.musicData);
                                        temp.percent = value;
                                        root.musicData = temp;
                                        var safePlayer = root.musicData.playerName || "";
                                        Quickshell.execDetached([
                                        "bash",
                                        Quickshell.env("HOME") + "/.config/quickshell/widgets/music/player_control.sh",
                                        "seek",
                                        value.toFixed(2),
                                        root.musicData.length,
                                        safePlayer
                                        ]);
                                        seekDebounceTimer.restart();
                                    }
                                }

                                background: Item {
                                    x: progBar.leftPadding
                                    y: progBar.topPadding + (progBar.availableHeight - 12) / 2
                                    width: progBar.availableWidth; height: 12

                                    Rectangle {
                                        anchors.fill: parent; radius: 6
                                        color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.7)
                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            shadowEnabled: true; shadowColor: "#000000"
                                            shadowOpacity: 0.9; shadowBlur: 0.5; shadowVerticalOffset: 1
                                        }
                                    }

                                    // Flowing gradient fill
                                    Item {
                                        width: progBar.handle.x - progBar.leftPadding + (progBar.handle.width / 2)
                                        height: parent.height
                                        layer.enabled: true
                                        layer.effect: MultiEffect {
                                            maskEnabled: true
                                            maskSource: sliderFillMask
                                        }

                                        Rectangle {
                                            id: sliderFillMask
                                            width: parent.width; height: parent.height
                                            radius: 6; visible: false; layer.enabled: true
                                        }

                                        Rectangle {
                                            width: 2000; height: parent.height
                                            x: -(root.catppuccinFlowOffset * 1000)
                                            gradient: Gradient {
                                                orientation: Gradient.Horizontal
                                                GradientStop { position: 0.0000; color: Qt.lighter(root.blue, 1.2);     Behavior on color { ColorAnimation { duration: 800 } } }
                                                GradientStop { position: 0.1666; color: Qt.lighter(root.sapphire, 1.15); Behavior on color { ColorAnimation { duration: 800 } } }
                                                GradientStop { position: 0.3333; color: Qt.lighter(root.mauve, 1.15);   Behavior on color { ColorAnimation { duration: 800 } } }
                                                GradientStop { position: 0.5000; color: Qt.lighter(root.blue, 1.2);     Behavior on color { ColorAnimation { duration: 800 } } }
                                                GradientStop { position: 0.6666; color: Qt.lighter(root.sapphire, 1.15); Behavior on color { ColorAnimation { duration: 800 } } }
                                                GradientStop { position: 0.8333; color: Qt.lighter(root.mauve, 1.15);   Behavior on color { ColorAnimation { duration: 800 } } }
                                                GradientStop { position: 1.0000; color: Qt.lighter(root.blue, 1.2);     Behavior on color { ColorAnimation { duration: 800 } } }
                                            }
                                        }
                                    }
                                }

                                handle: Rectangle {
                                    x: progBar.leftPadding + progBar.visualPosition * (progBar.availableWidth - width)
                                    y: progBar.topPadding + (progBar.availableHeight - height) / 2
                                    width: 18; height: 18; radius: 9; color: root.text
                                    scale: progBar.pressed ? 1.3 : 1.0
                                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                }
                            }

                            RowLayout {
                                Layout.fillWidth: true
                                Text { text: root.musicData.positionStr || "00:00"; color: root.overlay2; font.family: "JetBrains Mono"; font.bold: true; font.pixelSize: 13 }
                                Item { Layout.fillWidth: true }
                                Text { text: root.musicData.lengthStr  || "00:00"; color: root.overlay2; font.family: "JetBrains Mono"; font.bold: true; font.pixelSize: 13 }
                            }
                        }

                        // ── Playback Controls ──
                        RowLayout {
                            Layout.alignment: Qt.AlignHCenter
                            spacing: 30

                            MouseArea {
                                width: 30; height: 30; cursorShape: Qt.PointingHandCursor
                                onClicked: root.execCmd("playerctl previous")
                                Text { anchors.centerIn: parent; text: ""; color: parent.pressed ? root.text : root.overlay2; font.family: "Iosevka Nerd Font"; font.pixelSize: 24 }
                            }

                            MouseArea {
                                id: playPauseBtn
                                width: 50; height: 50; cursorShape: Qt.PointingHandCursor
                                onClicked: {
                                    root.userToggledPlay = true;
                                    playDebounceTimer.restart();
                                    var temp = Object.assign({}, root.musicData);
                                    temp.status = (temp.status === "Playing" ? "Paused" : "Playing");
                                    root.musicData = temp;
                                    root.execCmd("playerctl play-pause");
                                }

                                Rectangle {
                                    id: playPulse
                                    anchors.centerIn: parent
                                    width: parent.width; height: parent.height
                                    radius: width / 2; color: root.mauve
                                    opacity: 0; scale: 1

                                    NumberAnimation { id: playPulseScaleAnim; target: playPulse; property: "scale";   from: 1.0; to: 1.8; duration: 500; easing.type: Easing.OutQuart }
                                    NumberAnimation { id: playPulseFadeAnim;  target: playPulse; property: "opacity"; from: 0.5; to: 0.0; duration: 500; easing.type: Easing.OutQuart }

                                    function trigger() {
                                        playPulseScaleAnim.restart();
                                        playPulseFadeAnim.restart();
                                    }
                                }

                                Text {
                                    anchors.centerIn: parent
                                    text: root.musicData.status === "Playing" ? "" : ""
                                    color: parent.pressed ? root.pink : root.mauve
                                    font.family: "Iosevka Nerd Font"; font.pixelSize: 42
                                    scale: parent.pressed ? 0.8 : 1.0
                                    Behavior on color { ColorAnimation { duration: 150 } }
                                    Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                }
                            }

                            MouseArea {
                                width: 30; height: 30; cursorShape: Qt.PointingHandCursor
                                onClicked: root.execCmd("playerctl next")
                                Text { anchors.centerIn: parent; text: ""; color: parent.pressed ? root.text : root.overlay2; font.family: "Iosevka Nerd Font"; font.pixelSize: 24 }
                            }
                        }
                    }
                }

                // ══════════════════════════════════════
                // SEPARATOR
                // ══════════════════════════════════════
                Rectangle {
                    Layout.fillWidth: true; Layout.preferredHeight: 2
                    Layout.topMargin: 20; Layout.bottomMargin: 20
                    color: "#1AFFFFFF"; radius: 1
                    opacity: root.introEq
                    transform: Translate { y: 15 * (1 - root.introEq) }
                }

                // ══════════════════════════════════════
                // EQUALIZER
                // ══════════════════════════════════════
                ColumnLayout {
                    Layout.fillWidth: true
                    spacing: 15
                    opacity: root.introEq
                    transform: Translate { y: 25 * (1 - root.introEq) }

                    // Header
                    RowLayout {
                        Layout.fillWidth: true

                        Text {
                            text: "Equalizer"; color: root.mauve
                            font.family: "JetBrains Mono"; font.pixelSize: 16; font.bold: true
                            Layout.fillWidth: true
                        }

                        Rectangle {
                            Layout.preferredHeight: 28
                            Layout.preferredWidth: applyTxt.width + 30
                            radius: 14
                            color: root.eqData.pending ? root.mauve : root.surface1
                            border.color: root.eqData.pending ? root.mauve : root.surface2
                            border.width: 1
                            Behavior on color { ColorAnimation { duration: 300; easing.type: Easing.OutCubic } }
                            Behavior on border.color { ColorAnimation { duration: 300; easing.type: Easing.OutCubic } }

                            layer.enabled: root.eqData.pending
                            layer.effect: MultiEffect {
                                shadowEnabled: true; shadowColor: root.mauve; shadowOpacity: 0.4; shadowBlur: 0.6
                            }

                            Text {
                                id: applyTxt
                                anchors.centerIn: parent
                                text: root.eqData.pending ? "Apply" : "Saved"
                                color: root.eqData.pending ? root.base : root.subtext0
                                font.family: "JetBrains Mono"; font.pixelSize: 12; font.bold: true
                                Behavior on color { ColorAnimation { duration: 300 } }
                            }
                            MouseArea {
                                anchors.fill: parent
                                cursorShape: root.eqData.pending ? Qt.PointingHandCursor : Qt.ArrowCursor
                                onClicked: {
                                    if (root.eqData.pending) {
                                        var temp = Object.assign({}, root.eqData);
                                        temp.pending = false;
                                        root.eqData = temp;
                                        root.lastEqUpdate = Date.now();
                                        root.execCmd("$HOME/.config/quickshell/widgets/music/equalizer.sh apply");
                                    }
                                }
                            }
                        }

                        Text {
                            text: root.eqData.preset || "Flat"; color: root.subtext0
                            font.family: "JetBrains Mono"; font.pixelSize: 14; font.bold: true
                            Layout.leftMargin: 15
                        }
                    }

                    // EQ Sliders
                    Item {
                        Layout.fillWidth: true
                        Layout.preferredHeight: 180

                        Row {
                            id: eqSliderRow
                            anchors.fill: parent

                            Repeater {
                                model: [
                                    { idx: 1,  lbl: "31"  }, { idx: 2,  lbl: "63"  }, { idx: 3,  lbl: "125" },
                                    { idx: 4,  lbl: "250" }, { idx: 5,  lbl: "500" }, { idx: 6,  lbl: "1k"  },
                                    { idx: 7,  lbl: "2k"  }, { idx: 8,  lbl: "4k"  }, { idx: 9,  lbl: "8k"  },
                                    { idx: 10, lbl: "16k" }
                                ]
                                delegate: Item {
                                    id: sliderDelegate
                                    width: eqSliderRow.width / 10
                                    height: eqSliderRow.height

                                    ColumnLayout {
                                        anchors.fill: parent
                                        spacing: 5

                                        Slider {
                                            id: eqSlider
                                            Layout.fillHeight: true
                                            Layout.alignment: Qt.AlignHCenter
                                            orientation: Qt.Vertical
                                            from: -12; to: 12; stepSize: 1

                                            Connections {
                                                target: root
                                                function onEqDataChanged() {
                                                    if (!eqSlider.pressed) {
                                                        if (root.eqData && root.eqData["b" + modelData.idx] !== undefined) {
                                                            var p = Number(root.eqData["b" + modelData.idx]);
                                                            if (!isNaN(p)) eqSlider.value = p;
                                                        }
                                                    }
                                                }
                                            }

                                            Behavior on value {
                                                enabled: !eqSlider.pressed
                                                NumberAnimation { duration: 350; easing.type: Easing.OutQuart }
                                            }

                                            onPressedChanged: {
                                                if (!pressed) {
                                                    var temp = Object.assign({}, root.eqData);
                                                    temp["b" + modelData.idx] = Math.round(value);
                                                    temp.preset  = "Custom";
                                                    temp.pending = true;
                                                    root.eqData  = temp;
                                                    root.lastEqUpdate = Date.now();
                                                    root.execCmd("$HOME/.config/quickshell/widgets/music/equalizer.sh set_band " + modelData.idx + " " + Math.round(value));
                                                }
                                            }

                                            background: Rectangle {
                                                x: eqSlider.leftPadding + (eqSlider.availableWidth - width) / 2
                                                y: eqSlider.topPadding
                                                width: 10; height: eqSlider.availableHeight; radius: 5
                                                color: Qt.rgba(root.surface0.r, root.surface0.g, root.surface0.b, 0.7)
                                                layer.enabled: true
                                                layer.effect: MultiEffect {
                                                    shadowEnabled: true; shadowColor: "#000000"
                                                    shadowOpacity: 0.9; shadowBlur: 0.5; shadowVerticalOffset: 1
                                                }

                                                Item {
                                                    width: parent.width
                                                    height: (1 - eqSlider.visualPosition) * parent.height
                                                    y: eqSlider.visualPosition * parent.height
                                                    layer.enabled: true
                                                    layer.effect: MultiEffect {
                                                        maskEnabled: true
                                                        maskSource: eqFillMask
                                                    }

                                                    Rectangle {
                                                        id: eqFillMask
                                                        anchors.fill: parent; radius: 5
                                                        visible: false; layer.enabled: true
                                                    }

                                                    Rectangle {
                                                        anchors.fill: parent
                                                        color: root.blue
                                                    }
                                                }
                                            }

                                            handle: Rectangle {
                                                x: eqSlider.leftPadding + (eqSlider.availableWidth - width) / 2
                                                y: eqSlider.topPadding + eqSlider.visualPosition * (eqSlider.availableHeight - height)
                                                width: 18; height: 18; radius: 9; color: root.text
                                                scale: eqSlider.pressed ? 1.2 : 1.0
                                                Behavior on scale { NumberAnimation { duration: 150; easing.type: Easing.OutBack } }
                                            }
                                        }

                                        Text {
                                            text: modelData.lbl; color: root.overlay1
                                            font.family: "JetBrains Mono"; font.pixelSize: 10; font.bold: true
                                            Layout.alignment: Qt.AlignHCenter
                                        }
                                    }
                                }
                            }
                        }
                    }

                    // Preset buttons
                    ColumnLayout {
                        Layout.fillWidth: true
                        spacing: 8

                        RowLayout {
                            Layout.fillWidth: true; spacing: 10
                            Repeater {
                                model: ["Flat", "Bass", "Treble", "Vocal"]
                                delegate: PresetButton { name: modelData }
                            }
                        }
                        RowLayout {
                            Layout.fillWidth: true; spacing: 10
                            Repeater {
                                model: ["Pop", "Rock", "Jazz", "Classic"]
                                delegate: PresetButton { name: modelData }
                            }
                        }
                    }
                }
            }
        }
    }

    // ─────────────────────────────────────────────
    // PRESET BUTTON COMPONENT
    // ─────────────────────────────────────────────
    component PresetButton : Rectangle {
        property string name: ""
        Layout.fillWidth: true
        Layout.preferredHeight: 32
        radius: 8

        property bool isActivePreset: root.eqData && root.eqData.preset === name
        property bool isHovered:      hoverMa.containsMouse

        color: isActivePreset ? root.mauve : (isHovered ? root.surface1 : "#BF1E1E2E")
        scale: isHovered && !isActivePreset ? 1.05 : 1.0

        Behavior on color { ColorAnimation { duration: 200 } }
        Behavior on scale { NumberAnimation { duration: 200; easing.type: Easing.OutBack } }

        Text {
            anchors.centerIn: parent
            text: parent.name
            color: parent.isActivePreset ? root.base : (parent.isHovered ? root.text : root.subtext0)
            font.family: "JetBrains Mono"; font.pixelSize: 12; font.bold: true
            Behavior on color { ColorAnimation { duration: 200 } }
        }

        MouseArea {
            id: hoverMa
            anchors.fill: parent
            hoverEnabled: true
            cursorShape: Qt.PointingHandCursor
            onClicked: root.applyPresetOptimistically(parent.name)
        }
    }
}
