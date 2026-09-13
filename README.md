# Sunshine Virtual Display (NVIDIA + KDE Wayland)

Backup of the headless virtual display setup for Sunshine/Moonlight streaming on CachyOS with an NVIDIA GPU.

## Contents

| Path | Purpose |
|------|---------|
| `scripts/create-vdisplay-edid.py` | Generate custom EDID with HDMI 2.1 VSDB blocks |
| `scripts/vdisplay-common.sh` | Shared KDE Wayland session helpers |
| `scripts/vdisplay-on.sh` | Enable virtual display at 2560x1600@120 |
| `scripts/vdisplay-off.sh` | Disable virtual display |
| `scripts/install-local.sh` | Install scripts + sunshine.conf + EDID |
| `config/sunshine.conf` | Sunshine KMS capture config |
| `system/mkinitcpio.files.snippet` | Initramfs EDID bundling |
| `system/limine.cmdline.snippet` | Kernel params for HDMI-A-1 virtual output |

## Hardware / software (this machine)

- GPU: NVIDIA RTX 2070 SUPER
- OS: CachyOS, Limine bootloader, KDE Plasma 6 Wayland
- Virtual connector: `HDMI-A-1`
- Physical monitor: `DP-3`
- Sunshine `output_name = 0` (HDMI-A-1 virtual display)

## Quick restore

```bash
git clone https://gitea.home.mdj2812.top/mdj2812/sunshine-vdisplay.git
cd sunshine-vdisplay
./scripts/install-local.sh
```

Merge the snippets into `/etc/mkinitcpio.conf` and `/etc/default/limine`, rebuild initramfs, update Limine, reboot.

## After reboot

```bash
cat /sys/class/drm/card*-HDMI-A-1/status   # connected
~/bin/vdisplay-on.sh
systemctl --user restart sunshine
```

## Notes

- `output_name` in Sunshine must be a **numeric KMS index**, not a connector name.
- New EDID modes require regenerating the binary, rebuilding initramfs, and rebooting.
- HDR does not work on NVIDIA force-enabled virtual connectors.
- Do not commit `sunshine_state.json`, credentials, or generated `.bin` files.
