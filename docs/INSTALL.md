# Install and uninstall

## Supported distros

The installer auto-detects the initramfs backend:

| Backend | Distros | What the installer does |
|---------|---------|-------------------------|
| **mkinitcpio** | Arch, CachyOS, EndeavourOS, Manjaro, … | Adds EDID to `FILES=` in `/etc/mkinitcpio.conf`, runs `mkinitcpio -P` |
| **dracut** | Fedora, Nobara, RHEL, openSUSE, … | Writes `/etc/dracut.conf.d/99-sunshine-vdisplay.conf`, runs `dracut -f` |
| **initramfs-tools** | Debian, Ubuntu, Linux Mint, Pop!\_OS, … | Installs `/etc/initramfs-tools/hooks/sunshine-vdisplay-edid`, runs `update-initramfs -u -k all` |

Detection order: `mkinitcpio` → `dracut` → `initramfs-tools`. Override with `INITRAMFS_BACKEND=dracut` if needed.

GRUB handling also adapts per distro (`update-grub`, `grub-mkconfig`, or `grub2-mkconfig`).

## Install

Works on Arch, CachyOS, Fedora, Nobara, Debian, Ubuntu, openSUSE, and other distros with one of the supported initramfs backends.

**Back up first.** The installer changes initramfs, bootloader cmdline, and system config. It shows a confirmation prompt and requires typing `yes` before making changes.

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/mdj2812/sunshine-vdisplay/main/scripts/install.sh | bash
```

For non-interactive installs (e.g. piped from curl), set `I_HAVE_BACKED_UP=1` only after you have a backup:

```bash
I_HAVE_BACKED_UP=1 curl -fsSL https://raw.githubusercontent.com/mdj2812/sunshine-vdisplay/main/scripts/install.sh | bash
```

### With explicit connectors

```bash
VDISPLAY=HDMI-A-1 PDISPLAY=DP-3 bash <(curl -fsSL \
  https://raw.githubusercontent.com/mdj2812/sunshine-vdisplay/main/scripts/install.sh)
```

### From a clone

```bash
git clone https://github.com/mdj2812/sunshine-vdisplay.git
cd sunshine-vdisplay
./scripts/install.sh
```

### What the installer does

1. Detect distro and initramfs backend
2. Auto-detect connectors (prefers unused **HDMI**, then **DP**)
3. Generate and install EDID firmware to `/usr/lib/firmware/edid/`
4. Install scripts to `~/bin` and Sunshine config to `~/.config/sunshine/` (backs up an existing `sunshine.conf` before replacing it)
5. Patch initramfs config and your bootloader cmdline
6. Rebuild initramfs and apply Sunshine capabilities
7. Disable screen blanking that breaks headless virtual outputs
8. Configure Sunshine `global_prep_cmd` to swap displays when a Moonlight session starts and ends

Reboot when prompted, then connect with Moonlight.

### Automatic display switching

The installer writes this to `~/.config/sunshine/sunshine.conf`:

```ini
global_prep_cmd = [{"do":"~/bin/vdisplay-on.sh","undo":"~/bin/vdisplay-off.sh"}]
```

| Event | What happens |
|-------|----------------|
| **Moonlight session starts** | `vdisplay-on.sh` enables the virtual display, tunes brightness/scale, then **disables the physical monitor** |
| **Moonlight session ends** | `vdisplay-off.sh` **restores the physical monitor** and disables the virtual display |

The virtual display is enabled before the physical one is disabled — KDE requires at least one active output. Resolution can follow the client via `SUNSHINE_CLIENT_*` env vars (see [USAGE.md](USAGE.md)).

Local overrides for connector names and modes are saved to `~/bin/vdisplay-common.local.sh`.

### Installer options

| Variable | Default | Description |
|----------|---------|-------------|
| `VDISPLAY` | first free HDMI, else DP | Virtual connector name |
| `PDISPLAY` | first connected monitor | Physical connector name |
| `RES` | `2560x1600@120` | Virtual display mode |
| `PDISPLAY_RES` | `2560x1440@143.99` | Physical display mode |
| `SUNSHINE_OUTPUT` | `0` | Sunshine KMS monitor index |
| `SKIP_REBOOT` | `0` | Set to `1` to skip reboot prompt |
| `I_HAVE_BACKED_UP` | `0` | Set to `1` to skip the startup backup confirmation |
| `KEEP_SUNSHINE_CONF` | `0` | Set to `1` to leave `~/.config/sunshine/sunshine.conf` untouched |
| `MERGE_SUNSHINE_CONF` | `0` | Set to `1` to merge only `global_prep_cmd` into an existing config (still creates a backup) |
| `REPO_URL` | this repo | Override clone URL |
| `INITRAMFS_BACKEND` | auto-detect | Force `mkinitcpio`, `dracut`, or `initramfs-tools` |

## Uninstall

To remove a sunshine-vdisplay installation and revert boot/initramfs changes:

**Back up first.** The uninstaller also changes initramfs and bootloader config. It requires typing `yes` before making changes.

### One-liner

```bash
curl -fsSL https://raw.githubusercontent.com/mdj2812/sunshine-vdisplay/main/scripts/uninstall.sh | bash
```

For non-interactive uninstall:

```bash
I_CONFIRM_UNINSTALL=1 curl -fsSL https://raw.githubusercontent.com/mdj2812/sunshine-vdisplay/main/scripts/uninstall.sh | bash
```

### From a clone

```bash
git clone https://github.com/mdj2812/sunshine-vdisplay.git
cd sunshine-vdisplay
./scripts/uninstall.sh
```

Or, if you already have the repo:

```bash
./scripts/uninstall.sh
```

### What the uninstaller does

1. Run `vdisplay-off.sh` if present (restore physical display)
2. Remove virtual-display kernel parameters from your bootloader
3. Remove initramfs EDID bundling and rebuild initramfs
4. Delete `virtual-display.bin` firmware and `~/bin/vdisplay-*` scripts
5. Back up and strip Sunshine `global_prep_cmd` hooks for vdisplay-on/off
6. Remove `cap_sys_admin` from the Sunshine binary

Reboot when prompted.

### Uninstaller options

| Variable | Default | Description |
|----------|---------|-------------|
| `I_CONFIRM_UNINSTALL` | `0` | Set to `1` to skip the confirmation prompt |
| `SKIP_REBOOT` | `0` | Set to `1` to skip reboot prompt |
| `KEEP_SUNSHINE_CONF` | `0` | Set to `1` to leave `~/.config/sunshine/sunshine.conf` untouched |
| `INITRAMFS_BACKEND` | auto-detect | Force `mkinitcpio`, `dracut`, or `initramfs-tools` |

**Not reverted automatically:**

- KDE power-management tweaks applied by the installer (screen blanking, autolock)
- Other Sunshine settings the installer wrote (`capture`, `encoder`, `output_name`) — review `~/.config/sunshine/sunshine.conf` or restore from the backup created during uninstall
