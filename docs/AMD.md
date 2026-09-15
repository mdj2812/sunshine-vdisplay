# AMD GPU

Notes for the [AMD GPU milestone](https://github.com/mdj2812/sunshine-vdisplay/milestone/2). Baseline today is **NVIDIA + KDE Wayland**; AMD support is planned and needs testers.

## Paths under consideration

| Path | Best for | Notes |
|------|----------|-------|
| **EDID + force-enable** (primary) | Desktops that also use a physical monitor | Same technique as NVIDIA: `drm.edid_firmware=<connector>:edid/virtual-display.bin video=<connector>:e`, KMS capture, `kscreen-doctor` switching. Confirmed on AMD with a dummy plug and, without one, via the runtime force flag on RDNA4 ([field report](#field-reports)); the boot-time `video=:e` variant is still untested. The only Linux path that can advertise **HDR** via custom EDID (see [milestone 6](https://github.com/mdj2812/sunshine-vdisplay/milestone/6)). |
| **`krfb-virtualmonitor` + portal** | KDE-only, no boot changes | Compositor-native virtual output, `capture = portal`. See [ALTERNATIVES.md](ALTERNATIVES.md). Works on AMD and NVIDIA. |
| **`amdgpu.virtual_display` / vkms** | Dedicated headless boxes only | Kernel param replaces the normal display block with `amdgpu_vkms` — machine becomes **virtual-only** while enabled. Fixed mode list, **all 60 Hz** (640×480 … 4096×2160). Poor fit when you still use a physical monitor daily. See [kernel bug 203339](https://bugzilla.kernel.org/show_bug.cgi?id=203339) and [ArchWiki Headless](https://wiki.archlinux.org/title/Headless#AMD). |

## Encoders

Sunshine on AMD may use:

- **VAAPI** (`encoder = vaapi` or auto)
- **`hevc_vulkan`** — Vulkan Video via RADV (reported on RX 9070 XT)

List both when reporting test results.

## What we need from testers

Open an [AMD testing issue](https://github.com/mdj2812/sunshine-vdisplay/issues/new?template=amd-testing.md) with:

Issues created with the **`[AMD]`** title prefix are automatically assigned to the **AMD GPU** milestone.

- GPU model and driver (`amdgpu`, Mesa/RADV versions)
- Distro, kernel, bootloader, KDE Plasma version
- Virtual display path (EDID / krfb / vkms)
- Sunshine capture mode and encoder
- Whether physical monitor switching works on session start/end
- HDR, high refresh, and client-adaptive resolution results

## Field reports

Reports from hardware this project does not have in hand. They are volunteer results, not project-verified setups.

### RX 9070 XT (RDNA4) — EDID + force-enable works

From [issue #1](https://github.com/mdj2812/sunshine-vdisplay/issues/1): CachyOS, kernel 7.2.4, Mesa/RADV (`RADV GFX1201`), Limine with `limine-mkinitcpio-hook`, Secure Boot, KDE Plasma Wayland 6.7.5.

- The EDID plus force-enable path was exercised through the **runtime force flag** (see [TROUBLESHOOTING](TROUBLESHOOTING.md#runtime-force-flag)) rather than the boot-time parameters, because the machine is dual-boot with Secure Boot and the installer touches initramfs and the cmdline.
- `HDMI-A-1` reported `connected` with 14 modes from a custom EDID (preferred 3840x2160@60), KWin enabled it, and KMS showed the same. The dummy plug's own EDID had capped the output at 1080p60 — cheap dummies often ship tiny EDIDs.
- Sunshine captured it with `capture = kms` and `hevc_vulkan`, logging `Mapped 'HDMI-A-1' to kmsgrab monitor index 0`.
- **Latency ties the portal path.** Two 4K60 sessions to an Apple TV 4K averaged 4.2–4.4 ms (min 4.2, max 5.0) and 4.3 ms; krfb + portal on the same host, same game and client measured 4.3–5 ms. The difference is within noise, so pick a path on other grounds — HDR, non-KDE compositors, no dummy plug — rather than performance.
- Host load while streaming 4K60: GPU ~70 %, 74 W, 50 °C junction 52 °C, CPU ~35 %, ~101 Mbps on the wire.
- `Skipping FEC for abnormally large encoded frame` warnings appeared in one session and not the other, and also appear on the portal path, so they look scene related rather than KMS specific.

Caveats: the two paths were compared in separate sessions rather than simultaneously, and the boot-time `video=<connector>:e` variant was not exercised. The reporter offered to run a controlled A/B or the boot-time variant.

## References

- [Harry Ankers — NVIDIA virtual display gist](https://gist.github.com/HarryAnkers/8dbf551d66f00e8156ef4dd2b2b090a0) (EDID technique; applies to AMD force-enable as well)
- [Sunshine configuration — HDR](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html) — HDR wants an HDR-capable output or EDID that advertises it
