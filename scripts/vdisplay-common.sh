#!/usr/bin/env bash
# Shared helpers for virtual display scripts on KDE Plasma Wayland.

VDISPLAY="${VDISPLAY:-HDMI-A-1}"
RES="${RES:-2560x1600@120}"

export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"

kscreen() {
    kscreen-doctor "$@"
}

connector_status() {
    local path
    for path in /sys/class/drm/card*-"${VDISPLAY}"/status; do
        [[ -f "$path" ]] || continue
        cat "$path"
        return 0
    done
    return 1
}

connector_present() {
    [[ "$(connector_status 2>/dev/null || true)" == "connected" ]]
}

kscreen_has_output() {
    kscreen -o 2>/dev/null | grep -qE "Output:.* ${VDISPLAY} "
}
