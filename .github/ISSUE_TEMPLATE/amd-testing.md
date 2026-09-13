---
name: AMD GPU testing
about: Report AMD virtual display testing for milestone 2
title: "[AMD] "
labels: []
assignees: []
---

## Hardware and OS

- **GPU:**
- **Driver / Mesa / RADV:**
- **Distro / kernel:**
- **Bootloader:**
- **Desktop:** KDE Plasma Wayland (version: )

## Virtual display path

- [ ] EDID + `drm.edid_firmware` + `video=<connector>:e` (no dummy plug)
- [ ] EDID + dummy plug
- [ ] `krfb-virtualmonitor` + portal capture
- [ ] `amdgpu.virtual_display` / vkms
- [ ] Other:

**Virtual connector (if EDID):**
**Physical connector:**

## Sunshine configuration

- **Sunshine version:**
- **Capture mode:** (kms / portal / kwin / other)
- **Encoder:** (vaapi / hevc_vulkan / other)
- **HDR working?** yes / no / untested

## Display switching

- [ ] Virtual display on + physical off when Moonlight session starts
- [ ] Physical restored when session ends
- **Client-adaptive resolution:** (SUNSHINE_CLIENT_* / fixed / broken)

## Results

**What worked:**

**What failed:**

**Logs / commands:**

```text
(paste journalctl --user -u sunshine snippets, kscreen-doctor -o, /proc/cmdline, etc.)
```

## Notes

Optional: link to related Reddit thread, prior EDID setup, or installer output.
