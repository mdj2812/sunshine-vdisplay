#!/usr/bin/env bash
# Tests for the KDE display helpers behind VDISPLAY_HDR.
#
# The helpers run against a fake kscreen-doctor, so no session, GPU, or root is
# needed and nothing on screen is touched.
#
# Usage:
#   ./tests/hdr-helpers-test.sh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
work="$(mktemp -d "${TMPDIR:-/tmp}/vdisplay-hdr.XXXXXX")"
trap 'rm -rf "$work"' EXIT

export HOME="${work}/home"
export STATE_DIR="${work}/state"
export VDISPLAY=HDMI-A-1
export PDISPLAY=DP-3
mkdir -p "$HOME" "$STATE_DIR" "${work}/bin"

calls="${work}/kscreen-calls"
status_file="${work}/kscreen-status"
outputs_file="${work}/kscreen-outputs"
echo 0 >"$status_file"
: >"$outputs_file"

cat >"${work}/bin/kscreen-doctor" <<EOF
#!/usr/bin/env bash
printf '%s\n' "\$*" >>"${calls}"
if [[ "\$*" == *" -o"* || "\$1" == "-o" ]]; then
    cat "${outputs_file}"
fi
exit "\$(cat "${status_file}")"
EOF
chmod +x "${work}/bin/kscreen-doctor"
export PATH="${work}/bin:${PATH}"

# shellcheck source=scripts/vdisplay-common.sh
source "${repo_root}/scripts/vdisplay-common.sh"

failures=0

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    failures=$((failures + 1))
}

pass() { printf 'ok: %s\n' "$*"; }

cat >"$outputs_file" <<'EOF'
Output: 1 DP-3 61861c4f
	enabled
	connected
	HDR: enabled
		SDR brightness: 400 nits
	Wide Color Gamut: enabled
Output: 2 HDMI-A-1 7a4c3c7e
	disabled
	connected
	HDR: disabled
	Wide Color Gamut: disabled
EOF

if output_hdr_enabled DP-3; then
    pass "detects HDR enabled on DP-3"
else
    fail "should detect HDR enabled on DP-3"
fi

if output_hdr_enabled HDMI-A-1; then
    fail "should not report HDR for a disabled HDMI-A-1"
else
    pass "reports HDR off for HDMI-A-1"
fi

# HDR state changes reach KWin through both properties.
: >"$calls"
if set_output_hdr HDMI-A-1 enable >/dev/null \
    && grep -qxF "output.HDMI-A-1.hdr.enable" "$calls" \
    && grep -qxF "output.HDMI-A-1.wcg.enable" "$calls"; then
    pass "enables HDR and WCG on the virtual output"
else
    fail "expected separate hdr.enable and wcg.enable calls"
    cat "$calls" >&2
fi

: >"$calls"
if set_output_hdr HDMI-A-1 disable >/dev/null \
    && grep -qxF "output.HDMI-A-1.hdr.disable" "$calls" \
    && grep -qxF "output.HDMI-A-1.wcg.disable" "$calls"; then
    pass "disables HDR and WCG again"
else
    fail "expected separate hdr.disable and wcg.disable calls"
    cat "$calls" >&2
fi

# A rejected toggle must not take the session script down with it.
echo 1 >"$status_file"
rc=0
err="$(set_output_hdr HDMI-A-1 enable 2>&1 >/dev/null)" || rc=$?
if [[ "$rc" -eq 1 ]] && [[ "$err" == *"did not accept HDR enable"* ]]; then
    pass "reports a rejected HDR toggle without failing hard"
else
    fail "expected rc=1 and a warning, got rc=${rc} err=${err}"
fi
echo 0 >"$status_file"

# With HDR on, the tuning step also sets the SDR brightness level.
cat >"$outputs_file" <<'EOF'
Output: 2 HDMI-A-1 7a4c3c7e
	enabled
	HDR: enabled
EOF
: >"$calls"
tune_virtual_display HDMI-A-1 >/dev/null
if grep -qF "sdr-brightness.400" "$calls"; then
    pass "applies SDR brightness while HDR is on"
else
    fail "expected sdr-brightness.400"
    cat "$calls" >&2
fi

if [[ "$failures" -eq 0 ]]; then
    printf '\nAll display helper tests passed.\n'
else
    printf '\n%d display helper test(s) failed.\n' "$failures" >&2
    exit 1
fi
