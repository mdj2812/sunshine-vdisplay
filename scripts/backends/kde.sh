#!/usr/bin/env bash
# KDE Plasma backend: drives kscreen-doctor.
#
# Sourced by vdisplay-common.sh through the backend_* interface, never executed
# on its own. kscreen-doctor talks to KScreen, which drives KWin on Wayland and
# RandR on X11, so this backend is not Wayland-only — but only Wayland is tested
# (see docs/DESKTOPS.md).

kde_kscreen() {
    kscreen-doctor "$@"
}

# kscreen-doctor colours its output even when it is piped, and the escape codes
# break every anchored match below, so strip them first.
kde_output() {
    kde_kscreen -o 2>/dev/null | sed -E 's/\x1b\[[0-9;]*[A-Za-z]//g'
}

kde_output_enabled() {
    local connector="$1"

    kde_output | awk -v name="$connector" '
        $0 ~ "^Output:.* " name " " { found=1; next }
        found && /disabled/ { exit 1 }
        found && /enabled/ { exit 0 }
        found && /^Output:/ { exit 1 }
    '
}

kde_has_output() {
    local connector="${1:-$VDISPLAY}"
    kde_output | grep -qE "^Output:.* ${connector} "
}

# Is HDR currently on for <connector> according to KWin?
kde_hdr_enabled() {
    local connector="${1:-$VDISPLAY}"

    kde_output | awk -v name="$connector" '
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

    if ! kde_kscreen "output.${connector}.hdr.${mode}" 2>/dev/null; then
        echo "warning: KWin did not accept HDR ${mode} on $connector; continuing in SDR" >&2
        return 1
    fi

    # Wide color gamut is paired with HDR on the physical output, but not every
    # connector exposes it — a refusal here should not fail the stream.
    kde_kscreen "output.${connector}.wcg.${mode}" 2>/dev/null \
        || echo "warning: could not switch wide color gamut ${mode} on $connector" >&2

    echo "HDR ${mode}d on $connector"
}

kde_enable_output() {
    local connector="$1"
    local res="$2"
    local x="$3"
    local y="$4"
    local priority="$5"

    kde_kscreen "output.${connector}.enable"
    kde_kscreen "output.${connector}.mode.${res}"
    kde_kscreen "output.${connector}.position.${x},${y}"
    kde_kscreen "output.${connector}.priority.${priority}"
    echo "Enabled $connector at ${res} (${x},${y})"
}

kde_disable_output() {
    local connector="$1"

    if kde_has_output "$connector" && kde_output_enabled "$connector"; then
        kde_kscreen "output.${connector}.disable"
        echo "Disabled $connector"
    fi
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

    kde_kscreen "${args[@]}"
    echo "Tuned $connector brightness (scale=${VDISPLAY_SCALE}, brightness=${VDISPLAY_BRIGHTNESS}%, dimming=${VDISPLAY_DIMMING}%)"
}

# ---- backend interface ----------------------------------------------------

backend_require_tools() {
    if command -v kscreen-doctor >/dev/null 2>&1; then
        return 0
    fi

    echo "kscreen-doctor not found: the KDE backend needs KDE Plasma." >&2
    return 1
}

backend_has_output() {
    kde_has_output "$@"
}

backend_switch_to_virtual() {
    local res="$1"

    kde_enable_output "$VDISPLAY" "$res" 0 0 1
    if [[ "$VDISPLAY_HDR" == "1" ]]; then
        kde_set_hdr "$VDISPLAY" enable || true
    fi
    kde_tune_output "$VDISPLAY"
    kde_disable_output "$PDISPLAY"
}

backend_switch_to_physical() {
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

backend_show_outputs() {
    echo "Current outputs:"
    kde_output | grep -E 'Output:|enabled|disabled|connected|Geometry|Scale|Brightness|HDR|Modes:'
}

backend_disable_night_color() {
    kreadconfig6 --file kwinrc --group NightColor --key Active 2>/dev/null >"${STATE_DIR}/night-color" \
        || echo false >"${STATE_DIR}/night-color"

    qdbus org.kde.KWin /ColorCorrect org.kde.kwin.ColorCorrect.setActive false 2>/dev/null \
        || kwriteconfig6 --file kwinrc --group NightColor --key Active false
}

backend_restore_night_color() {
    if [[ ! -f "${STATE_DIR}/night-color" ]]; then
        return
    fi

    if [[ "$(cat "${STATE_DIR}/night-color")" == "true" ]]; then
        qdbus org.kde.KWin /ColorCorrect org.kde.kwin.ColorCorrect.setActive true 2>/dev/null \
            || kwriteconfig6 --file kwinrc --group NightColor --key Active true
    fi

    rm -f "${STATE_DIR}/night-color"
}
