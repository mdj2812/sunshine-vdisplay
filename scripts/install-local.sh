#!/usr/bin/env bash
# Install virtual display scripts and regenerate EDID firmware.
set -euo pipefail

repo_root="$(cd "$(dirname "$0")/.." && pwd)"
install -d "$HOME/bin"
install -m 755 "$repo_root/scripts/"*.py "$repo_root/scripts/"*.sh "$HOME/bin/"

python3 "$HOME/bin/create-vdisplay-edid.py" /tmp/virtual-display.bin
sudo install -d /usr/lib/firmware/edid
sudo install -m 644 /tmp/virtual-display.bin /usr/lib/firmware/edid/virtual-display.bin

install -d "$HOME/.config/sunshine"
sed "s|__HOME__|${HOME}|g" "$repo_root/config/sunshine.conf" > "$HOME/.config/sunshine/sunshine.conf"

echo "Installed scripts to ~/bin and sunshine.conf to ~/.config/sunshine/"
echo
echo "Next, customize and merge system snippets:"
echo "  1. Pick an unused GPU connector (see README)"
echo "  2. system/mkinitcpio.files.snippet   -> /etc/mkinitcpio.conf"
echo "  3. system/limine.cmdline.snippet     -> /etc/default/limine (or GRUB/systemd-boot)"
echo "  4. sudo mkinitcpio -P && sudo limine-update && sudo reboot"
echo "  5. Set output_name in sunshine.conf from the KMS monitor list in sunshine.log"
