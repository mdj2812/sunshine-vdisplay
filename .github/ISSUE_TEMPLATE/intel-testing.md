---
name: Intel iGPU testing
about: Report Intel iGPU virtual display and Sunshine streaming results
title: "[Intel] "
labels: []
assignees: []
---

## Hardware

- **GPU:**
- **Driver:** i915 / xe
- **Mesa / intel-media-driver:**

## Software

- **Distro + version:**
- **Kernel:**
- **Bootloader:**
- **KDE Plasma (Wayland):**
- **Sunshine version:**

## Virtual display path

- [ ] EDID + `drm.edid_firmware` + `video=<connector>:e` (no dummy plug)
- [ ] EDID + dummy plug on spare connector
- [ ] `krfb-virtualmonitor` + portal capture
- [ ] Other:

**Connectors tested (`VDISPLAY` / `PDISPLAY`):**

## Sunshine

- **Capture mode:**
- **Encoder:** VAAPI / QSV / other
- **Physical monitor auto-switch on session start/end:** yes / no

## Results

- **Moonlight connect:** yes / no
- **Stable stream:** yes / no
- **HDR:** yes / no / untested
- **High refresh / adaptive resolution:** notes

## Logs / notes

```
(paste relevant kernel cmdline, /sys/class/drm connector status, Sunshine log excerpts)
```
