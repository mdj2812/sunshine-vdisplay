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

## Quick start

**Back up first.** The installer changes initramfs, bootloader cmdline, and system config.

```bash
curl -fsSL https://raw.githubusercontent.com/mdj2812/sunshine-vdisplay/main/scripts/install.sh | bash
```

Reboot when prompted, then connect with Moonlight.

When a Moonlight **session starts**, Sunshine runs `vdisplay-on.sh`: the **virtual display turns on** and your **physical monitor turns off**. When the session **ends**, `vdisplay-off.sh` restores the physical monitor and disables the virtual display. No manual steps needed during streaming.

To remove the installation:

```bash
curl -fsSL https://raw.githubusercontent.com/mdj2812/sunshine-vdisplay/main/scripts/uninstall.sh | bash
```

See [docs/INSTALL.md](docs/INSTALL.md) for connector overrides, environment variables, and non-interactive usage.

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

## Documentation

| Doc | Contents |
|-----|----------|
| [docs/INSTALL.md](docs/INSTALL.md) | Supported distros, install/uninstall options |
| [docs/MANUAL.md](docs/MANUAL.md) | Manual setup without the installer |
| [docs/USAGE.md](docs/USAGE.md) | Day-to-day usage, brightness, custom resolutions |
| [docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md) | Common problems and known limitations |
| [docs/ROADMAP.md](docs/ROADMAP.md) | Milestones and planned platform support |
| [docs/AMD.md](docs/AMD.md) | AMD GPU paths, encoders, and testing notes |
| [docs/ALTERNATIVES.md](docs/ALTERNATIVES.md) | KDE krfb vs EDID and other approaches |

## Repository layout

| Path | Purpose |
|------|---------|
| `scripts/install.sh` | Full automated installer |
| `scripts/uninstall.sh` | Remove installation and revert boot/initramfs changes |
| `scripts/install-local.sh` | Wrapper → `install.sh` |
| `scripts/create-vdisplay-edid.py` | EDID generator |
| `scripts/vdisplay-on.sh` | Enable virtual, disable physical |
| `scripts/vdisplay-off.sh` | Restore physical, disable virtual |
| `scripts/vdisplay-common.sh` | Shared KDE/Wayland helpers |
| `config/sunshine.conf` | Sunshine config template (`__HOME__` placeholders) |
| `system/mkinitcpio.files.snippet` | Initramfs EDID reference |
| `system/limine.cmdline.snippet` | Kernel param reference |

## References

- [NVIDIA virtual display gist (Harry Ankers)](https://gist.github.com/HarryAnkers/8dbf551d66f00e8156ef4dd2b2b090a0)
- [Sunshine configuration docs](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html)

## License

MIT — see [LICENSE](LICENSE).
