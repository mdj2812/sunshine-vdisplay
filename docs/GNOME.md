# GNOME

Tracked in the [other desktop environments milestone](https://github.com/mdj2812/sunshine-vdisplay/milestone/5). The EDID, initramfs, and Sunshine parts of this repo do not care which desktop you run — only the **display switching scripts** are KDE-specific, because they drive `kscreen-doctor`.

**Status: implemented, unverified.** `vdisplay-common.sh` has a GNOME backend that drives `gdctl`, covered by `tests/desktop-backends-test.sh` against a stub. Nobody has run it in a real GNOME session yet — [issue #4](https://github.com/mdj2812/sunshine-vdisplay/issues/4) has a reporter with working scripts.

## Switching with `gdctl`

GNOME has no `kscreen-doctor` equivalent, but `gdctl` covers the same ground. The switch needs four operations — enable the virtual output at a resolution, place it, disable the physical output, restore both at the end — and `gdctl` expresses them as one declarative call rather than a sequence:

- **Any monitor omitted from a `gdctl set` command line is turned off**, so declaring a logical monitor for the virtual connector alone blanks the physical one. That is the GNOME counterpart of `kscreen-doctor output.<name>.disable`, and it is why the backend needs only one call per direction.
- The switch is expressed with long options, matching the manual page: `gdctl set --logical-monitor --primary --monitor HDMI-A-1 --mode 2560x1440@60 --x 0 --y 0 --scale 1.5`.
- `-P` (persist) is an option of the `set` subcommand: `gdctl set -P …`, not `gdctl -P set …`.
- Adding the virtual monitor changes the set of connected monitors, so mutter discards its stored layout and auto-configures: the desktop extends onto the virtual screen and the physical panel drops to its **preferred** timing — 3440x1440@50 instead of its usual 144 Hz in the field report. Persisting a configuration for the new monitor set and normalising it once at login resolved that.
- `gdctl show` lists only *configured* monitors, so "is this connector usable" cannot be answered from it — the backend reads connector presence from `/sys/class/drm` instead. Mode matching for `SUNSHINE_CLIENT_WIDTH/HEIGHT/FPS` uses `EDID_MODES` from the installer, the same list the KDE backend uses.
- `gdctl show --modes` exists in mutter 50 and lists available modes, which the field report found missing from plain `gdctl show`.

## HDR

GNOME exposes HDR as a per-monitor *colour mode* rather than a toggle: `--color-mode bt2100` (PQ / BT.2100) or `sdr-native`/`default`. With `VDISPLAY_HDR=1` the backend adds `--color-mode bt2100` to the same `gdctl set` call that switches the display, so nothing has to be restored afterwards. Whether mutter accepts BT.2100 for a force-enabled virtual output is unverified — HDR is tracked in [milestone 6](https://github.com/mdj2812/sunshine-vdisplay/milestone/6).

## References

- [UHD 770 field report](INTEL.md#field-reports) — the `gdctl` details above come from this report
- [ALTERNATIVES.md](ALTERNATIVES.md) — portal capture, including the ScreenCast restore-token caveat that hits RustDesk-style tools
