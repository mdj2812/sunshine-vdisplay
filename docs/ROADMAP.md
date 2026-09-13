# Roadmap

Current scope is **NVIDIA + KDE Plasma Wayland**. Planned work is tracked in [GitHub milestones](https://github.com/mdj2812/sunshine-vdisplay/milestones):

| Milestone | Goal |
|-----------|------|
| [NVIDIA + KDE Wayland](https://github.com/mdj2812/sunshine-vdisplay/milestone/1) | Baseline: EDID virtual display, installer, Sunshine automation, multi-distro initramfs; document KDE-native alternatives |
| [AMD GPU](https://github.com/mdj2812/sunshine-vdisplay/milestone/2) | EDID + force-enable on spare connector (primary); VAAPI and `hevc_vulkan` encoders; evaluate vkms headless-only path — see [AMD.md](AMD.md) |
| [Intel iGPU](https://github.com/mdj2812/sunshine-vdisplay/milestone/3) | i915/xe virtual outputs, QSV/VAAPI encoding |
| [X11](https://github.com/mdj2812/sunshine-vdisplay/milestone/4) | X11 session support via `xrandr` display switching |
| [Other desktop environments](https://github.com/mdj2812/sunshine-vdisplay/milestone/5) | GNOME, Sway, labwc, and other compositors beyond `kscreen-doctor` |

Related docs:

- [AMD.md](AMD.md) — AMD testing paths and encoder notes
- [ALTERNATIVES.md](ALTERNATIVES.md) — KDE `krfb-virtualmonitor` vs EDID tradeoffs

Contributions and issues for future milestones are welcome — please tag the relevant milestone when opening an issue. For AMD hardware, use the [AMD testing issue template](https://github.com/mdj2812/sunshine-vdisplay/issues/new?template=amd-testing.md).
