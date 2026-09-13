#!/usr/bin/env bash
# Full installer for NVIDIA + KDE Wayland Sunshine virtual display.
#
# One-liner:
#   curl -fsSL https://raw.githubusercontent.com/mdj2812/sunshine-vdisplay/main/scripts/install.sh | bash
#
# Uninstall:
#   ./scripts/uninstall.sh
#
# With options:
#   VDISPLAY=HDMI-A-1 PDISPLAY=DP-3 bash install.sh
#
# Environment variables:
#   VDISPLAY          Virtual connector (default: first disconnected HDMI/DP)
#   PDISPLAY          Physical connector (default: first connected non-virtual)
#   RES               Virtual resolution (default: 2560x1600@120)
#   PDISPLAY_RES      Physical resolution (default: 2560x1440@143.99)
#   SUNSHINE_OUTPUT   Sunshine KMS output index (default: 0)
#   SKIP_REBOOT       Set to 1 to skip reboot prompt
#   I_HAVE_BACKED_UP     Set to 1 to skip the startup backup confirmation
#   KEEP_SUNSHINE_CONF   Set to 1 to leave ~/.config/sunshine/sunshine.conf untouched
#   MERGE_SUNSHINE_CONF  Set to 1 to merge only global_prep_cmd into an existing sunshine.conf
#   REPO_URL             Git clone URL (used when script is piped from curl)
#   INITRAMFS_BACKEND    Force backend: mkinitcpio, dracut, initramfs-tools
#   SKIP_BOOTLOADER      Set to 1 to skip bootloader cmdline changes (for VM smoke tests)
#   SKIP_INITRAMFS_REBUILD Set to 1 to write initramfs config but skip rebuild
#   SKIP_POWER_MGMT      Set to 1 to skip KDE power-management tweaks

set -euo pipefail

VDISPLAY="${VDISPLAY:-}"
PDISPLAY="${PDISPLAY:-}"
RES="${RES:-2560x1600@120}"
PDISPLAY_RES="${PDISPLAY_RES:-2560x1440@143.99}"
SUNSHINE_OUTPUT="${SUNSHINE_OUTPUT:-0}"
REPO_URL="${REPO_URL:-https://github.com/mdj2812/sunshine-vdisplay.git}"
WORK_DIR="${WORK_DIR:-$(mktemp -d /tmp/sunshine-vdisplay.XXXXXX)}"
KEEP_WORK_DIR="${KEEP_WORK_DIR:-0}"
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

confirm_backup() {
    if [[ "${I_HAVE_BACKED_UP:-0}" == "1" ]]; then
        return
    fi

    printf '\n'
    printf '%b%s%b\n' "$C_BG_RED" \
        "                                                                                " "$C_RESET"
    printf '%b%s%b\n' "$C_BG_RED" \
        "  !!!  DANGER: THIS SCRIPT MODIFIES BOOT AND DISPLAY CONFIGURATION  !!!         " "$C_RESET"
    printf '%b%s%b\n' "$C_BG_RED" \
        "                                                                                " "$C_RESET"
    printf '\n'
    printf '%b%bDO NOT RUN THIS ON A PRODUCTION MACHINE WITHOUT A RECENT BACKUP.%b\n\n' \
        "$C_BOLD" "$C_BRIGHT_RED" "$C_RESET"
    printf '%bThis installer will:%b\n' "$C_BOLD" "$C_RESET"
    printf '  %b•%b Rebuild your %binitramfs%b\n' "$C_RED" "$C_RESET" "$C_YELLOW" "$C_RESET"
    printf '  %b•%b Edit your %bbootloader kernel command line%b (GRUB / Limine / systemd-boot)\n' \
        "$C_RED" "$C_RESET" "$C_YELLOW" "$C_RESET"
    printf '  %b•%b Install firmware under %b/usr/lib/firmware/edid/%b\n' \
        "$C_RED" "$C_RESET" "$C_YELLOW" "$C_RESET"
    printf '  %b•%b Overwrite %b~/.config/sunshine/sunshine.conf%b and scripts in %b~/bin/%b\n\n' \
        "$C_RED" "$C_RESET" "$C_YELLOW" "$C_RESET" "$C_YELLOW" "$C_RESET"
    printf '%bIf anything goes wrong you may get:%b\n' "$C_BOLD" "$C_RESET"
    printf '  %b-%b An unbootable system until you restore from backup\n' "$C_BRIGHT_RED" "$C_RESET"
    printf '  %b-%b A black screen or wrong display until config is reverted\n' "$C_BRIGHT_RED" "$C_RESET"
    printf '  %b-%b Broken Sunshine capture until settings are fixed\n\n' "$C_BRIGHT_RED" "$C_RESET"
    printf '%b%s%b\n' "$C_BG_YELLOW" \
        "  Create a snapshot, btrfs subvolume backup, or Timeshift restore point NOW.  " "$C_RESET"
    printf '%b%s%b\n\n' "$C_BG_YELLOW" \
        "  Know how to undo initramfs + bootloader changes before you continue.         " "$C_RESET"

    if [[ ! -t 0 ]]; then
        die "non-interactive install blocked — set I_HAVE_BACKED_UP=1 only after you have a backup"
    fi

    printf '%bType %byes%b to confirm you have a backup and accept the risk: %b' \
        "$C_BOLD" "$C_BRIGHT_RED" "$C_RESET" "$C_YELLOW"
    read -r answer
    printf '%b' "$C_RESET"
    if [[ "$answer" != "yes" ]]; then
        die "aborted — no changes were made; back up first, then run again"
    fi
    printf '\n'
}

