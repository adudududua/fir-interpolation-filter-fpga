#!/usr/bin/env python3
from pathlib import Path
import struct
import sys
import zlib

blob = Path("network_capture/results/tx_frames.bin").read_bytes()
frame_size = 8 + 14 + 828 + 4
if len(blob) != 16 * frame_size:
    raise SystemExit(f"文件长度 {len(blob)} != 期望长度 {16 * frame_size}")

all_samples = []
for packet_index in range(16):
    frame = blob[packet_index*frame_size:(packet_index+1)*frame_size]
    assert frame[:7] == b"\x55" * 7 and frame[7] == 0xD5
    body, fcs = frame[8:-4], frame[-4:]
    expected_fcs = struct.pack("<I", zlib.crc32(body) & 0xFFFFFFFF)
    assert fcs == expected_fcs, (packet_index, fcs.hex(), expected_fcs.hex())
    assert body[:6] == b"\xff" * 6
    assert body[12:14] == b"\x08\x00"
    ip = body[14:34]
    checksum = sum(struct.unpack("!10H", ip))
    while checksum >> 16:
        checksum = (checksum & 0xFFFF) + (checksum >> 16)
    assert checksum == 0xFFFF
    udp = body[34:]
    assert struct.unpack("!HHH", udp[:6]) == (4000, 4000, 808)
    app = udp[8:]
    magic, version, flags, index, count, frame_id, offset, samples, bits, fmt, \
        total, start_index, _ = struct.unpack("<4sBBBBIIHBBHI6s", app[:32])
    assert (magic, version, flags, index, count) == (b"DAC2", 1, 7, packet_index, 16)
    assert (frame_id, offset, samples, bits, fmt, total) == \
           (0x12345678, packet_index * 256, 256, 24, 1, 4096)
    assert start_index == 0x11223344
    payload = app[32:]
    for pos in range(0, len(payload), 3):
        all_samples.append(int.from_bytes(payload[pos:pos+3], "little", signed=False))

expected = list(range(4096))
if all_samples != expected:
    for i, (got, want) in enumerate(zip(all_samples, expected)):
        if got != want:
            raise SystemExit(f"样本 {i} 不一致：实际 {got}，期望 {want}")
print("通过：以太网/IP/UDP/应用头/FCS 以及全部 4096 个样本均完全正确")
