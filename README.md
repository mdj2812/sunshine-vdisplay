# Sunshine Virtual Display (NVIDIA + KDE Wayland)

Headless virtual display setup for Sunshine/Moonlight streaming on Linux with an NVIDIA GPU and KDE Plasma Wayland.

Works without a dummy plug: force-enable a spare GPU connector with a custom EDID loaded from initramfs.

## Contents

| Path | Purpose |
|------|---------|
| `scripts/create-vdisplay-edid.py` | Generate custom EDID with HDMI 2.1 VSDB blocks |
| `scripts/vdisplay-common.sh` | Shared KDE Wayland session helpers |
| `scripts/vdisplay-on.sh` | Enable virtual display, disable physical monitor |
| `scripts/vdisplay-off.sh` | Restore physical monitor, disable virtual display |
| `scripts/install-local.sh` | Install scripts, EDID firmware, and Sunshine config |
| `config/sunshine.conf` | Sunshine KMS capture config template |
| `system/mkinitcpio.files.snippet` | Initramfs EDID bundling (Arch/CachyOS) |
| `system/limine.cmdline.snippet` | Kernel params for the virtual connector |

## Tested on

- GPU: NVIDIA RTX 2070 SUPER
- OS: CachyOS (Arch-based), Limine bootloader, KDE Plasma 6 Wayland
- Sunshine 2026.x with KMS capture + NVENC

Example connector layout on the test machine:

| Connector | Role |
|-----------|------|
| `HDMI-A-1` | Virtual display (force-enabled) |
| `DP-3` | Physical monitor |

Your connector names will differ — check `/sys/class/drm/card*-* /status`.

## Quick start

**One-liner (Arch/CachyOS + Limine + NVIDIA + KDE):**

```bash
curl -fsSL https://gitea.home.mdj2812.top/mdj2812/sunshine-vdisplay/raw/branch/main/scripts/install.sh | bash
```

**With explicit connectors:**

```bash
VDISPLAY=HDMI-A-1 PDISPLAY=DP-3 bash <(curl -fsSL https://gitea.home.mdj2812.top/mdj2812/sunshine-vdisplay/raw/branch/main/scripts/install.sh)
```

**From a clone:**

```bash
git clone https://gitea.home.mdj2812.top/mdj2812/sunshine-vdisplay.git
cd sunshine-vdisplay
./scripts/install.sh
```

The installer will:

1. Generate and install the EDID firmware
2. Install scripts to `~/bin`
3. Configure Sunshine (`global_prep_cmd`, KMS capture)
4. Update `mkinitcpio.conf` and your bootloader (Limine, GRUB, or systemd-boot)
5. Rebuild initramfs
6. Disable screen blanking that breaks virtual displays

Then reboot when prompted.

## Customize for your machine

### 1. Pick a free GPU connector

```bash
for p in /sys/class/drm/card*-*; do
  [ -f "$p/status" ] && echo "$(basename "$p"): $(cat "$p/status")"
done
```

Use a connector that is **disconnected** and not your physical monitor, e.g. `HDMI-A-1` or `DP-2`.

### 2. Set kernel parameters

Add both parameters — **both are required on the NVIDIA proprietary driver**:

```
drm.edid_firmware=<CONNECTOR>:edid/virtual-display.bin video=<CONNECTOR>:e
```

Examples:

- **Limine** — append to `KERNEL_CMDLINE` in `/etc/default/limine`, then `sudo limine-update`
- **GRUB** — append to `GRUB_CMDLINE_LINUX_DEFAULT`, then `sudo grub-mkconfig -o /boot/grub/grub.cfg`
- **systemd-boot** — append to your boot entry `options` line

See `system/limine.cmdline.snippet` for a connector-only example (no root/filesystem params).

### 3. Bundle EDID in initramfs

Arch/CachyOS: add to `FILES=()` in `/etc/mkinitcpio.conf`:

```
FILES=(/usr/lib/firmware/edid/virtual-display.bin)
```

Then `sudo mkinitcpio -P`.

### 4. Configure Sunshine output index

After reboot, check Sunshine's log for the KMS monitor list:

```bash
journalctl --user -u sunshine | rg 'Monitor [0-9]'
```

Set `output_name` in `~/.config/sunshine/sunshine.conf` to the **numeric index** of your virtual display (not the connector name).

### 5. Set physical/virtual connector names (optional)

Defaults in `vdisplay-common.sh`:

```bash
VDISPLAY=HDMI-A-1   # virtual
PDISPLAY=DP-3       # physical
PDISPLAY_RES=2560x1440@143.99
RES=2560x1600@120   # virtual resolution
```

Override when calling the scripts if your connectors differ.

### 6. Custom resolutions

Edit `CUSTOM_DTDS` in `scripts/create-vdisplay-edid.py`, regenerate, reinstall, rebuild initramfs, reboot.

## After reboot

```bash
cat /sys/class/drm/card*-HDMI-A-1/status   # should say "connected"
~/bin/vdisplay-on.sh
systemctl --user restart sunshine
```

## Automation

Sunshine `global_prep_cmd` switches displays when a Moonlight session starts and ends:

- **Session start:** `vdisplay-on.sh` — virtual on, physical off
- **Session end:** `vdisplay-off.sh` — physical on, virtual off

Brightness tuning on the virtual display:

- Scale matched to the physical monitor
- Brightness `100%`, dimming floor `100%`
- Night Color disabled while streaming

```bash
VDISPLAY_BRIGHTNESS=100 VDISPLAY_DIMMING=100 VDISPLAY_SCALE=1.5 ~/bin/vdisplay-on.sh
```

## Limitations

- `output_name` must be a **numeric KMS index**, not a connector name.
- New EDID modes require regenerating the binary, rebuilding initramfs, and rebooting.
- **HDR does not work** on NVIDIA force-enabled virtual connectors.
- 4K@120 may cap at 4K@60 on virtual outputs (driver FRL limitation).
- Do not commit `sunshine_state.json`, credentials, or generated `.bin` files.

## References

- [NVIDIA virtual display gist (Harry Ankers)](https://gist.github.com/HarryAnkers/8dbf551d66f00e8156ef4dd2b2b090a0)
- [Sunshine configuration docs](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html)