need_cmd() {
    command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

cleanup() {
    if [[ "$KEEP_WORK_DIR" != "1" && -d "$WORK_DIR" ]]; then
        rm -rf "$WORK_DIR"
    fi
}
trap cleanup EXIT

as_root() {
    if [[ "${EUID}" -eq 0 ]]; then
        "$@"
    else
        sudo "$@"
    fi
}

connector_status() {
    local connector="$1"
    local path
    for path in /sys/class/drm/card*-"${connector}"/status; do
        [[ -f "$path" ]] || continue
        cat "$path"
        return 0
    done
    return 1
}

list_connectors() {
    local path connector
    for path in /sys/class/drm/card*-*; do
        [[ -f "$path/status" ]] || continue
        connector="$(basename "$path")"
        connector="${connector#card*-}"
        printf '%s:%s\n' "$connector" "$(cat "$path/status")"
    done
}

pick_virtual_connector() {
    local connector status
    while IFS=: read -r connector status; do
        [[ "$status" == "disconnected" ]] || continue
        case "$connector" in
            HDMI-*)
                echo "$connector"
                return 0
                ;;
        esac
    done < <(list_connectors)

    while IFS=: read -r connector status; do
        [[ "$status" == "disconnected" ]] || continue
        case "$connector" in
            DP-* | eDP-*)
                echo "$connector"
                return 0
                ;;
        esac
    done < <(list_connectors)
    return 1
}

pick_physical_connector() {
    local connector status virtual="$1"
    while IFS=: read -r connector status; do
        [[ "$status" == "connected" ]] || continue
        [[ "$connector" == "$virtual" ]] && continue
        case "$connector" in
            HDMI-* | DP-* | eDP-*)
                echo "$connector"
                return 0
                ;;
        esac
    done < <(list_connectors)
    return 1
}

prepare_repo() {
    if [[ -n "${SUNSHINE_VDISPLAY_REPO:-}" && -f "${SUNSHINE_VDISPLAY_REPO}/scripts/create-vdisplay-edid.py" ]]; then
        REPO_ROOT="${SUNSHINE_VDISPLAY_REPO}"
        return
    fi

    if [[ -n "${BASH_SOURCE[0]:-}" && "${BASH_SOURCE[0]}" != bash && -f "${BASH_SOURCE[0]}" ]]; then
        local maybe_root
        maybe_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
        if [[ -f "${maybe_root}/scripts/create-vdisplay-edid.py" ]]; then
            REPO_ROOT="$maybe_root"
            return
        fi
    fi

    need_cmd git
    log "Fetching repository into ${WORK_DIR}"
    git clone --depth 1 "$REPO_URL" "$WORK_DIR"
    REPO_ROOT="$WORK_DIR"
}

