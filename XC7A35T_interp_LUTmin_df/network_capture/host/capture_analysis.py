#!/usr/bin/env python3
"""Numerical analysis for one DAC24 board-capture frame."""
from __future__ import annotations

from dataclasses import dataclass
from pathlib import Path
import re
from typing import Optional

import numpy as np

from dac24_protocol import CaptureFrame


class ReferenceError(ValueError):
    """The selected RTL reference cannot be applied to a board frame."""


@dataclass(frozen=True)
class BitTrueResult:
    compared_samples: int
    reference_start: int
    reference_stop: int
    mismatch_count: int
    max_abs_error: int
    first_mismatch_offset: Optional[int]

    @property
    def passed(self) -> bool:
        return self.mismatch_count == 0 and self.max_abs_error == 0


@dataclass(frozen=True)
class SpectrumPreview:
    frequency_hz: np.ndarray
    dbfs: np.ndarray
    resolution_hz: float
    window_name: str = "Hann"

    def below(self, stop_hz: float) -> "SpectrumPreview":
        mask = self.frequency_hz <= stop_hz
        return SpectrumPreview(
            self.frequency_hz[mask],
            self.dbfs[mask],
            self.resolution_hz,
            self.window_name,
        )


@dataclass(frozen=True)
class FrameAnalysis:
    samples_i32: np.ndarray
    normalized: np.ndarray
    time_seconds: np.ndarray
    spectrum: SpectrumPreview
    bit_true: Optional[BitTrueResult]


@dataclass(frozen=True)
class ImpulseResponseMetrics:
    passband_max_db: float
    passband_min_db: float
    passband_max_abs_db: float
    passband_pp_db: float
    stopband_attenuation_db: float
    worst_stop_frequency_hz: float
    capture_complete: bool
    passed: bool
    frequency_hz: np.ndarray
    gain_db: np.ndarray


MINIMUM_IMPULSE_CAPTURE = {4: 512, 8: 1024, 128: 8192}
FORMAL_IMPULSE_AMPLITUDE = 1 << 22
FORMAL_CAPTURE_SAMPLES = 16384

_REFERENCE_NAME_RE = re.compile(
    r"rtl_reference_(44100|48000)_(1x|4x|8x|128x)(?:\.|$)", re.IGNORECASE
)
_REFERENCE_MODE_CODES = {"1x": 0, "4x": 1, "8x": 2, "128x": 3}


def infer_reference_target(path: Path) -> Optional[tuple[int, int]]:
    """Infer (family_48k, mode) from a standard RTL reference filename."""

    match = _REFERENCE_NAME_RE.search(Path(path).name)
    if match is None:
        return None
    family_48k = 1 if match.group(1) == "48000" else 0
    return family_48k, _REFERENCE_MODE_CODES[match.group(2).lower()]


