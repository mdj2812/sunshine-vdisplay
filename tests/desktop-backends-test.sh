#!/usr/bin/env bash
# Smoke-test the display switching scripts per desktop backend.
#
# The compositor tools are stubbed, so nothing here needs a session, a GPU, or
# root. What it verifies is the contract each backend has to honour: which calls
# go out, with which arguments, and that the restore path brings the physical
# monitor back before switching away from the virtual one.
#
# Usage:
#   ./tests/desktop-backends-test.sh [kde|gnome]

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
only_desktop="${1:-}"

work="$(mktemp -d "${TMPDIR:-/tmp}/vdisplay-desktop.XXXXXX")"
trap 'rm -rf "$work"' EXIT

export HOME="${work}/home"
export STATE_DIR="${work}/state"
export VDISPLAY_SYSFS="${work}/drm"
export VDISPLAY=HDMI-A-1
export PDISPLAY=DP-3
export RES=2560x1440@120
export PDISPLAY_RES=2560x1440@143.99

mkdir -p "$HOME" "$STATE_DIR" "${work}/bin" \
    "${work}/drm/card1-${VDISPLAY}" "${work}/drm/card1-${PDISPLAY}"
echo connected >"${work}/drm/card1-${VDISPLAY}/status"
echo connected >"${work}/drm/card1-${PDISPLAY}/status"
export PATH="${work}/bin:${PATH}"

calls="${work}/calls"
: >"$calls"

cat >"${work}/bin/kscreen-doctor" <<EOF
#!/usr/bin/env bash
printf 'kscreen-doctor %s\n' "\$*" >>"${calls}"
if [[ "\$*" == *"-o"* ]]; then
    cat <<'OUT'
