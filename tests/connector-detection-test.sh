#!/usr/bin/env bash
# shellcheck disable=SC2030,SC2031
# Verify that connector auto-detection does not confuse an existing virtual
# EDID output with the physical monitor.

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/vdisplay-connectors.XXXXXX")"
trap 'rm -rf "$work"' EXIT

sysfs="${work}/drm"
cmdline="${work}/cmdline"
mkdir -p \
    "${sysfs}/card1-DP-1" \
    "${sysfs}/card1-DP-2" \
    "${sysfs}/card1-DP-3" \
    "${sysfs}/card1-HDMI-A-1"

printf 'connected\n' >"${sysfs}/card1-DP-1/status"
printf 'disconnected\n' >"${sysfs}/card1-DP-2/status"
printf 'connected\n' >"${sysfs}/card1-DP-3/status"
printf 'disconnected\n' >"${sysfs}/card1-HDMI-A-1/status"
printf '%s\n' \
    'quiet drm.edid_firmware=DP-1:edid/virtual-display.bin video=DP-1:e' \
    >"$cmdline"

export VDISPLAY_SYSFS="$sysfs"
export VDISPLAY_CMDLINE_FILE="$cmdline"
# shellcheck disable=SC1091
source "${repo_root}/scripts/install.sh"

virtual="$(pick_virtual_connector)"
physical="$(pick_physical_connector "$virtual")"

if [[ "$virtual" != "HDMI-A-1" ]]; then
    printf 'FAIL: expected HDMI-A-1 as the new virtual connector, got %s\n' "$virtual" >&2
    exit 1
fi

if [[ "$physical" != "DP-3" ]]; then
    printf 'FAIL: expected DP-3 as the physical connector, got %s\n' "$physical" >&2
    exit 1
fi

printf 'ok: ignores the previous virtual EDID connector during physical detection\n'

# Runtime recovery: the installed local override can become stale after the
# virtual connector moves. With one unambiguous physical monitor, the swap
# scripts should recover without requiring a manual edit first.
printf 'disconnected\n' >"${sysfs}/card1-DP-1/status"
printf 'connected\n' >"${sysfs}/card1-HDMI-A-1/status"
printf '%s\n' \
    'quiet drm.edid_firmware=HDMI-A-1:edid/virtual-display.bin video=HDMI-A-1:e' \
    >"$cmdline"
(
    VDISPLAY_SYSFS="$sysfs"
    VDISPLAY_CMDLINE_FILE="$cmdline"
    HOME="${work}/home"
    VDISPLAY="HDMI-A-1"
    PDISPLAY="DP-1"
    STATE_DIR="${work}/state"
    # shellcheck disable=SC1091
    source "${repo_root}/scripts/vdisplay-common.sh"

    resolve_physical_connector
    [[ "$PDISPLAY" == "DP-3" ]]
)
printf 'ok: resolves one unambiguous physical output from a stale override\n'

# Installer reruns must not silently replace a custom mode list with defaults.
mkdir -p "${work}/preserve-home/bin"
cat >"${work}/preserve-home/bin/vdisplay-common.local.sh" <<'EOF'
RES="3200x2136@60"
VDISPLAY_SCALE="2.0"
PDISPLAY_SCALE="1.5"
EXTRA_MODES="2560x1440@120,1920x1080@60"
EDID_MODES="3200x2136@60,2560x1440@120,1920x1080@60"
EOF
(
    export HOME="${work}/preserve-home"
    unset RES EXTRA_MODES EDID_MODES VDISPLAY_SCALE PDISPLAY_SCALE
    # shellcheck disable=SC1091
    source "${repo_root}/scripts/install.sh"
    load_existing_edid_config
    [[ "$RES" == "3200x2136@60" ]]
    [[ "$VDISPLAY_SCALE" == "2.0" ]]
    [[ "$PDISPLAY_SCALE" == "1.5" ]]
    [[ "$EXTRA_MODES" == "2560x1440@120,1920x1080@60" ]]
    [[ "$EDID_MODES" == "3200x2136@60,2560x1440@120,1920x1080@60" ]]
    [[ "$EDID_MODES_FROM_EXISTING" -eq 1 ]]

    selector_ran=0
    have_install_tty() { return 0; }
    run_edid_setup_tui() { selector_ran=1; }
    configure_edid_modes
    [[ "$selector_ran" -eq 1 ]]
)
printf 'ok: preserves custom modes and still offers the interactive selector\n'

# The installer's support warning must agree with the runtime backend list.
(
    export HOME="${work}/desktop-home"
    unset RES EXTRA_MODES EDID_MODES
    # shellcheck disable=SC1091
    source "${repo_root}/scripts/install.sh"
    XDG_CURRENT_DESKTOP=umbriel warn_desktop_support
) 2>"${work}/desktop-warning.err"
if [[ ! -s "${work}/desktop-warning.err" ]]; then
    printf 'ok: installer recognizes the Umbriel backend\n'
else
    printf 'FAIL: installer warned about Umbriel support:\\n' >&2
    cat "${work}/desktop-warning.err" >&2
    exit 1
fi

printf 'All connector detection tests passed.\n'
