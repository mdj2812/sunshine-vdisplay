#!/usr/bin/env bash
# Enable virtual display for streaming and disable the physical monitor.

set -euo pipefail

source "$(dirname "$0")/vdisplay-common.sh"

RES="${1:-$RES}"

if ! connector_present "$VDISPLAY"; then
    echo "Virtual display $VDISPLAY is not connected at the kernel level."
    echo "Expected kernel params: drm.edid_firmware=${VDISPLAY}:edid/virtual-display.bin video=${VDISPLAY}:e"
    echo "Check: cat /proc/cmdline"
    exit 1
fi

if ! kscreen_has_output "$VDISPLAY"; then
    echo "Virtual display $VDISPLAY is connected in DRM but not visible to KDE yet."
    echo "Try logging out/in, or reboot if you just changed kernel parameters."
    exit 1
fi

echo "Switching to virtual display..."
enable_output "$VDISPLAY" "$RES" 0 0 1
disable_output "$PDISPLAY"
show_outputs
