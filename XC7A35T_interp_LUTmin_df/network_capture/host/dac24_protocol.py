#!/usr/bin/env python3
"""DAC24 v1 UDP protocol parsing and stateful frame assembly.

This module intentionally has no GUI or NumPy dependency.  Both the command-line
receiver and the Qt application can use it without duplicating protocol rules.
"""
from __future__ import annotations

import struct
from collections import OrderedDict
from dataclasses import dataclass, field
from typing import Optional, Tuple


MAGIC = b"DAC2"
VERSION = 1
# bytes 26..31 were all-zero reserved bytes in the original bitstream.  The
# compatible extension names them without changing the 32-byte wire layout.
HEADER = struct.Struct("<4sBBBBIIHBBHIIH")
SAMPLE_BITS = 24
SAMPLE_FORMAT_SIGNED_LE = 1
SAMPLES_PER_PACKET = 256
SUPPORTED_FRAME_SPECS = {(16, 4096), (64, 16384)}

MODE_NAMES = {0: "1x", 1: "4x", 2: "8x", 3: "128x"}
MODE_CODES = {name: code for code, name in MODE_NAMES.items()}
MODE_FACTORS = {0: 1, 1: 4, 2: 8, 3: 128}


class ProtocolError(ValueError):
    """A datagram violates the DAC24 v1 wire format."""


@dataclass(frozen=True)
class ParsedPacket:
    """One validated DAC24 UDP application datagram."""

    peer_ip: str
    flags: int
    packet_index: int
    packet_count: int
    frame_id: int
    sample_offset: int
    total_samples: int
    start_sample_index: int
    samples: Tuple[int, ...]
    input_transaction_id: int = 0
    capture_status: int = 0

    @property
    def family_48k(self) -> int:
        return (self.flags >> 2) & 1

    @property
    def mode(self) -> int:
        return self.flags & 0x3

    @property
    def upload_source(self) -> int:
        return (self.flags >> 3) & 1

    @property
    def descriptor_key(self) -> Tuple[str, int, int, int, int, int, int, int]:
        # The full descriptor is part of the key.  This prevents packets left
        # over from a previous FPGA configuration (whose frame_id restarted)
        # from being merged with the new reset epoch.
        return (
            self.peer_ip,
            self.frame_id,
            self.flags,
            self.packet_count,
            self.total_samples,
            self.start_sample_index,
            self.input_transaction_id,
            self.capture_status,
        )


@dataclass(frozen=True)
class CaptureFrame:
    """One immutable, fully reassembled 4096- or 16384-sample capture."""

    peer_ip: str
    frame_id: int
    flags: int
    packet_count: int
    total_samples: int
    start_sample_index: int
    samples: Tuple[int, ...]
    input_transaction_id: int = 0
    capture_status: int = 0
    duplicate_packets: int = 0

    @property
    def family_48k(self) -> int:
        return (self.flags >> 2) & 1

    @property
    def family_rate(self) -> int:
        return 48000 if self.family_48k else 44100

    @property
    def mode(self) -> int:
        return self.flags & 0x3

    @property
    def mode_name(self) -> str:
        return MODE_NAMES[self.mode]

    @property
    def sample_rate(self) -> int:
        return self.family_rate * MODE_FACTORS[self.mode]

    @property
    def upload_source(self) -> int:
        return (self.flags >> 3) & 1


@dataclass(frozen=True)
class PacketProgress:
    peer_ip: str
    frame_id: int
    flags: int
    start_sample_index: int
    packet_index: int
    received_packets: int
    packet_count: int
    duplicate_packets: int

    @property
    def family_48k(self) -> int:
        return (self.flags >> 2) & 1

    @property
    def mode(self) -> int:
        return self.flags & 0x3


@dataclass(frozen=True)
class FeedResult:
    """Result of feeding one valid packet to a :class:`FrameAssembler`."""

    progress: Optional[PacketProgress] = None
    frame: Optional[CaptureFrame] = None
    ignored_by_filter: bool = False
    ignored_packet: Optional[ParsedPacket] = None


@dataclass
class _PartialFrame:
    packet: ParsedPacket
    packets: dict[int, Tuple[int, ...]] = field(default_factory=dict)
    duplicate_packets: int = 0


def decode_s24le(payload: bytes) -> Tuple[int, ...]:
    """Decode packed signed 24-bit little-endian samples."""

    if len(payload) % 3:
        raise ProtocolError("24 位数据区的字节数不是 3 的整数倍")
    values = []
    for offset in range(0, len(payload), 3):
        value = (
            payload[offset]
            | (payload[offset + 1] << 8)
            | (payload[offset + 2] << 16)
        )
        if value & 0x800000:
            value -= 1 << 24
        values.append(value)
    return tuple(values)


