#!/usr/bin/env python3
"""Qt worker objects for continuous DAC24 UDP reception and artifact saving."""
from __future__ import annotations

import csv
import json
import socket
import threading
from dataclasses import dataclass
from pathlib import Path
from typing import Optional

import numpy as np

try:
    from PySide6.QtCore import QObject, Signal, Slot
except ImportError as exc:  # Keep the failure clear when imported without GUI extras.
    raise ImportError(
        "capture_worker 需要 PySide6；请安装 requirements-gui.txt"
    ) from exc

from capture_analysis import (
    FrameAnalysis,
    ImpulseResponseMetrics,
    normalize_spectrum_to_peak,
)
from dac24_protocol import (
    CaptureFrame,
    FrameAssembler,
    MODE_NAMES,
    ProtocolError,
    parse_packet,
)


@dataclass(frozen=True)
class ReceiverConfig:
    bind_address: str = "0.0.0.0"
    port: int = 4000
    expected_family_48k: Optional[int] = 0
    expected_mode: Optional[int] = 3


class CaptureWorker(QObject):
    """Owns a persistent UDP socket and runs inside a dedicated QThread."""

    listening = Signal(str, int)
    valid_packet_seen = Signal(str)
    # Every syntactically valid DAC2 packet reports the live board descriptor,
    # including packets that the fixed receive filter will subsequently drop.
    # This keeps GUI telemetry truthful while a physical SW transition is in
    # progress.  A live packet is display evidence only; uploads still wait for
    # a fully reassembled target frame.
    board_state_seen = Signal(object)
    packet_activity = Signal(str, int, int, int, int, int, int)
    # peer, frame_id, received, total, family_48k, mode, start_index
    frame_ready = Signal(object)
    transition_ignored = Signal(int, int, int)
    protocol_warning = Signal(str)
    stopped = Signal()
    failed = Signal(str)

    def __init__(self, config: ReceiverConfig) -> None:
        super().__init__()
        self.config = config
        self._stop_event = threading.Event()
        self._socket: Optional[socket.socket] = None

    @Slot()
    def stop(self) -> None:
        self._stop_event.set()

    @Slot()
    def run(self) -> None:
        assembler = FrameAssembler(
            expected_family_48k=self.config.expected_family_48k,
            expected_mode=self.config.expected_mode,
        )
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self._socket = sock
        try:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1 << 20)
            sock.settimeout(0.20)
            sock.bind((self.config.bind_address, self.config.port))
            shown = self.config.bind_address or "0.0.0.0"
            self.listening.emit(shown, self.config.port)

            last_ignored_descriptor = None
            last_board_descriptor = None
            while not self._stop_event.is_set():
                try:
                    data, peer = sock.recvfrom(2048)
                except socket.timeout:
                    continue
                except OSError:
                    if self._stop_event.is_set():
                        break
                    raise

                try:
                    packet = parse_packet(data, peer[0])
                    self.valid_packet_seen.emit(packet.peer_ip)
                    board_descriptor = (
                        packet.family_48k,
                        packet.mode,
                        packet.frame_id,
                        packet.start_sample_index,
                        packet.upload_source,
                        packet.input_transaction_id,
                        packet.capture_status,
                    )
                    if board_descriptor != last_board_descriptor:
                        self.board_state_seen.emit(packet)
                        last_board_descriptor = board_descriptor
                    result = assembler.feed(packet)
                except ProtocolError as exc:
                    self.protocol_warning.emit(str(exc))
                    continue

                if result.ignored_by_filter:
                    descriptor = (packet.family_48k, packet.mode, packet.frame_id)
                    if descriptor != last_ignored_descriptor:
                        self.transition_ignored.emit(
                            packet.family_48k, packet.mode, packet.frame_id
                        )
                        last_ignored_descriptor = descriptor
                    continue

                progress = result.progress
                if progress is not None:
                    self.packet_activity.emit(
                        progress.peer_ip,
                        progress.frame_id,
                        progress.received_packets,
                        progress.packet_count,
                        progress.family_48k,
                        progress.mode,
                        progress.start_sample_index,
                    )
                if result.frame is not None:
                    self.frame_ready.emit(result.frame)
        except OSError as exc:
            if getattr(exc, "winerror", None) == 10049:
                self.failed.emit(
                    "本机没有可绑定的该 IPv4 地址。请设置有线网卡静态地址，"
                    "或改为 0.0.0.0 监听全部网卡。"
                )
            else:
                self.failed.emit(str(exc))
        except Exception as exc:  # Keep a worker exception from silently killing QThread.
            self.failed.emit(f"接收线程异常：{exc}")
        finally:
            try:
                sock.close()
            finally:
                self._socket = None
                self.stopped.emit()


