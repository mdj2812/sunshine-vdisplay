#!/usr/bin/env bash
# GNOME backend: drives gdctl.
#
# Sourced by vdisplay-common.sh through the backend_* interface, never executed
# on its own. Written from mutter's gdctl manual page: `set` is declarative and
# every monitor that is *not* mentioned is turned off, so a single call switches
# the whole monitor set. Not verified on GNOME hardware yet — see docs/DESKTOPS.md.

gnome_has_output() {
    # `gdctl show` lists configured monitors only — a monitor that is switched
    # off is simply absent — so presence has to come from the kernel instead.
    connector_present "${1:-$VDISPLAY}"
}

# ---- backend interface ----------------------------------------------------

backend_require_tools() {
    if command -v gdctl >/dev/null 2>&1; then
        return 0
    fi

    echo "gdctl not found: the GNOME backend needs GNOME Shell (mutter)." >&2
    return 1
}

backend_has_output() {
    gnome_has_output "$@"
}

backend_switch_to_virtual() {
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

backend_switch_to_physical() {
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

backend_show_outputs() {
    echo "Current outputs:"
    gdctl show 2>/dev/null || true
}

# GNOME Night Light is not managed here: switching it needs gsettings and a
# session restart to take effect, so leave the user's setting alone.
backend_disable_night_color() { :; }
backend_restore_night_color() { :; }
