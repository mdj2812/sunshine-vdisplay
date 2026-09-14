# Intel iGPU

Notes for the [Intel iGPU milestone](https://github.com/mdj2812/sunshine-vdisplay/milestone/3). Baseline today is **NVIDIA + KDE Wayland**; Intel support is planned and needs testers.

## Paths under consideration

| Path | Best for | Notes |
|------|----------|-------|
| **EDID + force-enable** (primary) | Desktops that also use a physical monitor | Same technique as NVIDIA/AMD: `drm.edid_firmware=<connector>:edid/virtual-display.bin video=<connector>:e` on an **i915** or **xe** connector, KMS capture, `kscreen-doctor` switching. Pick a **disconnected** HDMI/DP port for `VDISPLAY`. |
| **`krfb-virtualmonitor` + portal** | KDE-only, no boot changes | Compositor-native virtual output, `capture = portal`. See [ALTERNATIVES.md](ALTERNATIVES.md). Works on Intel without boot params. |
| **Headless / vkms-style experiments** | Lab only | Intel has no direct `amdgpu.virtual_display` equivalent; vkms or mediatek-style paths are poor fits for daily-driver + physical monitor setups. |

## Encoders

Sunshine on Intel may use:

- **VAAPI** via `intel-media-driver` / iHD (`encoder = vaapi` or auto)
- **QSV** where supported by the Sunshine build and driver stack

List both when reporting test results. Verify with `vainfo` and Sunshine logs.

## PVE homelab (Intel UHD 630)

The repo includes scripts under `tests/pve/` to build a **QEMU VM** on Proxmox with optional **full Intel iGPU passthrough**:

| Script | Purpose |
|--------|---------|
| `setup-intel-vm.sh` | Create VM 122 (Fedora cloud + cloud-init) |
| `enable-gpu-passthrough.sh` | Bind `8086:3e92` to vfio and attach `hostpci` |
| `guest-setup.sh` | KDE + Sunshine + `install.sh` inside the guest |
| `run-guest-setup.sh` | Sync repo and run guest setup from the PVE host |

**Important:** GVT-g is not available on current PVE kernels. Passthrough gives the guest the real i915 device and **removes the iGPU from the PVE host** (manage the host over SSH / web UI only).

Typical flow:

```bash
rsync -a --exclude .git ./ pve:/tmp/sunshine-vdisplay/
ssh pve 'bash /tmp/sunshine-vdisplay/tests/pve/setup-intel-vm.sh'
ssh pve 'bash /tmp/sunshine-vdisplay/tests/pve/run-guest-setup.sh 122'
# After guest is up, enable passthrough + reboot host, then re-run install inside guest:
ssh pve 'bash /tmp/sunshine-vdisplay/tests/pve/enable-gpu-passthrough.sh 122'
# Reboot PVE host, start VM 122, SSH to guest, run install.sh + reboot guest
```

See [tests/README.md](../tests/README.md) for full PVE lab notes.

## What we need from testers

Open an [Intel testing issue](https://github.com/mdj2812/sunshine-vdisplay/issues/new?template=intel-testing.md) with:

Issues created with the **`[Intel]`** title prefix are automatically assigned to the **Intel iGPU** milestone.

- GPU model and driver (`i915` or `xe`, Mesa versions)
- Distro, kernel, bootloader, KDE Plasma version
- Virtual display path (EDID / krfb)
- Sunshine capture mode and encoder (VAAPI / QSV)
- Whether physical monitor switching works on session start/end
- HDR, high refresh, and client-adaptive resolution results

## References

- [Harry Ankers — NVIDIA virtual display gist](https://gist.github.com/HarryAnkers/8dbf551d66f00e8156ef4dd2b2b090a0) (EDID technique; applies to Intel force-enable as well)
- [Sunshine configuration — HDR](https://docs.lizardbyte.dev/projects/sunshine/latest/md_docs_2configuration.html)
