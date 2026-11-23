#!/usr/bin/env bash
# Smoke-test the display switching scripts per desktop backend.
#
# The compositor tools are stubbed, so nothing here needs a session, a GPU, or
# root. What it verifies is the contract each backend has to honour: which calls
# go out, with which arguments, and that the restore path brings the physical
# monitor back before switching away from the virtual one.
#
# Usage:
#   ./tests/desktop-backends-test.sh [kde|gnome|umbriel]

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
echo "${RES%@*}" >"${work}/drm/card1-${VDISPLAY}/modes"
echo "${PDISPLAY_RES%@*}" >"${work}/drm/card1-${PDISPLAY}/modes"
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

cat >"${work}/bin/umbriel" <<EOF
#!/usr/bin/env bash
printf 'umbriel %s\n' "\$*" >>"${calls}"
state="${work}/umbriel-state"
case "\${1:-}" in
    outputs)
        printf 'HDMI-A-1\\n'
        printf 'DP-3\\n'
        ;;
    config)
        key="\${3:-}"
        value="\${4:-}"
        connector="\${key#output.}"
        connector="\${connector%.enabled}"
        case "\${2:-}" in
            get)
                cat "\${state}/\${connector}" 2>/dev/null || printf 'true\\n'
                ;;
            set)
                case "\$key" in
                    *.mode | *.hdr)
                        if [[ ! "\$value" =~ ^\\".*\\"$ ]]; then
                            printf 'expected one TOML value, got: %s\\n' "\$value" >&2
                            exit 1
                        fi
                        ;;
                    *.position)
                        if [[ ! "\$value" =~ ^\\[[0-9-]+,[[:space:]]*[0-9-]+\\]$ ]]; then
                            printf 'expected one TOML value, got: %s\\n' "\$value" >&2
                            exit 1
                        fi
                        ;;
                    *.scale)
                        if [[ ! "\$value" =~ ^[0-9.]+$ ]]; then
                            printf 'expected one TOML value, got: %s\\n' "\$value" >&2
                            exit 1
                        fi
                        ;;
                esac
                ;;
        esac
        ;;
    msg)
        case "\${2:-}" in
            output-enable) printf 'true\\n' >"\${state}/\${3}" ;;
            output-disable) printf 'false\\n' >"\${state}/\${3}" ;;
        esac
        ;;
esac
exit 0
EOF

cat >"${work}/bin/pgrep" <<'EOF'
#!/usr/bin/env bash
[[ "${1:-}" == "-x" && "${2:-}" == "umbriel" ]]
EOF

# KDE night colour plumbing, called by the swap scripts.
for tool in qdbus kwriteconfig6 kreadconfig6; do
    printf '#!/usr/bin/env bash\nexit 0\n' >"${work}/bin/${tool}"
done
chmod +x "${work}/bin/"*
mkdir -p "${work}/umbriel-state"

failures=0
fail() {
    printf 'FAIL: %s\n' "$*" >&2
    failures=$((failures + 1))
}
pass() { printf 'ok: %s\n' "$*"; }

selected="$(
    env HOME="$HOME" STATE_DIR="$STATE_DIR" VDISPLAY_SYSFS="$VDISPLAY_SYSFS" \
        EDID_MODES="3200x2136@60,2560x1440@120" \
        SUNSHINE_CLIENT_WIDTH=3200 SUNSHINE_CLIENT_HEIGHT=2136 SUNSHINE_CLIENT_FPS=60 \
        /usr/bin/bash -c \
        "source '${repo_root}/scripts/vdisplay-common.sh'; pick_stream_resolution"
)"
if [[ "$selected" == "3200x2136@60" ]]; then
    pass "selects the exact custom client resolution"
else
    fail "expected 3200x2136@60, got '${selected}'"
fi

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

