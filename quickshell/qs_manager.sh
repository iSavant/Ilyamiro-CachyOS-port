#!/usr/bin/env bash

# ─────────────────────────────────────────────
# PATHS
# ─────────────────────────────────────────────
QS_DIR="$HOME/.config/quickshell"
SRC_DIR="$HOME/Pictures/Wallpapers"
THUMB_DIR="$HOME/.cache/wallpaper_picker/thumbs"

IPC_FILE="/tmp/qs_widget_state"
ACTION="$1"
TARGET="$2"

# ─────────────────────────────────────────────
# WALLPAPER THUMBNAIL PREP
# Generates thumbnails for the wallpaper picker widget
# Uses awww query to detect the currently active wallpaper
# ─────────────────────────────────────────────
handle_wallpaper_prep() {
    mkdir -p "$THUMB_DIR"

    # Generate thumbnails in background — don't block the widget from opening
    (
        # Clean up thumbnails for wallpapers that no longer exist
        for thumb in "$THUMB_DIR"/*; do
            [ -e "$thumb" ] || continue
            filename=$(basename "$thumb")
            if [ ! -f "$SRC_DIR/$filename" ]; then
                rm -f "$thumb"
            fi
        done

        # Generate missing thumbnails (images only — no video support)
        for img in "$SRC_DIR"/*.{jpg,jpeg,png,webp}; do
            [ -e "$img" ] || continue
            filename=$(basename "$img")
            thumb="$THUMB_DIR/$filename"
            if [ ! -f "$thumb" ]; then
                magick "$img" -resize x420 -quality 70 "$thumb"
            fi
        done
    ) &

    # Detect currently active wallpaper via awww query
    TARGET_THUMB=""
    CURRENT_SRC=""

    if command -v awww >/dev/null; then
        CURRENT_SRC=$(awww query 2>/dev/null | grep -o "$SRC_DIR/[^ ]*" | head -n1)
        CURRENT_SRC=$(basename "$CURRENT_SRC")
    fi

    if [ -n "$CURRENT_SRC" ]; then
        TARGET_THUMB="$CURRENT_SRC"
    fi

    export WALLPAPER_THUMB="$TARGET_THUMB"
}

# ─────────────────────────────────────────────
# NETWORK PREP
# Rescans WiFi networks before opening network widget
# Bluetooth removed — not in stack
# ─────────────────────────────────────────────
handle_network_prep() {
    (nmcli device wifi rescan) &
}

# ─────────────────────────────────────────────
# SHUTDOWN MAIN.QML WHEN NO WIDGET IS OPEN
# Kills Main.qml process if qs-master window is hidden
# Keeps setup lightweight — Main.qml only lives while a widget is open
# ─────────────────────────────────────────────
shutdown_if_idle() {
    sleep 0.5  # wait for IPC to process the close
    ACTIVE_WIDGET=$(cat /tmp/qs_active_widget 2>/dev/null)
    if [[ "$ACTIVE_WIDGET" == "hidden" || -z "$ACTIVE_WIDGET" ]]; then
        QS_PID=$(pgrep -f "quickshell.*Main\.qml")
        if [[ -n "$QS_PID" ]]; then
            kill "$QS_PID" 2>/dev/null
        fi
    fi
}

# ─────────────────────────────────────────────
# ZOMBIE WATCHDOG
# Ensures Main.qml and TopBar.qml are running
# Main.qml is launched on demand (not on startup)
# TopBar.qml is always kept alive
# ─────────────────────────────────────────────

# Only launch Main.qml if we're actually opening a widget
# (not for close actions or workspace switches)
if [[ "$ACTION" == "open" || "$ACTION" == "toggle" ]]; then
    QS_PID=$(pgrep -f "quickshell.*Main\.qml")
    WIN_EXISTS=$(hyprctl clients -j | grep "qs-master")

    if [[ -z "$QS_PID" ]] || [[ -z "$WIN_EXISTS" ]]; then
        if [[ -n "$QS_PID" ]]; then
            kill -9 "$QS_PID" 2>/dev/null
        fi
        quickshell -p "$QS_DIR/Main.qml" >/dev/null 2>&1 &
        disown
        sleep 0.6
    fi
fi

# Always keep TopBar alive
BAR_PID=$(pgrep -f "quickshell.*TopBar\.qml")
if [[ -z "$BAR_PID" ]]; then
    quickshell -p "$QS_DIR/TopBar.qml" >/dev/null 2>&1 &
    disown
fi

# ─────────────────────────────────────────────
# CLOSE ACTION
# ─────────────────────────────────────────────
if [[ "$ACTION" == "close" ]]; then
    echo "close" > "$IPC_FILE"
    shutdown_if_idle &
    exit 0
fi

# ─────────────────────────────────────────────
# OPEN / TOGGLE ACTIONS
# ─────────────────────────────────────────────
if [[ "$ACTION" == "open" || "$ACTION" == "toggle" ]]; then

    # ── Network widget ──
    if [[ "$TARGET" == "network" ]]; then
        ACTIVE_WIDGET=$(cat /tmp/qs_active_widget 2>/dev/null)

        if [[ "$ACTION" == "toggle" && "$ACTIVE_WIDGET" == "network" ]]; then
            # Already open — close it
            echo "close" > "$IPC_FILE"
            shutdown_if_idle &
        else
            handle_network_prep
            echo "$TARGET" > "$IPC_FILE"
        fi
        exit 0
    fi

    # ── Wallpaper widget ──
    if [[ "$TARGET" == "wallpaper" ]]; then
        ACTIVE_WIDGET=$(cat /tmp/qs_active_widget 2>/dev/null)

        if [[ "$ACTION" == "toggle" && "$ACTIVE_WIDGET" == "wallpaper" ]]; then
            echo "close" > "$IPC_FILE"
            shutdown_if_idle &
        else
            handle_wallpaper_prep
            echo "$TARGET:$WALLPAPER_THUMB" > "$IPC_FILE"
        fi
        exit 0
    fi

    # ── Music widget ──
    if [[ "$TARGET" == "music" ]]; then
        ACTIVE_WIDGET=$(cat /tmp/qs_active_widget 2>/dev/null)

        if [[ "$ACTION" == "toggle" && "$ACTIVE_WIDGET" == "music" ]]; then
            echo "close" > "$IPC_FILE"
            shutdown_if_idle &
        else
            echo "$TARGET" > "$IPC_FILE"
        fi
        exit 0
    fi

fi
