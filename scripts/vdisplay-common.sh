#!/usr/bin/env bash
# Shared helpers for virtual display scripts on KDE Plasma Wayland.

VDISPLAY="${VDISPLAY:-HDMI-A-1}"
PDISPLAY="${PDISPLAY:-DP-3}"
RES="${RES:-2560x1600@120}"
PDISPLAY_RES="${PDISPLAY_RES:-2560x1440@143.99}"

export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"

kscreen() {
    kscreen-doctor "$@"
}

connector_status() {
    local connector="$1"
    local path
    for path in /sys/class/drm/card*-"${connector}"/status; do
        [[ -f "$path" ]] || continue
        cat "$path"
        return 0
    done
    return 1
}

connector_present() {
    local connector="${1:-$VDISPLAY}"
    [[ "$(connector_status "$connector" 2>/dev/null || true)" == "connected" ]]
}

kscreen_has_output() {
    local connector="${1:-$VDISPLAY}"
    kscreen -o 2>/dev/null | grep -qE "Output:.* ${connector} "
}

kscreen_output_enabled() {
    local connector="$1"
    kscreen -o 2>/dev/null | awk -v name="$connector" '
        $0 ~ "^Output:.* " name " " { found=1; next }
        found && /disabled/ { exit 1 }
        found && /enabled/ { exit 0 }
        found && /^Output:/ { exit 1 }
    '
}

disable_output() {
    local connector="$1"
    if kscreen_has_output "$connector" && kscreen_output_enabled "$connector"; then
        kscreen "output.${connector}.disable"
        echo "Disabled $connector"
    fi
}

enable_output() {
    local connector="$1"
    local res="$2"
    local x="$3"
    local y="$4"
    local priority="$5"

    kscreen "output.${connector}.enable"
    kscreen "output.${connector}.mode.${res}"
    kscreen "output.${connector}.position.${x},${y}"
    kscreen "output.${connector}.priority.${priority}"
    echo "Enabled $connector at ${res} (${x},${y})"
}

show_outputs() {
    echo "Current outputs:"
    kscreen -o | grep -E 'Output:|enabled|disabled|connected|Geometry|Modes:'
}
