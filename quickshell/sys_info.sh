#!/usr/bin/env bash

# ─────────────────────────────────────────────
# sys_info.sh
# Called by TopBar.qml pollers to get system info
# Removed: bluetooth, battery, brightness, kb layout, cpu, memory, uptime
# Added: ethernet detection
# Fixed: volume uses wpctl (wireplumber/pipewire native)
# ─────────────────────────────────────────────

## ─── CONNECTION TYPE ─────────────────────────
# Checks ethernet first, then WiFi
# Returns: "ethernet", "wifi", or "none"
get_connection_type() {
    # Check for active ethernet connection
    local eth=$(nmcli -t -f TYPE,STATE dev 2>/dev/null | grep '^ethernet:connected' | head -n1)
    if [ -n "$eth" ]; then
        echo "ethernet"
        return
    fi

    # Check for active WiFi connection
    local wifi=$(nmcli -t -f TYPE,STATE dev 2>/dev/null | grep '^wifi:connected' | head -n1)
    if [ -n "$wifi" ]; then
        echo "wifi"
        return
    fi

    echo "none"
}

## ─── WIFI / ETHERNET STATUS ──────────────────
# Returns "enabled" if any network connection is active
get_wifi_status() {
    local conn_type=$(get_connection_type)
    if [ "$conn_type" = "ethernet" ] || [ "$conn_type" = "wifi" ]; then
        echo "enabled"
    else
        echo "disabled"
    fi
}

# Returns SSID if on WiFi, "Ethernet" if on ethernet, empty if disconnected
get_wifi_ssid() {
    local conn_type=$(get_connection_type)

    if [ "$conn_type" = "ethernet" ]; then
        echo "Ethernet"
        return
    fi

    if [ "$conn_type" = "wifi" ]; then
        local ssid=$(nmcli -t -f ACTIVE,SSID dev wifi 2>/dev/null | grep '^yes' | cut -d: -f2)
        echo "${ssid:-}"
        return
    fi

    echo ""
}

# Returns signal strength (0-100) for active WiFi, 100 for ethernet
get_wifi_strength() {
    local conn_type=$(get_connection_type)

    if [ "$conn_type" = "ethernet" ]; then
        echo "100"
        return
    fi

    local signal=$(nmcli -f IN-USE,SIGNAL dev wifi 2>/dev/null | grep '^\*' | awk '{print $2}')
    echo "${signal:-0}"
}

# Returns appropriate icon based on connection type and signal strength
get_wifi_icon() {
    local conn_type=$(get_connection_type)

    if [ "$conn_type" = "ethernet" ]; then
        echo "󰈀"   # Ethernet icon
        return
    fi

    if [ "$conn_type" = "wifi" ]; then
        local signal=$(get_wifi_strength)
        if [ "$signal" -ge 75 ]; then
            echo "󰤨"   # Full signal
        elif [ "$signal" -ge 50 ]; then
            echo "󰤥"   # Good signal
        elif [ "$signal" -ge 25 ]; then
            echo "󰤢"   # Weak signal
        else
            echo "󰤟"   # Very weak
        fi
        return
    fi

    echo "󰤮"   # Disconnected
}

toggle_wifi() {
    local conn_type=$(get_connection_type)

    # Don't toggle if on ethernet — would be confusing
    if [ "$conn_type" = "ethernet" ]; then
        notify-send -u low "Network" "Connected via Ethernet — WiFi toggle skipped"
        return
    fi

    if nmcli -t -f WIFI g 2>/dev/null | grep -q "enabled"; then
        nmcli radio wifi off
        notify-send -u low -i network-wireless-disabled "WiFi" "Disabled"
    else
        nmcli radio wifi on
        notify-send -u low -i network-wireless-enabled "WiFi" "Enabled"
    fi
}

## ─── VOLUME (wpctl — pipewire native) ────────
get_volume() {
    # wpctl outputs something like: "Volume: 0.75"
    # We convert to percentage (0-100)
    local vol=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null | awk '{print $2}')
    if [ -n "$vol" ]; then
        # Multiply by 100 and round to integer
        echo "$vol" | awk '{printf "%d", $1 * 100}'
    else
        echo "0"
    fi
}

is_muted() {
    local output=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null)
    if echo "$output" | grep -q "\[MUTED\]"; then
        echo "true"
    else
        echo "false"
    fi
}

toggle_mute() {
    wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle 2>/dev/null
}

get_volume_icon() {
    local vol=$(get_volume | tr -cd '0-9')
    local muted=$(is_muted)

    [ -z "$vol" ] && vol=0

    if [ "$muted" = "true" ]; then
        echo "󰝟"   # Muted
    elif [ "$vol" -ge 70 ]; then
        echo "󰕾"   # High
    elif [ "$vol" -ge 30 ]; then
        echo "󰖀"   # Medium
    elif [ "$vol" -gt 0 ]; then
        echo "󰕿"   # Low
    else
        echo "󰝟"   # Zero
    fi
}

## ─── EXECUTION ────────────────────────────────
cmd="$1"
case $cmd in
    --wifi-status)   get_wifi_status ;;
    --wifi-ssid)     get_wifi_ssid ;;
    --wifi-icon)     get_wifi_icon ;;
    --wifi-strength) get_wifi_strength ;;
    --wifi-toggle)   toggle_wifi ;;

    --volume)        get_volume ;;
    --volume-icon)   get_volume_icon ;;
    --is-muted)      is_muted ;;
    --toggle-mute)   toggle_mute ;;

    *) echo "Unknown command: $cmd" ;;
esac
