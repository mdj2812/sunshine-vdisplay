#!/usr/bin/env bash
# Disable the virtual display when not streaming remotely.

set -euo pipefail

source "$(dirname "$0")/vdisplay-common.sh"

if kscreen_has_output; then
    kscreen "output.${VDISPLAY}.disable"
    echo "Disabled $VDISPLAY"
elif connector_present; then
    echo "$VDISPLAY is connected in DRM but not managed by KDE."
else
    echo "$VDISPLAY not present"
fi
