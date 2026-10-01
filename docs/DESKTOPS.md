# Desktop environments

The EDID, initramfs, and Sunshine parts of this repo are desktop-agnostic — they end at "a connector exists and Sunshine can capture it". Only the **display switching** step is desktop specific, because every compositor configures outputs through its own tool.

| Desktop | Session | Switching tool | Status | Notes |
|---------|---------|----------------|--------|-------|
| **KDE Plasma** | Wayland | `kscreen-doctor` | **Supported** | What the installer sets up — [INSTALL.md](INSTALL.md), [USAGE.md](USAGE.md) |
| **GNOME** | Wayland | `gdctl` | **Implemented, unverified** | CI covers the call contract against a stub; no run on real GNOME hardware yet — [GNOME.md](GNOME.md) |
| **Sway, labwc, other wlroots** | Wayland | wlroots tooling (`wlr-randr`, `kanshi`) | Planned | [milestone 5](https://github.com/mdj2812/sunshine-vdisplay/milestone/5) |
| **Hyprland** | Wayland | `hyprctl` | Planned | [milestone 5](https://github.com/mdj2812/sunshine-vdisplay/milestone/5) |
| **Any desktop** | X11 | `xrandr` | Planned | [milestone 4](https://github.com/mdj2812/sunshine-vdisplay/milestone/4) |
| **No compositor** (headless) | — | none needed | n/a | Nothing to switch; capture the virtual output directly |

Planned rows name the tool we expect to use, not something this project has verified — no hardware report has exercised them yet. KDE Plasma Wayland is the only backend verified end to end; the GNOME backend is written from mutter's `gdctl` manual page and covered by tests against a stub, but nobody has run it in a GNOME session. On desktops without a backend the installer still does the EDID, initramfs, and Sunshine work, then warns that the swap step needs to be wired up by hand.

## What a backend has to provide

`vdisplay-on.sh` / `vdisplay-off.sh` never talk to a compositor directly. They call `scripts/vdisplay-common.sh`, which picks a backend from `XDG_CURRENT_DESKTOP` (falling back to whichever tool is installed) and dispatches:

| Entry point | Purpose |
|-------------|---------|
| `de_require_tools` | fail early when this desktop's tooling is missing |
| `de_has_output <connector>` | is the connector usable |
| `de_switch_to_virtual <res>` | virtual output on at `<res>`, physical one off, HDR applied when `VDISPLAY_HDR=1` |
| `de_switch_to_physical` | physical output back on, virtual one off, HDR state restored |
| `de_show_outputs` | dump the current configuration |
| `de_disable_night_color` / `de_restore_night_color` | pause and restore Night Color / Night Light |

A backend is a `kde_*` or `gnome_*` set of those functions; `de_desktop` chooses between them. Everything around the switch is shared: the `VDISPLAY`/`PDISPLAY` overrides in `vdisplay-common.local.sh`, connector presence from sysfs, client-adaptive resolution (matched against `EDID_MODES`, which the installer writes), and the `VDISPLAY_*` tuning knobs.

Two per-backend details worth knowing: `kscreen-doctor` colours its output even when piped, so the KDE backend strips escape codes before matching; and `gdctl show` lists only *configured* monitors, so the GNOME backend takes connector presence from sysfs instead.

`tests/desktop-backends-test.sh` runs both scripts per backend against stubbed tools, which is how the GNOME path is covered without a GNOME machine. HDR is a further per-desktop property, tracked in [milestone 6](https://github.com/mdj2812/sunshine-vdisplay/milestone/6).

## Adding a desktop

Add a `de_*` case for the new desktop plus its `tool_*` functions in `scripts/vdisplay-common.sh`, and extend `tests/desktop-backends-test.sh` with its stub and assertions — that test is what keeps the backends from drifting. Hardware reports for any of the planned rows are welcome: open an issue with the [AMD](https://github.com/mdj2812/sunshine-vdisplay/issues/new?template=amd-testing.md) or [Intel](https://github.com/mdj2812/sunshine-vdisplay/issues/new?template=intel-testing.md) template and say which desktop you run.
