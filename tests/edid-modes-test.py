#!/usr/bin/env python3
"""Verify that all six advertised EDID modes retain detailed timings."""

from __future__ import annotations

import importlib.util
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parent.parent
SPEC = importlib.util.spec_from_file_location(
    "create_vdisplay_edid", REPO_ROOT / "scripts" / "create-vdisplay-edid.py"
)
assert SPEC and SPEC.loader
EDID = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(EDID)


def dtd_resolution(descriptor: bytes) -> tuple[int, int] | None:
    if len(descriptor) != 18 or descriptor[:2] == b"\x00\x00":
        return None
    width = descriptor[2] | ((descriptor[4] & 0xF0) << 4)
    height = descriptor[5] | ((descriptor[7] & 0xF0) << 4)
    return width, height


modes = [
    "3200x2136@60",
    "2560x1440@120",
    "2560x1440@60",
    "2560x1600@120",
    "1920x1080@120",
    "3840x2160@60",
]
blob = EDID.build_edid(modes[0], modes[1:])
assert len(blob) == 256
assert blob[113:126] == b"eDP-Virtual\n "

detailed = []
for offset in (54, 72, 90, 108):
    resolution = dtd_resolution(blob[offset : offset + 18])
    if resolution:
        detailed.append(resolution)

extension = blob[128:256]
assert extension[0] == 0x02
for offset in range(extension[2], 127, 18):
    descriptor = extension[offset : offset + 18]
    resolution = dtd_resolution(descriptor)
    if resolution:
        detailed.append(resolution)

expected = [(3200, 2136), (2560, 1440), (2560, 1440), (2560, 1600),
            (1920, 1080), (3840, 2160)]
assert detailed == expected, (detailed, expected)
print("ok: EDID contains detailed timings for all six selected modes")
