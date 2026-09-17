#!/usr/bin/env bash
# Kernel command line helpers for the virtual-display EDID mapping.
#
# Sourced by scripts/install.sh and exercised by tests/cmdline-merge-test.sh.
#
# The kernel parses drm.edid_firmware as one comma-separated list of
# "connector:firmware" mappings (module_param_string in drm_edid_load.c), so a
# second drm.edid_firmware= parameter on the command line replaces the first
# instead of adding to it. Hosts that already map EDID firmware for another
# connector (a dummy plug, an eDP panel) would silently lose that mapping when
# the virtual display entry is appended, so it has to be merged into the
# existing value.

# Print the expression matching a kernel command line entry of the given
# bootloader style.
cmdline_line_expr() {
    local style="$1"

    case "$style" in
        limine)
            printf '%s' '^KERNEL_CMDLINE\[[^]]*default[^]]*\]\+?='
            ;;
        grub)
            printf '%s' '^GRUB_CMDLINE_LINUX_DEFAULT='
            ;;
        systemd-boot)
            printf '%s' '^options '
            ;;
        *)
            printf 'error: unknown bootloader style: %s\n' "$style" >&2
            return 1
            ;;
    esac
}

# Print the sed expression that adds " <params>" to the end of a kernel command
# line entry of the given bootloader style, keeping any closing quote in place.
cmdline_insert_expr() {
    local style="$1" params="$2"

    case "$style" in
        limine | grub)
            printf '%s' 's|"$| '"$params"'"|'
            ;;
        systemd-boot)
            printf '%s' 's|$| '"$params"'|'
            ;;
        *)
            printf 'error: unknown bootloader style: %s\n' "$style" >&2
            return 1
            ;;
    esac
}

# Merge the virtual-display kernel parameters into the bootloader config <file>
# and print the result on stdout:
#
#   cmdline_merge_params <limine|grub|systemd-boot> <file> <connector>
#
# Returns 0 when the file needed no change or was updated, and 3 when the file
# has no kernel command line entry to attach the parameters to. The caller owns
# the write, so this stays usable without root privileges.
cmdline_merge_params() {
    local style="$1" file="$2" connector="$3"
    local drm_entry="${connector}:edid/virtual-display.bin"
    local video_entry="video=${connector}:e"
    local work out params stale target drm_line line_re
    local -a strip=()

    [[ -f "$file" ]] || return 1

    work="$(mktemp)" || return 1
    out="$(mktemp)" || return 1
    line_re="$(cmdline_line_expr "$style")" || return 1

    # Leave other connectors' mappings alone, but drop ours: it may be first,
    # last, or the only entry in the comma-separated list.
    strip+=(
        -e 's|drm\.edid_firmware=[^ ",]+:edid/virtual-display\.bin,|drm.edid_firmware=|'
        -e 's|,[^ ",]+:edid/virtual-display\.bin||'
        -e 's| drm\.edid_firmware=[^ ",]+:edid/virtual-display\.bin||'
        -e 's|"drm\.edid_firmware=[^ ",]+:edid/virtual-display\.bin|"|'
    )

    # A stale install may have used a different connector, so drop the video=
    # flag for every connector that referenced our EDID blob.
    while read -r stale; do
        [[ -n "$stale" ]] || continue
        strip+=(-e "s| video=${stale}:e||")
    done < <(grep -oE '[^ ",=]+:edid/virtual-display\.bin' "$file" | cut -d: -f1 | sort -u)

    sed -E "${strip[@]}" "$file" >"$work"

    # Only the first command line entry is extended: Limine hosts can carry more
    # than one KERNEL_CMDLINE[default]+= line, and appending to each of them
    # would duplicate the parameters in the final command line.
    target="$(grep -nE "$line_re" "$work" | head -n 1 | cut -d: -f1 || true)"
    if [[ -z "$target" ]]; then
        rm -f "$work" "$out"
        return 3
    fi

    # Another connector may already map EDID firmware. Merge ours into that
    # value instead of adding a second drm.edid_firmware= parameter, which the
    # kernel would let override the existing mapping.
    drm_line="$(grep -nE 'drm\.edid_firmware=[^ "]+' "$work" | head -n 1 | cut -d: -f1 || true)"
    if [[ -n "$drm_line" ]] && sed -n "${drm_line}p" "$work" | grep -qE "$line_re"; then
        target="$drm_line"
        sed -i -E "${target}s|(drm\.edid_firmware=[^ \"]+)|\1,${drm_entry}|" "$work"
    fi

    params=""
    grep -qF "$drm_entry" "$work" || params="drm.edid_firmware=${drm_entry}"
    grep -qF "$video_entry" "$work" || params="${params:+$params }${video_entry}"

    if [[ -z "$params" ]]; then
        cat "$work"
    else
        sed -E "${target}$(cmdline_insert_expr "$style" "$params")" "$work" >"$out" \
            || {
                rm -f "$work" "$out"
                return 1
            }
        if ! grep -qF "$drm_entry" "$out" || ! grep -qF "$video_entry" "$out"; then
            rm -f "$work" "$out"
            return 3
        fi
        cat "$out"
    fi

    rm -f "$work" "$out"
}
