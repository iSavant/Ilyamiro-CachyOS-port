#!/usr/bin/env bash

# ─────────────────────────────────────────────
# screenshot.sh
# Region screenshot using slurp + grim
# --edit flag opens in satty for annotation
# Saves to ~/Pictures/Screenshots
# ─────────────────────────────────────────────

SAVE_DIR="$HOME/Pictures/Screenshots"
mkdir -p "$SAVE_DIR"

time=$(date +'%Y-%m-%d-%H%M%S')
FILENAME="$SAVE_DIR/Screenshot_$time.png"

# Slurp selection overlay styling
# -b background color, -c border color, -s selection fill, -w border width
SLURP_ARGS="-b 1B1F2844 -c E06B74ff -s C778DD0D -w 2"

send_notification() {
    if [ -s "$FILENAME" ]; then
        notify-send -a "Screenshot" \
                    -i "$FILENAME" \
                    "Screenshot Saved" \
                    "File: Screenshot_$time.png"
    fi
}

# Parse flags
EDIT_MODE=false
for arg in "$@"; do
    case $arg in
        --edit) EDIT_MODE=true ;;
    esac
done

# Select region — exits silently if user presses Escape
GEOMETRY=$(slurp $SLURP_ARGS)
if [ -z "$GEOMETRY" ]; then
    exit 0
fi

if [ "$EDIT_MODE" = true ]; then
    # Capture → open in satty for annotation → save + copy
    grim -g "$GEOMETRY" - | GSK_RENDERER=gl satty \
        --filename - \
        --output-filename "$FILENAME" \
        --init-tool brush \
        --copy-command wl-copy
    send_notification
else
    # Capture → save to file → copy to clipboard
    grim -g "$GEOMETRY" - | tee "$FILENAME" | wl-copy
    send_notification
fi
