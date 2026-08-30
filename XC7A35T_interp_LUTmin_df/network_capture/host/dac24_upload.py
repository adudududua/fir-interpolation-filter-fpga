#!/usr/bin/env python3
"""Pure host-side DACU V1 protocol and 1x waveform preparation helpers.

This module intentionally has no Qt dependency so packet construction, CRC and
sample quantisation can be tested without installing the GUI extras.
"""
from __future__ import annotations

import math
import struct
import wave
import zlib
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable, Optional

import numpy as np


MAGIC = b"DACU"
VERSION = 1
HEADER_BYTES = 32
HEADER = struct.Struct("<4sBBBBIIIIHBBI")
CONTROL_BODY = struct.Struct("<BBBBI")

MSG_CONTROL = 0x01
MSG_WAVE = 0x02
MSG_COMMIT = 0x03
MSG_ACK = 0x81
MSG_STATUS = 0x82

OP_BEGIN = 1
SOURCE_UPLOAD_RAM = 1

FLAG_ACK_REQUIRED = 1 << 0
FLAG_LOOP = 1 << 1
FLAG_RESET_PIPELINE = 1 << 2
FLAG_ONE_SHOT = 1 << 3
KNOWN_FLAGS = FLAG_ACK_REQUIRED | FLAG_LOOP | FLAG_RESET_PIPELINE | FLAG_ONE_SHOT

SAMPLE_BITS = 24
SAMPLE_FORMAT_S24LE = 1
SAMPLES_PER_WAVE = 256
MAX_UPLOAD_SAMPLES = 16384
S24_MIN = -(1 << 23)
S24_MAX = (1 << 23) - 1

STATUS_NAMES = {
    0: "OK",
    1: "PROTOCOL_ERROR",
    2: "NO_TRANSACTION",
    3: "TRANSACTION_ID",
    4: "SEQUENCE",
    5: "OFFSET",
    6: "RANGE",
    7: "INCOMPLETE",
    8: "CONTROL",
}


class UploadProtocolError(ValueError):
    """Raised for a malformed vector, DACU packet, or acknowledgement."""


@dataclass(frozen=True)
class UploadDatagram:
    stage: str
    sequence: int
    sample_offset: int
    sample_count: int
    expected_next_offset: int
    data: bytes


@dataclass(frozen=True)
class UploadPlan:
    transaction_id: int
    total_samples: int
    family_48k: int
    output_mode: int
    ack_required: bool
    datagrams: tuple[UploadDatagram, ...]

    @property
    def wave_packet_count(self) -> int:
        return max(0, len(self.datagrams) - 2)


@dataclass(frozen=True)
class AckPacket:
    message_type: int
    flags: int
    transaction_id: int
    sequence: int
    total_samples: int
    next_offset: int
    status_code: int

    @property
    def status_name(self) -> str:
        return STATUS_NAMES.get(self.status_code, f"UNKNOWN_{self.status_code}")


@dataclass(frozen=True)
class ImportedWaveform:
    samples: np.ndarray
    source_rate: Optional[int]
    resampled: bool
    note: str


def validate_s24(samples: Iterable[int] | np.ndarray) -> np.ndarray:
    values = np.asarray(samples)
    if values.ndim != 1:
        values = values.reshape(-1)
    if values.size == 0:
        raise UploadProtocolError("上传向量不能为空")
    if not np.issubdtype(values.dtype, np.integer):
        if not np.all(np.isfinite(values)) or not np.all(values == np.rint(values)):
            raise UploadProtocolError("整数码值向量包含非整数或非有限值")
    values64 = values.astype(np.int64, copy=False)
    low = int(values64.min())
    high = int(values64.max())
    if low < S24_MIN or high > S24_MAX:
        raise UploadProtocolError(
            f"24 位码值越界：范围 [{low}, {high}]，允许 [{S24_MIN}, {S24_MAX}]"
        )
    return values64.astype(np.int32, copy=True)


def quantize_normalized_s24(values: Iterable[float] | np.ndarray) -> np.ndarray:
    """Quantise normalised full-scale values; +1 clips to 0x7fffff."""
    waveform = np.asarray(values, dtype=np.float64).reshape(-1)
    if waveform.size == 0:
        raise UploadProtocolError("波形不能为空")
    if not np.all(np.isfinite(waveform)):
        raise UploadProtocolError("波形包含 NaN 或 Inf")
    clipped = np.clip(waveform, -1.0, 1.0)
    codes = np.rint(clipped * float(1 << 23))
    return np.clip(codes, S24_MIN, S24_MAX).astype(np.int32)


