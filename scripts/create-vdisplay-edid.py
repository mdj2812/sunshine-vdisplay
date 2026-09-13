#!/usr/bin/env python3
"""Generate a 256-byte EDID for NVIDIA virtual display (Sunshine/Moonlight)."""
import math
import struct
import sys


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
    pixel_clock = h_total * (v_active + v_blank) * refresh
    pixel_clock_khz = ((pixel_clock + 5000) // 10000) * 10
    return (pixel_clock_khz, rb_h_blank, rb_h_front, rb_h_sync, v_blank, rb_v_front, rb_v_sync)


VICS = [16, 63, 97, 118, 4, 31, 96]

CUSTOM_DTDS = [
    (2560, 1600, 120, 600, 375),  # 2560x1600 16:10 @120Hz
    (2560, 1440, 60, 600, 340),
    (1920, 1080, 120, 530, 300),
    (3840, 2160, 60, 600, 340),
]


def build_base_block():
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
    for i, (w, r) in enumerate([(1920, 60), (1280, 60), (1680, 60), (1600, 60)]):
        base[38 + i * 2] = (w // 8) - 31
        aspect = 0b00 if w == 1680 else 0b11
        base[39 + i * 2] = (aspect << 6) | (r - 60)
    for i in range(4, 8):
        base[38 + i * 2] = 0x01
        base[39 + i * 2] = 0x01

    base[54:72] = make_dtd(594000, 3840, 560, 176, 88, 2160, 90, 8, 10)
    pc, hb, hf, hs, vb, vf, vs = cvt_rb_timing(2560, 1440, 120)
    base[72:90] = make_dtd(pc, 2560, hb, hf, hs, 1440, vb, vf, vs, h_pol_pos=True, v_pol_pos=False)

    rl = bytearray(18)
    rl[0:4] = b"\x00\x00\x00\xFD"
    rl[5] = 24
    rl[6] = 120
    rl[7] = 15
    rl[8] = 200
    rl[9] = 70
    rl[10] = 0x00
    rl[11:18] = b"\x0A\x20\x20\x20\x20\x20\x20"
    base[90:108] = rl
    base[108:126] = make_descriptor(0xFC, b"VirtDisplay\n ")
    base[126] = 1
    return bytearray(fix_checksum(base))


def build_cta_extension():
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
    for w, h, r, hmm, vmm in CUSTOM_DTDS:
        if pos + 18 > 127:
            break
        pc, hb, hf, hs, vb, vf, vs = cvt_rb_timing(w, h, r)
        ext[pos:pos + 18] = make_dtd(
            pc, w, hb, hf, hs, h, vb, vf, vs, hmm, vmm,
            h_pol_pos=True, v_pol_pos=False,
        )
        pos += 18

    return bytearray(fix_checksum(ext))


def main():
    output = sys.argv[1] if len(sys.argv) > 1 else "virtual-display.bin"
    edid = build_base_block() + build_cta_extension()
    assert len(edid) == 256
    with open(output, "wb") as f:
        f.write(edid)
    print(f"Written {len(edid)} bytes to {output}")
    print(f"Validate with: edid-decode {output}")


if __name__ == "__main__":
    main()
