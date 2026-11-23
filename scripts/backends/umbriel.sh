#!/usr/bin/env bash
# Umbriel backend: drives the compositor's runtime output controls.
#
# Umbriel can add and remove an output from the desktop with `msg
# output-enable/disable`. Runtime config overrides provide the mode, position,
# scale, and HDR settings without modifying the user's Umbriel configuration.

umbriel_log() {
    mkdir -p "$STATE_DIR"
    printf '[%s] %s\n' "$(date '+%F %T')" "$*" >>"${STATE_DIR}/prep.log"
}

umbriel_command() {
    local output status

    if output="$(umbriel "$@" 2>&1)"; then
        [[ -n "$output" ]] && printf '%s\n' "$output"
        umbriel_log "ok: umbriel $*"
        return 0
    fi

    status=$?
    umbriel_log "failed (${status}): umbriel $*: ${output}"
    printf '%s\n' "$output" >&2
    return "$status"
}

umbriel_set_output_option() {
    local connector="$1"
    local option="$2"
    local value="$3"

    umbriel_command config set "output.${connector}.${option}" "$value"
}

umbriel_set_output_string_option() {
    local connector="$1"
    local option="$2"
    local value="$3"

    # `umbriel config set` parses its value as TOML. Bare output modes and HDR
    # enum values are not valid TOML strings, so quote them before sending.
    umbriel_set_output_option "$connector" "$option" "\"${value}\""
}

connector_has_mode() {
    local connector="$1"
    local mode="${2%@*}"
    local path

    for path in "${VDISPLAY_SYSFS}"/card*-"${connector}"/modes; do
        [[ -f "$path" ]] || continue
        grep -qxF "$mode" "$path"
        return
    done
    return 1
}

umbriel_enable_output() {
    local connector="$1"
    local res="$2"
    local x="$3"
    local y="$4"
    local scale="$5"

    if ! connector_has_mode "$connector" "$res"; then
        echo "$connector does not advertise the requested mode $res." >&2
        umbriel_log "requested mode unavailable: $connector $res"
        return 1
    fi

    umbriel_set_output_string_option "$connector" mode "$res"
    umbriel_set_output_option "$connector" position "[${x}, ${y}]"
    umbriel_set_output_option "$connector" scale "$scale"
    umbriel_set_output_option "$connector" enabled true
    umbriel_command msg output-enable "$connector"
    echo "Enabled $connector at ${res} (${x},${y}, scale=${scale})"
}

umbriel_disable_output() {
    local connector="$1"

    # Persist the disabled state as well as changing the live output set.
    umbriel_set_output_option "$connector" enabled false
    umbriel_command msg output-disable "$connector"
    echo "Disabled $connector"
}

# ---- backend interface ----------------------------------------------------

backend_require_tools() {
    if command -v umbriel >/dev/null 2>&1; then
        return 0
    fi

    echo "umbriel not found: install Umbriel or select the correct desktop backend." >&2
    return 1
}

backend_has_output() {
    # `umbriel outputs` also includes desktop outputs that are currently
    # removed, while sysfs answers the question this backend needs: the kernel
    # connector exists and the compositor can add it back.
    connector_present "${1:-$VDISPLAY}"
}

backend_switch_to_virtual() {
    local res="$1"

    if ! connector_present "$PDISPLAY"; then
        echo "Physical connector $PDISPLAY is not present; refusing to strand the session on the virtual output." >&2
        return 1
    fi

    umbriel_enable_output "$VDISPLAY" "$res" 0 0 "$VDISPLAY_SCALE"
    if [[ "$VDISPLAY_HDR" == "1" ]]; then
        umbriel_set_output_string_option "$VDISPLAY" hdr on
    fi
    umbriel_disable_output "$PDISPLAY"
}

backend_switch_to_physical() {
    if ! connector_present "$PDISPLAY"; then
        echo "Physical connector $PDISPLAY is not present; run 'umbriel outputs' and update PDISPLAY." >&2
        return 1
    fi

    # Let Umbriel reapply its own mode, position, and scale for this connector.
    # Replacing them with the repository defaults would lose machine-specific
    # desktop.toml settings, such as a fractional scale. Clear a persisted
    # disabled state first so a subsequent config reload cannot turn the
    # physical output back off after it has been enabled live.
    umbriel_set_output_option "$PDISPLAY" enabled true
    umbriel_command msg output-enable "$PDISPLAY"
    echo "Enabled $PDISPLAY with its Umbriel output configuration"

    if [[ "$VDISPLAY_HDR" == "1" ]]; then
        umbriel_set_output_string_option "$VDISPLAY" hdr off
    fi
    umbriel_disable_output "$VDISPLAY"
}

backend_show_outputs() {
    echo "Current outputs:"
    umbriel outputs
}

# Noctalia provides night light, but disabling its schedule changes user state
# outside the compositor. Leave it untouched rather than restoring a setting
# incorrectly after the stream.
backend_disable_night_color() { :; }
backend_restore_night_color() { :; }
