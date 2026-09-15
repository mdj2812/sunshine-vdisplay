#!/usr/bin/env bash
# Remove a sunshine-vdisplay installation created by install.sh.
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/mdj2812/sunshine-vdisplay/main/scripts/uninstall.sh | bash
#
# Usage:
#   ./scripts/uninstall.sh
#
# Environment variables:
#   I_CONFIRM_UNINSTALL  Set to 1 to skip the confirmation prompt
#   SKIP_REBOOT          Set to 1 to skip reboot prompt
#   KEEP_SUNSHINE_CONF   Set to 1 to leave ~/.config/sunshine/sunshine.conf untouched
#   INITRAMFS_BACKEND    Force backend: mkinitcpio, dracut, initramfs-tools
#   SKIP_BOOTLOADER      Set to 1 to skip bootloader cmdline cleanup
#   SKIP_INITRAMFS_REBUILD Set to 1 to remove initramfs config but skip rebuild

set -euo pipefail

SKIP_REBOOT="${SKIP_REBOOT:-0}"
INITRAMFS_BACKEND="${INITRAMFS_BACKEND:-}"
EDID_FIRMWARE="/usr/lib/firmware/edid/virtual-display.bin"

if [[ -t 1 ]]; then
    C_RESET=$'\033[0m'
    C_BOLD=$'\033[1m'
    C_RED=$'\033[31m'
    C_BRIGHT_RED=$'\033[1;31m'
    C_YELLOW=$'\033[1;33m'
    C_BG_RED=$'\033[41m'
    C_BG_YELLOW=$'\033[43m'
else
    C_RESET=''
    C_BOLD=''
    C_RED=''
    C_BRIGHT_RED=''
    C_YELLOW=''
    C_BG_RED=''
    C_BG_YELLOW=''
fi

log() { printf '==> %s\n' "$*"; }
warn() { printf 'warning: %s\n' "$*" >&2; }
die() {
    printf '%berror:%s %s\n' "$C_BRIGHT_RED" "$C_RESET" "$*" >&2
    exit 1
}