merge_mkinitcpio() {
    local conf="/etc/mkinitcpio.conf"

    [[ -f "$conf" ]] || return 1

    if grep -q 'virtual-display.bin' "$conf"; then
        log "mkinitcpio.conf already references virtual-display.bin"
        return
    fi

    log "Updating ${conf}"
    if grep -q '^FILES=' "$conf"; then
        as_root sed -i "s|^FILES=(\\(.*\\))|FILES=(\\1 ${EDID_FIRMWARE})|" "$conf"
    else
        as_root bash -c "echo 'FILES=(${EDID_FIRMWARE})' >> '$conf'"
    fi
}

merge_dracut() {
    local conf="/etc/dracut.conf.d/99-sunshine-vdisplay.conf"

    log "Updating ${conf}"
    as_root install -d /etc/dracut.conf.d
    as_root tee "$conf" >/dev/null <<EOF
# Added by sunshine-vdisplay install.sh
install_items+=" ${EDID_FIRMWARE} "
EOF
}

merge_initramfs_tools() {
    local hook="/etc/initramfs-tools/hooks/sunshine-vdisplay-edid"

    log "Installing initramfs-tools hook ${hook}"
    as_root install -d /etc/initramfs-tools/hooks
    as_root tee "$hook" >/dev/null <<'EOF'
#!/bin/sh
PREREQ=""
prereqs() { echo "$PREREQ"; }

case "$1" in
    prereqs) prereqs; exit 0 ;;
esac

. /usr/share/initramfs-tools/hook-functions

mkdir -p "${DESTDIR}/usr/lib/firmware/edid"
cp -a /usr/lib/firmware/edid/virtual-display.bin "${DESTDIR}/usr/lib/firmware/edid/virtual-display.bin"
exit 0
EOF
    as_root chmod 755 "$hook"
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

detect_distro_label() {
    if [[ -f /etc/os-release ]]; then
        # shellcheck disable=SC1091
        source /etc/os-release
        printf '%s' "${PRETTY_NAME:-${NAME:-Linux}}"
        return
    fi
    echo "Linux"
}

configure_initramfs() {
    local backend
    backend="$(detect_initramfs_backend)"

    case "$backend" in
        mkinitcpio)
            merge_mkinitcpio || die "failed to configure mkinitcpio"
            if [[ "${SKIP_INITRAMFS_REBUILD:-0}" == "1" ]]; then
                warn "SKIP_INITRAMFS_REBUILD=1 — skipped mkinitcpio -P"
            else
                log "Rebuilding initramfs with mkinitcpio"
                as_root mkinitcpio -P
            fi
            ;;
        dracut)
            merge_dracut
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
            merge_initramfs_tools
            if [[ "${SKIP_INITRAMFS_REBUILD:-0}" == "1" ]]; then
                warn "SKIP_INITRAMFS_REBUILD=1 — skipped update-initramfs"
            else
                log "Rebuilding initramfs with update-initramfs"
                as_root update-initramfs -u -k all
            fi
            ;;
        *)
            die "unsupported initramfs backend; install mkinitcpio, dracut, or initramfs-tools"
            ;;
    esac
}

kernel_param_snippet() {
    printf 'drm.edid_firmware=%s:edid/virtual-display.bin video=%s:e' "$VDISPLAY" "$VDISPLAY"
}

merge_limine() {
    local conf="/etc/default/limine"
    local snippet

    [[ -f "$conf" ]] || return 1
    snippet="$(kernel_param_snippet)"

    if grep -q 'virtual-display.bin' "$conf"; then
        log "Replacing existing virtual-display kernel params in ${conf}"
        as_root sed -i -E 's| drm\.edid_firmware=[^ "]+:edid/virtual-display\.bin video=[^ "]+:e||g' "$conf"
    fi

    if ! grep -qF "$snippet" "$conf"; then
        log "Updating ${conf}"
        as_root sed -i "s|^KERNEL_CMDLINE\[default\]+=\"\(.*\)\"|KERNEL_CMDLINE[default]+=\"\1 ${snippet}\"|" "$conf"
    fi

    need_cmd limine-update
    as_root limine-update
}

