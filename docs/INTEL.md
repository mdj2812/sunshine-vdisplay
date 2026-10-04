# Intel iGPU

Notes for the [Intel iGPU milestone](https://github.com/mdj2812/sunshine-vdisplay/milestone/3). Baseline today is **NVIDIA + KDE Wayland**; Intel support is planned and needs testers.

## Paths under consideration

| Path | Best for | Notes |
|------|----------|-------|
| **EDID + force-enable** (primary) | Desktops that also use a physical monitor | Same technique as NVIDIA/AMD: `drm.edid_firmware=<connector>:edid/virtual-display.bin video=<connector>:e` on an **i915** or **xe** connector, KMS capture, `kscreen-doctor` switching. Pick a **disconnected** HDMI/DP port for `VDISPLAY` — prefer **HDMI**, which exposes far more modes than DP on this hardware ([field report](#field-reports)). Confirmed end to end on UHD 770 (i915). |
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

## Field reports

Reports from hardware this project does not have in hand. They are volunteer results, not project-verified setups.

### UHD 770 (Raptor Lake-S) — EDID + force-enable works end-to-end

From [issue #4](https://github.com/mdj2812/sunshine-vdisplay/issues/4): Ubuntu 26.04, kernel 7.0, GRUB + initramfs-tools, GNOME Shell 50.1 Wayland, Sunshine 2026.914.

- **`i915` binds**, not `xe`: `xe` is present as a module but does not claim Raptor Lake-S iGPUs.
- `VDISPLAY=HDMI-A-1`, `PDISPLAY=DP-2`. The virtual connector came up with the injected EDID and streamed with `capture = kms` and `encoder = vaapi`, negotiating HEVC (`hevc_vaapi`). Gen12.2 has no AV1 encoder, so Sunshine's `av1_vaapi` probe error there is expected.
- **Prefer HDMI for the virtual connector**: after a runtime force-enable, every HDMI connector reported **38 modes**, while the DP connectors reported **7**. The installer already prefers a free HDMI port.
- Moonlight's requested size was matched exactly — 1280x720 and 2560x1440@60 requests each landed on the corresponding mode — and the physical monitor stayed dark for the whole session.
- Measured host cost at 2560x1440@60 HEVC: Sunshine ~7 % of one core, gnome-shell ~4 %, machine-wide CPU ~2 %, ~5 Mbps on the wire against a 44.6 Mbps ceiling. Encoding runs on the media engine, so CPU cost stays low.
- HDR was not tested on this machine.

The switching step was driven by `gdctl` rather than `kscreen-doctor`. The GNOME notes live in [DESKTOPS.md](DESKTOPS.md#gnome).

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
