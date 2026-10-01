# GNOME

Tracked in the [other desktop environments milestone](https://github.com/mdj2812/sunshine-vdisplay/milestone/5). The EDID, initramfs, and Sunshine parts of this repo do not care which desktop you run — only the **display switching scripts** are KDE-specific, because they drive `kscreen-doctor`.

**Status: not implemented.** `vdisplay-on.sh` and `vdisplay-off.sh` stop with a `kscreen-doctor not found` message under GNOME. A GNOME backend is wanted; [issue #4](https://github.com/mdj2812/sunshine-vdisplay/issues/4) has a reporter with working scripts.

## Switching with `gdctl`

GNOME has no `kscreen-doctor` equivalent, but `gdctl` covers the same ground. The switching step needs four operations — enable the virtual output at a resolution, place it, disable the physical output, restore both at the end — and `gdctl` expresses them as one declarative call rather than a sequence:

- **Any monitor omitted from a `gdctl set` command line is turned off**, so declaring a logical monitor for the virtual connector alone blanks the physical one. That is the GNOME counterpart of `kscreen-doctor output.<name>.disable`.
- `-P` (persist) is an option of the `set` subcommand: `gdctl set -P …`, not `gdctl -P set …`.
- Adding the virtual monitor changes the set of connected monitors, so mutter discards its stored layout and auto-configures: the desktop extends onto the virtual screen and the physical panel drops to its **preferred** timing — 3440x1440@50 instead of its usual 144 Hz in the field report. Persisting a configuration for the new monitor set and normalising it once at login resolved that.
- `gdctl show` prints only the current and preferred mode per monitor. The full mode list, needed to match `SUNSHINE_CLIENT_WIDTH/HEIGHT/FPS`, comes from mutter's `DisplayConfig.GetCurrentState` D-Bus reply.

## HDR

GNOME exposes HDR per monitor through mutter rather than a CLI toggle. The generated EDID advertises HDR10 (PQ) and BT.2020 colorimetry, but nobody has reported whether GNOME offers HDR for a force-enabled virtual output yet — HDR is tracked in [milestone 6](https://github.com/mdj2812/sunshine-vdisplay/milestone/6).

## References

- [UHD 770 field report](INTEL.md#field-reports) — the `gdctl` details above come from this report
- [ALTERNATIVES.md](ALTERNATIVES.md) — portal capture, including the ScreenCast restore-token caveat that hits RustDesk-style tools
