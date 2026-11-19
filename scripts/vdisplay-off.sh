#!/usr/bin/env bash
# Disable virtual display and restore the physical monitor.

set -euo pipefail

# shellcheck source=vdisplay-common.sh
source "$(dirname "$0")/vdisplay-common.sh"

resolve_physical_connector || exit 1
de_require_tools || exit 1

de_switch_to_physical
de_restore_night_color
de_show_outputs
