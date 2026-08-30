#!/usr/bin/env python3
"""Pure-core regression tests for the DAC24 GUI backend."""
from __future__ import annotations

import tempfile
import unittest
import wave
import zlib
from pathlib import Path

import numpy as np

from capture_analysis import (
    FORMAL_CAPTURE_SAMPLES,
    FORMAL_IMPULSE_AMPLITUDE,
    FrameAnalysis,
    ImpulseResponseMetrics,
    ReferenceError,
    ReferenceVector,
    SpectrumPreview,
    analyze_frame,
    analyze_impulse_response,
    infer_reference_target,
    normalize_spectrum_to_peak,
)
from capture_worker import ArtifactSaveWorker
from dac24_protocol import (
    HEADER,
    CaptureFrame,
    FrameAssembler,
    ProtocolError,
    decode_s24le,
    parse_packet,
)
from dac24_upload import (
    CONTROL_BODY,
    HEADER as UPLOAD_HEADER,
    FLAG_ACK_REQUIRED,
    FLAG_LOOP,
    FLAG_RESET_PIPELINE,
    MSG_COMMIT,
    MSG_CONTROL,
    MSG_WAVE,
    MAX_UPLOAD_SAMPLES,
    UploadProtocolError,
    build_upload_plan,
    generate_waveform,
    load_csv_waveform,
    load_wav_waveform,
    pack_s24le,
    unpack_s24le,
)


def _encode_s24le(values: list[int]) -> bytes:
    payload = bytearray()
    for value in values:
        word = value & 0xFFFFFF
        payload.extend((word & 0xFF, (word >> 8) & 0xFF, (word >> 16) & 0xFF))
    return bytes(payload)


def _packet(
    packet_index: int,
    *,
    frame_id: int = 7,
    flags: int = 3,
    start: int = 100,
    mutate_first: bool = False,
    transaction_id: int = 0,
    capture_status: int = 0,
    packet_count: int = 16,
) -> bytes:
    base = packet_index * 256
    values = [((base + offset) % 4000000) - 2000000 for offset in range(256)]
    if mutate_first:
        values[0] += 1
    header = HEADER.pack(
        b"DAC2",
        1,
        flags,
        packet_index,
        packet_count,
        frame_id,
        packet_index * 256,
        256,
        24,
        1,
        packet_count * 256,
        start,
        transaction_id,
        capture_status,
    )
    return header + _encode_s24le(values)


class ProtocolTests(unittest.TestCase):
    def test_s24_edges(self) -> None:
        values = [-(1 << 23), -1, 0, 1, (1 << 23) - 1]
        self.assertEqual(decode_s24le(_encode_s24le(values)), tuple(values))

    def test_packet_rejects_trailing_bytes_and_reserved_flags(self) -> None:
        with self.assertRaises(ProtocolError):
            parse_packet(_packet(0) + b"x", "192.168.1.10")
        with self.assertRaises(ProtocolError):
            parse_packet(_packet(0, flags=0x83), "192.168.1.10")

    def test_compatible_upload_metadata_extension(self) -> None:
        packet = parse_packet(
            _packet(
                0,
                flags=0x0B,
                transaction_id=0xA1B2C3D4,
                capture_status=0x1234,
            )
        )
        self.assertEqual(packet.upload_source, 1)
        self.assertEqual(packet.input_transaction_id, 0xA1B2C3D4)
        self.assertEqual(packet.capture_status, 0x1234)

    def test_out_of_order_frame_and_duplicate(self) -> None:
        assembler = FrameAssembler(expected_family_48k=0, expected_mode=3)
        order = [15, 0, 9, 4, 4, 1, 2, 3, 5, 6, 7, 8, 10, 11, 12, 13, 14]
        result = None
        for index in order:
            result = assembler.feed_datagram(_packet(index), "192.168.1.10")
        self.assertIsNotNone(result)
        self.assertIsNotNone(result.frame)
        frame = result.frame
        assert frame is not None
        self.assertEqual(len(frame.samples), 4096)
        self.assertEqual(frame.duplicate_packets, 1)
        self.assertEqual(frame.start_sample_index, 100)
        self.assertEqual(frame.samples[0], -2000000)
        self.assertEqual(frame.samples[-1], -1995905)

    def test_extended_16384_frame(self) -> None:
        assembler = FrameAssembler()
        result = None
        for index in range(63, -1, -1):
            result = assembler.feed_datagram(_packet(index, packet_count=64))
        self.assertIsNotNone(result)
        assert result is not None and result.frame is not None
        self.assertEqual(result.frame.packet_count, 64)
        self.assertEqual(result.frame.total_samples, 16384)
        self.assertEqual(len(result.frame.samples), 16384)

    def test_unsupported_frame_size_is_rejected(self) -> None:
        with self.assertRaises(ProtocolError):
            parse_packet(_packet(0, packet_count=32))

    def test_conflicting_duplicate_raises(self) -> None:
        assembler = FrameAssembler()
        assembler.feed_datagram(_packet(0), "192.168.1.10")
        with self.assertRaises(ProtocolError):
            assembler.feed_datagram(
                _packet(0, mutate_first=True), "192.168.1.10"
            )

    def test_family_filter_precedes_cache(self) -> None:
        assembler = FrameAssembler(expected_family_48k=0, expected_mode=3)
        result = assembler.feed_datagram(
            _packet(0, flags=(1 << 2) | 3), "192.168.1.10"
        )
        self.assertTrue(result.ignored_by_filter)
        self.assertEqual(assembler.partial_frame_count, 0)


