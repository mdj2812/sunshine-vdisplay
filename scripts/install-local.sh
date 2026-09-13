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
install -m 644 "$repo_root/config/sunshine.conf" "$HOME/.config/sunshine/sunshine.conf"

echo "Installed scripts to ~/bin and sunshine.conf to ~/.config/sunshine/"
echo "System files still need manual merge:"
echo "  - system/mkinitcpio.files.snippet -> /etc/mkinitcpio.conf"
echo "  - system/limine.cmdline.snippet   -> /etc/default/limine"
echo "Then run: sudo mkinitcpio -P && sudo limine-update && sudo reboot"
