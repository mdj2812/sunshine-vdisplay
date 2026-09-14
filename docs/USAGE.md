# Usage

## Automatic (default)

Once installed, just start a Moonlight session. No manual script needed.

Sunshine runs `vdisplay-on.sh` at session start and `vdisplay-off.sh` when the session ends via `global_prep_cmd`.

## Manual

```bash
~/bin/vdisplay-on.sh              # streaming mode
~/bin/vdisplay-on.sh 2560x1440@120
~/bin/vdisplay-off.sh             # back to physical monitor
```

## Brightness tuning

Virtual outputs are SDR-only on NVIDIA force-enabled connectors and may look darker than an HDR physical panel. The scripts apply:

- Matched scale (default `1.5`)
- Brightness `100%`, dimming floor `100%`
- Night Color paused while streaming

Override:

```bash
VDISPLAY_BRIGHTNESS=100 VDISPLAY_DIMMING=100 VDISPLAY_SCALE=1.5 ~/bin/vdisplay-on.sh
```

## Custom resolutions

Re-run the installer and choose a different primary mode, or regenerate EDID manually:

```bash
python3 scripts/create-vdisplay-edid.py \
  --primary 2560x1440@120 \
  --extra 1920x1080@60,3840x2160@60 \
  /tmp/virtual-display.bin
sudo cp /tmp/virtual-display.bin /usr/lib/firmware/edid/virtual-display.bin
sudo mkinitcpio -P    # or dracut / update-initramfs for your distro
sudo reboot
```

Installed modes are saved as `EDID_MODES` in `~/bin/vdisplay-common.local.sh`.

## Moonlight "native" resolution

When Moonlight sends client size via `SUNSHINE_CLIENT_WIDTH/HEIGHT/FPS`, `vdisplay-on.sh` tries an exact EDID mode first, then the closest mode with the same aspect ratio, then falls back to `RES`.