class AnalysisTests(unittest.TestCase):
    @staticmethod
    def _frame(samples: np.ndarray, start: int = 0) -> CaptureFrame:
        return CaptureFrame(
            peer_ip="192.168.1.10",
            frame_id=1,
            flags=3,
            packet_count=16,
            total_samples=4096,
            start_sample_index=start,
            input_transaction_id=0,
            capture_status=0,
            samples=tuple(int(value) for value in samples),
        )

    def test_bit_true_pass_fail_and_range(self) -> None:
        samples = np.arange(4096, dtype=np.int32) - 2048
        with tempfile.TemporaryDirectory() as folder:
            path = Path(folder) / "reference.npy"
            reference_values = np.concatenate(
                [np.zeros(25, dtype=np.int32), samples, np.zeros(10, dtype=np.int32)]
            )
            np.save(path, reference_values)
            reference = ReferenceVector.load(path)
            frame = self._frame(samples, start=25)
            result = reference.compare(frame)
            self.assertTrue(result.passed)
            self.assertEqual(result.mismatch_count, 0)

            bad = samples.copy()
            bad[123] += 7
            failed = reference.compare(self._frame(bad, start=25))
            self.assertFalse(failed.passed)
            self.assertEqual(failed.mismatch_count, 1)
            self.assertEqual(failed.max_abs_error, 7)
            self.assertEqual(failed.first_mismatch_offset, 123)

            with self.assertRaises(ReferenceError):
                reference.compare(self._frame(samples, start=36))

    def test_fft_preview_peak_and_resolution(self) -> None:
        rate = 44100 * 128
        bin_number = 100
        phase = np.arange(4096) * (2.0 * np.pi * bin_number / 4096)
        samples = np.rint(0.5 * (1 << 23) * np.sin(phase)).astype(np.int32)
        analysis = analyze_frame(self._frame(samples))
        peak = int(np.argmax(analysis.spectrum.dbfs[1:]) + 1)
        self.assertEqual(peak, bin_number)
        self.assertAlmostEqual(analysis.spectrum.resolution_hz, rate / 4096)
        self.assertAlmostEqual(analysis.spectrum.dbfs[peak], -6.0206, places=2)

    def test_fft_display_normalizes_frame_peak_to_zero_dbr(self) -> None:
        relative, peak_dbfs = normalize_spectrum_to_peak(
            np.asarray([-42.0, -60.0, -122.0], dtype=np.float64)
        )
        np.testing.assert_allclose(relative, [0.0, -18.0, -80.0])
        self.assertEqual(peak_dbfs, -42.0)

        silent, silent_peak = normalize_spectrum_to_peak(
            np.full(8, -300.0, dtype=np.float64)
        )
        np.testing.assert_allclose(silent, np.full(8, -160.0))
        self.assertEqual(silent_peak, -300.0)

    def test_reference_target_is_inferred_from_standard_filename(self) -> None:
        self.assertEqual(
            infer_reference_target(Path("rtl_reference_44100_128x.txt")), (0, 3)
        )
        self.assertEqual(
            infer_reference_target(Path("rtl_reference_48000_4x.npy")), (1, 1)
        )
        self.assertIsNone(infer_reference_target(Path("custom_reference.txt")))

    def test_formal_impulse_matches_reference_implementation(self) -> None:
        from tests.measurement_reference import impulse_response_metrics

        amplitude = 1 << 22
        response = np.zeros(FORMAL_CAPTURE_SAMPLES, dtype=np.int32)
        response[:5] = [1, 2, 3, 2, 1]
        frame = CaptureFrame(
            peer_ip="192.168.1.10",
            frame_id=2,
            flags=(1 << 3) | 3,
            packet_count=64,
            total_samples=response.size,
            start_sample_index=0,
            samples=tuple(int(value) for value in response),
        )
        actual = analyze_impulse_response(frame, amplitude)
        expected = impulse_response_metrics(
            response,
            input_impulse_amplitude=amplitude,
            interpolation=128,
            input_sample_rate_hz=44100,
        )
        self.assertAlmostEqual(actual.passband_max_abs_db, expected.passband_max_abs_db)
        self.assertAlmostEqual(
            actual.stopband_attenuation_db, expected.stopband_attenuation_db
        )
        self.assertEqual(actual.capture_complete, expected.capture_complete)
        self.assertEqual(actual.passed, expected.passed)

    def test_formal_impulse_rejects_nonformal_provenance(self) -> None:
        response = np.zeros(FORMAL_CAPTURE_SAMPLES, dtype=np.int32)
        good = CaptureFrame(
            peer_ip="192.168.1.10",
            frame_id=3,
            flags=(1 << 3) | 3,
            packet_count=64,
            total_samples=FORMAL_CAPTURE_SAMPLES,
            start_sample_index=0,
            samples=tuple(int(value) for value in response),
        )
        with self.assertRaisesRegex(ValueError, r"2\^22"):
            analyze_impulse_response(good, FORMAL_IMPULSE_AMPLITUDE - 1)
        for changed in (
            {"flags": 3},
            {"total_samples": 4096, "packet_count": 16, "samples": tuple([0] * 4096)},
            {"start_sample_index": 1},
            {"capture_status": 1},
        ):
            fields = dict(good.__dict__)
            fields.update(changed)
            with self.assertRaises(ValueError):
                analyze_impulse_response(CaptureFrame(**fields), FORMAL_IMPULSE_AMPLITUDE)

    def test_formal_impulse_save_contains_time_and_full_frequency_csv(self) -> None:
        samples = np.asarray([0, 1, -2, 3, -4, 5, 0, 0], dtype=np.int32)
        frame = CaptureFrame(
            peer_ip="192.168.1.10",
            frame_id=42,
            flags=(1 << 3) | 3,
            packet_count=64,
            total_samples=samples.size,
            start_sample_index=0,
            input_transaction_id=0x1234ABCD,
            capture_status=0,
            samples=tuple(int(value) for value in samples),
        )
        frequency = np.asarray([0.0, 10.0, 20_000.0, 24_100.0, 100_000.0])
        gain = np.asarray([0.0, 0.001, -0.002, -72.5, -110.0])
        metrics = ImpulseResponseMetrics(
            passband_max_db=0.001,
            passband_min_db=-0.002,
            passband_max_abs_db=0.002,
            passband_pp_db=0.003,
            stopband_attenuation_db=72.5,
            worst_stop_frequency_hz=24_100.0,
            capture_complete=True,
            passed=True,
            frequency_hz=frequency,
            gain_db=gain,
        )
        sample_rate = frame.sample_rate
        normalized = samples.astype(np.float64) / float(1 << 23)
        analysis = FrameAnalysis(
            samples_i32=samples,
            normalized=normalized,
            time_seconds=np.arange(samples.size, dtype=np.float64) / sample_rate,
            spectrum=SpectrumPreview(
                frequency_hz=np.asarray([0.0, sample_rate / 2]),
                dbfs=np.asarray([-120.0, -140.0]),
                resolution_hz=float(sample_rate / samples.size),
            ),
            bit_true=None,
        )

        with tempfile.TemporaryDirectory() as folder:
            worker = ArtifactSaveWorker(frame, analysis, Path(folder), metrics)
            worker.run()
            stem = Path(folder) / "frame_00000042_start_0_44100_128x"
            time_rows = stem.with_name(stem.name + "_formal_impulse_time.csv").read_text(
                encoding="utf-8"
            ).splitlines()
            frequency_rows = stem.with_name(
                stem.name + "_formal_impulse_frequency.csv"
            ).read_text(encoding="utf-8").splitlines()

            self.assertEqual(
                time_rows[0],
                "relative_sample_index,output_sample_index,time_seconds,signed_24bit,normalized_fs",
            )
            self.assertEqual(len(time_rows), samples.size + 1)
            self.assertIn(",3,", time_rows[4])
            self.assertEqual(frequency_rows[0], "frequency_hz,gain_db")
            self.assertEqual(len(frequency_rows), frequency.size + 1)
            self.assertEqual(frequency_rows[-1], "100000,-110")
            self.assertTrue(stem.with_name(stem.name + "_formal_impulse.json").is_file())


