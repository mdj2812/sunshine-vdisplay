# KDE Wayland alternatives

This repo’s default path is **custom EDID + kernel force-enable + KMS capture + `kscreen-doctor` display switching**. On **KDE Plasma Wayland**, there is also a compositor-native option that avoids initramfs and bootloader changes.

## EDID + KMS (this repo)

| Pros | Cons |
|------|------|
| Works without KDE-specific APIs | Requires initramfs + kernel cmdline changes |
| Same approach across NVIDIA and AMD | Needs a spare GPU connector |
| Custom EDID can advertise HDR metadata | NVIDIA virtual connectors still don’t enable HDR at runtime |
| High refresh modes in EDID | EDID changes need initramfs rebuild + reboot |

See [INSTALL.md](INSTALL.md) and [MANUAL.md](MANUAL.md).

## `krfb-virtualmonitor` + portal capture

KWin can create a virtual output that Sunshine captures through the desktop portal (`capture = portal` or Sunshine’s `kwin` capture mode).

| Pros | Cons |
|------|------|
| No initramfs or kernel parameters | **KDE only** |
| No spare connector required | Virtual output must exist **before** Sunshine starts |
| Arbitrary resolution per client | Portal token is tied to the output UUID |
| Similar latency to EDID + KMS (~4.5 ms @ 4K60 reported) | Different automation than `global_prep_cmd` + `kscreen-doctor` |

Typical flow:

1. Moonlight connects → Sunshine injects `SUNSHINE_CLIENT_WIDTH`, `SUNSHINE_CLIENT_HEIGHT`, `SUNSHINE_CLIENT_FPS`
2. Prep script starts `krfb-virtualmonitor` at that resolution
3. Disable physical output(s) via `kscreen-doctor`
4. Sunshine captures the virtual output through the portal
5. On disconnect → stop virtual monitor, restore physical display

Community guides:

- [KDE Wayland virtual display with krfb-virtualmonitor](https://www.reddit.com/r/MoonlightStreaming/comments/1tg1dnc/guide_sunshine_on_kde_wayland_virtual_display/) (r/MoonlightStreaming)

This does **not** replace other milestones (Sway, GNOME, X11, Intel, etc.) — those still need compositor-specific tooling.

## `amdgpu.virtual_display` / vkms

See [AMD.md](AMD.md). Intended for **headless-only** AMD hosts, not daily desktop + streaming on the same session.

## Choosing a path

| Your situation | Consider |
|----------------|----------|
| NVIDIA desktop, want one installer | **EDID + KMS** (current repo) |
| AMD desktop, keep physical monitor | **EDID + force-enable** (milestone 2) or **krfb** |
| KDE only, avoid boot changes | **krfb + portal** |
| Dedicated headless AMD box | **vkms** or EDID |
| Need HDR on Linux | **EDID** (verify end-to-end; vkms has no EDID HDR path) |

Contributions documenting krfb automation in a separate script or optional install profile are welcome — please tag the relevant [milestone](https://github.com/mdj2812/sunshine-vdisplay/milestones).
