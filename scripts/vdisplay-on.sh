#!/usr/bin/env bash
# Enable virtual display for streaming and disable the physical monitor.

set -euo pipefail

# shellcheck source=vdisplay-common.sh
source "$(dirname "$0")/vdisplay-common.sh"

de_require_tools || exit 1

RES="$(pick_stream_resolution)"
if [[ -n "${1:-}" ]]; then
    RES="$1"
fi

if ! connector_present "$VDISPLAY"; then
    echo "Virtual display $VDISPLAY is not connected at the kernel level."
    echo "Expected kernel params: drm.edid_firmware=${VDISPLAY}:edid/virtual-display.bin video=${VDISPLAY}:e"
    echo "Check: cat /proc/cmdline"
    exit 1
fi

if ! de_has_output "$VDISPLAY"; then
    echo "Virtual display $VDISPLAY is connected in DRM but not visible to the desktop yet."
    echo "Try logging out/in, or reboot if you just changed kernel parameters."
    exit 1
fi

echo "Switching to virtual display at ${RES}..."
de_disable_night_color
de_switch_to_virtual "$RES"
de_show_outputs