def parse_packet(data: bytes, peer_ip: str = "") -> ParsedPacket:
    """Validate and decode one DAC24 v1 UDP payload."""

    if len(data) < HEADER.size:
        raise ProtocolError("DAC24 网络包长度不足")
    fields = HEADER.unpack_from(data)
    (
        magic,
        version,
        flags,
        packet_index,
        packet_count,
        frame_id,
        sample_offset,
        samples_in_packet,
        sample_bits,
        sample_format,
        total_samples,
        start_sample_index,
        input_transaction_id,
        capture_status,
    ) = fields

    if magic != MAGIC or version != VERSION:
        raise ProtocolError("不是 DAC24 v1 网络包")
    if flags & 0xF0:
        raise ProtocolError("DAC24 v1 flags 的保留位不为零")
    if sample_bits != SAMPLE_BITS or sample_format != SAMPLE_FORMAT_SIGNED_LE:
        raise ProtocolError("不支持的样本格式")
    if packet_index >= packet_count:
        raise ProtocolError("DAC24 v1 网络包编号或总包数无效")
    if (
        samples_in_packet != SAMPLES_PER_PACKET
        or (packet_count, total_samples) not in SUPPORTED_FRAME_SPECS
    ):
        raise ProtocolError(
            "DAC24 v1 帧必须是 16 包/4096 点或 64 包/16384 点"
        )
    if sample_offset != packet_index * SAMPLES_PER_PACKET:
        raise ProtocolError("DAC24 v1 样本偏移量无效")

    expected_size = HEADER.size + samples_in_packet * 3
    if len(data) != expected_size:
        raise ProtocolError(
            f"数据包长度为 {len(data)} 字节，应为 {expected_size} 字节"
        )
    samples = decode_s24le(data[HEADER.size:])
    return ParsedPacket(
        peer_ip=peer_ip,
        flags=flags,
        packet_index=packet_index,
        packet_count=packet_count,
        frame_id=frame_id,
        sample_offset=sample_offset,
        total_samples=total_samples,
        start_sample_index=start_sample_index,
        input_transaction_id=input_transaction_id,
        capture_status=capture_status,
        samples=samples,
    )


class FrameAssembler:
    """Stateful, out-of-order DAC24 frame assembler.

    Family/mode filtering happens before a packet enters the partial-frame
    cache.  This is important during the SW8 -> SW4 reset procedure: 48 kHz
    transition packets cannot consume cache entries or be compared with a
    44.1 kHz reference.
    """

    def __init__(
        self,
        expected_family_48k: Optional[int] = None,
        expected_mode: Optional[int] = None,
        max_partial_frames: int = 64,
    ) -> None:
        if expected_family_48k not in (None, 0, 1):
            raise ValueError("expected_family_48k 必须为 None、0 或 1")
        if expected_mode not in (None, 0, 1, 2, 3):
            raise ValueError("expected_mode 必须为 None 或 0..3")
        if max_partial_frames < 1:
            raise ValueError("max_partial_frames 必须大于零")
        self.expected_family_48k = expected_family_48k
        self.expected_mode = expected_mode
        self.max_partial_frames = max_partial_frames
        self._frames: "OrderedDict[Tuple[str, int, int, int, int, int, int, int], _PartialFrame]" = OrderedDict()

    @property
    def partial_frame_count(self) -> int:
        return len(self._frames)

    def clear(self) -> None:
        self._frames.clear()

    def _matches_filter(self, packet: ParsedPacket) -> bool:
        return not (
            self.expected_family_48k is not None
            and packet.family_48k != self.expected_family_48k
        ) and not (
            self.expected_mode is not None and packet.mode != self.expected_mode
        )

    def feed_datagram(self, data: bytes, peer_ip: str = "") -> FeedResult:
        return self.feed(parse_packet(data, peer_ip))

    def feed(self, packet: ParsedPacket) -> FeedResult:
        if not self._matches_filter(packet):
            return FeedResult(ignored_by_filter=True, ignored_packet=packet)

        key = packet.descriptor_key
        partial = self._frames.get(key)
        if partial is None:
            partial = _PartialFrame(packet=packet)
            self._frames[key] = partial
            while len(self._frames) > self.max_partial_frames:
                self._frames.popitem(last=False)
        else:
            self._frames.move_to_end(key)

        previous = partial.packets.get(packet.packet_index)
        if previous is not None:
            if previous != packet.samples:
                raise ProtocolError(
                    f"帧 {packet.frame_id}：重复包 {packet.packet_index} 的内容发生冲突"
                )
            partial.duplicate_packets += 1
        else:
            partial.packets[packet.packet_index] = packet.samples

        progress = PacketProgress(
            peer_ip=packet.peer_ip,
            frame_id=packet.frame_id,
            flags=packet.flags,
            start_sample_index=packet.start_sample_index,
            packet_index=packet.packet_index,
            received_packets=len(partial.packets),
            packet_count=packet.packet_count,
            duplicate_packets=partial.duplicate_packets,
        )

        if len(partial.packets) != packet.packet_count:
            return FeedResult(progress=progress)

        samples = tuple(
            sample
            for index in range(packet.packet_count)
            for sample in partial.packets[index]
        )
        if len(samples) != packet.total_samples:
            raise ProtocolError(
                f"帧 {packet.frame_id}：重组得到 {len(samples)} 个样本，"
                f"包头声明 {packet.total_samples} 个"
            )
        del self._frames[key]
        frame = CaptureFrame(
            peer_ip=packet.peer_ip,
            frame_id=packet.frame_id,
            flags=packet.flags,
            packet_count=packet.packet_count,
            total_samples=packet.total_samples,
            start_sample_index=packet.start_sample_index,
            input_transaction_id=packet.input_transaction_id,
            capture_status=packet.capture_status,
            samples=samples,
            duplicate_packets=partial.duplicate_packets,
        )
        return FeedResult(progress=progress, frame=frame)
