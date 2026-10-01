#!/usr/bin/env bash
# Shared helpers for the virtual display scripts.
#
# The EDID and initramfs side of this repo is desktop-agnostic; only the display
# switch differs, so each desktop gets a backend behind the de_* entry points:
#
#   de_require_tools        fail early when this desktop's tooling is missing
#   de_has_output           is <connector> known to the compositor
#   de_switch_to_virtual    virtual output on at <res>, physical one off
#   de_switch_to_physical   physical output on, virtual one off
#   de_show_outputs         dump the current configuration
#   de_disable_night_color  pause Night Color / Night Light while streaming
#   de_restore_night_color  restore it afterwards
#
# KDE Plasma Wayland (kscreen-doctor) and GNOME (gdctl) are implemented. See
# docs/DESKTOPS.md for the contract and what a new backend has to provide.

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

export WAYLAND_DISPLAY="${WAYLAND_DISPLAY:-wayland-0}"
export XDG_RUNTIME_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
export DBUS_SESSION_BUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=${XDG_RUNTIME_DIR}/bus}"

mkdir -p "$STATE_DIR"

_local_overrides="${HOME}/bin/vdisplay-common.local.sh"
# shellcheck source=/dev/null
[[ -f "$_local_overrides" ]] && source "$_local_overrides"

# ---- backend selection ----------------------------------------------------

de_desktop() {
    case "${XDG_CURRENT_DESKTOP:-}" in
        *KDE*) echo kde ;;
        *GNOME*) echo gnome ;;
        *)
            # Unset (ssh, console) or an unusual name: go by the tool present.
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

de_require_tools() {
    case "$(de_desktop)" in
        kde)
            if command -v kscreen-doctor >/dev/null 2>&1; then
                return 0
            fi
            echo "kscreen-doctor not found: the KDE backend needs KDE Plasma Wayland." >&2
            ;;
        gnome)
            if command -v gdctl >/dev/null 2>&1; then
                return 0
            fi
            echo "gdctl not found: the GNOME backend needs GNOME Shell (mutter)." >&2
            ;;
        *)
            echo "No display backend for this desktop: it needs KDE Plasma Wayland (kscreen-doctor) or GNOME (gdctl)." >&2
            ;;
    esac

    echo "Other desktops need their own backend — see docs/DESKTOPS.md." >&2
    return 1
}

# ---- connector state (desktop-agnostic) -----------------------------------

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

# ---- KDE Plasma Wayland backend (kscreen-doctor) --------------------------

kscreen() {
    kscreen-doctor "$@"
}

# kscreen-doctor colours its output even when it is piped, and the escape codes
# break every anchored match below, so strip them first.
kscreen_output() {
    kscreen -o 2>/dev/null | sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g'
}

kde_has_output() {
    local connector="${1:-$VDISPLAY}"
    kscreen_output | grep -qE "^Output:.* ${connector} "
}

kde_output_enabled() {
    local connector="$1"
    kscreen_output | awk -v name="$connector" '
        $0 ~ "^Output:.* " name " " { found=1; next }
        found && /disabled/ { exit 1 }
        found && /enabled/ { exit 0 }
        found && /^Output:/ { exit 1 }
    '
}