merge_grub() {
    local conf="/etc/default/grub"
    local snippet

    [[ -f "$conf" ]] || return 1
    snippet="$(kernel_param_snippet)"

    if grep -q 'virtual-display.bin' "$conf"; then
        as_root sed -i -E 's| drm\.edid_firmware=[^ "]+:edid/virtual-display\.bin video=[^ "]+:e||g' "$conf"
    fi

    if ! grep -qF "$snippet" "$conf"; then
        log "Updating ${conf}"
        as_root sed -i "s/^GRUB_CMDLINE_LINUX_DEFAULT=\"\\(.*\\)\"/GRUB_CMDLINE_LINUX_DEFAULT=\"\\1 ${snippet}\"/" "$conf"
    fi

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

merge_systemd_boot() {
    local entry snippet updated=0

    snippet="$(kernel_param_snippet)"
    shopt -s nullglob
    for entry in /boot/loader/entries/*.conf; do
        [[ -f "$entry" ]] || continue
        if grep -q '^options ' "$entry"; then
            if grep -q 'virtual-display.bin' "$entry"; then
                as_root sed -i -E 's| drm\.edid_firmware=[^ ]+:edid/virtual-display\.bin video=[^ ]+:e||g' "$entry"
            fi
            as_root sed -i "s|^options \\(.*\\)|options \\1 ${snippet}|" "$entry"
            updated=1
        fi
    done
    shopt -u nullglob
    [[ "$updated" -eq 1 ]] || return 1
    log "Updated systemd-boot entries"
}

configure_bootloader() {
    if [[ "${SKIP_BOOTLOADER:-0}" == "1" ]]; then
        warn "SKIP_BOOTLOADER=1 — skipped bootloader configuration"
        return
    fi

    if [[ -f /etc/default/limine ]]; then
        merge_limine
    elif [[ -f /etc/default/grub ]]; then
        merge_grub
    elif compgen -G "/boot/loader/entries/*.conf" >/dev/null; then
        merge_systemd_boot
    else
        die "unsupported bootloader; manually add: $(kernel_param_snippet)"
    fi
}

install_edid_and_scripts() {
    need_cmd python3
    log "Generating EDID"
    python3 "${REPO_ROOT}/scripts/create-vdisplay-edid.py" /tmp/virtual-display.bin

    log "Installing EDID firmware"
    as_root install -d /usr/lib/firmware/edid /lib/firmware/edid
    as_root install -m 644 /tmp/virtual-display.bin "$EDID_FIRMWARE"
    as_root install -m 644 /tmp/virtual-display.bin /lib/firmware/edid/virtual-display.bin

    log "Installing user scripts to ${HOME}/bin"
    install -d "${HOME}/bin"
    install -m 755 "${REPO_ROOT}/scripts/"*.py "${HOME}/bin/"
    install -m 755 "${REPO_ROOT}/scripts/vdisplay-common.sh" "${HOME}/bin/"
    install -m 755 "${REPO_ROOT}/scripts/vdisplay-on.sh" "${HOME}/bin/"
    install -m 755 "${REPO_ROOT}/scripts/vdisplay-off.sh" "${HOME}/bin/"

    cat >"${HOME}/bin/vdisplay-common.local.sh" <<EOF
# Local overrides generated by install.sh
VDISPLAY="${VDISPLAY}"
PDISPLAY="${PDISPLAY}"
RES="${RES}"
PDISPLAY_RES="${PDISPLAY_RES}"
EOF
}

install_sunshine_config() {
    local sunshine_bin cap_path
    local sunshine_conf="${HOME}/.config/sunshine/sunshine.conf"
    local template backup prep_cmd

    install -d "${HOME}/.config/sunshine"
    template="$(mktemp)"
    sed "s|__HOME__|${HOME}|g" "${REPO_ROOT}/config/sunshine.conf" \
        | sed "s|^output_name = .*|output_name = ${SUNSHINE_OUTPUT}|" \
            >"$template"
    prep_cmd="$(grep '^global_prep_cmd' "$template")"

    if [[ "${KEEP_SUNSHINE_CONF:-0}" == "1" ]]; then
        warn "KEEP_SUNSHINE_CONF=1 — leaving ${sunshine_conf} untouched"
    elif [[ -f "$sunshine_conf" ]]; then
        backup="${sunshine_conf}.bak.sunshine-vdisplay.$(date +%Y%m%d%H%M%S)"
        log "Backing up ${sunshine_conf} to ${backup}"
        cp "$sunshine_conf" "$backup"

        if [[ "${MERGE_SUNSHINE_CONF:-0}" == "1" ]]; then
            log "Merging vdisplay global_prep_cmd into ${sunshine_conf}"
            sed -i '/global_prep_cmd.*vdisplay-on\.sh/d' "$sunshine_conf"
            printf '%s\n' "$prep_cmd" >>"$sunshine_conf"
            warn "merged global_prep_cmd only; review ${sunshine_conf} or restore from ${backup}"
        else
            cp "$template" "$sunshine_conf"
            warn "replaced ${sunshine_conf}; previous version saved as ${backup}"
        fi
    else
        cp "$template" "$sunshine_conf"
    fi
    rm -f "$template"

    if sunshine_bin="$(command -v sunshine 2>/dev/null)"; then
        cap_path="$(readlink -f "$sunshine_bin")"
        log "Ensuring Sunshine capabilities on ${cap_path}"
        as_root setcap cap_sys_admin,cap_sys_nice+p "$cap_path" || warn "setcap failed; KMS capture may not work"
    else
        warn "sunshine not installed; skipped setcap"
    fi

    if systemctl --user is-enabled sunshine.service >/dev/null 2>&1 \
        || systemctl --user is-enabled app-dev.lizardbyte.app.Sunshine.service >/dev/null 2>&1; then
        log "Restarting Sunshine"
        systemctl --user restart sunshine.service 2>/dev/null \
            || systemctl --user restart app-dev.lizardbyte.app.Sunshine.service 2>/dev/null \
            || true
    fi
}

configure_power_management() {
    if [[ "${SKIP_POWER_MGMT:-0}" == "1" ]]; then
        warn "SKIP_POWER_MGMT=1 — skipped power management tweaks"
        return
    fi

    command -v kwriteconfig6 >/dev/null 2>&1 || {
        warn "kwriteconfig6 not found; skipped power management tweaks"
        return
    }

    log "Disabling screen blanking for virtual display stability"
    kwriteconfig6 --file kscreenlockerrc --group Daemon --key Autolock false
    kwriteconfig6 --file powermanagementprofilesrc --group AC --group DPMSControl --key idleTime 0
    kwriteconfig6 --file powermanagementprofilesrc --group AC --group DPMSControl --key lockBeforeTurnOff 0
    kwriteconfig6 --file powermanagementprofilesrc --group AC --group DimDisplay --key idleTime 0
    kwriteconfig6 --file powermanagementprofilesrc --group Battery --group DPMSControl --key idleTime 0
    kwriteconfig6 --file powermanagementprofilesrc --group Battery --group DimDisplay --key idleTime 0
}

rebuild_initramfs() {
    configure_initramfs
}

main() {
    confirm_backup
    need_cmd sudo
    prepare_repo

    if [[ -z "$VDISPLAY" ]]; then
        VDISPLAY="$(pick_virtual_connector)" || die "could not auto-detect a disconnected HDMI/DP connector; set VDISPLAY="
    fi
    if [[ -z "$PDISPLAY" ]]; then
        PDISPLAY="$(pick_physical_connector "$VDISPLAY")" || warn "could not auto-detect physical connector; set PDISPLAY="
    fi

    log "Detected distro: $(detect_distro_label)"
    log "Initramfs backend: $(detect_initramfs_backend)"
    log "Virtual connector: ${VDISPLAY}"
    [[ -n "$PDISPLAY" ]] && log "Physical connector: ${PDISPLAY}"
    log "Virtual mode: ${RES}"

    install_edid_and_scripts
    configure_initramfs
    configure_bootloader
    install_sunshine_config
    configure_power_management

    cat <<EOF

Installation complete.

Configured:
  distro          : $(detect_distro_label)
  initramfs       : $(detect_initramfs_backend)
  virtual display : ${VDISPLAY}
  physical display: ${PDISPLAY:-unknown}
  sunshine output : ${SUNSHINE_OUTPUT}

Next:
  sudo reboot

After reboot:
  ~/bin/vdisplay-on.sh
  cat /sys/class/drm/card*-${VDISPLAY}/status

EOF

    if [[ "${SKIP_REBOOT:-0}" != "1" && -t 0 ]]; then
        read -r -p "Reboot now? [y/N] " answer
        if [[ "$answer" =~ ^[Yy]$ ]]; then
            as_root reboot
        fi
    elif [[ "${SKIP_REBOOT:-0}" != "1" ]]; then
        echo "Reboot manually when ready: sudo reboot"
    fi
}

main "$@"
