# AMD GPU

Notes for the [AMD GPU milestone](https://github.com/mdj2812/sunshine-vdisplay/milestone/2). Baseline today is **NVIDIA + KDE Wayland**; AMD support is planned and needs testers.

## Paths under consideration

| Path | Best for | Notes |
|------|----------|-------|
| **EDID + force-enable** (primary) | Desktops that also use a physical monitor | Same technique as NVIDIA: `drm.edid_firmware=<connector>:edid/virtual-display.bin video=<connector>:e`, KMS capture, `kscreen-doctor` switching. Confirmed on AMD with dummy plug; `video=:e` without a plug still needs testing. Likely the only Linux path that can advertise **HDR** via custom EDID. |
| **`krfb-virtualmonitor` + portal** | KDE-only, no boot changes | Compositor-native virtual output, `capture = portal`. See [ALTERNATIVES.md](ALTERNATIVES.md). Works on AMD and NVIDIA. |
| **`amdgpu.virtual_display` / vkms** | Dedicated headless boxes only | Kernel param replaces the normal display block with `amdgpu_vkms` — machine becomes **virtual-only** while enabled. Fixed mode list, **all 60 Hz** (640×480 … 4096×2160). Poor fit when you still use a physical monitor daily. See [kernel bug 203339](https://bugzilla.kernel.org/show_bug.cgi?id=203339) and [ArchWiki Headless](https://wiki.archlinux.org/title/Headless#AMD). |

## Encoders

Sunshine on AMD may use:

- **VAAPI** (`encoder = vaapi` or auto)
- **`hevc_vulkan`** — Vulkan Video via RADV (reported on RX 9070 XT)

List both when reporting test results.

## What we need from testers

Open an [AMD testing issue](https://github.com/mdj2812/sunshine-vdisplay/issues/new?template=amd-testing.md) with:

- GPU model and driver (`amdgpu`, Mesa/RADV versions)
- Distro, kernel, bootloader, KDE Plasma version
- Virtual display path (EDID / krfb / vkms)
- Sunshine capture mode and encoder
- Whether physical monitor switching works on session start/end
- HDR, high refresh, and client-adaptive resolution results

## References

- [Harry Ankers — NVIDIA virtual display gist](https://gist.github.com/HarryAnkers/8dbf551d66f00e8156ef4dd2b2b090a0) (EDID technique; applies to AMD force-enable as well)
- [Sunshine configuration — HDR](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html) — HDR wants an HDR-capable output or EDID that advertises it
