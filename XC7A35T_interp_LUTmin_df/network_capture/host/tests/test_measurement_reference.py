"""DAC24 正式测量口径的回归测试（stdlib unittest + NumPy）。"""

from __future__ import annotations

import math
import unittest

import numpy as np

from measurement_reference import (
    FULL_SCALE_24,
    amplitude_to_dbfs,
    coherent_tone_dbfs,
    impulse_response_metrics,
)


def design_interpolator(
    *,
    taps: int,
    beta: float,
    interpolation: int = 4,
    input_sample_rate_hz: float = 44_100.0,
) -> np.ndarray:
    """构造确定性的窗化 sinc，仅作为指标计算测试夹具。"""
    output_sample_rate_hz = input_sample_rate_hz * interpolation
    pass_edge_hz = 20_000.0
    stop_edge_hz = input_sample_rate_hz - pass_edge_hz
    cutoff_hz = (pass_edge_hz + stop_edge_hz) / 2.0
    index = np.arange(taps, dtype=np.float64)
    center = (taps - 1) / 2.0
    response = interpolation * (2.0 * cutoff_hz / output_sample_rate_hz) * np.sinc(
        2.0 * cutoff_hz / output_sample_rate_hz * (index - center)
    )
    response *= np.kaiser(taps, beta)
    response *= interpolation / response.sum()
    return response


def pad_capture(response: np.ndarray, length: int) -> np.ndarray:
    """把有限冲激支撑放入包含明确零尾的板级捕获记录。"""
    if len(response) > length:
        raise ValueError("捕获长度不能短于冲激支撑")
    return np.pad(response, (0, length - len(response)))


class DbfsTests(unittest.TestCase):
    def test_full_scale_and_half_scale(self) -> None:
        self.assertAlmostEqual(amplitude_to_dbfs(FULL_SCALE_24), 0.0, places=12)
        self.assertAlmostEqual(
            amplitude_to_dbfs(FULL_SCALE_24 / 2),
            -6.020599913279624,
            places=12,
        )

    def test_zero_is_negative_infinity(self) -> None:
        self.assertTrue(math.isinf(amplitude_to_dbfs(0.0)))
        self.assertLess(amplitude_to_dbfs(0.0), 0.0)

    def test_invalid_amplitude_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            amplitude_to_dbfs(-1.0)


class CoherentToneTests(unittest.TestCase):
    def test_exact_fft_bin_recovers_peak_amplitude(self) -> None:
        sample_count = 4096
        bin_index = 137
        expected_dbfs = -12.0
        amplitude = FULL_SCALE_24 * 10.0 ** (expected_dbfs / 20.0)
        index = np.arange(sample_count, dtype=np.float64)
        samples = amplitude * np.cos(2.0 * np.pi * bin_index * index / sample_count)
        self.assertAlmostEqual(
            coherent_tone_dbfs(samples, bin_index), expected_dbfs, places=10
        )

    def test_wrong_bin_does_not_report_tone(self) -> None:
        sample_count = 4096
        bin_index = 137
        index = np.arange(sample_count, dtype=np.float64)
        samples = (FULL_SCALE_24 / 2) * np.cos(
            2.0 * np.pi * bin_index * index / sample_count
        )
        self.assertLess(coherent_tone_dbfs(samples, bin_index + 1), -250.0)


class ImpulseResponseTests(unittest.TestCase):
    def test_passing_lowpass_meets_both_gates(self) -> None:
        interpolation = 4
        impulse_amplitude = 1 << 22
        response = pad_capture(
            impulse_amplitude * design_interpolator(taps=257, beta=8.0), 512
        )
        metric = impulse_response_metrics(
            response,
            input_impulse_amplitude=impulse_amplitude,
            interpolation=interpolation,
            input_sample_rate_hz=44_100.0,
        )
        self.assertTrue(metric.passed)
        self.assertTrue(metric.capture_complete)
        self.assertLess(metric.passband_max_abs_db, 0.05)
        self.assertGreater(metric.stopband_attenuation_db, 70.0)
        self.assertGreaterEqual(metric.worst_stop_frequency_hz, 24_100.0)

    def test_inadequate_filter_fails_passband_and_stopband(self) -> None:
        impulse_amplitude = 1 << 22
        response = pad_capture(
            impulse_amplitude * design_interpolator(taps=65, beta=2.0), 512
        )
        metric = impulse_response_metrics(
            response,
            input_impulse_amplitude=impulse_amplitude,
            interpolation=4,
            input_sample_rate_hz=44_100.0,
        )
        self.assertFalse(metric.passed)
        self.assertGreater(metric.passband_max_abs_db, 0.05)
        self.assertLess(metric.stopband_attenuation_db, 70.0)

    def test_gain_error_fails_absolute_passband_gate(self) -> None:
        impulse_amplitude = 1 << 22
        good = pad_capture(
            impulse_amplitude * design_interpolator(taps=257, beta=8.0), 512
        )
        response = good * 10.0 ** (0.06 / 20.0)
        metric = impulse_response_metrics(
            response,
            input_impulse_amplitude=impulse_amplitude,
            interpolation=4,
            input_sample_rate_hz=44_100.0,
        )
        self.assertFalse(metric.passed)
        self.assertGreater(metric.passband_max_abs_db, 0.05)

    def test_normalization_requires_impulse_amplitude_times_factor(self) -> None:
        interpolation = 8
        impulse_amplitude = 1 << 22
        response = np.zeros(1024, dtype=np.float64)
        response[229] = impulse_amplitude * interpolation
        metric = impulse_response_metrics(
            response,
            input_impulse_amplitude=impulse_amplitude,
            interpolation=interpolation,
            input_sample_rate_hz=48_000.0,
        )
        self.assertAlmostEqual(metric.passband_max_abs_db, 0.0, places=12)
        self.assertAlmostEqual(metric.stopband_attenuation_db, 0.0, places=12)
        self.assertFalse(metric.passed)

    def test_short_capture_cannot_pass_even_when_shape_is_good(self) -> None:
        impulse_amplitude = 1 << 22
        response = pad_capture(
            impulse_amplitude * design_interpolator(taps=257, beta=8.0), 300
        )
        metric = impulse_response_metrics(
            response,
            input_impulse_amplitude=impulse_amplitude,
            interpolation=4,
            input_sample_rate_hz=44_100.0,
        )
        self.assertLess(metric.passband_max_abs_db, 0.05)
        self.assertGreater(metric.stopband_attenuation_db, 70.0)
        self.assertFalse(metric.capture_complete)
        self.assertFalse(metric.passed)

    def test_nonzero_tail_cannot_pass(self) -> None:
        impulse_amplitude = 1 << 22
        response = np.zeros(512, dtype=np.float64)
        good = impulse_amplitude * design_interpolator(taps=257, beta=8.0)
        response[-len(good) :] = good
        metric = impulse_response_metrics(
            response,
            input_impulse_amplitude=impulse_amplitude,
            interpolation=4,
            input_sample_rate_hz=44_100.0,
        )
        self.assertLess(metric.passband_max_abs_db, 0.05)
        self.assertGreater(metric.stopband_attenuation_db, 70.0)
        self.assertFalse(metric.capture_complete)
        self.assertFalse(metric.passed)

    def test_invalid_nfft_is_rejected(self) -> None:
        with self.assertRaises(ValueError):
            impulse_response_metrics(
                np.ones(225),
                input_impulse_amplitude=1 << 22,
                interpolation=4,
                input_sample_rate_hz=44_100.0,
                nfft=1000,
            )


if __name__ == "__main__":
    unittest.main()
