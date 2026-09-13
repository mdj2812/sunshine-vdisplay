#!/usr/bin/env bash
# Disable virtual display and restore the physical monitor.

set -euo pipefail

source "$(dirname "$0")/vdisplay-common.sh"

if kscreen_has_output "$PDISPLAY"; then
    echo "Restoring physical display..."
    enable_output "$PDISPLAY" "$PDISPLAY_RES" 0 0 1
else
    echo "Physical display $PDISPLAY not found in KDE."
fi

if kscreen_has_output "$VDISPLAY"; then
    disable_output "$VDISPLAY"
elif connector_present "$VDISPLAY"; then
    echo "$VDISPLAY is connected in DRM but not managed by KDE."
else
    echo "$VDISPLAY not present"
fi

show_outputs
