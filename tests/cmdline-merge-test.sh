#!/usr/bin/env bash
# Bootloader kernel command line tests: EDID mappings are merged, never replaced,
# and removed cleanly again.
#
# No root, GPU, or reboot is required.
#
# Usage:
#   ./tests/cmdline-merge-test.sh

set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"

# shellcheck source=scripts/vdisplay-cmdline.sh
source "${repo_root}/scripts/vdisplay-cmdline.sh"
# shellcheck source=scripts/uninstall.sh
source "${repo_root}/scripts/uninstall.sh"

# uninstall.sh edits through as_root; these tests run unprivileged.
as_root() { "$@"; }

work="$(mktemp -d "${TMPDIR:-/tmp}/vdisplay-cmdline.XXXXXX")"
trap 'rm -rf "$work"' EXIT

failures=0

fail() {
    printf 'FAIL: %s\n' "$*" >&2
    failures=$((failures + 1))
}

pass() { printf 'ok: %s\n' "$*"; }

# expect_merge <name> <style> <connector> <input> <expected>
expect_merge() {
    local name="$1" style="$2" connector="$3" input="$4" expected="$5"
    local file="${work}/${name}.conf" rc=0

    printf '%s\n' "$input" >"$file"
    cmdline_merge_params "$style" "$file" "$connector" >"${file}.new" || rc=$?

    if [[ "$rc" -ne 0 ]]; then
        fail "${name}: expected exit 0, got ${rc}"
        return
    fi

    if diff -u <(printf '%s\n' "$expected") "${file}.new" >"${file}.diff"; then
        pass "$name"
    else
        fail "$name"
        cat "${file}.diff" >&2
    fi
}

# expect_remove <name> <input> <expected>
expect_remove() {
    local name="$1" input="$2" expected="$3"
    local file="${work}/${name}.conf"

    printf '%s\n' "$input" >"$file"
    remove_kernel_params_from_file "$file"

    if diff -u <(printf '%s\n' "$expected") "$file" >"${file}.diff"; then
        pass "$name"
    else
        fail "$name"
        cat "${file}.diff" >&2
    fi
}

# A host without any EDID firmware mapping gets the standalone parameter.
expect_merge \
    "limine-add-to-fresh-host" limine HDMI-A-2 \
    'KERNEL_CMDLINE[default]+=" root=UUID=abc quiet"' \
    'KERNEL_CMDLINE[default]+=" root=UUID=abc quiet drm.edid_firmware=HDMI-A-2:edid/virtual-display.bin video=HDMI-A-2:e"'

# The reported case: an existing mapping for another connector must survive, and
# a host with two KERNEL_CMDLINE[default]+= lines must not get the parameters
# twice.
expect_merge \
    "limine-merge-and-no-duplicates" limine HDMI-A-2 \
    'KERNEL_CMDLINE[default]+=" root=UUID=abc quiet"
KERNEL_CMDLINE[default]+=" drm.edid_firmware=HDMI-A-1:edid/4k60-dummy.bin"' \
    'KERNEL_CMDLINE[default]+=" root=UUID=abc quiet"
KERNEL_CMDLINE[default]+=" drm.edid_firmware=HDMI-A-1:edid/4k60-dummy.bin,HDMI-A-2:edid/virtual-display.bin video=HDMI-A-2:e"'

expect_merge \
    "grub-merge-into-existing-mapping" grub HDMI-A-2 \
    'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash drm.edid_firmware=eDP-1:edid/panel.bin"' \
    'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash drm.edid_firmware=eDP-1:edid/panel.bin,HDMI-A-2:edid/virtual-display.bin video=HDMI-A-2:e"'

# A stale mapping of ours that sits first in the list is replaced, not duplicated.
expect_merge \
    "limine-replace-leading-stale-mapping" limine HDMI-A-2 \
    'KERNEL_CMDLINE[default,fallback]+=" quiet drm.edid_firmware=HDMI-A-2:edid/virtual-display.bin,eDP-1:edid/panel.bin"' \
    'KERNEL_CMDLINE[default,fallback]+=" quiet drm.edid_firmware=eDP-1:edid/panel.bin,HDMI-A-2:edid/virtual-display.bin video=HDMI-A-2:e"'

expect_merge \
    "systemd-boot-merge-into-existing-mapping" systemd-boot HDMI-A-2 \
    'options root=/dev/nvme0n1p2 rw drm.edid_firmware=HDMI-A-1:edid/dummy.bin' \
    'options root=/dev/nvme0n1p2 rw drm.edid_firmware=HDMI-A-1:edid/dummy.bin,HDMI-A-2:edid/virtual-display.bin video=HDMI-A-2:e'

