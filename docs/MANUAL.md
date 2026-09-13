# Manual setup

Use this if you prefer not to run the installer, or need to adapt for another distro. For automated setup, see [INSTALL.md](INSTALL.md).

## 1. Find connectors

```bash
for p in /sys/class/drm/card*-*; do
  [ -f "$p/status" ] && echo "$(basename "$p"): $(cat "$p/status")"
done
```

Pick a **disconnected** port for the virtual display.

## 2. Generate and install EDID

```bash
python3 scripts/create-vdisplay-edid.py /tmp/virtual-display.bin
sudo install -d /usr/lib/firmware/edid
sudo cp /tmp/virtual-display.bin /usr/lib/firmware/edid/virtual-display.bin
```

## 3. Kernel parameters

Both are required on the NVIDIA proprietary driver:

```
drm.edid_firmware=<CONNECTOR>:edid/virtual-display.bin video=<CONNECTOR>:e
```

| Bootloader | Where to add |
|------------|--------------|
| Limine | `KERNEL_CMDLINE` in `/etc/default/limine` → `sudo limine-update` |
| GRUB | `GRUB_CMDLINE_LINUX_DEFAULT` → `sudo grub-mkconfig -o /boot/grub/grub.cfg` |
| systemd-boot | `options` line in `/boot/loader/entries/*.conf` |

See also `system/limine.cmdline.snippet` in the repo for an example.

## 4. Initramfs

The installer handles this automatically. Manual reference by backend:

**mkinitcpio (Arch/CachyOS):** add to `FILES=()` in `/etc/mkinitcpio.conf`, then `sudo mkinitcpio -P`

**dracut (Fedora/openSUSE):** create `/etc/dracut.conf.d/99-sunshine-vdisplay.conf`:

```
install_items+=" /usr/lib/firmware/edid/virtual-display.bin "
```

Then `sudo dracut -f`

**initramfs-tools (Debian/Ubuntu):** the installer writes `/etc/initramfs-tools/hooks/sunshine-vdisplay-edid`, then `sudo update-initramfs -u -k all`

See also `system/mkinitcpio.files.snippet` in the repo.

Reboot after rebuilding initramfs.

## 5. User scripts and Sunshine config

```bash
./scripts/install-local.sh
```

Or copy scripts to `~/bin` manually and edit `~/.config/sunshine/sunshine.conf` from `config/sunshine.conf`.

## 6. Sunshine output index

After reboot, check which monitor index is the virtual display:

```bash
journalctl --user -u sunshine | rg 'Monitor [0-9]'
```

Set `output_name` in `~/.config/sunshine/sunshine.conf` to that **number** (not the connector name).
