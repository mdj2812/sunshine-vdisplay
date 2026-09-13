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
- **4K@120** may cap at 4K@60 on virtual outputs (driver FRL limitation)
- New EDID modes require regenerating the binary, rebuilding initramfs, and rebooting
- Linux-only; Sunshine does not create virtual displays — this repo handles that part
- Display switching scripts require **KDE Plasma Wayland** (`kscreen-doctor`); other desktops need different tooling
