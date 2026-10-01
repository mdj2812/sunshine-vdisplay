# Desktop environments

The EDID, initramfs, and Sunshine parts of this repo are desktop-agnostic — they end at "a connector exists and Sunshine can capture it". Only the **display switching** step is desktop specific, because every compositor configures outputs through its own tool.

| Desktop | Session | Switching tool | Status | Notes |
|---------|---------|----------------|--------|-------|
| **KDE Plasma** | Wayland | `kscreen-doctor` | **Supported** | What the installer sets up — [INSTALL.md](INSTALL.md), [USAGE.md](USAGE.md) |
| **GNOME** | Wayland | `gdctl` | Planned | [GNOME.md](GNOME.md), reporter scripts offered in [#4](https://github.com/mdj2812/sunshine-vdisplay/issues/4) |
| **Sway, labwc, other wlroots** | Wayland | wlroots tooling (`wlr-randr`, `kanshi`) | Planned | [milestone 5](https://github.com/mdj2812/sunshine-vdisplay/milestone/5) |
| **Hyprland** | Wayland | `hyprctl` | Planned | [milestone 5](https://github.com/mdj2812/sunshine-vdisplay/milestone/5) |
| **Any desktop** | X11 | `xrandr` | Planned | [milestone 4](https://github.com/mdj2812/sunshine-vdisplay/milestone/4) |
| **No compositor** (headless) | — | none needed | n/a | Nothing to switch; capture the virtual output directly |

Planned rows name the tool we expect to use, not something this project has verified — no hardware report has exercised them yet. KDE Plasma Wayland is the only path the installer currently automates. On other desktops the installer still does the EDID, initramfs, and Sunshine work, then warns that the swap step needs to be wired up by hand.

## What a desktop backend has to do

`vdisplay-on.sh` / `vdisplay-off.sh` need four things from the compositor:

1. enable the virtual output at a given resolution
2. place it (position, scale, priority) so the desktop does not end up somewhere unexpected
3. disable the physical output, and keep the desktop on an output that is still scanning out
4. restore the physical output and disable the virtual one when the session ends

Client-adaptive resolution needs one more thing: the full mode list, so a `SUNSHINE_CLIENT_WIDTH/HEIGHT/FPS` request can be matched against the EDID modes (KDE reads it from `kscreen-doctor -o`; GNOME has to ask mutter's `DisplayConfig.GetCurrentState` over D-Bus, since `gdctl show` prints only current and preferred).

HDR is a further per-desktop property, tracked in [milestone 6](https://github.com/mdj2812/sunshine-vdisplay/milestone/6).

## Adding a desktop

The KDE implementation lives in `scripts/vdisplay-common.sh`: `enable_output`, `disable_output`, `tune_virtual_display`, `show_outputs`, plus `output_hdr_enabled` / `set_output_hdr` for HDR. A new desktop means a parallel set of those functions, selected at runtime from `XDG_CURRENT_DESKTOP` or by which tool is present, rather than a separate script — that keeps resolution matching, night-colour handling, and the `VDISPLAY`/`PDISPLAY` overrides in `vdisplay-common.local.sh` shared.

[GNOME.md](GNOME.md) records the `gdctl` behaviour such a backend has to encode. Hardware reports for any of the planned rows are welcome — open an issue with the [AMD](https://github.com/mdj2812/sunshine-vdisplay/issues/new?template=amd-testing.md) or [Intel](https://github.com/mdj2812/sunshine-vdisplay/issues/new?template=intel-testing.md) template and say which desktop you run.
