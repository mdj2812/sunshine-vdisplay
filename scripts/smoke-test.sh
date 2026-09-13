#!/usr/bin/env bash
# Smoke-test install/uninstall in a VM or container (no GPU, bootloader, or reboot).
#
# Usage:
#   ./scripts/smoke-test.sh
#
# Environment:
#   REPO_URL   Override clone URL when not run from a checkout

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
export SUNSHINE_VDISPLAY_REPO="$repo_root"
export I_HAVE_BACKED_UP=1
export I_CONFIRM_UNINSTALL=1
export SKIP_REBOOT=1
export SKIP_BOOTLOADER=1
export SKIP_INITRAMFS_REBUILD=1
export SKIP_POWER_MGMT=1
export VDISPLAY=HDMI-A-1
export PDISPLAY=DP-1

log() { printf '==> %s\n' "$*"; }
die() { printf 'error: %s\n' "$*" >&2; exit 1; }

detect_backend() {
    if [[ -f /etc/mkinitcpio.conf ]] && command -v mkinitcpio >/dev/null 2>&1; then
        echo mkinitcpio
    elif command -v dracut >/dev/null 2>&1; then
        echo dracut
    elif [[ -d /etc/initramfs-tools ]] && command -v update-initramfs >/dev/null 2>&1; then
        echo initramfs-tools
    else
        echo unknown
    fi
}

verify_install_artifacts() {
    local backend
    backend="$(detect_backend)"

    test -f /usr/lib/firmware/edid/virtual-display.bin
    test -f "${HOME}/bin/vdisplay-on.sh"
    test -f "${HOME}/.config/sunshine/sunshine.conf"

    case "$backend" in
        mkinitcpio)
            grep -q 'virtual-display.bin' /etc/mkinitcpio.conf
            ;;
        dracut)
            test -f /etc/dracut.conf.d/99-sunshine-vdisplay.conf
            ;;
        initramfs-tools)
            test -f /etc/initramfs-tools/hooks/sunshine-vdisplay-edid
            ;;
        *)
            die "unsupported initramfs backend for smoke test: ${backend}"
            ;;
    esac
}

verify_uninstall_artifacts() {
    local backend
    backend="$(detect_backend)"

    test ! -f /usr/lib/firmware/edid/virtual-display.bin
    test ! -f "${HOME}/bin/vdisplay-on.sh"

    case "$backend" in
        mkinitcpio)
            ! grep -q 'virtual-display.bin' /etc/mkinitcpio.conf
            ;;
        dracut)
            test ! -f /etc/dracut.conf.d/99-sunshine-vdisplay.conf
            ;;
        initramfs-tools)
            test ! -f /etc/initramfs-tools/hooks/sunshine-vdisplay-edid
            ;;
    esac
}

log "Backend: $(detect_backend)"
log "Testing EDID generator"
python3 "${repo_root}/scripts/create-vdisplay-edid.py" /tmp/sunshine-vdisplay-smoke-edid.bin
test "$(wc -c < /tmp/sunshine-vdisplay-smoke-edid.bin)" -eq 256

log "Running install.sh (smoke mode)"
"${repo_root}/scripts/install.sh"
verify_install_artifacts

log "Running uninstall.sh (smoke mode)"
"${repo_root}/scripts/uninstall.sh"
verify_uninstall_artifacts

log "Smoke test passed on $(detect_backend)"
