# Usage

## Automatic (default)

Once installed, just start a Moonlight session. No manual script needed.

Sunshine runs `vdisplay-on.sh` at session start and `vdisplay-off.sh` when the session ends via `global_prep_cmd`.

## Manual

```bash
~/bin/vdisplay-on.sh              # streaming mode
~/bin/vdisplay-on.sh 2560x1600@120
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

Edit `CUSTOM_DTDS` in `scripts/create-vdisplay-edid.py`, then:

```bash
python3 ~/bin/create-vdisplay-edid.py /tmp/virtual-display.bin
sudo cp /tmp/virtual-display.bin /usr/lib/firmware/edid/virtual-display.bin
sudo mkinitcpio -P    # or dracut / update-initramfs for your distro
sudo reboot
```
