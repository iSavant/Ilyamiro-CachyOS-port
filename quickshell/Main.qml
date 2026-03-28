import QtQuick
import QtQuick.Window
import QtQuick.Controls
import Quickshell
import Quickshell.Io

FloatingWindow {
    id: masterWindow
    title: "qs-master"
    color: "transparent"

    // Always mapped — prevents Wayland from destroying the surface
    // and Hyprland from auto-centering on next open
    visible: true

    // Push offscreen the moment the component loads
    Component.onCompleted: {
        Quickshell.execDetached(["bash", "-c",
            `hyprctl dispatch resizewindowpixel "exact 1 1,title:^(qs-master)$" && ` +
            `hyprctl dispatch movewindowpixel "exact -5000 -5000,title:^(qs-master)$"`
        ]);
    }

    // ─────────────────────────────────────────────
    // SCREEN DIMENSIONS
    // Set to your main monitor (DP-1 — 2560x1440)
    // ─────────────────────────────────────────────
    property int screenW: 2560
    property int screenH: 1440

    // ─────────────────────────────────────────────
    // STATE
    // ─────────────────────────────────────────────
    property string currentActive: "hidden"
    onCurrentActiveChanged: {
        // Write active widget name to file so qs_manager.sh can read it
        Quickshell.execDetached(["bash", "-c",
            "echo '" + currentActive + "' > /tmp/qs_active_widget"
        ]);
    }

    property bool isVisible: false
    property bool disableMorph: false
    property bool isWallpaperTransition: false

    // Fast open (250ms) vs smooth morph between widgets (500ms)
    property int morphDuration: 500

    property int currentX: -5000
    property int currentY: -5000

    property real animW: 1
    property real animH: 1

    // ─────────────────────────────────────────────
    // WIDGET LAYOUTS
    // Defines size and position of each panel on your 2560x1440 screen
    // Removed: battery, stewart, monitors, focustime
    // ─────────────────────────────────────────────
    property var layouts: {
        "music":     { w: 700,  h: 620, x: 12,                              y: 70,  comp: "widgets/music/MusicPopup.qml"         },
        "network":   { w: 900,  h: 700, x: screenW - 920,                   y: 70,  comp: "widgets/network/NetworkPopup.qml"      },
        "wallpaper": { w: 2560, h: 500, x: 0,                               y: Math.floor((screenH / 2) - (500 / 2)),
                                                                                     comp: "widgets/wallpaper/WallpaperPicker.qml" },
        "hidden":    { w: 1,    h: 1,   x: -5000,                           y: -5000, comp: ""                                   }
    }


    implicitWidth: width
    implicitHeight: height
    width: 1
    height: 1


    // ─────────────────────────────────────────────
    // MORPH CONTAINER
    // The single window that resizes and repositions itself
    // ─────────────────────────────────────────────
    Item {
        anchors.centerIn: parent
        width: masterWindow.animW
        height: masterWindow.animH
        clip: true

        Behavior on width  { enabled: !masterWindow.disableMorph; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.InOutCubic } }
        Behavior on height { enabled: !masterWindow.disableMorph; NumberAnimation { duration: masterWindow.morphDuration; easing.type: Easing.InOutCubic } }

        opacity: masterWindow.isVisible ? 1.0 : 0.0
        Behavior on opacity {
            NumberAnimation {
                duration: masterWindow.isWallpaperTransition ? 150 : (masterWindow.morphDuration === 500 ? 300 : 200)
                easing.type: Easing.InOutSine
            }
        }

        // Inner fixed container — holds the actual widget at its target size
        Item {
            anchors.centerIn: parent
            width:  masterWindow.currentActive !== "hidden" && layouts[masterWindow.currentActive] ? layouts[masterWindow.currentActive].w : 1
            height: masterWindow.currentActive !== "hidden" && layouts[masterWindow.currentActive] ? layouts[masterWindow.currentActive].h : 1

            // StackView loads widgets dynamically by file path
            // Crossfades between widgets with scale + opacity animation
            StackView {
                id: widgetStack
                anchors.fill: parent
                focus: true

                // Escape key bubbles up if the widget doesn't handle it
                Keys.onEscapePressed: {
                    Quickshell.execDetached([
                        "bash",
                        Quickshell.env("HOME") + "/.config/quickshell/qs_manager.sh",
                        "close"
                    ])
                    event.accepted = true
                }

                onCurrentItemChanged: {
                    if (currentItem) currentItem.forceActiveFocus();
                }

                // New widget fades + scales in
                replaceEnter: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 0.0; to: 1.0; duration: 350; easing.type: Easing.InOutQuad }
                        NumberAnimation { property: "scale";   from: 0.95; to: 1.0; duration: 350; easing.type: Easing.OutBack  }
                    }
                }

                // Old widget fades + scales out
                replaceExit: Transition {
                    ParallelAnimation {
                        NumberAnimation { property: "opacity"; from: 1.0; to: 0.0; duration: 350; easing.type: Easing.InOutQuad }
                        NumberAnimation { property: "scale";   from: 1.0; to: 1.05; duration: 350; easing.type: Easing.InCubic  }
                    }
                }
            }
        }
    }

    // ─────────────────────────────────────────────
    // SWITCH WIDGET
    // Core morphing logic — three modes:
    //   1. Fast open (250ms)  — coming from hidden
    //   2. Smooth morph (500ms) — switching between two visible widgets
    //   3. Wallpaper transition (150ms) — special fade for fullscreen wallpaper picker
    // ─────────────────────────────────────────────
    function switchWidget(newWidget, arg) {
        let involvesWallpaper = (newWidget === "wallpaper" || currentActive === "wallpaper");
        masterWindow.isWallpaperTransition = involvesWallpaper;

        if (newWidget === "hidden") {
            // ── CLOSE ──
            if (currentActive !== "hidden" && layouts[currentActive]) {
                masterWindow.morphDuration = 250;
                masterWindow.disableMorph = false;

                let t = layouts[currentActive];
                let cx = Math.floor(t.x + (t.w / 2));
                let cy = Math.floor(t.y + (t.h / 2));

                masterWindow.animW = 1;
                masterWindow.animH = 1;
                masterWindow.isVisible = false;

                Quickshell.execDetached(["bash", "-c",
                    `hyprctl dispatch resizewindowpixel "exact 1 1,title:^(qs-master)$" && ` +
                    `hyprctl dispatch movewindowpixel "exact ${cx} ${cy},title:^(qs-master)$"`
                ]);

                delayedClear.start();
            }
        } else {
            if (currentActive === "hidden") {
                // ── FAST OPEN from hidden ──
                masterWindow.morphDuration = 250;
                masterWindow.disableMorph = false;

                let t = layouts[newWidget];
                let cx = Math.floor(t.x + (t.w / 2));
                let cy = Math.floor(t.y + (t.h / 2));

                masterWindow.animW = 1;
                masterWindow.animH = 1;
                masterWindow.width = 1;
                masterWindow.height = 1;

                Quickshell.execDetached(["bash", "-c",
                    `hyprctl dispatch movewindowpixel "exact ${cx} ${cy},title:^(qs-master)$"`
                ]);

                prepTimer.newWidget = newWidget;
                prepTimer.newArg = arg;
                prepTimer.start();

            } else {
                // ── MORPH between two visible widgets ──
                masterWindow.morphDuration = 500;

                if (involvesWallpaper) {
                    // Wallpaper is fullscreen — morph looks wrong, use fade instead
                    masterWindow.disableMorph = true;
                    masterWindow.isVisible = false;
                    teleportFadeOutTimer.newWidget = newWidget;
                    teleportFadeOutTimer.newArg = arg;
                    teleportFadeOutTimer.start();
                } else {
                    masterWindow.disableMorph = false;
                    executeSwitch(newWidget, arg, false);
                }
            }
        }
    }

    // ─────────────────────────────────────────────
    // TIMERS
    // ─────────────────────────────────────────────

    // 50ms prep delay after moving window — lets Hyprland process the move
    // before QML resizes and loads the widget
    Timer {
        id: prepTimer
        interval: 50
        property string newWidget: ""
        property string newArg: ""
        onTriggered: executeSwitch(newWidget, newArg, false)
    }

    // Wallpaper transition — fade out, teleport, then fade back in
    Timer {
        id: teleportFadeOutTimer
        interval: 150
        property string newWidget: ""
        property string newArg: ""
        onTriggered: {
            let t = layouts[newWidget];

            masterWindow.currentActive = newWidget;
            masterWindow.animW = t.w;
            masterWindow.animH = t.h;
            masterWindow.width = t.w;
            masterWindow.height = t.h;
            masterWindow.currentX = t.x;
            masterWindow.currentY = t.y;

            Quickshell.execDetached(["bash", "-c",
                `hyprctl dispatch resizewindowpixel "exact ${t.w} ${t.h},title:^(qs-master)$" && ` +
                `hyprctl dispatch movewindowpixel "exact ${t.x} ${t.y},title:^(qs-master)$"`
            ]);

            let props = newWidget === "wallpaper" ? { "widgetArg": newArg } : {};
            widgetStack.replace(Qt.resolvedUrl(t.comp), props, StackView.Immediate);

            teleportFadeInTimer.start();
        }
    }

    Timer {
        id: teleportFadeInTimer
        interval: 50
        onTriggered: {
            masterWindow.isVisible = true;
            resetMorphTimer.start();
        }
    }

    // Re-enable morph after animation completes
    Timer {
        id: resetMorphTimer
        interval: masterWindow.morphDuration
        onTriggered: masterWindow.disableMorph = false
    }

    // Clears the StackView and banishes window offscreen after close animation
    Timer {
        id: delayedClear
        interval: masterWindow.isWallpaperTransition ? 150 : masterWindow.morphDuration
        onTriggered: {
            masterWindow.currentActive = "hidden";
            widgetStack.clear();
            masterWindow.disableMorph = false;

            Quickshell.execDetached(["bash", "-c",
                `hyprctl dispatch resizewindowpixel "exact 1 1,title:^(qs-master)$" && ` +
                `hyprctl dispatch movewindowpixel "exact -5000 -5000,title:^(qs-master)$"`
            ]);
        }
    }

    // ─────────────────────────────────────────────
    // IPC POLLER
    // Reads /tmp/qs_widget_state every 50ms
    // qs_manager.sh writes to this file when you press a keybind
    // ─────────────────────────────────────────────
    Timer {
        interval: 50
        running: true
        repeat: true
        onTriggered: { if (!ipcPoller.running) ipcPoller.running = true; }
    }

    Process {
        id: ipcPoller
        command: ["bash", "-c",
            "if [ -f /tmp/qs_widget_state ]; then cat /tmp/qs_widget_state; rm /tmp/qs_widget_state; fi"
        ]
        stdout: StdioCollector {
            onStreamFinished: {
                let rawCmd = this.text.trim();
                if (rawCmd === "") return;

                let parts = rawCmd.split(":");
                let cmd = parts[0];
                let arg = parts.length > 1 ? parts[1] : "";

                if (cmd === "close") {
                    switchWidget("hidden", "");
                } else if (layouts[cmd]) {
                    // Stop pending close animation if user quickly reopens
                    delayedClear.stop();

                    if (masterWindow.isVisible && masterWindow.currentActive === cmd) {
                        // Same widget toggled — close it
                        switchWidget("hidden", "");
                    } else {
                        switchWidget(cmd, arg);
                    }
                }
            }
        }
    }

    // ─────────────────────────────────────────────
    // EXECUTE SWITCH
    // Does the actual resize + move + load
    // ─────────────────────────────────────────────
    function executeSwitch(newWidget, arg, immediate) {
        masterWindow.currentActive = newWidget;

        let t = layouts[newWidget];
        masterWindow.animW = t.w;
        masterWindow.animH = t.h;
        masterWindow.width = t.w;
        masterWindow.height = t.h;
        masterWindow.currentX = t.x;
        masterWindow.currentY = t.y;

        Quickshell.execDetached(["bash", "-c",
            `hyprctl dispatch resizewindowpixel "exact ${t.w} ${t.h},title:^(qs-master)$" && ` +
            `hyprctl dispatch movewindowpixel "exact ${t.x} ${t.y},title:^(qs-master)$"`
        ]);

        masterWindow.isVisible = true;

        let props = newWidget === "wallpaper" ? { "widgetArg": arg } : {};

        if (immediate) {
            widgetStack.replace(Qt.resolvedUrl(t.comp), props, StackView.Immediate);
        } else {
            widgetStack.replace(Qt.resolvedUrl(t.comp), props);
        }
    }
}
