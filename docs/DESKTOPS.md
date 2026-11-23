# Desktop environments

The EDID, initramfs, and Sunshine parts of this repo are desktop-agnostic — they end at "a connector exists and Sunshine can capture it". Only the **display switching** step is desktop specific, because every compositor configures outputs through its own tool.

| Desktop | Session | Switching tool | Status | Notes |
|---------|---------|----------------|--------|-------|
| **KDE Plasma** | Wayland; X11 through RandR | `kscreen-doctor` | **Supported** | What the installer sets up — [INSTALL.md](INSTALL.md), [USAGE.md](USAGE.md) |
| **GNOME** | Wayland | `gdctl` | **Implemented, unverified** | CI covers the call contract against a stub; no run on real GNOME hardware yet — [notes](#gnome) |
| **Umbriel** | Wayland | `umbriel msg` and `umbriel config` | **Implemented, unverified end to end** | Runtime output controls; CI covers the call contract — [notes](#umbriel) |
| **Sway, labwc, other wlroots** | Wayland | wlroots tooling (`wlr-randr`, `kanshi`) | Planned | [milestone 5](https://github.com/mdj2812/sunshine-vdisplay/milestone/5) |
| **Hyprland** | Wayland | `hyprctl` | Planned | [milestone 5](https://github.com/mdj2812/sunshine-vdisplay/milestone/5) |
| **Any desktop** | X11 | `xrandr` | Planned | [milestone 4](https://github.com/mdj2812/sunshine-vdisplay/milestone/4) |
| **No compositor** (headless) | — | none needed | n/a | Nothing to switch; capture the virtual output directly |

Planned rows name the tool we expect to use, not something this project has verified — no hardware report has exercised them yet. KDE Plasma Wayland is the only backend verified end to end; the GNOME and Umbriel backends are covered by tests against their documented command contracts. On desktops without a backend the installer still does the EDID, initramfs, and Sunshine work, then warns that the swap step needs to be wired up by hand.

The session column says what a backend drives, not what has been tested: `kscreen-doctor` talks to KScreen, which drives KWin on Wayland and RandR on X11, though only Wayland has been run end to end here.

## Per-desktop notes

### KDE Plasma Wayland

The baseline this project was built on, and the only backend verified end to end. The installer wires `global_prep_cmd` to the scripts, Night Color is paused for the duration of a stream, and HDR is opt-in per output (`kscreen-doctor output.<connector>.hdr.enable`, paired with wide color gamut) — see [HDR.md](HDR.md).

One parsing trap worth knowing: `kscreen-doctor` colours its output **even when piped**, so the backend strips the escape codes before matching. Without that, `HDR:` and enabled/disabled detection silently returns the wrong answer.

### GNOME

Tracked in the [other desktop environments milestone](https://github.com/mdj2812/sunshine-vdisplay/milestone/5). The EDID, initramfs, and Sunshine parts of this repo do not care which desktop you run — only the display switching does.

**Status: implemented, unverified.** `scripts/backends/gnome.sh` drives `gdctl`, covered by `tests/desktop-backends-test.sh` against a stub. Nobody has run it in a real GNOME session yet — [issue #4](https://github.com/mdj2812/sunshine-vdisplay/issues/4) has a reporter with working scripts, and the [UHD 770 field report](INTEL.md#field-reports) is where the `gdctl` behaviour below was observed.

`gdctl` expresses the switch as one declarative call rather than a sequence:

- **Any monitor omitted from a `gdctl set` command line is turned off**, so declaring a logical monitor for the virtual connector alone blanks the physical one. That is the GNOME counterpart of `kscreen-doctor output.<name>.disable`, and it is why the backend needs one call per direction.
- The switch uses long options, matching the manual page: `gdctl set --logical-monitor --primary --monitor HDMI-A-1 --mode 2560x1440@60 --x 0 --y 0 --scale 1.5`.
- `-P` (persist) is an option of the `set` subcommand: `gdctl set -P …`, not `gdctl -P set …`.
- Adding the virtual monitor changes the set of connected monitors, so mutter discards its stored layout and auto-configures: the desktop extends onto the virtual screen and the physical panel drops to its **preferred** timing — 3440x1440@50 instead of its usual 144 Hz in that report. Persisting a configuration for the new monitor set and normalising it once at login resolved it.
- `gdctl show` lists only *configured* monitors, so "is this connector usable" cannot be answered from it — the backend reads connector presence from `/sys/class/drm` instead. Mode matching for `SUNSHINE_CLIENT_WIDTH/HEIGHT/FPS` uses `EDID_MODES` from the installer, the same list the KDE backend uses.
- `gdctl show --modes` exists in mutter 50 and lists available modes, which the field report found missing from plain `gdctl show`.
- HDR is a per-monitor *colour mode* rather than a toggle: `--color-mode bt2100` (PQ / BT.2100) or `sdr-native`/`default`. With `VDISPLAY_HDR=1` the backend adds `--color-mode bt2100` to the same `gdctl set` call that switches the display, so nothing has to be restored afterwards. Whether mutter accepts BT.2100 for a force-enabled virtual output is unverified — see [milestone 6](https://github.com/mdj2812/sunshine-vdisplay/milestone/6).

### Umbriel

Umbriel reports `XDG_CURRENT_DESKTOP=umbriel`. The backend uses:

- `umbriel msg output-enable <connector>` to add an output to the desktop.
- `umbriel msg output-disable <connector>` to remove it from the desktop.
- `umbriel config set output.<connector>.mode|position|scale|hdr <value>` for runtime overrides. These do not rewrite the user's `config.toml` and last until the compositor exits.

Umbriel parses the value passed to `config set` as TOML, so string values such as `mode` and `hdr` are sent quoted. `backend_has_output` reads connector presence from `/sys/class/drm` because an output removed with `output-disable` is still a valid connector and can be enabled again. The backend sets `output.<connector>.enabled` before calling `output-enable`/`output-disable`, so a persisted disabled state does not block the stream-start transition.

When restoring the physical monitor, the backend only sends `output-enable`. Umbriel then reapplies that connector's mode, position, and fractional scale from the user's configuration instead of replacing them with the repository defaults.

The display backend does not depend on Noctalia. Noctalia provides the shell, bar, notifications, and night-light schedule. The backend deliberately leaves Noctalia's night-light schedule alone instead of changing desktop state that is outside the compositor.

Some Sunshine builds abort under Noctalia immediately after logging `Starting system tray`. That is separate from KMS capture and output switching; see the tray workaround in [TROUBLESHOOTING.md](TROUBLESHOOTING.md#sunshine-crashes-at-startup-under-noctalia).

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

A backend is one file, `scripts/backends/<desktop>.sh`, implementing the `backend_*` versions of those entry points — `backend_require_tools`, `backend_has_output`, `backend_switch_to_virtual`, `backend_switch_to_physical`, `backend_show_outputs`, `backend_disable_night_color`, `backend_restore_night_color`. `vdisplay-common.sh` works out the desktop, sources the matching file, and dispatches; the installer copies the `backends/` directory to `~/bin/backends`.

Everything around the switch is shared: the `VDISPLAY`/`PDISPLAY` overrides in `vdisplay-common.local.sh`, connector presence from sysfs, client-adaptive resolution (matched against `EDID_MODES`, which the installer writes), and the `VDISPLAY_*` tuning knobs.

Three per-backend details worth knowing: `kscreen-doctor` colours its output even when piped, so the KDE backend strips escape codes before matching; `gdctl show` lists only *configured* monitors, so the GNOME backend takes connector presence from sysfs instead; and Umbriel's runtime config overrides avoid rewriting its TOML configuration.

`tests/desktop-backends-test.sh` runs both scripts per backend against stubbed tools, which is how the GNOME and Umbriel paths are covered without a matching desktop session. Reports from real sessions are what the [milestone 5](https://github.com/mdj2812/sunshine-vdisplay/milestone/5) rows still need.

## Adding a desktop

Add `scripts/backends/<desktop>.sh` with the `backend_*` functions, a case for it in `de_desktop`, and a stub plus assertions in `tests/desktop-backends-test.sh` — that test is what keeps the backends from drifting. `scripts/backends/kde.sh`, `gnome.sh`, and `umbriel.sh` are the references. Hardware reports for any of the planned rows are welcome: open an issue with the [AMD](https://github.com/mdj2812/sunshine-vdisplay/issues/new?template=amd-testing.md) or [Intel](https://github.com/mdj2812/sunshine-vdisplay/issues/new?template=intel-testing.md) template and say which desktop you run.
