# Troubleshooting

| Problem | Fix |
|---------|-----|
| Sunshine: "Couldn't find monitor" | `output_name` must be a numeric KMS index — check `sunshine.log` |
| Virtual connector stays disconnected | Verify kernel cmdline includes both `drm.edid_firmware` and `video=:e`; rebuild initramfs |
| `vdisplay-on.sh`: display not found | Script needs a running session (`WAYLAND_DISPLAY=wayland-0`) and a supported desktop backend ([DESKTOPS.md](DESKTOPS.md)) |
| Stream goes black when idle | Disable DPMS / screen blanking (installer does this) |
| Modes capped at 1080p | EDID missing HDMI VSDB blocks — regenerate with included script |
| Undo cmd doesn't run | Runs when the Moonlight **session ends**, not when the app is minimized |
| Display stays swapped after a Sunshine crash | Sunshine never runs the prep-cmd undo if it dies — see [Crash recovery](#crash-recovery) |
| Re-testing the force flag without a reboot | The connector only changes state when the compositor re-enumerates it — see [Runtime force flag](#runtime-force-flag) |
| `.../force` write fails with *Permission denied* | Kernel 7.0 dropped that attribute — write `status` instead, see [Runtime force flag](#runtime-force-flag) |
| Physical monitor shows the virtual EDID or the wrong modes | A `drm.edid_firmware` entry with no `<connector>:` prefix applies to every connector — always write `connector:file` (see [MANUAL.md](MANUAL.md#3-kernel-parameters)) |

## Verify after reboot

```bash
cat /proc/cmdline
cat /sys/class/drm/card*-HDMI-A-1/status
cat /sys/class/drm/card*-HDMI-A-1/modes

# the kernel adopted the injected blob if the first bytes are the EDID header
od -An -tx1 -N8 /sys/class/drm/card*-HDMI-A-1/edid   # 00 ff ff ff ff ff ff 00
```

Replace `HDMI-A-1` with your virtual connector name.

`connected` on its own is weak evidence — the kernel reports it for any attached monitor. The `edid` attribute is the real confirmation: an empty file or one without the `00 ff ff ff ff ff ff 00` header means the firmware blob was not picked up.

## Runtime force flag

The installer sets the kernel parameters at boot, which needs an initramfs rebuild and a reboot. To exercise the same DRM force state on a running system:

```bash
# force the connector on (printf, not echo: the bare value must have no newline)
printf on | sudo tee /sys/class/drm/card1-HDMI-A-1/force >/dev/null

# the connector only changes state once the compositor re-enumerates it
printf change | sudo tee /sys/class/drm/card1/uevent >/dev/null
```

On **kernel 7.0 and later** there is no per-connector `force` attribute; the connector directory carries `status` instead, and that is what you write:

```bash
# DRM_FORCE_ON — the connector reports connected
printf on | sudo tee /sys/class/drm/card1-HDMI-A-1/status >/dev/null
printf change | sudo tee /sys/class/drm/card1/uevent >/dev/null

# back to UNSPECIFIED, plus a re-probe
printf detect | sudo tee /sys/class/drm/card1-HDMI-A-1/status >/dev/null
```

`off` and `on-digital` set the remaining DRM force states. If writing to `.../force` fails with *Permission denied* rather than *No such file or directory*, this is why: sysfs directories are read-only, so the shell cannot create the missing file and reports the failure as an access error.

Two caveats either way:

- The kernel caches connector status, so reverting (`unspecified` on kernels with `force`, `detect` without it) also needs a reboot or a compositor restart before it takes effect.
- At boot neither applies: the force is set before the first connector probe, so no `uevent` nudge is needed.

This is a testing shortcut for hardware reports, not a substitute for the kernel parameters — a runtime force is gone after reboot. It is also how the [AMD field report](AMD.md#field-reports) and the [Intel field report](INTEL.md#field-reports) were measured.

## Crash recovery

Display switching runs through Sunshine's `global_prep_cmd` **undo** command, which only fires when the session ends normally. If Sunshine crashes or is killed mid-session, the undo never runs and the machine stays swapped: virtual output on, physical monitor off.

Restore the displays by hand:

```bash
~/bin/vdisplay-off.sh
```

To make it automatic, add a systemd drop-in that runs the restore command whenever the service stops, including a crash or `SIGKILL`:

```bash
mkdir -p ~/.config/systemd/user/sunshine.service.d
cat > ~/.config/systemd/user/sunshine.service.d/restore-display.conf <<'EOF'
[Service]
ExecStopPost=%h/bin/vdisplay-off.sh
EOF
systemctl --user daemon-reload
systemctl --user restart sunshine.service
```

Use the unit name that matches your install: `sunshine.service` (distro package) or `app-dev.lizardbyte.app.Sunshine.service` (Flatpak). This covers Sunshine stopping, not the machine going down — if the outputs are still swapped after a reboot, run `~/bin/vdisplay-off.sh`.

## Limitations

- **HDR** on force-enabled virtual connectors is unverified end to end. The generated EDID advertises HDR10 static metadata (PQ) and BT.2020 colorimetry, and KWin accepts `output.<connector>.hdr.enable` — but an active virtual output has not been confirmed to drive HDR. See [HDR.md](HDR.md) and [milestone 6](https://github.com/mdj2812/sunshine-vdisplay/milestone/6)
- **4K above 60 Hz** cannot be encoded in a standard EDID detailed timing (pixel clock cap ~655 MHz), so **3840x2160@60** is the practical maximum here. A 4K120 mode would need a YCbCr 4:2:0 timing — RGB at 4K120 wants roughly 1188 MHz TMDS against the 600 MHz budget the generated HDMI VSDB declares — and the generator emits neither a 4:2:0 VIC nor the matching capability flags
- **Dummy plugs** often ship an EDID capped at 1080p60, and it cannot be changed — inject a custom EDID (this repo) or use a dummy known to carry a larger one
- **144 Hz** works on Linux when the mode is listed in EDID and `kscreen-doctor output.<connector>.mode.*` shows it — common for 1080p/1440p/1600p on force-enabled connectors; Moonlight must request 144 (`SUNSHINE_CLIENT_FPS`). Only **6 modes** fit in one EDID blob, so pick 144 Hz variants deliberately in the installer
- New EDID modes require regenerating the binary, rebuilding initramfs, and rebooting
- Linux-only; Sunshine does not create virtual displays — this repo handles that part
- Display switching scripts need a desktop backend — see [DESKTOPS.md](DESKTOPS.md) for which desktops have one
