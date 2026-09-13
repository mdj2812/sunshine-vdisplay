# sunshine-vdisplay

Virtual display setup for **Sunshine/Moonlight** streaming on **Linux**, **NVIDIA**, and **KDE Plasma Wayland**.

Force-enable a spare GPU output with a custom EDID — no dummy plug required. Includes automatic display switching when a Moonlight session starts and ends.

**Tested on:** CachyOS · RTX 2070 SUPER · Limine · Sunshine 2026.x · KDE Plasma 6

## Features

- Custom EDID with HDMI 2.1 VSDB blocks (2560×1600@120, 4K, and more)
- One-line installer for Arch/CachyOS (Limine, GRUB, or systemd-boot)
- Automatic virtual/physical display swap via Sunshine `global_prep_cmd`
- Brightness tuning for virtual outputs (scale, brightness, dimming, Night Color)
- Client-adaptive resolution via `SUNSHINE_CLIENT_*` env vars

## Requirements

| Component | Notes |
|-----------|-------|
| GPU | NVIDIA with proprietary driver |
| Desktop | KDE Plasma **Wayland** |
| Streaming | [Sunshine](https://app.lizardbyte.dev/) with KMS capture |
| Bootloader | Limine, GRUB, or systemd-boot |
| Spare connector | Unused HDMI or DisplayPort (nothing plugged in) |

Sunshine also needs `cap_sys_admin` for KMS capture — the installer sets this automatically.

## Supported distros

The installer auto-detects the initramfs backend:

| Backend | Distros | What the installer does |
|---------|---------|-------------------------|
| **mkinitcpio** | Arch, CachyOS, EndeavourOS, Manjaro, … | Adds EDID to `FILES=` in `/etc/mkinitcpio.conf`, runs `mkinitcpio -P` |
| **dracut** | Fedora, Nobara, RHEL, openSUSE, … | Writes `/etc/dracut.conf.d/99-sunshine-vdisplay.conf`, runs `dracut -f` |
| **initramfs-tools** | Debian, Ubuntu, Linux Mint, Pop!\_OS, … | Installs `/etc/initramfs-tools/hooks/sunshine-vdisplay-edid`, runs `update-initramfs -u -k all` |

Detection order: `mkinitcpio` → `dracut` → `initramfs-tools`. Override with `INITRAMFS_BACKEND=dracut` if needed.

GRUB handling also adapts per distro (`update-grub`, `grub-mkconfig`, or `grub2-mkconfig`).

## Quick start

### One-liner

Works on Arch, CachyOS, Fedora, Nobara, Debian, Ubuntu, openSUSE, and other distros with one of the supported initramfs backends:

```bash
curl -fsSL https://gitea.home.mdj2812.top/mdj2812/sunshine-vdisplay/raw/branch/main/scripts/install.sh | bash
```

### With explicit connectors

```bash
VDISPLAY=HDMI-A-1 PDISPLAY=DP-3 bash <(curl -fsSL \
  https://gitea.home.mdj2812.top/mdj2812/sunshine-vdisplay/raw/branch/main/scripts/install.sh)
```

### From a clone

```bash
git clone https://gitea.home.mdj2812.top/mdj2812/sunshine-vdisplay.git
cd sunshine-vdisplay
./scripts/install.sh
```

The installer will:

1. Detect distro and initramfs backend
2. Auto-detect connectors (prefers unused **HDMI**, then **DP**)
3. Generate and install EDID firmware to `/usr/lib/firmware/edid/`
4. Install scripts to `~/bin` and Sunshine config to `~/.config/sunshine/`
5. Patch initramfs config and your bootloader cmdline
6. Rebuild initramfs and apply Sunshine capabilities
7. Disable screen blanking that breaks headless virtual outputs

Reboot when prompted, then connect with Moonlight — display switching is automatic.

### Installer options

| Variable | Default | Description |
|----------|---------|-------------|
| `VDISPLAY` | first free HDMI, else DP | Virtual connector name |
| `PDISPLAY` | first connected monitor | Physical connector name |
| `RES` | `2560x1600@120` | Virtual display mode |
| `PDISPLAY_RES` | `2560x1440@143.99` | Physical display mode |
| `SUNSHINE_OUTPUT` | `0` | Sunshine KMS monitor index |
| `SKIP_REBOOT` | `0` | Set to `1` to skip reboot prompt |
| `REPO_URL` | this repo | Override clone URL |
| `INITRAMFS_BACKEND` | auto-detect | Force `mkinitcpio`, `dracut`, or `initramfs-tools` |

Local overrides are saved to `~/bin/vdisplay-common.local.sh`.

## How it works

```
Boot
  └─ kernel loads custom EDID on spare connector (e.g. HDMI-A-1)
       └─ KDE sees a second monitor

Moonlight session start
  └─ Sunshine global_prep_cmd → vdisplay-on.sh
       ├─ enable virtual display at (0,0)
       ├─ tune brightness / scale
       └─ disable physical monitor

Moonlight session end
  └─ Sunshine undo cmd → vdisplay-off.sh
       ├─ restore physical monitor
       └─ disable virtual display
```

Sunshine captures the virtual output via **KMS** (`capture = kms`, `encoder = nvenc`).

## Repository layout

| Path | Purpose |
|------|---------|
| `scripts/install.sh` | Full automated installer |
| `scripts/install-local.sh` | Wrapper → `install.sh` |
| `scripts/create-vdisplay-edid.py` | EDID generator |
| `scripts/vdisplay-on.sh` | Enable virtual, disable physical |
| `scripts/vdisplay-off.sh` | Restore physical, disable virtual |
| `scripts/vdisplay-common.sh` | Shared KDE/Wayland helpers |
| `config/sunshine.conf` | Sunshine config template (`__HOME__` placeholders) |
| `system/mkinitcpio.files.snippet` | Initramfs EDID reference |
| `system/limine.cmdline.snippet` | Kernel param reference |

## Manual setup

Use this if you prefer not to run the installer, or need to adapt for another distro.

### 1. Find connectors

```bash
for p in /sys/class/drm/card*-*; do
  [ -f "$p/status" ] && echo "$(basename "$p"): $(cat "$p/status")"
done
```

Pick a **disconnected** port for the virtual display.

### 2. Kernel parameters

Both are required on the NVIDIA proprietary driver:

```
drm.edid_firmware=<CONNECTOR>:edid/virtual-display.bin video=<CONNECTOR>:e
```

| Bootloader | Where to add |
|------------|--------------|
| Limine | `KERNEL_CMDLINE` in `/etc/default/limine` → `sudo limine-update` |
| GRUB | `GRUB_CMDLINE_LINUX_DEFAULT` → `sudo grub-mkconfig -o /boot/grub/grub.cfg` |
| systemd-boot | `options` line in `/boot/loader/entries/*.conf` |

### 3. Initramfs (Arch/CachyOS)

Add to `FILES=()` in `/etc/mkinitcpio.conf`:

```
FILES=(/usr/lib/firmware/edid/virtual-display.bin)
```

Then `sudo mkinitcpio -P` and reboot.

### 4. Sunshine output index

After reboot, check which monitor index is the virtual display:

```bash
journalctl --user -u sunshine | rg 'Monitor [0-9]'
```

Set `output_name` in `~/.config/sunshine/sunshine.conf` to that **number** (not the connector name).

## Usage

### Automatic (default)

Once installed, just start a Moonlight session. No manual script needed.

### Manual

```bash
~/bin/vdisplay-on.sh              # streaming mode
~/bin/vdisplay-on.sh 2560x1600@120
~/bin/vdisplay-off.sh             # back to physical monitor
```

### Brightness tuning

Virtual outputs are SDR-only on NVIDIA force-enabled connectors and may look darker than an HDR physical panel. The scripts apply:

- Matched scale (default `1.5`)
- Brightness `100%`, dimming floor `100%`
- Night Color paused while streaming

Override:

```bash
VDISPLAY_BRIGHTNESS=100 VDISPLAY_DIMMING=100 VDISPLAY_SCALE=1.5 ~/bin/vdisplay-on.sh
```

### Custom resolutions

Edit `CUSTOM_DTDS` in `scripts/create-vdisplay-edid.py`, then:

```bash
python3 ~/bin/create-vdisplay-edid.py /tmp/virtual-display.bin
sudo cp /tmp/virtual-display.bin /usr/lib/firmware/edid/virtual-display.bin
sudo mkinitcpio -P
sudo reboot
```

## Troubleshooting

| Problem | Fix |
|---------|-----|
| Sunshine: "Couldn't find monitor" | `output_name` must be a numeric KMS index — check `sunshine.log` |
| Virtual connector stays disconnected | Verify kernel cmdline includes both `drm.edid_firmware` and `video=:e`; rebuild initramfs |
| `vdisplay-on.sh`: display not found | Script needs a KDE Wayland session (`WAYLAND_DISPLAY=wayland-0`) |
| Stream goes black when idle | Disable DPMS / screen blanking (installer does this) |
| Modes capped at 1080p | EDID missing HDMI VSDB blocks — regenerate with included script |
| Undo cmd doesn't run | Runs when the Moonlight **session ends**, not when the app is minimized |

Verify virtual display after reboot:

```bash
cat /proc/cmdline
cat /sys/class/drm/card*-HDMI-A-1/status
cat /sys/class/drm/card*-HDMI-A-1/modes
```

## Limitations

- **HDR** does not work on NVIDIA force-enabled virtual connectors
- **4K@120** may cap at 4K@60 on virtual outputs (driver FRL limitation)
- New EDID modes require regenerating the binary, rebuilding initramfs, and rebooting
- Linux-only; Sunshine does not create virtual displays — this repo handles that part
- Display switching scripts require **KDE Plasma Wayland** (`kscreen-doctor`); other desktops need different tooling

## References

- [NVIDIA virtual display gist (Harry Ankers)](https://gist.github.com/HarryAnkers/8dbf551d66f00e8156ef4dd2b2b090a0)
- [Sunshine configuration docs](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html)

## License

MIT — see [LICENSE](LICENSE).