class ReferenceVector:
    """One immutable RTL reference, loaded once and reused for every frame."""

    def __init__(self, path: Path, values: np.ndarray) -> None:
        vector = np.asarray(values, dtype=np.int64).reshape(-1)
        if vector.size == 0:
            raise ReferenceError("RTL 参考向量为空")
        if np.any(vector < -(1 << 23)) or np.any(vector >= (1 << 23)):
            raise ReferenceError("RTL 参考样本超出 24 位有符号数范围")
        vector.setflags(write=False)
        self.path = Path(path)
        self.values = vector

    @classmethod
    def load(cls, path: Path) -> "ReferenceVector":
        path = Path(path)
        if not path.is_file():
            raise ReferenceError(f"找不到 RTL 参考文件：{path}")
        if path.suffix.lower() == ".npy":
            return cls(path, np.load(path, allow_pickle=False))

        values: list[int] = []
        for line_number, line in enumerate(
            path.read_text(encoding="utf-8").splitlines(), start=1
        ):
            stripped = line.strip()
            if not stripped or stripped.startswith("#"):
                continue
            token = stripped.split(",")[-1].strip()
            try:
                values.append(int(token, 0))
            except ValueError as exc:
                # Permit a single CSV heading before any numeric samples.
                if not values and line_number == 1:
                    continue
                raise ReferenceError(
                    f"{path}:{line_number}：参考样本 {token!r} 不是整数"
                ) from exc
        return cls(path, np.asarray(values, dtype=np.int64))

    def compare(self, frame: CaptureFrame) -> BitTrueResult:
        start = frame.start_sample_index
        stop = start + frame.total_samples
        if stop > self.values.size:
            raise ReferenceError(
                f"当前帧需要参考区间 [{start}:{stop}]，参考向量只有 "
                f"{self.values.size} 个样本"
            )
        actual = np.asarray(frame.samples, dtype=np.int64)
        expected = self.values[start:stop]
        errors = actual - expected
        mismatches = np.flatnonzero(errors)
        return BitTrueResult(
            compared_samples=int(actual.size),
            reference_start=start,
            reference_stop=stop,
            mismatch_count=int(mismatches.size),
            max_abs_error=int(np.max(np.abs(errors))) if errors.size else 0,
            first_mismatch_offset=(int(mismatches[0]) if mismatches.size else None),
        )


def compute_spectrum(samples_i32: np.ndarray, sample_rate: int) -> SpectrumPreview:
    """Compute a single-frame Hann-window FFT amplitude preview in dBFS.

    This is deliberately called a preview.  A single board snapshot does
    not prove the competition's passband-ripple or stopband specification.
    """

    normalized = np.asarray(samples_i32, dtype=np.float64) / float(1 << 23)
    if normalized.size < 2:
        raise ValueError("FFT 至少需要两个样本")
    window = np.hanning(normalized.size)
    coherent_gain = window.sum() / normalized.size
    centered = normalized - normalized.mean()
    spectrum = np.fft.rfft(centered * window)
    amplitude = np.abs(spectrum) / (normalized.size * coherent_gain / 2.0)
    # DC and Nyquist are not doubled by a one-sided spectrum.
    amplitude[0] *= 0.5
    if normalized.size % 2 == 0:
        amplitude[-1] *= 0.5
    dbfs = 20.0 * np.log10(np.maximum(amplitude, 1e-15))
    frequency = np.fft.rfftfreq(normalized.size, d=1.0 / sample_rate)
    return SpectrumPreview(
        frequency_hz=frequency,
        dbfs=dbfs,
        resolution_hz=float(sample_rate / normalized.size),
    )


def normalize_spectrum_to_peak(
    dbfs: np.ndarray, floor_db: float = -160.0
) -> tuple[np.ndarray, float]:
    """Return a display-only spectrum relative to the frame peak (0 dBr).

    The returned curve is useful for showing tones, harmonics and image
    rejection without confusing input amplitude with filter gain.  The
    original absolute peak is returned separately so the dBFS information is
    not lost.  An all-zero frame stays at the display floor instead of being
    misleadingly promoted to 0 dBr.
    """

    values = np.asarray(dbfs, dtype=np.float64)
    if values.size == 0:
        raise ValueError("频谱不能为空")
    finite = values[np.isfinite(values)]
    if finite.size == 0:
        return np.full(values.shape, floor_db, dtype=np.float64), float("-inf")
    peak_dbfs = float(np.max(finite))
    if peak_dbfs <= -299.0:
        return np.full(values.shape, floor_db, dtype=np.float64), peak_dbfs
    relative = np.clip(values - peak_dbfs, floor_db, 0.0)
    return relative, peak_dbfs


def analyze_frame(
    frame: CaptureFrame, reference: Optional[ReferenceVector] = None
) -> FrameAnalysis:
    samples_i32 = np.asarray(frame.samples, dtype=np.int32)
    normalized = samples_i32.astype(np.float64) / float(1 << 23)
    time_seconds = np.arange(samples_i32.size, dtype=np.float64) / frame.sample_rate
    return FrameAnalysis(
        samples_i32=samples_i32,
        normalized=normalized,
        time_seconds=time_seconds,
        spectrum=compute_spectrum(samples_i32, frame.sample_rate),
        bit_true=(reference.compare(frame) if reference is not None else None),
    )


