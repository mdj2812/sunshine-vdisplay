#!/usr/bin/env python3
"""Generate a 256-byte EDID for virtual display (Sunshine/Moonlight).

Usage:
  create-vdisplay-edid.py [--primary WxH@Hz] [--extra MODE,MODE,...] OUTPUT.bin

Examples:
  create-vdisplay-edid.py /tmp/virtual-display.bin
  create-vdisplay-edid.py --primary 2560x1440@120 --extra 1920x1080@60,3840x2160@60 out.bin
"""
import argparse
import math
import re
import struct
import sys

MODE_PATTERN = re.compile(r"^(\d+)x(\d+)@(\d+(?:\.\d+)?)$")

# width, height, refresh_hz, h_mm, v_mm
MODE_CATALOG = {
    "2560x1440@144": (2560, 1440, 144, 600, 340),
    "2560x1440@120": (2560, 1440, 120, 600, 340),
    "2560x1440@60": (2560, 1440, 60, 600, 340),
    "2560x1440@143.99": (2560, 1440, 143.99, 600, 340),
    "2560x1600@144": (2560, 1600, 144, 600, 375),
    "2560x1600@120": (2560, 1600, 120, 600, 375),
    "2560x1600@60": (2560, 1600, 60, 600, 375),
    "1920x1080@144": (1920, 1080, 144, 530, 300),
    "1920x1080@120": (1920, 1080, 120, 530, 300),
    "1920x1080@60": (1920, 1080, 60, 530, 300),
    "1920x1200@120": (1920, 1200, 120, 520, 320),
    "1920x1200@60": (1920, 1200, 60, 520, 320),
    "3840x2160@60": (3840, 2160, 60, 600, 340),
    "1600x1200@120": (1600, 1200, 120, 400, 300),
    "1600x1200@60": (1600, 1200, 60, 400, 300),
    "1280x960@120": (1280, 960, 120, 320, 240),
    "1280x960@60": (1280, 960, 60, 320, 240),
    "1280x1024@120": (1280, 1024, 120, 320, 260),
    "1280x1024@60": (1280, 1024, 60, 320, 260),
}

DEFAULT_PRIMARY = "2560x1440@120"
DEFAULT_EXTRAS = [
    "2560x1440@60",
    "2560x1600@120",
    "2560x1600@60",
    "1920x1080@120",
    "1920x1080@60",
]

VICS = [16, 63, 97, 118, 4, 31, 96]
MAX_MODES = 6
# EDID detailed timings store pixel clock in 10 kHz units (16-bit, max 655.35 MHz).
MAX_DTD_PIXEL_CLOCK_KHZ = 655350


