#!/usr/bin/env bash

# ─────────────────────────────────────────────
# workspaces.sh
# Streams workspace state as JSON to /tmp/qs_workspaces.json
# TopBar.qml reads this every 100ms to update workspace dots
# Uses socat to listen to Hyprland socket for instant updates
# ─────────────────────────────────────────────

# Total number of workspaces to show (1-10)
SEQ_END=10

print_workspaces() {
    local spaces=$(hyprctl workspaces -j)
    local active=$(hyprctl activeworkspace -j | jq '.id')

    echo "$spaces" | jq --unbuffered --argjson a "$active" --arg end "$SEQ_END" -c '
        (map( { (.id|tostring): . } ) | add) as $s
        |
        [range(1; ($end|tonumber) + 1)] | map(
            . as $i |
            (if $i == $a then "active"
             elif ($s[$i|tostring] != null and $s[$i|tostring].windows > 0) then "occupied"
             else "empty" end) as $state |
            (if $s[$i|tostring] != null then $s[$i|tostring].lastwindowtitle else "Empty" end) as $win |
            {
                id: $i,
                state: $state,
                tooltip: $win
            }
        )
    '
}

# Print initial state on launch
print_workspaces

# Listen to Hyprland socket for real-time updates
# Triggers on: workspace switch, monitor focus, window open/close/move, workspace destroy
socat -u UNIX-CONNECT:$XDG_RUNTIME_DIR/hypr/$HYPRLAND_INSTANCE_SIGNATURE/.socket2.sock - | while read -r line; do
    case "$line" in
        workspace*|focusedmon*|activewindow*|createwindow*|closewindow*|movewindow*|destroyworkspace*)
            print_workspaces
            ;;
    esac
done
