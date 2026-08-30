"""DAC24 测量算法的独立参考实现。

本模块只供数值规格测试使用，不是生产 GUI/API。生产分析模块可以采用不同的
组织形式，但相同输入必须给出等价的归一化和 PASS/FAIL 结果。
"""

from __future__ import annotations

from dataclasses import dataclass

import numpy as np


FULL_SCALE_24 = 1 << 23
MINIMUM_CAPTURE_SAMPLES = {4: 512, 8: 1024, 128: 8192}


def amplitude_to_dbfs(amplitude: float, full_scale: float = FULL_SCALE_24) -> float:
    """把线性峰值幅度转换为 dBFS；零幅度返回负无穷。"""
    if full_scale <= 0:
        raise ValueError("full_scale 必须为正数")
    if amplitude < 0:
        raise ValueError("amplitude 不能为负数")
    if amplitude == 0:
        return float("-inf")
    return float(20.0 * np.log10(amplitude / full_scale))


def coherent_tone_dbfs(samples: np.ndarray, bin_index: int) -> float:
    """用矩形窗测量实数、零相位、相干正弦的峰值 dBFS。

    该函数故意只接受普通正频率栅格，排除 DC 和 Nyquist 的单边谱特例。
    """
    values = np.asarray(samples, dtype=np.float64).reshape(-1)
    if values.size < 4:
        raise ValueError("至少需要 4 个样本")
    if not 0 < bin_index < values.size // 2:
        raise ValueError("bin_index 必须是普通正频率 FFT 栅格")
    spectrum = np.fft.rfft(values)
    peak_amplitude = 2.0 * abs(spectrum[bin_index]) / values.size
    return amplitude_to_dbfs(float(peak_amplitude))


@dataclass(frozen=True)
class ResponseMetrics:
    passband_max_db: float
    passband_min_db: float
    passband_max_abs_db: float
    passband_pp_db: float
    stopband_attenuation_db: float
    worst_stop_frequency_hz: float
    capture_complete: bool
    passed: bool


def impulse_response_metrics(
    response: np.ndarray,
    *,
    input_impulse_amplitude: float,
    interpolation: int,
    input_sample_rate_hz: float,
    nfft: int = 1 << 20,
    passband_hz: tuple[float, float] = (10.0, 20_000.0),
    passband_limit_db: float = 0.05,
    stopband_min_db: float = 70.0,
    required_zero_tail_samples: int = 16,
) -> ResponseMetrics:
    """按正式冲激响应口径计算通带和阻带指标。"""
    y = np.asarray(response, dtype=np.float64).reshape(-1)
    if y.size == 0 or not np.all(np.isfinite(y)):
        raise ValueError("response 必须包含有限样本")
    if input_impulse_amplitude == 0:
        raise ValueError("输入冲激幅度不能为零")
    if interpolation not in (4, 8, 128):
        raise ValueError("正式测量只支持 4x、8x、128x")
    if input_sample_rate_hz <= 0:
        raise ValueError("输入采样率必须为正数")
    if nfft < y.size or nfft < 2 or nfft & (nfft - 1):
        raise ValueError("nfft 必须是不短于响应的 2 的幂")
    if not 0 <= passband_hz[0] <= passband_hz[1]:
        raise ValueError("通带边界无效")
    if required_zero_tail_samples < 1:
        raise ValueError("尾部归零检查长度必须为正数")

    output_sample_rate_hz = input_sample_rate_hz * interpolation
    stopband_start_hz = input_sample_rate_hz - passband_hz[1]
    frequency = np.fft.rfftfreq(nfft, 1.0 / output_sample_rate_hz)
    spectrum = np.fft.rfft(y, nfft)
    normalized = np.abs(spectrum) / abs(input_impulse_amplitude * interpolation)
    gain_db = 20.0 * np.log10(np.maximum(normalized, np.finfo(np.float64).tiny))

    pass_selector = (frequency >= passband_hz[0]) & (frequency <= passband_hz[1])
    stop_selector = (frequency >= stopband_start_hz) & (
        frequency <= output_sample_rate_hz / 2.0
    )
    if not np.any(pass_selector) or not np.any(stop_selector):
        raise ValueError("FFT 栅格没有覆盖待验收频带")

    pass_values = gain_db[pass_selector]
    stop_values = gain_db[stop_selector]
    worst_stop_local = int(np.argmax(stop_values))
    stop_frequencies = frequency[stop_selector]
    passband_max_db = float(np.max(pass_values))
    passband_min_db = float(np.min(pass_values))
    passband_max_abs_db = float(np.max(np.abs(pass_values)))
    stopband_attenuation_db = float(-stop_values[worst_stop_local])
    capture_complete = (
        y.size >= MINIMUM_CAPTURE_SAMPLES[interpolation]
        and y.size >= required_zero_tail_samples
        and bool(np.all(y[-required_zero_tail_samples:] == 0.0))
    )

    return ResponseMetrics(
        passband_max_db=passband_max_db,
        passband_min_db=passband_min_db,
        passband_max_abs_db=passband_max_abs_db,
        passband_pp_db=passband_max_db - passband_min_db,
        stopband_attenuation_db=stopband_attenuation_db,
        worst_stop_frequency_hz=float(stop_frequencies[worst_stop_local]),
        capture_complete=capture_complete,
        passed=(
            capture_complete
            and passband_max_abs_db <= passband_limit_db
            and stopband_attenuation_db >= stopband_min_db
        ),
    )
