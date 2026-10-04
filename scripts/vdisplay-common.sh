#!/usr/bin/env bash
# Shared helpers for the virtual display scripts.
#
# The EDID and initramfs side of this repo is desktop-agnostic; only the display
# switch differs. Every desktop gets a file under scripts/backends/ implementing
# the backend_* interface, and this file picks one and dispatches:
#
#   de_require_tools        fail early when this desktop's tooling is missing
#   de_has_output           is <connector> known to the compositor
#   de_switch_to_virtual    virtual output on at <res>, physical one off
#   de_switch_to_physical   physical output on, virtual one off
#   de_show_outputs         dump the current configuration
#   de_disable_night_color  pause Night Color / Night Light while streaming
#   de_restore_night_color  restore it afterwards
#
# See docs/DESKTOPS.md for the backend contract and for adding a desktop.

VDISPLAY="${VDISPLAY:-HDMI-A-1}"
PDISPLAY="${PDISPLAY:-DP-3}"
RES="${RES:-2560x1440@120}"
EDID_MODES="${EDID_MODES:-$RES}"
PDISPLAY_RES="${PDISPLAY_RES:-2560x1440@143.99}"
PDISPLAY_SCALE="${PDISPLAY_SCALE:-1}"
VDISPLAY_SCALE="${VDISPLAY_SCALE:-1.5}"
VDISPLAY_BRIGHTNESS="${VDISPLAY_BRIGHTNESS:-100}"
VDISPLAY_DIMMING="${VDISPLAY_DIMMING:-100}"
VDISPLAY_SDR_BRIGHTNESS="${VDISPLAY_SDR_BRIGHTNESS:-400}"
VDISPLAY_HDR="${VDISPLAY_HDR:-0}"
STATE_DIR="${STATE_DIR:-$HOME/.cache/vdisplay}"
# Overridable so the smoke tests can fake a connector layout.
VDISPLAY_SYSFS="${VDISPLAY_SYSFS:-/sys/class/drm}"

export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"

# Sunshine runs the prep commands outside the compositor's own environment, so
# fill in the display variable. Wayland is the tested path, but an X11 session
# that already exports DISPLAY is left alone rather than being handed a
# WAYLAND_DISPLAY it cannot use.
if [[ -z "${WAYLAND_DISPLAY:-}" ]] \
    && [[ "${XDG_SESSION_TYPE:-}" != "x11" || -z "${DISPLAY:-}" ]]; then
    export WAYLAND_DISPLAY="wayland-0"
fi

_self_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BACKEND_DIR="${VDISPLAY_BACKEND_DIR:-${_self_dir}/backends}"
_backend_loaded=""

mkdir -p "$STATE_DIR"

_local_overrides="${HOME}/bin/vdisplay-common.local.sh"
# shellcheck source=/dev/null
[[ -f "$_local_overrides" ]] && source "$_local_overrides"

# ---- backend selection ----------------------------------------------------

# Which desktop are we on? XDG_CURRENT_DESKTOP decides when it is set; when it
# is not (ssh, console), fall back to whichever tool is installed.
de_desktop() {
    case "${XDG_CURRENT_DESKTOP:-}" in
        *KDE*) echo kde ;;
        *GNOME*) echo gnome ;;
        *)
            if command -v kscreen-doctor >/dev/null 2>&1; then
                echo kde
            elif command -v gdctl >/dev/null 2>&1; then
                echo gnome
            else
                echo unknown
            fi
            ;;
    esac
}

# Source scripts/backends/<desktop>.sh. Returns non-zero when this desktop has
# no backend, which is what every de_* entry point reports.
load_backend() {
    local desktop file

    if [[ -n "$_backend_loaded" ]]; then
        return 0
    fi

    desktop="$(de_desktop)"
    [[ "$desktop" != "unknown" ]] || return 1

    file="${BACKEND_DIR}/${desktop}.sh"
    [[ -f "$file" ]] || return 1

    # shellcheck source=/dev/null
    source "$file"
    _backend_loaded="$desktop"
}

# ---- connector state and mode matching (desktop-agnostic) -----------------

connector_status() {
    local connector="$1"
    local path
    for path in "${VDISPLAY_SYSFS}"/card*-"${connector}"/status; do
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

# Pick the EDID mode closest to what the client asked for. The mode list comes
# from the installed EDID (EDID_MODES), so this is the same on every desktop.
pick_stream_resolution() {
    local width="${SUNSHINE_CLIENT_WIDTH:-}"
    local height="${SUNSHINE_CLIENT_HEIGHT:-}"
    local fps="${SUNSHINE_CLIENT_FPS:-120}"

    if [[ -z "$width" || -z "$height" ]]; then
        echo "$RES"
        return
    fi

    local requested="${width}x${height}@${fps}"
    local mode best="" best_score=-1
    local req_w="$width" req_h="$height"
    local mode_w mode_h mode_fps aspect_req aspect_mode score

    IFS=',' read -r -a _edid_modes <<<"$EDID_MODES"
    for mode in "${_edid_modes[@]}"; do
        mode="${mode// /}"
        [[ -n "$mode" ]] || continue
        if [[ "$mode" == "$requested" ]]; then
            echo "$requested"
            return
        fi
    done

    aspect_req="$(awk "BEGIN { printf \"%.6f\", ${req_w}/${req_h} }")"
    for mode in "${_edid_modes[@]}"; do
        mode="${mode// /}"
        [[ "$mode" =~ ^([0-9]+)x([0-9]+)@([0-9.]+)$ ]] || continue
        mode_w="${BASH_REMATCH[1]}"
        mode_h="${BASH_REMATCH[2]}"
        mode_fps="${BASH_REMATCH[3]}"

        if [[ "$mode_w" == "$req_w" && "$mode_h" == "$req_h" ]]; then
            score=$((1000000000 - ${mode_fps%.*} * 1000))
        else
            aspect_mode="$(awk "BEGIN { printf \"%.6f\", ${mode_w}/${mode_h} }")"
            if [[ "$aspect_mode" != "$aspect_req" ]]; then
                continue
            fi
            score=$((1000000 - (mode_w - req_w) * (mode_w - req_w) - (mode_h - req_h) * (mode_h - req_h)))
        fi

        if ((score > best_score)); then
            best_score=$score
            best="$mode"
        fi
    done

    if [[ -n "$best" ]]; then
        echo "$best"
        return
    fi

    echo "$RES"
}

# ---- dispatch -------------------------------------------------------------

de_require_tools() {
    if ! load_backend; then
        echo "No display backend for this desktop: this system has neither a KDE Plasma nor a GNOME session." >&2
        echo "Other desktops need their own backend — see docs/DESKTOPS.md." >&2
        return 1
    fi

    backend_require_tools
}

de_has_output() {
    load_backend || return 1
    backend_has_output "$@"
}

de_switch_to_virtual() {
    load_backend || return 1
    backend_switch_to_virtual "$@"
}

de_switch_to_physical() {
    load_backend || return 1
    backend_switch_to_physical
}

de_show_outputs() {
    load_backend || return 1
    backend_show_outputs
}

de_disable_night_color() {
    load_backend || return 1
    backend_disable_night_color
}

de_restore_night_color() {
    load_backend || return 1
    backend_restore_night_color
}