# A hand-edited config without the leading space is normalized, not duplicated.
expect_merge \
    "limine-normalize-hand-edited-entry" limine HDMI-A-2 \
    'KERNEL_CMDLINE[default]+="drm.edid_firmware=HDMI-A-2:edid/virtual-display.bin"' \
    'KERNEL_CMDLINE[default]+=" drm.edid_firmware=HDMI-A-2:edid/virtual-display.bin video=HDMI-A-2:e"'

# Re-running the installer must not change the file again.
idempotent_file="${work}/idempotent.conf"
printf '%s\n' \
    'KERNEL_CMDLINE[default]+=" root=UUID=abc quiet"' \
    'KERNEL_CMDLINE[default]+=" drm.edid_firmware=HDMI-A-1:edid/4k60-dummy.bin"' \
    >"$idempotent_file"
cmdline_merge_params limine "$idempotent_file" HDMI-A-2 >"$idempotent_file.first"
cmdline_merge_params limine "$idempotent_file.first" HDMI-A-2 >"$idempotent_file.second"
if diff -u "$idempotent_file.first" "$idempotent_file.second" >"$idempotent_file.diff"; then
    pass "merge-is-idempotent"
else
    fail "merge-is-idempotent"
    cat "$idempotent_file.diff" >&2
fi

if [[ "$(grep -c 'drm\.edid_firmware=' "$idempotent_file.second")" -eq 1 ]] \
    && [[ "$(grep -c 'video=HDMI-A-2:e' "$idempotent_file.second")" -eq 1 ]]; then
    pass "merge-writes-parameters-once"
else
    fail "merge-writes-parameters-once"
    cat "$idempotent_file.second" >&2
fi

# A config without a kernel command line entry cannot take the parameters.
no_entry_file="${work}/no-entry.conf"
printf 'ESP_PATH="/boot"\n' >"$no_entry_file"
no_entry_rc=0
cmdline_merge_params limine "$no_entry_file" HDMI-A-2 >"${no_entry_file}.new" || no_entry_rc=$?
if [[ "$no_entry_rc" -eq 3 ]] && [[ ! -s "${no_entry_file}.new" ]]; then
    pass "merge-reports-missing-cmdline-line"
else
    fail "merge-reports-missing-cmdline-line (exit ${no_entry_rc})"
fi

# Uninstall restores the previous state in both parameter shapes.
expect_remove \
    "uninstall-restores-merged-mapping" \
    'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash drm.edid_firmware=eDP-1:edid/panel.bin,HDMI-A-2:edid/virtual-display.bin video=HDMI-A-2:e"' \
    'GRUB_CMDLINE_LINUX_DEFAULT="quiet splash drm.edid_firmware=eDP-1:edid/panel.bin"'

expect_remove \
    "uninstall-restores-standalone-mapping" \
    'KERNEL_CMDLINE[default]+=" quiet drm.edid_firmware=HDMI-A-2:edid/virtual-display.bin video=HDMI-A-2:e"' \
    'KERNEL_CMDLINE[default]+=" quiet"'

# Both scripts must still run main() when read from stdin, which is how the
# documented `curl ... | bash` one-liners feed them. Under `set -u` that mode
# leaves BASH_SOURCE unset, so an entry-point guard has to allow it.
expect_runs_from_stdin() {
    local name="$1" script="$2" marker="$3"
    local out rc=0

    out="$(bash <"${repo_root}/${script}" 2>&1)" || rc=$?

    if [[ "$rc" -ne 0 ]] && [[ "$out" == *"$marker"* ]]; then
        pass "$name"
    else
        fail "${name}: expected '${marker}' (exit ${rc})"
        printf '%s\n' "$out" | tail -n 3 >&2
    fi
}

# Neither script may touch the system on the way there: both stop at the
# non-interactive confirmation prompt.
expect_runs_from_stdin \
    "install-runs-when-read-from-stdin" scripts/install.sh \
    "non-interactive install blocked"
expect_runs_from_stdin \
    "uninstall-runs-when-read-from-stdin" scripts/uninstall.sh \
    "non-interactive uninstall blocked"

if [[ "$failures" -eq 0 ]]; then
    printf '\nAll command line tests passed.\n'
else
    printf '\n%d command line test(s) failed.\n' "$failures" >&2
    exit 1
fi
