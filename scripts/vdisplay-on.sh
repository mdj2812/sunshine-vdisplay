#!/usr/bin/env bash
# Enable the virtual display (HDMI-A-1) for Sunshine remote desktop.

set -euo pipefail

source "$(dirname "$0")/vdisplay-common.sh"

RES="${1:-$RES}"

if ! connector_present; then
    echo "Virtual display $VDISPLAY is not connected at the kernel level."
    echo "Expected kernel params: drm.edid_firmware=${VDISPLAY}:edid/virtual-display.bin video=${VDISPLAY}:e"
    echo "Check: cat /proc/cmdline"
    exit 1
fi

if ! kscreen_has_output; then
    echo "Virtual display $VDISPLAY is connected in DRM but not visible to KDE yet."
    echo "Try logging out/in, or reboot if you just changed kernel parameters."
    exit 1
fi

echo "Enabling $VDISPLAY at $RES..."
kscreen "output.${VDISPLAY}.enable"
kscreen "output.${VDISPLAY}.mode.${RES}"
kscreen "output.${VDISPLAY}.position.2560,0"
kscreen "output.${VDISPLAY}.priority.2"

echo "Current outputs:"
kscreen -o | grep -E 'Output:|enabled|connected|Geometry|Modes:'