def analyze_impulse_response(
    frame: CaptureFrame,
    input_impulse_amplitude: int,
    nfft: int = 1 << 20,
) -> ImpulseResponseMetrics:
    """Formal no-window impulse response gates for 4x/8x/128x captures."""
    interpolation = {1: 4, 2: 8, 3: 128}.get(frame.mode)
    if interpolation is None:
        raise ValueError("正式冲激频响只支持 4x、8x、128x")
    if input_impulse_amplitude != FORMAL_IMPULSE_AMPLITUDE:
        raise ValueError(
            f"正式冲激幅度必须精确为 {FORMAL_IMPULSE_AMPLITUDE} (2^22) 码值"
        )
    if not frame.upload_source:
        raise ValueError("回传头未声明上传 RAM 源")
    if frame.total_samples != FORMAL_CAPTURE_SAMPLES:
        raise ValueError(
            f"正式冲激必须是 {FORMAL_CAPTURE_SAMPLES} 点完整回传，"
            f"当前为 {frame.total_samples} 点"
        )
    if frame.start_sample_index != 0:
        raise ValueError(
            f"正式冲激必须从输出索引 0 开始，"
            f"当前为 {frame.start_sample_index}"
        )
    if frame.capture_status != 0:
        raise ValueError(
            f"板端 capture_status 异常：0x{frame.capture_status:04X}"
        )
    y = np.asarray(frame.samples, dtype=np.float64).reshape(-1)
    if y.size == 0 or not np.all(np.isfinite(y)):
        raise ValueError("冲激响应必须包含有限样本")
    if nfft < y.size or nfft < 2 or nfft & (nfft - 1):
        raise ValueError("NFFT 必须是不短于捕获的 2 的幂")
    output_rate = frame.family_rate * interpolation
    frequency = np.fft.rfftfreq(nfft, 1.0 / output_rate)
    spectrum = np.fft.rfft(y, nfft)
    magnitude = np.abs(spectrum) / abs(input_impulse_amplitude * interpolation)
    gain_db = 20.0 * np.log10(
        np.maximum(magnitude, np.finfo(np.float64).tiny)
    )
    pass_selector = (frequency >= 10.0) & (frequency <= 20_000.0)
    stop_start = frame.family_rate - 20_000.0
    stop_selector = (frequency >= stop_start) & (frequency <= output_rate / 2.0)
    if not np.any(pass_selector) or not np.any(stop_selector):
        raise ValueError("FFT 栅格没有覆盖验收频带")
    pass_values = gain_db[pass_selector]
    stop_values = gain_db[stop_selector]
    worst_local = int(np.argmax(stop_values))
    stop_frequencies = frequency[stop_selector]
    pass_max = float(np.max(pass_values))
    pass_min = float(np.min(pass_values))
    pass_abs = float(np.max(np.abs(pass_values)))
    stop_attenuation = float(-stop_values[worst_local])
    capture_complete = bool(
        y.size >= MINIMUM_IMPULSE_CAPTURE[interpolation]
        and y.size >= 16
        and np.all(y[-16:] == 0.0)
    )
    return ImpulseResponseMetrics(
        passband_max_db=pass_max,
        passband_min_db=pass_min,
        passband_max_abs_db=pass_abs,
        passband_pp_db=pass_max - pass_min,
        stopband_attenuation_db=stop_attenuation,
        worst_stop_frequency_hz=float(stop_frequencies[worst_local]),
        capture_complete=capture_complete,
        passed=(capture_complete and pass_abs <= 0.05 and stop_attenuation >= 70.0),
        frequency_hz=frequency,
        gain_db=gain_db,
    )