def make_dtd(pixel_clock_khz, h_active, h_blank, h_front, h_sync,
             v_active, v_blank, v_front, v_sync, h_mm=600, v_mm=340,
             h_pol_pos=True, v_pol_pos=True):
    dtd = bytearray(18)
    struct.pack_into("<H", dtd, 0, pixel_clock_khz // 10)
    dtd[2] = h_active & 0xFF
    dtd[3] = h_blank & 0xFF
    dtd[4] = ((h_active >> 8) & 0x0F) << 4 | ((h_blank >> 8) & 0x0F)
    dtd[5] = v_active & 0xFF
    dtd[6] = v_blank & 0xFF
    dtd[7] = ((v_active >> 8) & 0x0F) << 4 | ((v_blank >> 8) & 0x0F)
    dtd[8] = h_front & 0xFF
    dtd[9] = h_sync & 0xFF
    dtd[10] = ((v_front & 0x0F) << 4) | (v_sync & 0x0F)
    dtd[11] = (((h_front >> 8) & 0x03) << 6 | ((h_sync >> 8) & 0x03) << 4 |
               ((v_front >> 4) & 0x03) << 2 | ((v_sync >> 4) & 0x03))
    dtd[12] = h_mm & 0xFF
    dtd[13] = v_mm & 0xFF
    dtd[14] = ((h_mm >> 8) & 0x0F) << 4 | ((v_mm >> 8) & 0x0F)
    dtd[15] = 0
    dtd[16] = 0
    flags = 0x18
    if h_pol_pos:
        flags |= 0x02
    if v_pol_pos:
        flags |= 0x04
    dtd[17] = flags
    return bytes(dtd)


def make_descriptor(tag, data):
    desc = bytearray(18)
    desc[3] = tag
    for i, b in enumerate(data[:13]):
        desc[5 + i] = b
    return bytes(desc)


def fix_checksum(block):
    block = bytearray(block)
    block[127] = (256 - (sum(block[:127]) % 256)) % 256
    return bytes(block)


def cvt_rb_timing(h_active, v_active, refresh):
    rb_h_blank, rb_h_sync, rb_h_front = 160, 32, 48
    rb_v_sync = 8 if v_active < 1200 else (7 if v_active < 2000 else 10)
    rb_v_front = 3
    h_total = h_active + rb_h_blank
    v_blank = max(
        rb_v_front + rb_v_sync + 1,
        int(460 * refresh * (v_active + rb_v_front + rb_v_sync + 1) / 1_000_000) + 1,
    )
    pixel_clock_khz = _pixel_clock_khz(h_total, v_active + v_blank, refresh)
    return (pixel_clock_khz, rb_h_blank, rb_h_front, rb_h_sync, v_blank, rb_v_front, rb_v_sync)


def _pixel_clock_khz(h_total, v_total, refresh):
    pixel_clock = h_total * v_total * float(refresh)
    return int(((pixel_clock + 5000) // 10000) * 10)


def fit_dtd_timing(width, height, refresh):
    """Return CVT-RB-ish timings that fit the EDID DTD pixel clock field."""
    pc, hb, hf, hs, vb, vf, vs = cvt_rb_timing(width, height, refresh)
    min_v_blank = vf + vs + 1
    h_total = width + hb

    while pc // 10 > MAX_DTD_PIXEL_CLOCK_KHZ // 10:
        if vb <= min_v_blank:
            raise ValueError(
                f"mode {mode_key(width, height, refresh)} exceeds EDID pixel clock limit "
                f"({pc} kHz > {MAX_DTD_PIXEL_CLOCK_KHZ} kHz)"
            )
        vb -= 1
        pc = _pixel_clock_khz(h_total, height + vb, refresh)

    return pc, hb, hf, hs, vb, vf, vs


def mode_key(width, height, refresh):
    refresh_text = f"{refresh:g}"
    if refresh_text.endswith(".0"):
        refresh_text = refresh_text[:-2]
    return f"{width}x{height}@{refresh_text}"


def parse_mode(text):
    match = MODE_PATTERN.match(text.strip())
    if not match:
        raise ValueError(f"invalid mode '{text}' (expected WIDTHxHEIGHT@HZ, e.g. 2560x1440@120)")
    width, height, refresh = int(match.group(1)), int(match.group(2)), float(match.group(3))
    if width < 640 or height < 480 or refresh < 24 or refresh > 360:
        raise ValueError(f"mode out of supported range: {text}")
    return mode_key(width, height, refresh)


def mode_tuple(key):
    if key in MODE_CATALOG:
        return MODE_CATALOG[key]
    match = MODE_PATTERN.match(key)
    width, height, refresh = int(match.group(1)), int(match.group(2)), float(match.group(3))
    aspect = width / height
    if abs(aspect - 16 / 10) < 0.02:
        h_mm, v_mm = 600, 375
    elif abs(aspect - 16 / 9) < 0.02:
        h_mm, v_mm = 600, 340
    elif abs(aspect - 4 / 3) < 0.02:
        h_mm, v_mm = 400, 300
    else:
        h_mm = max(160, width // 4)
        v_mm = max(90, height // 4)
    return (width, height, refresh, h_mm, v_mm)


def normalize_mode_list(primary, extras):
    ordered = []
    seen = set()

    def add(key):
        key = parse_mode(key)
        if key in seen:
            return
        seen.add(key)
        ordered.append(key)

    add(primary)
    for item in extras:
        if item:
            add(item)

    if len(ordered) > MAX_MODES:
        ordered = ordered[:MAX_MODES]
    return ordered


def make_dtd_for_mode(key):
    width, height, refresh, h_mm, v_mm = mode_tuple(key)
    pc, hb, hf, hs, vb, vf, vs = fit_dtd_timing(width, height, refresh)
    return make_dtd(pc, width, hb, hf, hs, height, vb, vf, vs, h_mm, v_mm,
                    h_pol_pos=True, v_pol_pos=False)


def build_base_block(primary, secondary=None, modes=None):
    modes = modes or [primary]
    base = bytearray(128)
    base[0:8] = b"\x00\xFF\xFF\xFF\xFF\xFF\xFF\x00"
    base[8:10] = b"\x32\xF8"
    base[10:12] = b"\x01\x00"
    base[12:16] = b"\x00\x00\x00\x00"
    base[16] = 1
    base[17] = 36
    base[18] = 1
    base[19] = 4
    base[20] = 0xB2
    base[21] = 60
    base[22] = 34
    base[23] = 120
    base[24] = 0x0B
    base[25:35] = bytes([0xEE, 0x95, 0xA3, 0x54, 0x4C, 0x99, 0x26, 0x0F, 0x50, 0x54])
    base[35:38] = bytes([0x21, 0x08, 0x00])
    for i in range(8):
        base[38 + i * 2] = 0x01
        base[39 + i * 2] = 0x01

    primary_dtd = make_dtd_for_mode(primary)
    base[54:72] = primary_dtd
    if secondary and secondary != primary:
        base[72:90] = make_dtd_for_mode(secondary)
    else:
        base[72:90] = primary_dtd

    max_refresh = max(int(mode_tuple(mode)[2]) for mode in modes)
    rl = bytearray(18)
    rl[0:4] = b"\x00\x00\x00\xFD"
    rl[5] = 24
    rl[6] = min(200, max(60, max_refresh))
    rl[7] = 15
    rl[8] = 200
    rl[9] = 70
    rl[10] = 0x00
    rl[11:18] = b"\x0A\x20\x20\x20\x20\x20\x20"
    base[90:108] = rl
    base[108:126] = make_descriptor(0xFC, b"VirtDisplay\n ")
    base[126] = 1
    return bytearray(fix_checksum(base))


def build_cta_extension(modes):
    ext = bytearray(128)
    ext[0] = 0x02
    ext[1] = 0x03
    data = bytearray()

    data.append(0x40 | len(VICS))
    data.extend(VICS)

    data.extend([
        0xE6, 0x06, 0x07, 0x01,
        int(32 * math.log2(1000 / 50)),
        int(32 * math.log2(400 / 50)),
        int(255 * math.sqrt(0.01 * 100 / 1000)),
    ])

    data.extend([0xE3, 0x05, 0xC0, 0x00])
    data.extend([0x66, 0x03, 0x0C, 0x00, 0x10, 0x00, 0x78])
    data.extend([0x67, 0xD8, 0x5D, 0xC4, 0x01, 0x78, 0x80, 0x00])
    data.extend([0xE2, 0x00, 0x00])

    dtd_offset = 4 + len(data)
    ext[2] = dtd_offset
    ext[3] = 0x30
    ext[4:4 + len(data)] = data

    pos = dtd_offset
    for key in modes:
        if pos + 18 > 127:
            break
        ext[pos:pos + 18] = make_dtd_for_mode(key)
        pos += 18

    return bytearray(fix_checksum(ext))


def build_edid(primary=DEFAULT_PRIMARY, extras=None):
    extras = DEFAULT_EXTRAS if extras is None else extras
    modes = normalize_mode_list(primary, extras)
    secondary = modes[1] if len(modes) > 1 else None
    return build_base_block(modes[0], secondary, modes) + build_cta_extension(modes)


def parse_args(argv):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("output", nargs="?", default="virtual-display.bin")
    parser.add_argument("--primary", default=DEFAULT_PRIMARY,
                        help=f"Preferred mode (default: {DEFAULT_PRIMARY})")
    parser.add_argument("--extra", default="",
                        help="Comma-separated additional modes (default: common presets)")
    return parser.parse_args(argv)


def main():
    args = parse_args(sys.argv[1:])
    extras = [item.strip() for item in args.extra.split(",") if item.strip()] if args.extra else None
    primary = parse_mode(args.primary)
    edid = build_edid(primary, extras)
    assert len(edid) == 256
    with open(args.output, "wb") as handle:
        handle.write(edid)
    modes = normalize_mode_list(primary, extras or DEFAULT_EXTRAS)
    print(f"Written {len(edid)} bytes to {args.output}")
    print(f"Primary mode: {modes[0]}")
    if len(modes) > 1:
        print(f"Additional modes: {', '.join(modes[1:])}")
    print(f"Validate with: edid-decode {args.output}")


if __name__ == "__main__":
    main()