def pack_s24le(samples: Iterable[int] | np.ndarray) -> bytes:
    values = validate_s24(samples).astype(np.int64)
    unsigned = values & 0xFFFFFF
    packed = np.empty(values.size * 3, dtype=np.uint8)
    packed[0::3] = unsigned & 0xFF
    packed[1::3] = (unsigned >> 8) & 0xFF
    packed[2::3] = (unsigned >> 16) & 0xFF
    return packed.tobytes()


def unpack_s24le(payload: bytes) -> np.ndarray:
    if len(payload) % 3:
        raise UploadProtocolError("s24le payload 长度不是 3 的整数倍")
    octets = np.frombuffer(payload, dtype=np.uint8).reshape(-1, 3)
    raw = (
        octets[:, 0].astype(np.uint32)
        | (octets[:, 1].astype(np.uint32) << 8)
        | (octets[:, 2].astype(np.uint32) << 16)
    )
    signed = raw.astype(np.int32)
    signed[(raw & 0x800000) != 0] -= 1 << 24
    return signed


def generate_waveform(
    kind: str,
    sample_rate: int,
    sample_count: int,
    amplitude_dbfs: float = -1.0,
    frequency1_hz: float = 997.0,
    frequency2_hz: float = 15000.0,
    seed: int = 20260813,
) -> np.ndarray:
    """Generate deterministic 1x input samples and quantise them to s24."""
    if sample_rate not in (44100, 48000):
        raise UploadProtocolError("1x 输入采样率必须为 44100 或 48000 Hz")
    if not 1 <= sample_count <= MAX_UPLOAD_SAMPLES:
        raise UploadProtocolError(
            f"样本数必须在 1..{MAX_UPLOAD_SAMPLES} 范围内（板端双 bank 容量）"
        )
    if amplitude_dbfs > 0.0 or amplitude_dbfs < -180.0:
        raise UploadProtocolError("幅度必须位于 -180..0 dBFS")
    amplitude = 10.0 ** (amplitude_dbfs / 20.0)
    index = np.arange(sample_count, dtype=np.float64)
    phase1 = 2.0 * math.pi * frequency1_hz * index / float(sample_rate)

    if kind == "sine":
        _validate_tone(frequency1_hz, sample_rate, "单音频率")
        waveform = amplitude * np.sin(phase1)
    elif kind == "dual_tone":
        _validate_tone(frequency1_hz, sample_rate, "频率 1")
        _validate_tone(frequency2_hz, sample_rate, "频率 2")
        phase2 = 2.0 * math.pi * frequency2_hz * index / float(sample_rate)
        waveform = amplitude * 0.5 * (np.sin(phase1) + np.sin(phase2))
    elif kind == "impulse":
        waveform = np.zeros(sample_count, dtype=np.float64)
        waveform[0] = amplitude
    elif kind == "square":
        _validate_tone(frequency1_hz, sample_rate, "方波频率")
        waveform = amplitude * np.where(np.sin(phase1) >= 0.0, 1.0, -1.0)
    elif kind == "white_noise":
        rng = np.random.default_rng(int(seed) & 0xFFFFFFFF)
        waveform = amplitude * rng.uniform(-1.0, 1.0, sample_count)
    else:
        raise UploadProtocolError(f"不支持的波形类型：{kind}")
    return quantize_normalized_s24(waveform)


def load_csv_waveform(path: Path, normalised: bool) -> ImportedWaveform:
    path = Path(path)
    delimiter = "," if path.suffix.lower() == ".csv" else None
    try:
        table = np.genfromtxt(
            path,
            delimiter=delimiter,
            comments="#",
            dtype=np.float64,
            invalid_raise=False,
        )
    except (OSError, ValueError) as exc:
        raise UploadProtocolError(f"无法读取 CSV/TXT：{exc}") from exc
    if np.asarray(table).size == 0:
        raise UploadProtocolError("CSV/TXT 中没有数值样本")
    if table.ndim == 0:
        values = table.reshape(1)
    elif table.ndim == 1:
        values = table
    else:
        # Capture CSV files contain index,value.  The last numeric column is
        # therefore the useful default and avoids treating indices as samples.
        useful_columns = [
            column
            for column in range(table.shape[1])
            if np.isfinite(table[:, column]).any()
        ]
        if not useful_columns:
            raise UploadProtocolError("CSV/TXT 中没有数值列")
        values = table[:, useful_columns[-1]]
    values = values[np.isfinite(values)]
    if values.size == 0:
        raise UploadProtocolError("CSV/TXT 中没有有限数值样本")
    samples = quantize_normalized_s24(values) if normalised else validate_s24(values)
    _validate_capacity(samples.size)
    interpretation = "归一化满量程" if normalised else "有符号 24 位整数码值"
    return ImportedWaveform(samples, None, False, f"按{interpretation}读取 {samples.size} 点")


