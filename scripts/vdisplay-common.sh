#!/usr/bin/env bash
# Shared helpers for virtual display scripts on KDE Plasma Wayland.

VDISPLAY="${VDISPLAY:-HDMI-A-1}"
PDISPLAY="${PDISPLAY:-DP-3}"
RES="${RES:-2560x1440@120}"
EDID_MODES="${EDID_MODES:-$RES}"
PDISPLAY_RES="${PDISPLAY_RES:-2560x1440@143.99}"
VDISPLAY_SCALE="${VDISPLAY_SCALE:-1.5}"
VDISPLAY_BRIGHTNESS="${VDISPLAY_BRIGHTNESS:-100}"
VDISPLAY_DIMMING="${VDISPLAY_DIMMING:-100}"
VDISPLAY_SDR_BRIGHTNESS="${VDISPLAY_SDR_BRIGHTNESS:-400}"
VDISPLAY_HDR="${VDISPLAY_HDR:-0}"
STATE_DIR="${STATE_DIR:-$HOME/.cache/vdisplay}"

export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"

mkdir -p "$STATE_DIR"

_local_overrides="${HOME}/bin/vdisplay-common.local.sh"
# shellcheck source=/dev/null
[[ -f "$_local_overrides" ]] && source "$_local_overrides"

kscreen() {
    kscreen-doctor "$@"
}

# The switching helpers drive kscreen-doctor, which exists only on KDE Plasma
# Wayland. Other desktops need their own swap step — see docs/DESKTOPS.md.
require_kscreen() {
    command -v kscreen-doctor >/dev/null 2>&1 && return 0

    echo "kscreen-doctor not found: display switching needs KDE Plasma Wayland." >&2
    echo "Other desktops need their own swap step — see docs/DESKTOPS.md." >&2
    return 1
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

# Is HDR currently on for <connector> according to KWin?
output_hdr_enabled() {
    local connector="${1:-$VDISPLAY}"

    kscreen -o 2>/dev/null | awk -v name="$connector" '
        $0 ~ "^Output:.* " name " " { found=1; next }
        found && /HDR:.*enabled/ { hdr=1; exit }
        found && /^Output:/ { exit }
        END { exit(hdr ? 0 : 1) }
    '
}

# Turn HDR and wide color gamut on or off for <connector>.
#
# KWin accepts the toggle for force-enabled virtual outputs and reports the HDR
# color profile as coming from the injected EDID. Whether an active virtual
# output really drives HDR is still unverified — see docs/HDR.md.
set_output_hdr() {
    local connector="$1"
    local mode="$2"

    if ! kscreen "output.${connector}.hdr.${mode}" 2>/dev/null; then
        echo "warning: KWin did not accept HDR ${mode} on $connector; continuing in SDR" >&2
        return 1
    fi

    # Wide color gamut is paired with HDR on the physical output, but not every
    # connector exposes it — a refusal here should not fail the stream.
    kscreen "output.${connector}.wcg.${mode}" 2>/dev/null \
        || echo "warning: could not switch wide color gamut ${mode} on $connector" >&2

    echo "HDR ${mode}d on $connector"
}

tune_virtual_display() {
    local connector="$1"
    local -a args=(
        "output.${connector}.scale.${VDISPLAY_SCALE}"
        "output.${connector}.brightness.${VDISPLAY_BRIGHTNESS}"
        "output.${connector}.dimming.${VDISPLAY_DIMMING}"
    )

    if output_hdr_enabled "$connector"; then
        args+=("output.${connector}.sdr-brightness.${VDISPLAY_SDR_BRIGHTNESS}")
    fi

    kscreen "${args[@]}"
    echo "Tuned $connector brightness (scale=${VDISPLAY_SCALE}, brightness=${VDISPLAY_BRIGHTNESS}%, dimming=${VDISPLAY_DIMMING}%)"
}

save_night_color_state() {
    kreadconfig6 --file kwinrc --group NightColor --key Active 2>/dev/null >"${STATE_DIR}/night-color" || echo false >"${STATE_DIR}/night-color"
}

disable_night_color() {
    save_night_color_state
    qdbus org.kde.KWin /ColorCorrect org.kde.kwin.ColorCorrect.setActive false 2>/dev/null \
        || kwriteconfig6 --file kwinrc --group NightColor --key Active false
}

restore_night_color() {
    if [[ ! -f "${STATE_DIR}/night-color" ]]; then
        return
    fi

    if [[ "$(cat "${STATE_DIR}/night-color")" == "true" ]]; then
        qdbus org.kde.KWin /ColorCorrect org.kde.kwin.ColorCorrect.setActive true 2>/dev/null \
            || kwriteconfig6 --file kwinrc --group NightColor --key Active true
    fi

    rm -f "${STATE_DIR}/night-color"
}

show_outputs() {
    echo "Current outputs:"
    kscreen -o | grep -E 'Output:|enabled|disabled|connected|Geometry|Scale|Brightness|HDR|Modes:'
}