[01;32mOutput: [0;0m1 DP-3 61861c4f-2f85-4ea9-ac40-ec54731af0a8
	[01;32menabled[0;0m
	[01;32mconnected[0;0m
	[01;33mHDR: [0;0menabled
	[01;33mWide Color Gamut: [0;0menabled
[01;32mOutput: [0;0m2 HDMI-A-1 7a4c3c7e-b3e3-4b22-ab3b-0fc8e873b7b0
	[01;32menabled[0;0m
	[01;32mconnected[0;0m
	[01;33mHDR: [0;0mdisabled
	[01;33mWide Color Gamut: [0;0mdisabled
OUT
fi
exit 0
EOF

cat >"${work}/bin/gdctl" <<EOF
#!/usr/bin/env bash
printf 'gdctl %s\n' "\$*" >>"${calls}"
if [[ "\${1:-}" == "show" ]]; then
    printf 'Monitors:\\n'
    printf '  %s\\n' "${VDISPLAY}"
fi
exit 0
EOF

# KDE night colour plumbing, called by the swap scripts.
for tool in qdbus kwriteconfig6 kreadconfig6; do
    printf '#!/usr/bin/env bash\nexit 0\n' >"${work}/bin/${tool}"
done
chmod +x "${work}/bin/"*

failures=0
fail() {
    printf 'FAIL: %s\n' "$*" >&2
    failures=$((failures + 1))
}
pass() { printf 'ok: %s\n' "$*"; }

expect_call() {
    local name="$1" pattern="$2"
    if grep -qF -- "$pattern" "$calls"; then
        pass "$name"
    else
        fail "$name: expected '$pattern'"
        cat "$calls" >&2
    fi
}

expect_no_call() {
    local name="$1" pattern="$2"
    if grep -q -- "$pattern" "$calls"; then
        fail "$name: '$pattern' should not have been called"
        cat "$calls" >&2
    else
        pass "$name"
    fi
}

run_scripts() {
    local desktop="$1" desktop_value="$2"
    shift 2

    if ! env XDG_CURRENT_DESKTOP="$desktop_value" "$@" "${repo_root}/scripts/vdisplay-on.sh" \
        >"${work}/${desktop}-on.log" 2>&1; then
        fail "${desktop}: vdisplay-on.sh failed"
        cat "${work}/${desktop}-on.log" >&2
        return 1
    fi

    if ! env XDG_CURRENT_DESKTOP="$desktop_value" "$@" "${repo_root}/scripts/vdisplay-off.sh" \
        >"${work}/${desktop}-off.log" 2>&1; then
        fail "${desktop}: vdisplay-off.sh failed"
        cat "${work}/${desktop}-off.log" >&2
        return 1
    fi
}

if [[ -z "$only_desktop" || "$only_desktop" == "kde" ]]; then
    : >"$calls"
    run_scripts kde KDE || true

    expect_call "kde: enables the virtual output" "kscreen-doctor output.${VDISPLAY}.enable"
    expect_call "kde: sets the requested mode" "kscreen-doctor output.${VDISPLAY}.mode.${RES}"
    expect_call "kde: places the virtual output" "kscreen-doctor output.${VDISPLAY}.position.0,0"
    expect_call "kde: makes the virtual output primary" "kscreen-doctor output.${VDISPLAY}.priority.1"
    expect_call "kde: blanks the physical output" "kscreen-doctor output.${PDISPLAY}.disable"
    expect_call "kde: restores the physical output" "kscreen-doctor output.${PDISPLAY}.enable"
    expect_call "kde: turns the virtual output off again" "kscreen-doctor output.${VDISPLAY}.disable"
    expect_no_call "kde: leaves gdctl alone" "gdctl"
fi

if [[ -z "$only_desktop" || "$only_desktop" == "gnome" ]]; then
    : >"$calls"
    run_scripts gnome ubuntu:GNOME || true

    expect_call "gnome: switches to the virtual output in one call" \
        "gdctl set --logical-monitor --primary --monitor ${VDISPLAY} --mode ${RES} --x 0 --y 0 --scale 1.5"
    expect_call "gnome: switches back to the physical output" \
        "gdctl set --logical-monitor --primary --monitor ${PDISPLAY} --mode ${PDISPLAY_RES} --x 0 --y 0 --scale 1"
    expect_no_call "gnome: leaves kscreen-doctor alone" "kscreen-doctor"

    # HDR is part of the same declarative call on GNOME.
    : >"$calls"
    run_scripts gnome-hdr ubuntu:GNOME env VDISPLAY_HDR=1 || true
    expect_call "gnome: requests the HDR colour mode" "--color-mode bt2100"
fi

# With no known desktop and no compositor tool, the scripts must say what is
# missing instead of half-switching the displays.
corebin="${work}/corebin"
mkdir -p "$corebin"
ln -sf "$(command -v mkdir)" "$(command -v id)" "$corebin/"
unknown="$(
    env PATH="$corebin" XDG_CURRENT_DESKTOP=sway /usr/bin/bash -c \
        "source '${repo_root}/scripts/vdisplay-common.sh'; de_desktop" 2>/dev/null
)"
if [[ "$unknown" == "unknown" ]]; then
    pass "unknown desktop is detected"
else
    fail "expected de_desktop=unknown, got '${unknown}'"
fi

if env PATH="$corebin" XDG_CURRENT_DESKTOP=sway /usr/bin/bash -c \
    "source '${repo_root}/scripts/vdisplay-common.sh'; de_require_tools" 2>"${work}/unknown.err"; then
    fail "de_require_tools should fail without a backend"
else
    if grep -q "docs/DESKTOPS.md" "${work}/unknown.err"; then
        pass "unknown desktop points at the docs"
    else
        fail "expected a docs/DESKTOPS.md pointer"
        cat "${work}/unknown.err" >&2
    fi
fi

if [[ "$failures" -eq 0 ]]; then
    printf '\nAll desktop backend tests passed.\n'
else
    printf '\n%d desktop backend test(s) failed.\n' "$failures" >&2
    exit 1
fi
