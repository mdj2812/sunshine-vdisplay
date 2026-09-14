# Troubleshooting

| Problem | Fix |
|---------|-----|
| Sunshine: "Couldn't find monitor" | `output_name` must be a numeric KMS index — check `sunshine.log` |
| Virtual connector stays disconnected | Verify kernel cmdline includes both `drm.edid_firmware` and `video=:e`; rebuild initramfs |
| `vdisplay-on.sh`: display not found | Script needs a KDE Wayland session (`WAYLAND_DISPLAY=wayland-0`) |
| Stream goes black when idle | Disable DPMS / screen blanking (installer does this) |
| Modes capped at 1080p | EDID missing HDMI VSDB blocks — regenerate with included script |
| Undo cmd doesn't run | Runs when the Moonlight **session ends**, not when the app is minimized |

## Verify after reboot

```bash
cat /proc/cmdline
cat /sys/class/drm/card*-HDMI-A-1/status
cat /sys/class/drm/card*-HDMI-A-1/modes
```

Replace `HDMI-A-1` with your virtual connector name.

## Limitations

- **HDR** does not work on NVIDIA force-enabled virtual connectors
- **4K above 60 Hz** cannot be encoded in a standard EDID detailed timing (pixel clock cap ~655 MHz) — use **3840x2160@60** only
- **144 Hz** works on Linux when the mode is listed in EDID and `kscreen-doctor output.<connector>.mode.*` shows it — common for 1080p/1440p/1600p on force-enabled connectors; Moonlight must request 144 (`SUNSHINE_CLIENT_FPS`). Only **6 modes** fit in one EDID blob, so pick 144 Hz variants deliberately in the installer
- New EDID modes require regenerating the binary, rebuilding initramfs, and rebooting
- Linux-only; Sunshine does not create virtual displays — this repo handles that part
- Display switching scripts require **KDE Plasma Wayland** (`kscreen-doctor`); other desktops need different tooling