def load_wav_waveform(path: Path, target_rate: int) -> ImportedWaveform:
    """Load PCM WAV, mix channels to mono and linearly resample if necessary."""
    path = Path(path)
    if target_rate not in (44100, 48000):
        raise UploadProtocolError("目标采样率必须为 44100 或 48000 Hz")
    try:
        with wave.open(str(path), "rb") as stream:
            if stream.getcomptype() != "NONE":
                raise UploadProtocolError("仅支持未压缩 PCM WAV")
            channel_count = stream.getnchannels()
            sample_width = stream.getsampwidth()
            source_rate = stream.getframerate()
            frame_count = stream.getnframes()
            raw = stream.readframes(frame_count)
    except (OSError, wave.Error) as exc:
        raise UploadProtocolError(f"无法读取 WAV：{exc}") from exc
    if channel_count < 1 or frame_count < 1:
        raise UploadProtocolError("WAV 没有音频样本")
    normalised = _decode_pcm_wav(raw, sample_width)
    if normalised.size != frame_count * channel_count:
        raise UploadProtocolError("WAV PCM 数据长度与文件头不一致")
    mono = normalised.reshape(-1, channel_count).mean(axis=1)
    resampled = source_rate != target_rate
    if resampled:
        new_count = max(1, int(round(mono.size * target_rate / source_rate)))
        positions = np.arange(new_count, dtype=np.float64) * source_rate / target_rate
        mono = np.interp(positions, np.arange(mono.size, dtype=np.float64), mono)
        note = (
            f"{source_rate} Hz/{channel_count} 声道 PCM 已混合为单声道并线性重采样到 "
            f"{target_rate} Hz；这是输入准备，不作为频响测量依据"
        )
    else:
        note = f"{source_rate} Hz/{channel_count} 声道 PCM 已混合为单声道"
    samples = quantize_normalized_s24(mono)
    _validate_capacity(samples.size)
    return ImportedWaveform(samples, source_rate, resampled, note)


def build_upload_plan(
    samples: Iterable[int] | np.ndarray,
    *,
    transaction_id: int,
    family_48k: int,
    output_mode: int,
    loop: bool,
    repeat_count: int = 1,
    ack_required: bool = True,
) -> UploadPlan:
    """Build BEGIN, ordered WAVE packets, then COMMIT.

    Sequence convention is intentionally stage-local and matches the board
    transaction controller: BEGIN=0, WAVE=0..N-1, COMMIT=N.
    """
    values = validate_s24(samples)
    _validate_capacity(values.size)
    _validate_u32(transaction_id, "transaction_id")
    if family_48k not in (0, 1):
        raise UploadProtocolError("family_48k 必须为 0 或 1")
    if output_mode not in (0, 1, 2, 3):
        raise UploadProtocolError("output_mode 必须为 0..3")
    _validate_u32(repeat_count, "repeat_count")
    if not loop and repeat_count == 0:
        raise UploadProtocolError("非循环播放的 repeat_count 不能为 0")

    total = int(values.size)
    common_flags = FLAG_ACK_REQUIRED if ack_required else 0
    begin_body = CONTROL_BODY.pack(
        OP_BEGIN,
        family_48k,
        output_mode,
        SOURCE_UPLOAD_RAM,
        repeat_count,
    )
    datagrams = [
        UploadDatagram(
            "BEGIN",
            0,
            0,
            0,
            0,
            _build_packet(
                MSG_CONTROL,
                common_flags,
                transaction_id,
                0,
                total,
                0,
                0,
                begin_body,
            ),
        )
    ]

    wave_packet_count = (total + SAMPLES_PER_WAVE - 1) // SAMPLES_PER_WAVE
    for sequence in range(wave_packet_count):
        offset = sequence * SAMPLES_PER_WAVE
        chunk = values[offset : offset + SAMPLES_PER_WAVE]
        payload = pack_s24le(chunk)
        next_offset = offset + int(chunk.size)
        datagrams.append(
            UploadDatagram(
                "WAVE",
                sequence,
                offset,
                int(chunk.size),
                next_offset,
                _build_packet(
                    MSG_WAVE,
                    common_flags,
                    transaction_id,
                    sequence,
                    total,
                    offset,
                    int(chunk.size),
                    payload,
                ),
            )
        )

    commit_flags = common_flags | FLAG_RESET_PIPELINE
    commit_flags |= FLAG_LOOP if loop else FLAG_ONE_SHOT
    datagrams.append(
        UploadDatagram(
            "COMMIT",
            wave_packet_count,
            total,
            0,
            total,
            _build_packet(
                MSG_COMMIT,
                commit_flags,
                transaction_id,
                wave_packet_count,
                total,
                total,
                0,
                b"",
            ),
        )
    )
    return UploadPlan(
        transaction_id,
        total,
        family_48k,
        output_mode,
        ack_required,
        tuple(datagrams),
    )