if [[ -z "$only_desktop" || "$only_desktop" == "umbriel" ]]; then
    : >"$calls"
    printf 'false\n' >"${work}/umbriel-state/${VDISPLAY}"
    printf 'true\n' >"${work}/umbriel-state/${PDISPLAY}"
    run_scripts umbriel umbriel || true

    expect_call "umbriel: sets the virtual mode" \
        "umbriel config set output.${VDISPLAY}.mode \"${RES}\""
    expect_call "umbriel: places the virtual output" \
        "umbriel config set output.${VDISPLAY}.position [0, 0]"
    expect_call "umbriel: sets the virtual scale" \
        "umbriel config set output.${VDISPLAY}.scale 1.5"
    expect_call "umbriel: marks the virtual output enabled" \
        "umbriel config set output.${VDISPLAY}.enabled true"
    expect_call "umbriel: enables the virtual output" \
        "umbriel msg output-enable ${VDISPLAY}"
    expect_call "umbriel: removes the physical output" \
        "umbriel msg output-disable ${PDISPLAY}"
    expect_call "umbriel: marks the physical output enabled on restore" \
        "umbriel config set output.${PDISPLAY}.enabled true"
    expect_call "umbriel: restores the physical output" \
        "umbriel msg output-enable ${PDISPLAY}"
    expect_no_call "umbriel: preserves the physical output mode" \
        "umbriel config set output.${PDISPLAY}.mode"
    expect_no_call "umbriel: preserves the physical output position" \
        "umbriel config set output.${PDISPLAY}.position"
    expect_no_call "umbriel: preserves the physical output scale" \
        "umbriel config set output.${PDISPLAY}.scale"
    expect_call "umbriel: removes the virtual output" \
        "umbriel msg output-disable ${VDISPLAY}"
    expect_call "umbriel: marks the virtual output disabled" \
        "umbriel config set output.${VDISPLAY}.enabled false"
    expect_no_call "umbriel: leaves kscreen-doctor alone" "kscreen-doctor"
    expect_no_call "umbriel: leaves gdctl alone" "gdctl"
    if grep -qF 'ok: umbriel config set output.HDMI-A-1.mode' \
        "${STATE_DIR}/prep.log"; then
        pass "umbriel: records successful commands for diagnostics"
    else
        fail "umbriel: command diagnostics were not written"
        cat "${STATE_DIR}/prep.log" >&2 2>/dev/null || true
    fi

    : >"$calls"
    printf 'false\n' >"${work}/umbriel-state/${VDISPLAY}"
    printf 'true\n' >"${work}/umbriel-state/${PDISPLAY}"
    run_scripts umbriel-hdr umbriel env VDISPLAY_HDR=1 || true
    expect_call "umbriel: enables HDR while streaming" \
        "umbriel config set output.${VDISPLAY}.hdr \"on\""
    expect_call "umbriel: turns HDR off on restore" \
        "umbriel config set output.${VDISPLAY}.hdr \"off\""

    : >"$calls"
    printf 'true\n' >"${work}/umbriel-state/${VDISPLAY}"
    printf 'true\n' >"${work}/umbriel-state/${PDISPLAY}"
    if env XDG_CURRENT_DESKTOP=umbriel "${repo_root}/scripts/vdisplay-on.sh" \
        >"${work}/umbriel-already-enabled.log" 2>&1; then
        pass "umbriel: enables an already-enabled virtual output"
    else
        fail "umbriel: failed with an already-enabled virtual output"
        cat "${work}/umbriel-already-enabled.log" >&2
    fi
    expect_call "umbriel: sends output-enable even when config state is stale" \
        "umbriel msg output-enable ${VDISPLAY}"

    detected="$(
        env PATH="${work}/bin:${PATH}" XDG_CURRENT_DESKTOP= /usr/bin/bash -c \
            "source '${repo_root}/scripts/vdisplay-common.sh'; de_desktop"
    )"
    if [[ "$detected" == "umbriel" ]]; then
        pass "umbriel: detects the compositor when XDG_CURRENT_DESKTOP is missing"
    else
        fail "umbriel: expected process detection, got '${detected}'"
    fi
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