confirm_uninstall() {
    if [[ "${I_CONFIRM_UNINSTALL:-0}" == "1" ]]; then
        return
    fi

    printf '\n'
    printf '%b%s%b\n' "$C_BG_RED" \
        "                                                                                " "$C_RESET"
    printf '%b%s%b\n' "$C_BG_RED" \
        "  !!!  UNINSTALL: REVERTING BOOT AND DISPLAY CONFIGURATION  !!!                " "$C_RESET"
    printf '%b%s%b\n' "$C_BG_RED" \
        "                                                                                " "$C_RESET"
    printf '\n'
    printf '%bThis will remove sunshine-vdisplay changes, including:%b\n\n' "$C_BOLD" "$C_RESET"
    printf '  %b•%b Virtual-display kernel parameters from your bootloader\n' "$C_RED" "$C_RESET"
    printf '  %b•%b Initramfs EDID bundling (mkinitcpio / dracut / initramfs-tools)\n' "$C_RED" "$C_RESET"
    printf '  %b•%b %s and copies under /lib/firmware/edid/\n' "$C_RED" "$C_RESET" "$EDID_FIRMWARE"
    printf '  %b•%b Scripts in %b~/bin/%b matching vdisplay-* and create-vdisplay-edid.py\n' \
        "$C_RED" "$C_RESET" "$C_YELLOW" "$C_RESET"
    printf '  %b•%b Sunshine %bglobal_prep_cmd%b hooks for vdisplay-on/off\n' \
        "$C_RED" "$C_RESET" "$C_YELLOW" "$C_RESET"
    printf '  %b•%b %bcap_sys_admin%b capabilities from the sunshine binary\n\n' \
        "$C_RED" "$C_RESET" "$C_YELLOW" "$C_RESET"
    printf '%b%s%b\n' "$C_BG_YELLOW" \
        "  A reboot is required afterward. Have a backup before continuing.            " "$C_RESET"
    printf '%b%s%b\n\n' "$C_BG_YELLOW" \
        "  KDE power-management tweaks from install.sh are NOT reverted automatically.   " "$C_RESET"

    if [[ ! -t 0 ]]; then
        die "non-interactive uninstall blocked — set I_CONFIRM_UNINSTALL=1 to proceed"
    fi

    printf '%bType %byes%b to uninstall sunshine-vdisplay: %b' \
        "$C_BOLD" "$C_BRIGHT_RED" "$C_RESET" "$C_YELLOW"
    read -r answer
    printf '%b' "$C_RESET"
    if [[ "$answer" != "yes" ]]; then
        die "aborted — no changes were made"
    fi
    printf '\n'
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

as_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

detect_initramfs_backend() {
    if [[ -n "$INITRAMFS_BACKEND" ]]; then
        echo "$INITRAMFS_BACKEND"
        return
    fi

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

remove_kernel_params_from_file() {
    local file="$1"
    local connector

    [[ -f "$file" ]] || return 0
    if grep -q 'virtual-display.bin' "$file"; then
        log "Removing virtual-display kernel params from ${file}"
        # The video= flag sits next to the EDID mapping, so collect the
        # connectors that reference our blob before removing the mapping.
        while read -r connector; do
            [[ -n "$connector" ]] || continue
            as_root sed -i -E "s| video=${connector}:e||" "$file"
        done < <(grep -oE '[^ ",=]+:edid/virtual-display\.bin' "$file" | cut -d: -f1 | sort -u)

        # Our mapping may be first, last, or the only entry in a
        # comma-separated drm.edid_firmware list next to other connectors.
        as_root sed -i -E \
            -e 's|drm\.edid_firmware=[^ ",]+:edid/virtual-display\.bin,|drm.edid_firmware=|' \
            -e 's|,[^ ",]+:edid/virtual-display\.bin||' \
            -e 's| drm\.edid_firmware=[^ ",]+:edid/virtual-display\.bin||' \
            -e 's|"drm\.edid_firmware=[^ ",]+:edid/virtual-display\.bin|"|' \
            "$file"
    fi
}

remove_limine() {
    local conf="/etc/default/limine"
    [[ -f "$conf" ]] || return 1

    remove_kernel_params_from_file "$conf"
    need_cmd limine-update
    as_root limine-update
}

remove_grub() {
    local conf="/etc/default/grub"
    [[ -f "$conf" ]] || return 1

    remove_kernel_params_from_file "$conf"

    if command -v update-grub >/dev/null 2>&1; then
        as_root update-grub
    elif command -v grub-mkconfig >/dev/null 2>&1; then
        if [[ -d /boot/grub ]]; then
            as_root grub-mkconfig -o /boot/grub/grub.cfg
        elif [[ -d /boot/grub2 ]]; then
            as_root grub-mkconfig -o /boot/grub2/grub.cfg
        else
            as_root grub-mkconfig -o /boot/grub/grub.cfg
        fi
    elif command -v grub2-mkconfig >/dev/null 2>&1; then
        as_root grub2-mkconfig -o /boot/grub2/grub.cfg
    else
        die "grub config updated but no update-grub/grub-mkconfig found"
    fi
}

remove_systemd_boot() {
    local entry updated=0
    shopt -s nullglob
    for entry in /boot/loader/entries/*.conf; do
        [[ -f "$entry" ]] || continue
        if grep -q 'virtual-display.bin' "$entry"; then
            remove_kernel_params_from_file "$entry"
            updated=1
        fi
    done
    shopt -u nullglob
    [[ "$updated" -eq 1 ]] || return 1
}

remove_bootloader() {
    if [[ "${SKIP_BOOTLOADER:-0}" == "1" ]]; then
        warn "SKIP_BOOTLOADER=1 — skipped bootloader cleanup"
        return
    fi

    if [[ -f /etc/default/limine ]]; then
        remove_limine
    elif [[ -f /etc/default/grub ]]; then
        remove_grub
    elif compgen -G "/boot/loader/entries/*.conf" >/dev/null; then
        remove_systemd_boot || warn "no virtual-display kernel params found in systemd-boot entries"
    else
        warn "no supported bootloader config found; remove kernel params manually if present"
    fi
}

remove_mkinitcpio() {
    local conf="/etc/mkinitcpio.conf"
    [[ -f "$conf" ]] || return 1

    if grep -q 'virtual-display.bin' "$conf"; then
        log "Removing virtual-display.bin from ${conf}"
        as_root sed -i -E 's| ?/usr/lib/firmware/edid/virtual-display\.bin||g' "$conf"
        as_root sed -i -E 's| ?/lib/firmware/edid/virtual-display\.bin||g' "$conf"
    fi
}

remove_dracut() {
    local conf="/etc/dracut.conf.d/99-sunshine-vdisplay.conf"
    if [[ -f "$conf" ]]; then
        log "Removing ${conf}"
        as_root rm -f "$conf"
    fi
}

remove_initramfs_tools() {
    local hook="/etc/initramfs-tools/hooks/sunshine-vdisplay-edid"
    if [[ -f "$hook" ]]; then
        log "Removing ${hook}"
        as_root rm -f "$hook"
    fi
}

rebuild_initramfs() {
    local backend
    backend="$(detect_initramfs_backend)"

    case "$backend" in
        mkinitcpio)
            remove_mkinitcpio || warn "mkinitcpio.conf not found"
            if [[ "${SKIP_INITRAMFS_REBUILD:-0}" == "1" ]]; then
                warn "SKIP_INITRAMFS_REBUILD=1 — skipped mkinitcpio -P"
            else
                log "Rebuilding initramfs with mkinitcpio"
                as_root mkinitcpio -P
            fi
            ;;
        dracut)
            remove_dracut
            if [[ "${SKIP_INITRAMFS_REBUILD:-0}" == "1" ]]; then
                warn "SKIP_INITRAMFS_REBUILD=1 — skipped dracut"
            else
                log "Rebuilding initramfs with dracut"
                if as_root dracut --regenerate-all -f 2>/dev/null; then
                    :
                else
                    as_root dracut -f
                fi
            fi
            ;;
        initramfs-tools)
            remove_initramfs_tools
            if [[ "${SKIP_INITRAMFS_REBUILD:-0}" == "1" ]]; then
                warn "SKIP_INITRAMFS_REBUILD=1 — skipped update-initramfs"
            else
                log "Rebuilding initramfs with update-initramfs"
                as_root update-initramfs -u -k all
            fi
            ;;
        *)
            warn "unknown initramfs backend; remove initramfs config manually"
            ;;
    esac
}

remove_edid_firmware() {
    local path
    for path in \
        "$EDID_FIRMWARE" \
        /lib/firmware/edid/virtual-display.bin; do
        if [[ -f "$path" ]]; then
            log "Removing ${path}"
            as_root rm -f "$path"
        fi
    done
}

restore_physical_display() {
    if [[ -x "${HOME}/bin/vdisplay-off.sh" ]]; then
        log "Restoring physical display via vdisplay-off.sh"
        "${HOME}/bin/vdisplay-off.sh" || warn "vdisplay-off.sh failed; check displays manually"
    fi
}

remove_user_scripts() {
    local path
    for path in \
        "${HOME}/bin/create-vdisplay-edid.py" \
        "${HOME}/bin/vdisplay-common.sh" \
        "${HOME}/bin/vdisplay-common.local.sh" \
        "${HOME}/bin/vdisplay-on.sh" \
        "${HOME}/bin/vdisplay-off.sh"; do
        if [[ -e "$path" ]]; then
            log "Removing ${path}"
            rm -f "$path"
        fi
    done
}

cleanup_sunshine_config() {
    local sunshine_conf="${HOME}/.config/sunshine/sunshine.conf"
    local backup

    if [[ "${KEEP_SUNSHINE_CONF:-0}" == "1" ]]; then
        warn "KEEP_SUNSHINE_CONF=1 — leaving ${sunshine_conf} untouched"
        return
    fi

    [[ -f "$sunshine_conf" ]] || {
        warn "no sunshine.conf found; skipped Sunshine config cleanup"
        return
    }

    if ! grep -q 'vdisplay-on\.sh' "$sunshine_conf"; then
        warn "sunshine.conf does not reference vdisplay-on.sh; skipped automatic edits"
        return
    fi

    backup="${sunshine_conf}.bak.uninstall.$(date +%Y%m%d%H%M%S)"
    log "Backing up ${sunshine_conf} to ${backup}"
    cp "$sunshine_conf" "$backup"

    log "Removing vdisplay global_prep_cmd from ${sunshine_conf}"
    sed -i '/global_prep_cmd.*vdisplay-on\.sh/d' "$sunshine_conf"

    warn "review ${sunshine_conf} for remaining installer settings (capture, encoder, output_name)"
    warn "restore from ${backup} if you want the previous file back"
}

remove_sunshine_capabilities() {
    local sunshine_bin cap_path

    sunshine_bin="$(command -v sunshine 2>/dev/null)" || {
        warn "sunshine not installed; skipped capability removal"
        return
    }

    cap_path="$(readlink -f "$sunshine_bin")"
    if getcap "$cap_path" 2>/dev/null | grep -q .; then
        log "Removing file capabilities from ${cap_path}"
        as_root setcap -r "$cap_path" || warn "setcap -r failed on ${cap_path}"
    else
        log "No file capabilities set on ${cap_path}"
    fi
}

remove_state_dir() {
    if [[ -d "${HOME}/.cache/vdisplay" ]]; then
        log "Removing ${HOME}/.cache/vdisplay"
        rm -rf "${HOME}/.cache/vdisplay"
    fi
}

restart_sunshine() {
    if systemctl --user is-enabled sunshine.service >/dev/null 2>&1 \
        || systemctl --user is-enabled app-dev.lizardbyte.app.Sunshine.service >/dev/null 2>&1; then
        log "Restarting Sunshine"
        systemctl --user restart sunshine.service 2>/dev/null \
            || systemctl --user restart app-dev.lizardbyte.app.Sunshine.service 2>/dev/null \
            || true
    fi
}

main() {
    confirm_uninstall
    need_cmd sudo

    log "Initramfs backend: $(detect_initramfs_backend)"

    restore_physical_display
    cleanup_sunshine_config
    remove_user_scripts
    remove_bootloader
    rebuild_initramfs
    remove_edid_firmware
    remove_sunshine_capabilities
    remove_state_dir
    restart_sunshine

    cat <<'EOF'

Uninstall complete.

Removed:
  - bootloader virtual-display kernel parameters
  - initramfs EDID bundling
  - virtual-display.bin firmware
  - ~/bin/vdisplay-* scripts
  - Sunshine global_prep_cmd hooks for vdisplay-on/off

Not reverted automatically:
  - KDE power-management settings changed by install.sh
  - other Sunshine settings (capture, encoder, output_name) — review ~/.config/sunshine/sunshine.conf

Next:
  sudo reboot

EOF

    if [[ "${SKIP_REBOOT}" != "1" && -t 0 ]]; then
        read -r -p "Reboot now? [y/N] " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            as_root reboot
        fi
    elif [[ "${SKIP_REBOOT}" != "1" ]]; then
        echo "Reboot manually when ready: sudo reboot"
    fi
}

# Run the uninstaller when it is executed, including `curl ... | bash` — reading
# the script from stdin leaves BASH_SOURCE unset. Skip main when a test sources
# this file to reach remove_kernel_params_from_file.
if [[ -z "${BASH_SOURCE[0]:-}" || "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
