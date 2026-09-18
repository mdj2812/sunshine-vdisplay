# HDR

Tracked in the [HDR milestone](https://github.com/mdj2812/sunshine-vdisplay/milestone/6). The EDID path is the only Linux option that can advertise HDR: `krfb-virtualmonitor` outputs have no EDID, and `amdgpu.virtual_display` / vkms has no EDID path either.

## What the generated EDID already advertises

`create-vdisplay-edid.py` emits the metadata an HDR sink needs. Decoding the CTA-861 extension of a generated blob:

| Block | Value |
|-------|-------|
| HDR Static Metadata (extended tag 0x06) | EOTF support: SDR, traditional HDR, **PQ (SMPTE ST 2084)**; static metadata type 1; ~1000 cd/m² peak, ~400 cd/m² max frame-average, ~0.01 cd/m² min |
| Colorimetry (0x05) | **BT.2020 RGB** and BT.2020 YCC |
| HDMI Forum VSDB | version 1, 600 MHz max TMDS rate |
| HDMI VSDB | OUI 00-0C-03, 600 MHz max TMDS rate |

## Status

Measured on CachyOS, KWin 6.7.5, NVIDIA 615.71.09, against a force-enabled `HDMI-A-1` carrying this repo's EDID:

- KWin accepts the toggle for the virtual output. `kscreen-doctor output.HDMI-A-1.hdr.enable` succeeds, and `kscreen-doctor -o` then reports `HDR: enabled` with `HDR color profile source: EDID` — KWin takes the HDR metadata from the injected EDID, not from a physical sink.
- Wide color gamut toggles the same way (`output.<connector>.wcg.enable`).
- Sunshine can encode HDR on this hardware: its startup probe logs `Color coding: HDR (Rec. 2020 + SMPTE 2084 PQ)`, and it logs `Sent HDR mode:` / `Reinitializing capture after HDR metadata change` when a client negotiates HDR.

Not verified yet: whether an **active** virtual output really drives HDR, and what a client decodes. See below.

## Trying it

HDR is opt-in per stream:

```bash
VDISPLAY_HDR=1 ~/bin/vdisplay-on.sh    # HDR + WCG on the virtual output
~/bin/vdisplay-off.sh                  # back to SDR and the physical monitor
```

Set `VDISPLAY_HDR=1` in `~/bin/vdisplay-common.local.sh`, or install with `VDISPLAY_HDR=1 ./scripts/install.sh`, to make it the default for every session. While HDR is on, `vdisplay-on.sh` also applies `VDISPLAY_SDR_BRIGHTNESS` (default 400 nits) so SDR content keeps a sane level.

Manual equivalent:

```bash
kscreen-doctor output.HDMI-A-1.hdr.enable output.HDMI-A-1.wcg.enable
```

## How to confirm it

`kscreen-doctor -o` prints the brightness block only for an output that is **enabled**:

```text
HDR: enabled
    SDR brightness: 400 nits
    Peak brightness: 400 nits
    HDR color profile source: EDID
```

A disabled output reports `HDR: enabled` without those lines — which is how far the measurements above go. So the next step is to start a session with `VDISPLAY_HDR=1` and check whether the enabled virtual output grows that brightness block. If it does not, the driver is not honouring HDR for the connector even though KWin stored the setting.

On the Sunshine side:

```bash
rg -i 'color coding|hdr mode|hdr metadata' ~/.config/sunshine/sunshine.log | tail
```

## Known limits

- **Clients must support HDR.** A Moonlight client that does not decode HDR10 shows washed-out or clipped colours while the host streams PQ.
- **Portal capture cannot do HDR** — there is no EDID behind a `krfb-virtualmonitor` output to advertise it with.
- **NVIDIA force-enabled connectors were previously reported as HDR-incapable.** The toggle is accepted today, but that only proves KWin stored the setting; see [How to confirm it](#how-to-confirm-it).
- HDR is a per-output KWin setting that persists, so `vdisplay-off.sh` turns it back off for the virtual output when `VDISPLAY_HDR=1`. The physical monitor's HDR state is never touched.