class ArtifactSaveWorker(QObject):
    """Save one immutable frame/analysis pair without blocking the GUI thread."""

    saved = Signal(str)
    failed = Signal(str)
    finished = Signal()

    def __init__(
        self,
        frame: CaptureFrame,
        analysis: FrameAnalysis,
        output_dir: Path,
        impulse_metrics: Optional[ImpulseResponseMetrics] = None,
    ) -> None:
        super().__init__()
        self.frame = frame
        self.analysis = analysis
        self.output_dir = Path(output_dir)
        self.impulse_metrics = impulse_metrics

    @Slot()
    def run(self) -> None:
        try:
            self.output_dir.mkdir(parents=True, exist_ok=True)
            stem = (
                f"frame_{self.frame.frame_id:08d}_start_{self.frame.start_sample_index}_"
                f"{self.frame.family_rate}_{MODE_NAMES[self.frame.mode]}"
            )
            np.save(self.output_dir / f"{stem}.npy", self.analysis.samples_i32)
            with (self.output_dir / f"{stem}.csv").open(
                "w", newline="", encoding="utf-8"
            ) as stream:
                writer = csv.writer(stream)
                writer.writerow(["sample_index", "signed_24bit"])
                writer.writerows(
                    (
                        self.frame.start_sample_index + offset,
                        int(value),
                    )
                    for offset, value in enumerate(self.analysis.samples_i32)
                )
            metadata_path = self.output_dir / f"{stem}.meta.txt"
            metadata_path.write_text(
                "\n".join(
                    (
                        f"peer_ip={self.frame.peer_ip}",
                        f"frame_id={self.frame.frame_id}",
                        f"family_rate={self.frame.family_rate}",
                        f"mode={self.frame.mode_name}",
                        f"output_sample_rate={self.frame.sample_rate}",
                        f"start_sample_index={self.frame.start_sample_index}",
                        f"input_source={'upload_ram' if self.frame.upload_source else 'rom'}",
                        f"input_transaction_id=0x{self.frame.input_transaction_id:08X}",
                        f"capture_status=0x{self.frame.capture_status:04X}",
                    )
                )
                + "\n",
                encoding="utf-8",
            )
            # Use an independent non-Qt Figure in this IO worker.  The live
            # Qt canvases stay exclusively in the GUI thread.
            from matplotlib.backends.backend_agg import FigureCanvasAgg
            from matplotlib.figure import Figure

            figure = Figure(figsize=(11, 8), facecolor="#0b1218")
            FigureCanvasAgg(figure)
            axes = figure.subplots(3, 1)
            _style_axes(axes)
            axes[0].plot(
                self.analysis.time_seconds * 1e6,
                self.analysis.normalized,
                color="#48d6cc",
                linewidth=0.85,
            )
            axes[0].set(title="24 位输出时域", xlabel="时间 / µs", ylabel="FS")
            relative_db, peak_dbfs = normalize_spectrum_to_peak(
                self.analysis.spectrum.dbfs
            )
            axes[1].plot(
                self.analysis.spectrum.frequency_hz / 1e6,
                relative_db,
                color="#75a7ff",
                linewidth=0.8,
            )
            axes[1].set(
                title=(
                    f"{self.frame.total_samples} 点归一化 FFT · "
                    f"原始峰值 {peak_dbfs:.2f} dBFS"
                ),
                xlabel="频率 / MHz",
                ylabel="dBr（谱峰=0 dB）",
            )
            axes[1].set_ylim(-160, 5)
            local = self.analysis.spectrum.below(50000.0)
            axes[2].plot(
                local.frequency_hz / 1e3,
                relative_db[: local.dbfs.size],
                color="#f4b860",
                marker="o",
                markersize=2.2,
                linewidth=0.9,
            )
            axes[2].axvspan(0.01, 20.0, color="#48d6cc", alpha=0.08)
            axes[2].set(
                title="0–50 kHz 归一化相对谱",
                xlabel="频率 / kHz",
                ylabel="dBr（谱峰=0 dB）",
            )
            axes[2].set_xlim(0, 50)
            axes[2].set_ylim(-160, 5)
            figure.suptitle(
                f"DAC24 板上帧 {self.frame.frame_id} · "
                f"{self.frame.family_rate} Hz/{self.frame.mode_name} · "
                f"start {self.frame.start_sample_index}",
                color="#e7eef3",
                fontsize=13,
            )
            if self.frame.upload_source:
                figure.text(
                    0.99,
                    0.006,
                    f"input txid 0x{self.frame.input_transaction_id:08X} · "
                    f"capture status 0x{self.frame.capture_status:04X}",
                    ha="right",
                    color="#91a5b3",
                    fontsize=8,
                )
            figure.tight_layout(rect=(0, 0, 1, 0.965))
            figure.savefig(self.output_dir / f"{stem}.png", dpi=150)
            if self.impulse_metrics is not None:
                self._save_formal_impulse_artifacts(stem)
            self.saved.emit(str((self.output_dir / stem).resolve()))
        except Exception as exc:
            self.failed.emit(f"保存失败：{exc}")
        finally:
            self.finished.emit()

    def _save_formal_impulse_artifacts(self, stem: str) -> None:
        """将正式冲激的原始时域、完整频响和判定指标一起归档。"""
        from matplotlib.backends.backend_agg import FigureCanvasAgg
        from matplotlib.figure import Figure

        metrics = self.impulse_metrics
        assert metrics is not None
        formal_stem = self.output_dir / f"{stem}_formal_impulse"
        stop_start = self.frame.family_rate - 20_000
        stride = max(1, metrics.frequency_hz.size // 50_000)
        result_label = (
            "PASS" if metrics.passed else "FAIL" if metrics.capture_complete else "UNDETERMINED"
        )

        figure = Figure(figsize=(12, 6.6), facecolor="#0b1218")
        FigureCanvasAgg(figure)
        axis = figure.subplots(1, 1)
        _style_axes((axis,))
        axis.plot(
            metrics.frequency_hz[::stride] / 1e3,
            metrics.gain_db[::stride],
            color="#47d7ce",
            linewidth=0.75,
        )
        axis.axvspan(0.01, 20.0, color="#47d7ce", alpha=0.08, label="通带 10 Hz–20 kHz")
        axis.axvspan(
            stop_start / 1e3,
            self.frame.sample_rate / 2e3,
            color="#ff6b72",
            alpha=0.06,
            label=f"阻带 {stop_start / 1e3:.1f} kHz–Nyquist",
        )
        axis.axhline(-70.0, color="#ff6b72", linestyle="--", linewidth=0.9)
        result_color = (
            "#70e0a0"
            if metrics.passed
            else "#ff6b72"
            if metrics.capture_complete
            else "#ffb454"
        )
        metric_summary = (
            f"正式指标：{result_label}\n"
            f"通带最大绝对偏差：{metrics.passband_max_abs_db:.6f} dB  "
            f"({'≤ 0.05 dB' if metrics.passband_max_abs_db <= 0.05 else '> 0.05 dB'})\n"
            f"通带峰峰纹波：{metrics.passband_pp_db:.6f} dB\n"
            f"通带范围：{metrics.passband_min_db:+.6f} ～ "
            f"{metrics.passband_max_db:+.6f} dB\n"
            f"阻带最小衰减：{metrics.stopband_attenuation_db:.3f} dB  "
            f"({'≥ 70 dB' if metrics.stopband_attenuation_db >= 70 else '< 70 dB'})\n"
            f"最差阻带频点：{metrics.worst_stop_frequency_hz / 1e3:.3f} kHz"
        )
        axis.text(
            0.985,
            0.965,
            metric_summary,
            transform=axis.transAxes,
            ha="right",
            va="top",
            color=result_color,
            fontsize=8.6,
            linespacing=1.35,
            bbox={
                "boxstyle": "round,pad=0.55",
                "facecolor": "#101b23",
                "edgecolor": result_color,
                "linewidth": 1.0,
                "alpha": 0.96,
            },
            zorder=5,
        )
        axis.set(
            title=(
                f"正式无窗冲激频响 · {result_label} · "
                f"txid 0x{self.frame.input_transaction_id:08X}"
            ),
            xlabel="频率 / kHz",
            ylabel="增益 / dB",
            xlim=(0, self.frame.sample_rate / 2e3),
            ylim=(-140, 2),
        )
        axis.legend(loc="upper right")
        figure.text(
            0.01,
            0.01,
            f"NFFT=2^20, H=FFT(y)/(A·L), A=4194304 | "
            f"max|Gpass|={metrics.passband_max_abs_db:.6f} dB | "
            f"ripple_pp={metrics.passband_pp_db:.6f} dB | "
            f"stop={metrics.stopband_attenuation_db:.3f} dB | "
            f"worst={metrics.worst_stop_frequency_hz / 1e3:.3f} kHz",
            color="#aebdc7",
            fontsize=9,
        )
        figure.tight_layout(rect=(0, 0.04, 1, 1))
        figure.savefig(formal_stem.with_suffix(".png"), dpi=180)

        # 两份 CSV 都保留完整数值，不使用绘图时为提速而采用的 stride。
        # time.csv 是板端回传的 16384 个 DAC 截位前 24 位输出样本；
        # frequency.csv 是 NFFT=2^20 的完整单边正式传递函数结果。
        with self.output_dir.joinpath(f"{stem}_formal_impulse_time.csv").open(
            "w", newline="", encoding="utf-8"
        ) as stream:
            writer = csv.writer(stream)
            writer.writerow(
                (
                    "relative_sample_index",
                    "output_sample_index",
                    "time_seconds",
                    "signed_24bit",
                    "normalized_fs",
                )
            )
            writer.writerows(
                (
                    offset,
                    self.frame.start_sample_index + offset,
                    f"{float(self.analysis.time_seconds[offset]):.17g}",
                    int(value),
                    f"{float(self.analysis.normalized[offset]):.17g}",
                )
                for offset, value in enumerate(self.analysis.samples_i32)
            )

        with self.output_dir.joinpath(f"{stem}_formal_impulse_frequency.csv").open(
            "w", newline="", encoding="utf-8"
        ) as stream:
            writer = csv.writer(stream)
            writer.writerow(("frequency_hz", "gain_db"))
            writer.writerows(
                (f"{float(frequency):.17g}", f"{float(gain):.17g}")
                for frequency, gain in zip(metrics.frequency_hz, metrics.gain_db)
            )

        record = {
            "result": result_label,
            "capture_complete": metrics.capture_complete,
            "input_transaction_id": f"0x{self.frame.input_transaction_id:08X}",
            "capture_status": f"0x{self.frame.capture_status:04X}",
            "family_rate_hz": self.frame.family_rate,
            "mode": self.frame.mode_name,
            "output_sample_rate_hz": self.frame.sample_rate,
            "total_samples": self.frame.total_samples,
            "start_sample_index": self.frame.start_sample_index,
            "input_impulse_amplitude_s24": 1 << 22,
            "nfft": 1 << 20,
            "passband_hz": [10.0, 20_000.0],
            "stopband_start_hz": float(stop_start),
            "passband_max_db": metrics.passband_max_db,
            "passband_min_db": metrics.passband_min_db,
            "passband_peak_to_peak_db": metrics.passband_pp_db,
            "passband_max_abs_db": metrics.passband_max_abs_db,
            "stopband_attenuation_db": metrics.stopband_attenuation_db,
            "worst_stop_frequency_hz": metrics.worst_stop_frequency_hz,
            "limits": {
                "passband_max_abs_db": 0.05,
                "stopband_min_attenuation_db": 70.0,
            },
        }
        formal_stem.with_suffix(".json").write_text(
            json.dumps(record, ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        formal_stem.with_suffix(".txt").write_text(
            "\n".join(f"{key}={value}" for key, value in record.items()) + "\n",
            encoding="utf-8",
        )


def _style_axes(axes) -> None:
    for axis in axes:
        axis.set_facecolor("#101b23")
        axis.tick_params(colors="#91a5b3", labelsize=8)
        axis.xaxis.label.set_color("#aebdc7")
        axis.yaxis.label.set_color("#aebdc7")
        axis.title.set_color("#e7eef3")
        for spine in axis.spines.values():
            spine.set_color("#2a3a45")
        axis.grid(True, color="#293943", alpha=0.55, linewidth=0.55)
