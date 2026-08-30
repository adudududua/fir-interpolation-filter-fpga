#!/usr/bin/env python3
"""Regression tests for safety/usability state transitions in the Qt GUI."""
from __future__ import annotations

import os
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

os.environ.setdefault("QT_QPA_PLATFORM", "offscreen")

import numpy as np
from PySide6.QtWidgets import QApplication, QScrollArea, QWidget

from capture_analysis import ImpulseResponseMetrics, ReferenceVector
from dac24_protocol import CaptureFrame
from gui_app import FORMAL_IMPULSE_WAITING_TEXT, MainWindow


class GuiBehaviorTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls) -> None:
        cls.app = QApplication.instance() or QApplication([])

    def setUp(self) -> None:
        self.window = MainWindow()
        self.window.auto_lock_pass_check.setChecked(True)
        self.window.auto_save_check.setChecked(False)

    def tearDown(self) -> None:
        self.window.hide()
        self.window.deleteLater()
        self.app.processEvents()

    def _show_at(self, width: int, height: int) -> None:
        self.window.resize(width, height)
        self.window.show()
        self.app.processEvents()

    @staticmethod
    def _visible_rect(widget: QWidget):
        top_left = widget.mapToGlobal(widget.rect().topLeft())
        return widget.rect().translated(top_left)

    def _assert_no_vertical_overlap(self, upper: QWidget, lower: QWidget) -> None:
        upper_rect = self._visible_rect(upper)
        lower_rect = self._visible_rect(lower)
        self.assertLessEqual(
            upper_rect.bottom(),
            lower_rect.top(),
            f"{upper.objectName() or type(upper).__name__} overlaps "
            f"{lower.objectName() or type(lower).__name__}",
        )

    def test_layout_has_scroll_fallback_and_unclipped_controls_at_minimum_size(self) -> None:
        self._show_at(1180, 760)

        self.assertIsInstance(self.window.control_scroll, QScrollArea)
        self.assertIsInstance(self.window.measurement_scroll, QScrollArea)
        self.assertIsInstance(self.window.upload_scroll, QScrollArea)
        self.assertGreaterEqual(self.window.network_group.height(), 145)
        self.assertGreaterEqual(self.window.adapter_hint.height(), 34)
        self.assertGreaterEqual(self.window.verify_group.height(), 175)
        self.assertGreaterEqual(self.window.reference_info.height(), 48)
        self.assertGreaterEqual(self.window.output_group.height(), 130)
        self.assertGreaterEqual(self.window.family_card.height(), 78)
        self.assertGreaterEqual(self.window.rate_card.height(), 78)
        self.assertGreaterEqual(self.window.family_card.value.height(), 36)
        self.assertGreaterEqual(self.window.rate_card.value.height(), 36)

        self.window.workspace_tabs.setCurrentWidget(self.window.upload_page)
        self.app.processEvents()
        self.assertGreaterEqual(self.window.transport_group.height(), 385)
        self.assertGreaterEqual(self.window.upload_board_status.height(), 47)
        self.assertGreaterEqual(self.window.upload_status.height(), 31)
        self.assertGreaterEqual(self.window.upload_detail.height(), 32)
        self._assert_no_vertical_overlap(
            self.window.upload_board_status, self.window.upload_status
        )
        self._assert_no_vertical_overlap(
            self.window.upload_status, self.window.upload_progress
        )
        self._assert_no_vertical_overlap(
            self.window.upload_progress, self.window.upload_detail
        )
        self._assert_no_vertical_overlap(
            self.window.upload_detail, self.window.upload_send_button
        )

    def test_layout_remains_unclipped_at_1920_by_1080(self) -> None:
        self._show_at(1920, 1080)
        self.window.workspace_tabs.setCurrentWidget(self.window.upload_page)
        self.app.processEvents()

        self.assertGreaterEqual(self.window.network_group.height(), 145)
        self.assertGreaterEqual(self.window.reference_info.height(), 48)
        self.assertGreaterEqual(self.window.transport_group.height(), 385)
        for card in (
            self.window.frame_card,
            self.window.index_card,
            self.window.family_card,
            self.window.rate_card,
            self.window.source_card,
            self.window.txid_card,
        ):
            self.assertGreaterEqual(card.height(), 78)
            self.assertGreaterEqual(card.value.height(), 36)

    def test_highlight_callouts_use_complete_border_not_single_edge(self) -> None:
        def assert_complete_border(widget: QWidget) -> None:
            style = widget.styleSheet().replace(" ", "")
            self.assertNotIn("border-left", style)
            self.assertIn("border:1pxsolid", style)

        assert_complete_border(self.window.formal_flow_status)
        assert_complete_border(self.window.upload_board_status)
        assert_complete_border(self.window.measurement_instruction)

        for tone in ("cyan", "amber", "green", "red", "muted"):
            self.window._set_formal_flow_stage("状态测试", tone)
            assert_complete_border(self.window.formal_flow_status)

        self.window.current_frame = self._frame(119, 0, tuple(range(32)))
        self.window._refresh_upload_board_status()
        assert_complete_border(self.window.upload_board_status)
        self.window.upload_family_combo.setCurrentIndex(
            self.window.upload_family_combo.findData(1)
        )
        self.window.upload_mode_combo.setCurrentIndex(
            self.window.upload_mode_combo.findData(2)
        )
        self.window._refresh_upload_board_status()
        assert_complete_border(self.window.upload_board_status)

    @staticmethod
    def _frame(frame_id: int, start: int, samples: tuple[int, ...]) -> CaptureFrame:
        return CaptureFrame(
            peer_ip="192.168.1.10",
            frame_id=frame_id,
            flags=3,  # 44.1 kHz / 128x / ROM source
            packet_count=1,
            total_samples=len(samples),
            start_sample_index=start,
            samples=samples,
        )

    def test_first_pass_is_latched_and_later_frame_cannot_overwrite_it(self) -> None:
        samples = tuple(range(32))
        passing_frame = self._frame(110, 0, samples)
        self.window.reference = ReferenceVector(
            Path("memory-reference.txt"), np.asarray(samples, dtype=np.int64)
        )

        self.window._on_frame_ready(passing_frame)
        self.app.processEvents()  # Run the non-blocking single-shot stop request.

        self.assertTrue(self.window.bit_true_pass_latched)
        self.assertIs(self.window.current_frame, passing_frame)
        self.assertIn("PASS 已锁定", self.window.bit_status.text())
        self.assertIn("PASS 结果已锁定", self.window.listener_pill.text())

        later_frame = self._frame(111, 1_000_000, tuple(-value for value in samples))
        self.window._on_frame_ready(later_frame)

        self.assertIs(self.window.current_frame, passing_frame)
        self.assertIn("PASS 已锁定", self.window.bit_status.text())
        self.assertEqual(self.window.mismatch_card.value.text(), "0 / 32")
        self.assertEqual(self.window.error_card.value.text(), "0 LSB")

    def test_formal_impulse_plot_explains_exact_trigger(self) -> None:
        displayed = "\n".join(
            text.get_text() for text in self.window.impulse_canvas.axis.texts
        )
        self.assertEqual(displayed, FORMAL_IMPULSE_WAITING_TEXT)
        for phrase in ("一键正式冲激测量", "自动监听", "什么时候按都可以", "无需抢时间"):
            self.assertIn(phrase, displayed)

    def test_formal_impulse_plot_displays_passband_and_stopband_metrics(self) -> None:
        frequency_hz = np.asarray([0.0, 10_000.0, 20_000.0, 24_100.0, 30_000.0])
        gain_db = np.asarray([0.0, 0.003, -0.004, -72.4, -90.0])
        metrics = ImpulseResponseMetrics(
            passband_max_db=0.003,
            passband_min_db=-0.004,
            passband_max_abs_db=0.004,
            passband_pp_db=0.007,
            stopband_attenuation_db=72.4,
            worst_stop_frequency_hz=24_100.0,
            capture_complete=True,
            passed=True,
            frequency_hz=frequency_hz,
            gain_db=gain_db,
        )

        self.window._draw_impulse_response(
            metrics, self._frame(118, 0, tuple(range(32)))
        )

        displayed = "\n".join(
            text.get_text() for text in self.window.impulse_canvas.axis.texts
        )
        self.assertIn("正式指标：PASS", displayed)
        self.assertIn("板端采样率族：44.1 kHz", displayed)
        self.assertIn("通带最大绝对偏差：0.004000 dB", displayed)
        self.assertIn("通带峰峰纹波：0.007000 dB", displayed)
        self.assertIn("阻带最小衰减：72.400 dB", displayed)
        self.assertIn("最差阻带频点：24.100 kHz", displayed)

        frame_48k = CaptureFrame(
            peer_ip="192.168.1.10",
            frame_id=119,
            flags=7,  # 48 kHz / 128x / ROM source
            packet_count=1,
            total_samples=32,
            start_sample_index=0,
            samples=tuple(range(32)),
        )
        self.window._draw_impulse_response(metrics, frame_48k)
        displayed_48k = "\n".join(
            text.get_text() for text in self.window.impulse_canvas.axis.texts
        )
        self.assertIn("板端采样率族：48 kHz", displayed_48k)

    def test_upload_status_accepts_matching_observed_board_without_sw_prompt(self) -> None:
        self.window.current_frame = self._frame(120, 1234, tuple(range(32)))
        self.window.upload_family_combo.setCurrentIndex(
            self.window.upload_family_combo.findData(0)
        )
        self.window.upload_mode_combo.setCurrentIndex(
            self.window.upload_mode_combo.findData(3)
        )

        self.window._refresh_upload_board_status()

        self.assertIn("与本次上传一致", self.window.upload_board_status.text())
        self.assertIn("可直接上传", self.window.upload_board_status.text())
        self.assertNotIn("请按", self.window.upload_board_status.text())

    def test_upload_status_names_only_required_sw_when_board_differs(self) -> None:
        self.window.current_frame = self._frame(121, 1234, tuple(range(32)))
        self.window.upload_family_combo.setCurrentIndex(
            self.window.upload_family_combo.findData(1)
        )
        self.window.upload_mode_combo.setCurrentIndex(
            self.window.upload_mode_combo.findData(2)
        )

        self.window._refresh_upload_board_status()

        status = self.window.upload_board_status.text()
        self.assertIn("板上当前为 44100 Hz / 128x", status)
        self.assertIn("本次上传目标为 48000 Hz / 8x", status)
        self.assertIn("请按住 SW7 约 0.2 秒后松开", status)
        self.assertNotIn("本轮", status)
        self.assertNotIn("不承诺", status)

    def test_ordinary_observation_follows_new_board_sw_target(self) -> None:
        self.window.follow_board_check.setChecked(True)

        with patch.object(self.window, "stop_capture") as stop_capture:
            self.window._on_transition_ignored(1, 3, 130)

        stop_capture.assert_called_once_with()
        self.assertEqual(self.window.follow_board_pending, (1, 3))
        self.assertIn("自动跟随", self.window.listener_pill.text())

    def test_filtered_packet_updates_live_board_telemetry_without_becoming_proof(self) -> None:
        self.window.current_frame = self._frame(121, 1234, tuple(range(32)))
        self.window.upload_family_combo.setCurrentIndex(
            self.window.upload_family_combo.findData(1)
        )
        self.window.upload_mode_combo.setCurrentIndex(
            self.window.upload_mode_combo.findData(3)
        )
        packet = SimpleNamespace(
            family_48k=0,
            mode=3,
            frame_id=25610,
            start_sample_index=987654,
            upload_source=1,
            input_transaction_id=0x12345678,
        )

        self.window._on_board_state_seen(packet)

        self.assertEqual(self.window.live_board_target, (0, 3))
        self.assertEqual(self.window._observed_board_target(), (0, 3))
        self.assertIn("25610", self.window.frame_card.value.text())
        self.assertIn("44100", self.window.family_card.value.text())
        self.assertIn("128x", self.window.family_card.value.text())
        self.assertIn("板上当前为 44100 Hz / 128x", self.window.upload_board_status.text())

    def test_live_target_match_waits_for_complete_frame_before_upload_ready(self) -> None:
        self.window.current_frame = self._frame(121, 1234, tuple(range(32)))
        self.window.upload_family_combo.setCurrentIndex(
            self.window.upload_family_combo.findData(1)
        )
        self.window.upload_mode_combo.setCurrentIndex(
            self.window.upload_mode_combo.findData(3)
        )
        packet = SimpleNamespace(
            family_48k=1,
            mode=3,
            frame_id=25611,
            start_sample_index=100,
            upload_source=0,
            input_transaction_id=0,
        )

        self.window._on_board_state_seen(packet)

        self.assertEqual(self.window.live_board_target, (1, 3))
        self.assertNotEqual(self.window._observed_board_target(), (1, 3))
        self.assertIn("正在等待这一工况的完整帧", self.window.upload_board_status.text())
        self.assertNotIn("可直接上传", self.window.upload_board_status.text())

    def test_follow_restart_updates_capture_and_upload_targets(self) -> None:
        self.window.follow_board_pending = (1, 3)
        self.window.receiver_thread = SimpleNamespace(deleteLater=lambda: None)
        self.window.receiver = SimpleNamespace()

        with patch.object(self.window, "start_capture") as start_capture:
            self.window._on_receiver_finished()
            self.app.processEvents()

        self.assertEqual(self.window.family_combo.currentData(), 1)
        self.assertEqual(self.window.mode_combo.currentData(), 3)
        self.assertEqual(self.window.upload_family_combo.currentData(), 1)
        self.assertEqual(self.window.upload_mode_combo.currentData(), 3)
        start_capture.assert_called_once_with()

    def test_reference_for_other_family_is_not_reported_as_bit_true_fail(self) -> None:
        samples = tuple(range(32))
        self.window.reference = ReferenceVector(
            Path("rtl_reference_44100_128x.txt"),
            np.asarray(samples, dtype=np.int64),
        )
        frame_48k_128x = CaptureFrame(
            peer_ip="192.168.1.10",
            frame_id=131,
            flags=(1 << 2) | 3,
            packet_count=1,
            total_samples=len(samples),
            start_sample_index=0,
            samples=samples,
        )

        self.window._on_frame_ready(frame_48k_128x)

        self.assertIn("参考不适用于当前帧", self.window.bit_status.text())
        self.assertEqual(self.window.mismatch_card.value.text(), "未比较")
        self.assertNotIn("FAIL", self.window.bit_status.text())
        self.assertIn("44100 Hz/128x", self.window.compare_range.text())
        self.assertIn("48000 Hz/128x", self.window.compare_range.text())

    def test_selecting_impulse_inherits_recent_board_target(self) -> None:
        frame = CaptureFrame(
            peer_ip="192.168.1.10",
            frame_id=122,
            flags=(1 << 2) | 2,  # 48 kHz / 8x
            packet_count=1,
            total_samples=32,
            start_sample_index=0,
            samples=tuple(range(32)),
        )
        self.window.current_frame = frame
        self.window.upload_family_combo.setCurrentIndex(
            self.window.upload_family_combo.findData(0)
        )
        self.window.upload_mode_combo.setCurrentIndex(
            self.window.upload_mode_combo.findData(3)
        )

        self.window.upload_source_combo.setCurrentIndex(
            self.window.upload_source_combo.findData("impulse")
        )

        self.assertEqual(self.window.upload_family_combo.currentData(), 1)
        self.assertEqual(self.window.upload_mode_combo.currentData(), 2)
        self.assertIn("与本次上传一致", self.window.upload_board_status.text())

    def test_selecting_impulse_replaces_unsupported_1x_with_128x(self) -> None:
        self.window.current_frame = CaptureFrame(
            peer_ip="192.168.1.10",
            frame_id=123,
            flags=0,  # 44.1 kHz / 1x
            packet_count=1,
            total_samples=32,
            start_sample_index=0,
            samples=tuple(range(32)),
        )
        self.window.upload_mode_combo.setCurrentIndex(
            self.window.upload_mode_combo.findData(1)
        )

        self.window.upload_source_combo.setCurrentIndex(
            self.window.upload_source_combo.findData("impulse")
        )

        self.assertEqual(self.window.upload_family_combo.currentData(), 0)
        self.assertEqual(self.window.upload_mode_combo.currentData(), 3)
        self.assertIn("请按住 SW4 约 0.2 秒后松开", self.window.upload_board_status.text())

    def test_generated_zero_dbfs_tone_is_automatically_limited_to_half_scale(self) -> None:
        self.window.upload_source_combo.setCurrentIndex(
            self.window.upload_source_combo.findData("sine")
        )
        self.window.upload_family_combo.setCurrentIndex(
            self.window.upload_family_combo.findData(1)
        )
        self.window.upload_count_spin.setValue(4096)
        self.window.upload_amp_spin.setValue(0.0)
        self.window.upload_f1_spin.setValue(15000.0)
        self.window.upload_headroom_check.setChecked(True)

        self.window._prepare_upload_waveform()

        self.assertIsNotNone(self.window.upload_samples)
        peak = int(np.max(np.abs(self.window.upload_samples.astype(np.int64))))
        self.assertLessEqual(peak, 1 << 22)
        self.assertAlmostEqual(self.window.upload_amp_spin.value(), -6.02, places=2)
        self.assertIn("实际峰值 -6.02 dBFS", self.window.upload_detail.text())
        self.assertIn("自动限幅", self.window.upload_detail.text())

    def test_headroom_protection_does_not_change_formal_impulse(self) -> None:
        self.window.upload_source_combo.setCurrentIndex(
            self.window.upload_source_combo.findData("impulse")
        )

        self.window._prepare_upload_waveform()

        self.assertIsNotNone(self.window.upload_samples)
        self.assertEqual(int(self.window.upload_samples[0]), 1 << 22)
        self.assertTrue(np.all(self.window.upload_samples[1:] == 0))
        self.assertFalse(self.window.upload_headroom_check.isEnabled())

    def test_parameter_edit_is_debounced_for_automatic_apply(self) -> None:
        self.window.upload_source_combo.setCurrentIndex(
            self.window.upload_source_combo.findData("sine")
        )
        self.window.upload_auto_apply_check.setChecked(True)

        self.window._schedule_auto_apply()

        self.assertTrue(self.window.auto_apply_timer.isActive())
        self.assertIn("0.9 秒后自动应用", self.window.upload_status.text())
        self.window.auto_apply_timer.stop()

    def test_disabling_auto_apply_leaves_manual_fallback(self) -> None:
        self.window.upload_auto_apply_check.setChecked(False)

        self.window._schedule_auto_apply()

        self.assertFalse(self.window.auto_apply_timer.isActive())
        self.assertFalse(self.window.auto_apply_pending)
        self.assertIn("输入到板卡", self.window.upload_send_button.text())
        self.assertIn("尚未输入板卡", self.window.upload_status.text())

    def test_matching_board_automatically_prepares_and_uploads_latest_frequency(self) -> None:
        self.window.upload_source_combo.setCurrentIndex(
            self.window.upload_source_combo.findData("sine")
        )
        self.window.upload_family_combo.setCurrentIndex(
            self.window.upload_family_combo.findData(0)
        )
        self.window.upload_mode_combo.setCurrentIndex(
            self.window.upload_mode_combo.findData(3)
        )
        self.window.upload_f1_spin.setValue(19000.0)
        self.window.current_frame = self._frame(170, 0, tuple(range(32)))
        self.window.receiver_thread = object()
        self.window.receiver = SimpleNamespace(
            config=SimpleNamespace(expected_family_48k=0, expected_mode=3)
        )
        self.window.auto_apply_pending = True
        self.window.auto_apply_target = (0, 3)

        def prepare() -> None:
            self.window.upload_samples = np.zeros(4096, dtype=np.int32)

        try:
            with (
                patch.object(
                    self.window, "_prepare_upload_waveform", side_effect=prepare
                ) as prepare_upload,
                patch.object(
                    self.window, "_start_upload", return_value=True
                ) as start_upload,
            ):
                self.assertTrue(self.window._drive_auto_apply())
        finally:
            self.window.receiver_thread = None
            self.window.receiver = None

        prepare_upload.assert_called_once_with()
        start_upload.assert_called_once_with()
        self.assertFalse(self.window.auto_apply_pending)

    def test_mismatching_board_waits_for_one_sw_without_upload(self) -> None:
        self.window.upload_family_combo.setCurrentIndex(
            self.window.upload_family_combo.findData(1)
        )
        self.window.upload_mode_combo.setCurrentIndex(
            self.window.upload_mode_combo.findData(3)
        )
        self.window.current_frame = self._frame(171, 0, tuple(range(32)))
        self.window.receiver_thread = object()
        self.window.receiver = SimpleNamespace(
            config=SimpleNamespace(expected_family_48k=1, expected_mode=3)
        )
        self.window.auto_apply_pending = True
        self.window.auto_apply_target = (1, 3)

        try:
            with (
                patch.object(self.window, "_prepare_upload_waveform") as prepare,
                patch.object(self.window, "_start_upload") as start_upload,
            ):
                self.assertFalse(self.window._drive_auto_apply())
        finally:
            self.window.receiver_thread = None
            self.window.receiver = None

        prepare.assert_not_called()
        start_upload.assert_not_called()
        self.assertTrue(self.window.auto_apply_pending)
        self.assertIn("SW8", self.window.upload_detail.text())

    def test_one_click_starts_listener_when_not_listening(self) -> None:
        self.assertIsNone(self.window.receiver_thread)

        with patch.object(self.window, "start_capture") as start_capture:
            self.window._start_formal_impulse_flow()

        start_capture.assert_called_once_with()
        self.assertEqual(self.window.upload_source_combo.currentData(), "impulse")
        self.assertEqual(self.window.upload_count_spin.value(), 16384)
        self.assertTrue(self.window.upload_ack_check.isChecked())
        self.assertFalse(self.window.upload_loop_check.isChecked())
        self.assertIn("未能启动监听", self.window.formal_flow_status.text())

    def test_one_click_uses_selected_48k_target_not_stale_44k_listener(self) -> None:
        self.window.upload_family_combo.setCurrentIndex(
            self.window.upload_family_combo.findData(1)
        )
        self.window.upload_mode_combo.setCurrentIndex(
            self.window.upload_mode_combo.findData(3)
        )
        self.window.receiver_thread = object()
        self.window.receiver = SimpleNamespace(
            config=SimpleNamespace(expected_family_48k=0, expected_mode=3)
        )

        try:
            with patch.object(self.window, "stop_capture") as stop_capture:
                self.window._start_formal_impulse_flow()
        finally:
            self.window.receiver_thread = None
            self.window.receiver = None

        self.assertEqual(self.window.formal_flow_target, (1, 3))
        self.assertTrue(self.window.formal_flow_restart_receiver)
        self.assertEqual(self.window.family_combo.currentData(), 1)
        self.assertEqual(self.window.mode_combo.currentData(), 3)
        self.assertIn("48000 Hz / 128x", self.window.formal_flow_status.text())
        stop_capture.assert_called_once_with()

    def test_one_click_waits_for_sw_without_upload_or_timeout(self) -> None:
        self.window.formal_flow_active = True
        self.window.formal_flow_upload_started = False
        self.window.formal_flow_target = (1, 2)  # 48 kHz / 8x -> SW7
        self.window.receiver_thread = object()
        self.window.current_frame = self._frame(140, 0, tuple(range(32)))

        with patch.object(self.window, "_start_upload") as start_upload:
            self.window._advance_formal_impulse_flow()

        start_upload.assert_not_called()
        self.assertTrue(self.window.formal_flow_active)
        self.assertFalse(self.window.formal_flow_upload_started)
        self.assertIn("请按住 SW7 约 0.2 秒后松开", self.window.formal_flow_status.text())
        self.assertIn("什么时候按都可以", self.window.formal_flow_status.text())

    def test_one_click_matching_complete_frame_uploads_only_once(self) -> None:
        self.window.formal_flow_active = True
        self.window.formal_flow_upload_started = False
        self.window.formal_flow_target = (0, 3)
        self.window.receiver_thread = object()
        self.window.current_frame = self._frame(141, 0, tuple(range(32)))

        def prepare() -> None:
            self.window.upload_samples = np.zeros(16384, dtype=np.int32)
            self.window.upload_samples[0] = 1 << 22

        with (
            patch.object(self.window, "_prepare_upload_waveform", side_effect=prepare),
            patch.object(self.window, "_start_upload", return_value=True) as start_upload,
        ):
            self.window._advance_formal_impulse_flow()
            self.window._advance_formal_impulse_flow()

        start_upload.assert_called_once_with()
        self.assertTrue(self.window.formal_flow_upload_started)

    def test_latched_formal_result_is_not_overwritten_by_next_frame(self) -> None:
        first = self._frame(150, 0, tuple(range(32)))
        self.window.current_frame = first
        self.window.formal_result_latched = True
        self.window.impulse_result.setText("正式冲激频响：PASS · 已锁定")

        later = self._frame(151, 16384, tuple(-value for value in range(32)))
        self.window._on_frame_ready(later)

        self.assertIs(self.window.current_frame, first)
        self.assertEqual(self.window.impulse_result.text(), "正式冲激频响：PASS · 已锁定")

    def test_formal_completion_latches_before_queued_next_frame(self) -> None:
        txid = 0x1234ABCD
        samples = tuple(0 for _ in range(16384))
        samples = ((1 << 22),) + samples[1:]
        formal = CaptureFrame(
            peer_ip="192.168.1.10",
            frame_id=160,
            flags=(1 << 3) | 3,  # upload source, 44.1 kHz / 128x
            packet_count=64,
            total_samples=16384,
            start_sample_index=0,
            samples=samples,
            input_transaction_id=txid,
        )
        self.window.formal_flow_active = True
        self.window.formal_flow_upload_started = True
        self.window.formal_flow_target = (0, 3)
        self.window.upload_impulses[txid] = 1 << 22
        self.window.confirmed_upload_transactions.add(txid)
        self.window.last_upload_transaction_id = txid

        with patch.object(self.window, "_queue_formal_artifact_save") as save_formal:
            self.window._on_frame_ready(formal)

        save_formal.assert_called_once()

        self.assertTrue(self.window.formal_result_latched)
        self.assertIs(self.window.current_frame, formal)
        frozen_text = self.window.impulse_result.text()
        later = CaptureFrame(
            peer_ip="192.168.1.10",
            frame_id=161,
            flags=(1 << 3) | 3,
            packet_count=64,
            total_samples=16384,
            start_sample_index=16384,
            samples=samples,
            input_transaction_id=txid,
        )
        self.window._on_frame_ready(later)
        self.assertIs(self.window.current_frame, formal)
        self.assertEqual(self.window.impulse_result.text(), frozen_text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