kde_enable_output() {
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

kde_disable_output() {
    local connector="$1"
    if kde_has_output "$connector" && kde_output_enabled "$connector"; then
        kscreen "output.${connector}.disable"
        echo "Disabled $connector"
    fi
}

# Is HDR currently on for <connector> according to KWin?
kde_hdr_enabled() {
    local connector="${1:-$VDISPLAY}"

    kscreen_output | awk -v name="$connector" '
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
kde_set_hdr() {
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

kde_tune_output() {
    local connector="${1:-$VDISPLAY}"
    local -a args=(
        "output.${connector}.scale.${VDISPLAY_SCALE}"
        "output.${connector}.brightness.${VDISPLAY_BRIGHTNESS}"
        "output.${connector}.dimming.${VDISPLAY_DIMMING}"
    )

    if kde_hdr_enabled "$connector"; then
        args+=("output.${connector}.sdr-brightness.${VDISPLAY_SDR_BRIGHTNESS}")
    fi

    kscreen "${args[@]}"
    echo "Tuned $connector brightness (scale=${VDISPLAY_SCALE}, brightness=${VDISPLAY_BRIGHTNESS}%, dimming=${VDISPLAY_DIMMING}%)"
}

kde_disable_night_color() {
    kreadconfig6 --file kwinrc --group NightColor --key Active 2>/dev/null >"${STATE_DIR}/night-color" \
        || echo false >"${STATE_DIR}/night-color"

    qdbus org.kde.KWin /ColorCorrect org.kde.kwin.ColorCorrect.setActive false 2>/dev/null \
        || kwriteconfig6 --file kwinrc --group NightColor --key Active false
}

kde_restore_night_color() {
    if [[ ! -f "${STATE_DIR}/night-color" ]]; then
        return
    fi

    if [[ "$(cat "${STATE_DIR}/night-color")" == "true" ]]; then
        qdbus org.kde.KWin /ColorCorrect org.kde.kwin.ColorCorrect.setActive true 2>/dev/null \
            || kwriteconfig6 --file kwinrc --group NightColor --key Active true
    fi

    rm -f "${STATE_DIR}/night-color"
}

kde_switch_to_virtual() {
    local res="$1"

    kde_enable_output "$VDISPLAY" "$res" 0 0 1
    if [[ "$VDISPLAY_HDR" == "1" ]]; then
        kde_set_hdr "$VDISPLAY" enable || true
    fi
    kde_tune_output "$VDISPLAY"
    kde_disable_output "$PDISPLAY"
}

kde_switch_to_physical() {
    # HDR is a per-output KWin setting, so turn it back off before the virtual
    # output is disabled, otherwise the next session would inherit it.
    if [[ "$VDISPLAY_HDR" == "1" ]] && kde_has_output "$VDISPLAY" && kde_hdr_enabled "$VDISPLAY"; then
        kde_set_hdr "$VDISPLAY" disable || true
    fi

    if kde_has_output "$PDISPLAY"; then
        echo "Restoring physical display..."
        kde_enable_output "$PDISPLAY" "$PDISPLAY_RES" 0 0 1
    else
        echo "Physical display $PDISPLAY not found in KDE."
    fi

    if kde_has_output "$VDISPLAY"; then
        kde_disable_output "$VDISPLAY"
    elif connector_present "$VDISPLAY"; then
        echo "$VDISPLAY is connected in DRM but not managed by KDE."
    else
        echo "$VDISPLAY not present"
    fi
}

kde_show_outputs() {
    echo "Current outputs:"
    kscreen_output | grep -E 'Output:|enabled|disabled|connected|Geometry|Scale|Brightness|HDR|Modes:'
}

# ---- GNOME backend (gdctl) ------------------------------------------------
#
# Written from mutter's gdctl manual page: `set` is declarative and every
# monitor that is *not* mentioned is turned off, so a single call switches the
# whole monitor set. Not verified on GNOME hardware yet — see docs/GNOME.md.

# `gdctl show` lists configured monitors only — a monitor that is switched off
# is simply absent — so presence has to come from the kernel instead.
gnome_has_output() {
    connector_present "${1:-$VDISPLAY}"
}

gnome_switch_to_virtual() {
    local res="$1"
    local -a args=(
        --logical-monitor
        --primary
        --monitor "$VDISPLAY"
        --mode "$res"
        --x 0
        --y 0
        --scale "$VDISPLAY_SCALE"
    )

    if [[ "$VDISPLAY_HDR" == "1" ]]; then
        # bt2100 is mutter's HDR (PQ / BT.2100) color mode.
        args+=(--color-mode bt2100)
    fi

    gdctl set "${args[@]}"
    echo "Enabled $VDISPLAY at ${res} (HDR: ${VDISPLAY_HDR})"
}

gnome_switch_to_physical() {
    if ! gnome_has_output "$PDISPLAY"; then
        echo "Physical display $PDISPLAY not found in GNOME."
        return 0
    fi

    # Mentioning only the physical monitor turns the virtual one off. Scale and
    # rotation are set explicitly because a `gdctl set` applies defaults for
    # anything it is not told about.
    gdctl set \
        --logical-monitor \
        --primary \
        --monitor "$PDISPLAY" \
        --mode "$PDISPLAY_RES" \
        --x 0 \
        --y 0 \
        --scale "$PDISPLAY_SCALE"

    echo "Enabled $PDISPLAY at ${PDISPLAY_RES}"
}

gnome_show_outputs() {
    echo "Current outputs:"
    gdctl show 2>/dev/null || true
}

# GNOME Night Light is not managed here: switching it needs gsettings and a
# session restart to take effect, so leave the user's setting alone.
gnome_disable_night_color() { :; }
gnome_restore_night_color() { :; }

# ---- dispatch -------------------------------------------------------------

de_has_output() {
    case "$(de_desktop)" in
        kde) kde_has_output "${1:-$VDISPLAY}" ;;
        gnome) gnome_has_output "${1:-$VDISPLAY}" ;;
        *) return 1 ;;
    esac
}

de_switch_to_virtual() {
    case "$(de_desktop)" in
        kde) kde_switch_to_virtual "$1" ;;
        gnome) gnome_switch_to_virtual "$1" ;;
        *) return 1 ;;
    esac
}

de_switch_to_physical() {
    case "$(de_desktop)" in
        kde) kde_switch_to_physical ;;
        gnome) gnome_switch_to_physical ;;
        *) return 1 ;;
    esac
}

de_show_outputs() {
    case "$(de_desktop)" in
        kde) kde_show_outputs ;;
        gnome) gnome_show_outputs ;;
        *) return 1 ;;
    esac
}

de_disable_night_color() {
    case "$(de_desktop)" in
        kde) kde_disable_night_color ;;
        gnome) gnome_disable_night_color ;;
        *) return 1 ;;
    esac
}

de_restore_night_color() {
    case "$(de_desktop)" in
        kde) kde_restore_night_color ;;
        gnome) gnome_restore_night_color ;;
        *) return 1 ;;
    esac
}