def parse_ack(data: bytes) -> AckPacket:
    if len(data) != HEADER_BYTES:
        raise UploadProtocolError(f"ACK/STATUS 长度应为 32，实际 {len(data)}")
    (
        magic,
        version,
        message_type,
        flags,
        header_bytes,
        transaction_id,
        sequence,
        total_samples,
        next_offset,
        status_code,
        sample_bits,
        sample_format,
        payload_crc32,
    ) = HEADER.unpack(data)
    if magic != MAGIC or version != VERSION or header_bytes != HEADER_BYTES:
        raise UploadProtocolError("ACK/STATUS magic、version 或 header_bytes 无效")
    if message_type not in (MSG_ACK, MSG_STATUS):
        raise UploadProtocolError(f"不是 ACK/STATUS 消息：0x{message_type:02x}")
    if flags & ~KNOWN_FLAGS:
        raise UploadProtocolError(f"ACK/STATUS 含未知 flags 0x{flags:02x}")
    if sample_bits != SAMPLE_BITS or sample_format != SAMPLE_FORMAT_S24LE:
        raise UploadProtocolError("ACK/STATUS 样本格式字段无效")
    if payload_crc32 != 0:
        raise UploadProtocolError("无正文 ACK/STATUS 的 CRC32 必须为 0")
    return AckPacket(
        message_type,
        flags,
        transaction_id,
        sequence,
        total_samples,
        next_offset,
        status_code,
    )


def _build_packet(
    message_type: int,
    flags: int,
    transaction_id: int,
    sequence: int,
    total_samples: int,
    sample_offset: int,
    sample_count: int,
    payload: bytes,
) -> bytes:
    if flags & ~KNOWN_FLAGS:
        raise UploadProtocolError(f"含未知 flags 0x{flags:02x}")
    for value, label in (
        (transaction_id, "transaction_id"),
        (sequence, "sequence"),
        (total_samples, "total_samples"),
        (sample_offset, "sample_offset"),
    ):
        _validate_u32(value, label)
    if not 0 <= sample_count <= 0xFFFF:
        raise UploadProtocolError("sample_count 超出 u16")
    crc = zlib.crc32(payload) & 0xFFFFFFFF if payload else 0
    header = HEADER.pack(
        MAGIC,
        VERSION,
        message_type,
        flags,
        HEADER_BYTES,
        transaction_id,
        sequence,
        total_samples,
        sample_offset,
        sample_count,
        SAMPLE_BITS,
        SAMPLE_FORMAT_S24LE,
        crc,
    )
    return header + payload


def _validate_tone(frequency_hz: float, sample_rate: int, label: str) -> None:
    if not math.isfinite(frequency_hz) or not 0.0 < frequency_hz < sample_rate / 2.0:
        raise UploadProtocolError(f"{label}必须大于 0 且小于 Nyquist ({sample_rate / 2:g} Hz)")


def _validate_u32(value: int, label: str) -> None:
    if not 0 <= int(value) <= 0xFFFFFFFF:
        raise UploadProtocolError(f"{label} 超出 u32")


def _validate_capacity(sample_count: int) -> None:
    if sample_count > MAX_UPLOAD_SAMPLES:
        raise UploadProtocolError(
            f"输入含 {sample_count} 点，超过板端双 bank 上限 {MAX_UPLOAD_SAMPLES}；"
            "请先在文件中明确裁剪，GUI 不会静默截断"
        )


def _decode_pcm_wav(raw: bytes, sample_width: int) -> np.ndarray:
    if sample_width == 1:
        return (np.frombuffer(raw, dtype=np.uint8).astype(np.float64) - 128.0) / 128.0
    if sample_width == 2:
        return np.frombuffer(raw, dtype="<i2").astype(np.float64) / float(1 << 15)
    if sample_width == 3:
        return unpack_s24le(raw).astype(np.float64) / float(1 << 23)
    if sample_width == 4:
        return np.frombuffer(raw, dtype="<i4").astype(np.float64) / float(1 << 31)
    raise UploadProtocolError(f"不支持 {sample_width * 8} 位 PCM WAV")