class UploadCoreTests(unittest.TestCase):
    def test_s24_pack_round_trip_and_packet_plan(self) -> None:
        samples = np.array(
            [-(1 << 23), -1, 0, 1, (1 << 23) - 1] * 103,
            dtype=np.int32,
        )
        self.assertTrue(np.array_equal(unpack_s24le(pack_s24le(samples)), samples))
        plan = build_upload_plan(
            samples,
            transaction_id=0x12345678,
            family_48k=0,
            output_mode=3,
            loop=True,
            ack_required=True,
        )
        self.assertEqual(plan.wave_packet_count, 3)
        self.assertEqual(plan.datagrams[0].stage, "BEGIN")
        self.assertEqual(plan.datagrams[0].sequence, 0)
        self.assertEqual([item.sequence for item in plan.datagrams[1:-1]], [0, 1, 2])
        self.assertEqual(plan.datagrams[-1].stage, "COMMIT")
        self.assertEqual(plan.datagrams[-1].sequence, 3)

        begin = UPLOAD_HEADER.unpack_from(plan.datagrams[0].data)
        self.assertEqual(begin[2], MSG_CONTROL)
        self.assertEqual(begin[5], 0x12345678)
        self.assertEqual(len(plan.datagrams[0].data), 40)
        self.assertEqual(len(plan.datagrams[0].data[32:]), CONTROL_BODY.size)
        self.assertEqual(begin[-1], zlib.crc32(plan.datagrams[0].data[32:]) & 0xFFFFFFFF)

        wave_header = UPLOAD_HEADER.unpack_from(plan.datagrams[1].data)
        self.assertEqual(wave_header[2], MSG_WAVE)
        self.assertEqual(wave_header[9], 256)
        self.assertEqual(len(plan.datagrams[1].data), 32 + 256 * 3)
        self.assertEqual(
            wave_header[-1], zlib.crc32(plan.datagrams[1].data[32:]) & 0xFFFFFFFF
        )

        commit = UPLOAD_HEADER.unpack_from(plan.datagrams[-1].data)
        self.assertEqual(commit[2], MSG_COMMIT)
        self.assertEqual(commit[3], FLAG_ACK_REQUIRED | FLAG_LOOP | FLAG_RESET_PIPELINE)
        self.assertEqual(commit[-1], 0)

    def test_generators_are_deterministic_and_validate_nyquist(self) -> None:
        first = generate_waveform("white_noise", 44100, 1024, seed=77)
        second = generate_waveform("white_noise", 44100, 1024, seed=77)
        different = generate_waveform("white_noise", 44100, 1024, seed=78)
        self.assertTrue(np.array_equal(first, second))
        self.assertFalse(np.array_equal(first, different))
        impulse = generate_waveform("impulse", 48000, 8, amplitude_dbfs=0.0)
        self.assertEqual(int(impulse[0]), (1 << 23) - 1)
        self.assertTrue(np.all(impulse[1:] == 0))
        with self.assertRaises(UploadProtocolError):
            generate_waveform("sine", 44100, 8, frequency1_hz=23000.0)
        with self.assertRaises(UploadProtocolError):
            generate_waveform("sine", 44100, MAX_UPLOAD_SAMPLES + 1)
        with self.assertRaises(UploadProtocolError):
            build_upload_plan(
                np.zeros(MAX_UPLOAD_SAMPLES + 1, dtype=np.int32),
                transaction_id=1,
                family_48k=0,
                output_mode=0,
                loop=False,
            )

    def test_csv_and_pcm_wav_import(self) -> None:
        with tempfile.TemporaryDirectory() as folder:
            csv_path = Path(folder) / "codes.csv"
            csv_path.write_text(
                "sample_index,signed_24bit\n0,-8388608\n1,0\n2,8388607\n",
                encoding="utf-8",
            )
            imported = load_csv_waveform(csv_path, normalised=False)
            self.assertEqual(imported.samples.tolist(), [-8388608, 0, 8388607])

            wav_path = Path(folder) / "stereo.wav"
            stereo = np.array([[32767, 32767], [-32768, -32768]], dtype="<i2")
            with wave.open(str(wav_path), "wb") as stream:
                stream.setnchannels(2)
                stream.setsampwidth(2)
                stream.setframerate(48000)
                stream.writeframes(stereo.tobytes())
            wav = load_wav_waveform(wav_path, 48000)
            self.assertEqual(wav.source_rate, 48000)
            self.assertFalse(wav.resampled)
            self.assertEqual(wav.samples.size, 2)

            oversized_path = Path(folder) / "oversized.txt"
            np.savetxt(
                oversized_path,
                np.zeros(MAX_UPLOAD_SAMPLES + 1, dtype=np.int32),
                fmt="%d",
            )
            with self.assertRaises(UploadProtocolError):
                load_csv_waveform(oversized_path, normalised=False)


if __name__ == "__main__":
    unittest.main(verbosity=2)
