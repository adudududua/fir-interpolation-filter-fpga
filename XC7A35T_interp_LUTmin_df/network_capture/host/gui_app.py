#!/usr/bin/env python3
"""Industrial-style Qt dashboard for FPGA DAC24 board measurements."""
from __future__ import annotations

import faulthandler
import sys
import time
from pathlib import Path
from typing import Optional

try:
    from PySide6.QtCore import QSettings, Qt, QThread, QTimer, Slot
    from PySide6.QtGui import QColor, QCloseEvent, QFont, QPalette
    from PySide6.QtNetwork import QAbstractSocket, QNetworkInterface
    from PySide6.QtWidgets import (
        QApplication,
        QCheckBox,
        QComboBox,
        QDoubleSpinBox,
        QFileDialog,
        QFrame,
        QGridLayout,
        QGroupBox,
        QHBoxLayout,
        QLabel,
        QLineEdit,
        QMainWindow,
        QMessageBox,
        QPlainTextEdit,
        QProgressBar,
        QPushButton,
        QScrollArea,
        QSizePolicy,
        QSpinBox,
        QSplitter,
        QTabWidget,
        QVBoxLayout,
        QWidget,
    )
except ImportError as exc:
    raise SystemExit(
        "未安装 GUI 依赖。请执行：\n"
        "python -m pip install -r network_capture/host/requirements-gui.txt"
    ) from exc

import numpy as np
import matplotlib

matplotlib.rcParams["font.sans-serif"] = [
    "Microsoft YaHei",
    "SimHei",
    "DejaVu Sans",
]
matplotlib.rcParams["axes.unicode_minus"] = False
from matplotlib.backends.backend_qtagg import FigureCanvasQTAgg
from matplotlib.figure import Figure

from capture_analysis import (
    FORMAL_CAPTURE_SAMPLES,
    FORMAL_IMPULSE_AMPLITUDE,
    FrameAnalysis,
    ImpulseResponseMetrics,
    ReferenceError,
    ReferenceVector,
    analyze_frame,
    analyze_impulse_response,
    infer_reference_target,
    normalize_spectrum_to_peak,
)
from capture_worker import (
    ArtifactSaveWorker,
    CaptureWorker,
    ReceiverConfig,
)
from dac24_protocol import CaptureFrame, MODE_NAMES
from dac24_upload import (
    MAX_UPLOAD_SAMPLES,
    UploadProtocolError,
    build_upload_plan,
    generate_waveform,
    load_csv_waveform,
    load_wav_waveform,
)
from upload_worker import UploadConfig, UploadWorker
from upload_network import UploadNetworkError, require_direct_fpga_subnet


APP_NAME = "DAC24 BOARD SCOPE"
PROJECT_ROOT = Path(__file__).resolve().parents[2]
DEFAULT_REFERENCE = PROJECT_ROOT / "network_capture/results/rtl_reference_44100_128x.txt"
DEFAULT_OUTPUT = PROJECT_ROOT / "network_capture/results/board_capture_gui"

# GUI 内置信号默认保留 6.02 dB（半满量程）峰值余量。这样即使用户
# 请求 0 dBFS，插值滤波器的启动瞬态、带限重构过冲和定点舍入也不会
# 立即撞到 24 位上下限。正式冲激另有固定 A=2^22 的验收定义。
SAFE_GENERATED_PEAK_DBFS = -6.020599913279624

FORMAL_IMPULSE_WAITING_TEXT = (
    "正式冲激频响尚未触发\n\n"
    "直接点击左侧“一键正式冲激测量”。程序会自动监听、生成冲激、上传并等待回传。\n"
    "如果板上工况不同，界面会一直等你按所提示的一个 SW 键；什么时候按都可以，"
    "无需抢时间，也无需再点上传。"
)

COLORS = {
    "bg": "#071017",
    "panel": "#0d1820",
    "panel2": "#111f29",
    "border": "#273945",
    "text": "#e8f0f4",
    "muted": "#8da2af",
    "cyan": "#47d7ce",
    "blue": "#75a7ff",
    "amber": "#f4b860",
    "green": "#54d88a",
    "red": "#ff6b72",
}


STYLE_SHEET = """
QWidget {
    background: #071017;
    color: #e8f0f4;
    font-family: "Microsoft YaHei UI";
    font-size: 12px;
}
QMainWindow { background: #071017; }
QFrame#TopBar, QFrame#Panel, QGroupBox {
    background: #0d1820;
    border: 1px solid #273945;
    border-radius: 5px;
}
QGroupBox {
    margin-top: 13px;
    padding: 14px 10px 10px 10px;
    font-weight: 600;
    color: #b9c8d1;
}
QGroupBox::title {
    subcontrol-origin: margin;
    left: 10px;
    padding: 0 5px;
    color: #7f98a8;
}
QLineEdit, QComboBox, QSpinBox, QDoubleSpinBox {
    background: #111f29;
    border: 1px solid #304550;
    border-radius: 3px;
    min-height: 29px;
    padding: 0 8px;
    selection-background-color: #2d7675;
}
QLineEdit:focus, QComboBox:focus, QSpinBox:focus, QDoubleSpinBox:focus {
    border-color: #47d7ce;
}
QComboBox::drop-down { border: none; width: 22px; }
QPushButton {
    background: #172832;
    border: 1px solid #35505d;
    border-radius: 3px;
    min-height: 31px;
    padding: 0 13px;
    font-weight: 600;
}
QPushButton:hover { border-color: #47d7ce; color: #69e4dc; }
QPushButton:pressed { background: #0f2029; }
QPushButton:disabled { color: #526672; border-color: #23343e; background: #0d1820; }
QPushButton#StartButton { background: #154744; border-color: #47d7ce; color: #eafffc; }
QPushButton#StopButton { background: #4a2529; border-color: #ad4f58; }
QProgressBar {
    background: #101b23;
    border: 1px solid #2d414d;
    border-radius: 3px;
    height: 13px;
    text-align: center;
    color: #d6e3e9;
    font: 10px "Bahnschrift";
}
QProgressBar::chunk { background: #47d7ce; border-radius: 2px; }
QPlainTextEdit {
    background: #081117;
    border: 1px solid #233541;
    color: #a8bac4;
    font: 11px "Consolas";
}
QTabWidget::pane { border: 1px solid #273945; background: #0d1820; }
QTabBar::tab {
    background: #0d1820;
    border: 1px solid #273945;
    padding: 8px 16px;
    color: #8ea3af;
}
QTabBar::tab:selected { color: #47d7ce; border-bottom-color: #47d7ce; }
QCheckBox { spacing: 8px; }
QCheckBox::indicator {
    width: 15px; height: 15px; border: 1px solid #405763; border-radius: 2px;
    background: #111f29;
}
QCheckBox::indicator:checked { background: #47d7ce; border-color: #47d7ce; }
QSplitter::handle { background: #172630; }
QScrollArea {
    background: #0d1820;
    border: none;
}
QScrollBar:vertical {
    background: #0a141b;
    width: 8px;
    margin: 0;
}
QScrollBar::handle:vertical {
    background: #304550;
    border-radius: 4px;
    min-height: 28px;
}
QScrollBar::handle:vertical:hover { background: #47d7ce; }
QScrollBar::add-line:vertical, QScrollBar::sub-line:vertical { height: 0; }
QScrollBar:horizontal {
    background: #0a141b;
    height: 8px;
    margin: 0;
}
QScrollBar::handle:horizontal {
    background: #304550;
    border-radius: 4px;
    min-width: 28px;
}
QScrollBar::add-line:horizontal, QScrollBar::sub-line:horizontal { width: 0; }
QToolTip { background: #162731; color: #e8f0f4; border: 1px solid #47d7ce; }
"""


class StatusPill(QLabel):
    def __init__(self, text: str, tone: str = "muted") -> None:
        super().__init__(text)
        self.setAlignment(Qt.AlignmentFlag.AlignCenter)
        self.setMinimumHeight(31)
        self.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum)
        self.set_tone(tone)

    def set_tone(self, tone: str) -> None:
        color = COLORS.get(tone, COLORS["muted"])
        self.setStyleSheet(
            f"background:#101b23; border:1px solid {color}; color:{color};"
            "border-radius:3px; padding:3px 10px; font-weight:700;"
        )

    def set_status(self, text: str, tone: str) -> None:
        self.setText(text)
        self.set_tone(tone)


class MetricCard(QFrame):
    def __init__(self, caption: str, value: str = "—", accent: str = "muted") -> None:
        super().__init__()
        self.setObjectName("Panel")
        self.setMinimumHeight(78)
        self.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Minimum)
        layout = QVBoxLayout(self)
        layout.setContentsMargins(10, 8, 10, 9)
        layout.setSpacing(2)
        title = QLabel(caption.upper())
        title.setMinimumHeight(13)
        title.setStyleSheet("color:#718b9a; font:10px 'Bahnschrift'; letter-spacing:1px;")
        self.value = QLabel(value)
        self.value.setWordWrap(True)
        self.value.setMinimumHeight(36)
        self.value.setAlignment(
            Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter
        )
        layout.addWidget(title)
        layout.addWidget(self.value)
        self.set_value(value, accent)

    def set_value(self, value: str, accent: str = "text") -> None:
        self.value.setText(value)
        color = COLORS.get(accent, COLORS["text"])
        longest_line = max((len(line) for line in value.splitlines()), default=0)
        font_size = 13 if longest_line >= 13 else 14 if longest_line >= 10 else 16
        self.value.setStyleSheet(
            f"color:{color}; font:600 {font_size}px 'Bahnschrift', 'Microsoft YaHei UI';"
        )


class PlotCanvas(FigureCanvasQTAgg):
    def __init__(self) -> None:
        self.figure = Figure(facecolor=COLORS["panel"])
        self.axis = self.figure.add_subplot(111)
        super().__init__(self.figure)
        self.setMinimumSize(580, 390)
        self.clear("等待完整的 4096 / 16384 点板上数据帧")

    def _style(self) -> None:
        axis = self.axis
        axis.set_facecolor("#101b23")
        axis.tick_params(colors=COLORS["muted"], labelsize=9)
        axis.xaxis.label.set_color("#aebdc7")
        axis.yaxis.label.set_color("#aebdc7")
        axis.title.set_color(COLORS["text"])
        for spine in axis.spines.values():
            spine.set_color(COLORS["border"])
        axis.grid(True, color="#293943", alpha=0.60, linewidth=0.55)
        self.figure.tight_layout(pad=1.6)

    def clear(self, message: str) -> None:
        self.axis.clear()
        self._style()
        self.axis.text(
            0.5,
            0.5,
            message,
            transform=self.axis.transAxes,
            ha="center",
            va="center",
            color=COLORS["muted"],
            fontsize=12,
        )
        self.axis.set_xticks([])
        self.axis.set_yticks([])
        self.draw_idle()


class MainWindow(QMainWindow):
    def __init__(self) -> None:
        super().__init__()
        self.setWindowTitle("FPGA DAC24 · 板级数字测量台")
        self.resize(1480, 900)
        self.setMinimumSize(1180, 760)
        self.settings = QSettings("FPGA-Lab", "DAC24BoardScope")

        self.receiver_thread: Optional[QThread] = None
        self.receiver: Optional[CaptureWorker] = None
        self.save_thread: Optional[QThread] = None
        self.save_worker: Optional[ArtifactSaveWorker] = None
        self.pending_formal_save: Optional[
            tuple[CaptureFrame, FrameAnalysis, ImpulseResponseMetrics]
        ] = None
        self.saved_formal_keys: set[tuple[int, int]] = set()
        self.active_save_formal_key: Optional[tuple[int, int]] = None
        self.upload_thread: Optional[QThread] = None
        self.upload_worker: Optional[UploadWorker] = None
        self.upload_samples: Optional[np.ndarray] = None
        self.upload_note = ""
        self.last_upload_transaction_id: Optional[int] = None
        self.last_upload_confirmed = False
        self.confirmed_upload_transactions: set[int] = set()
        self.upload_impulses: dict[int, int] = {}
        self.reference: Optional[ReferenceVector] = None
        self.current_frame: Optional[CaptureFrame] = None
        self.current_analysis: Optional[FrameAnalysis] = None
        self.current_impulse_metrics: Optional[ImpulseResponseMetrics] = None
        # 最新合法DAC2包反映“此刻板上实际工况”；current_frame则只代表已经
        # 完整重组的证据帧。二者必须分开，否则固定过滤会让右侧卡片永远显示
        # 旧模式，看起来像矩阵按键失效。
        self.live_board_target: Optional[tuple[int, int]] = None
        self.live_board_descriptor: Optional[tuple[int, int, int, int, int, int]] = None
        self.last_packet_monotonic: Optional[float] = None
        self.last_peer = ""
        # A verified PASS is evidence worth preserving.  Once latched, queued
        # packet/frame signals are ignored until the user explicitly starts a
        # new capture, so a later out-of-range frame cannot overwrite it.
        self.bit_true_pass_latched = False
        # “一键正式冲激测量”是一个持续等待的 GUI 状态机。它只在收到
        # 与目标采样率/插值模式一致的完整帧后触发一次上传，因此没有按键时间窗。
        self.formal_flow_active = False
        self.formal_flow_upload_started = False
        self.formal_flow_restart_receiver = False
        self.formal_flow_target: Optional[tuple[int, int]] = None
        self.formal_result_latched = False
        # 普通波形采用“参数即意图”的自动应用状态机。编辑结束后经短暂
        # debounce，自动完成量化、监听工况确认和 BEGIN/WAVE/COMMIT。
        self.auto_apply_pending = False
        self.auto_apply_restart_receiver = False
        self.auto_apply_target: Optional[tuple[int, int]] = None
        self.auto_apply_timer = QTimer(self)
        self.auto_apply_timer.setSingleShot(True)
        self.auto_apply_timer.setInterval(900)
        self.auto_apply_timer.timeout.connect(self._apply_upload_now)
        # 普通观察时，板上矩阵键是工况的事实来源。检测到新的合法
        # family/mode 后安全重启过滤，避免界面永远停在旧模式。
        self.follow_board_pending: Optional[tuple[int, int]] = None
        self._build_ui()
        self._restore_settings()

        self.activity_timer = QTimer(self)
        self.activity_timer.timeout.connect(self._refresh_activity_age)
        self.activity_timer.start(500)

    def _build_ui(self) -> None:
        central = QWidget()
        outer = QVBoxLayout(central)
        outer.setContentsMargins(12, 10, 12, 12)
        outer.setSpacing(9)
        self.setCentralWidget(central)

        top = QFrame()
        top.setObjectName("TopBar")
        top_layout = QHBoxLayout(top)
        top_layout.setContentsMargins(15, 10, 12, 10)
        title_box = QVBoxLayout()
        title_box.setSpacing(0)
        title = QLabel(APP_NAME)
        title.setStyleSheet(
            "color:#eaf7f7; font:700 21px 'Bahnschrift'; letter-spacing:2px;"
        )
        subtitle = QLabel("XC7A35T · DAC 截位前 24 位数字节点 · UDP 4000")
        subtitle.setStyleSheet("color:#718b99; font-size:11px;")
        title_box.addWidget(title)
        title_box.addWidget(subtitle)
        top_layout.addLayout(title_box)
        top_layout.addStretch()
        self.listener_pill = StatusPill("未监听", "muted")
        self.activity_pill = StatusPill("尚未收到 FPGA 包", "muted")
        top_layout.addWidget(self.listener_pill)
        top_layout.addWidget(self.activity_pill)
        outer.addWidget(top)

        splitter = QSplitter(Qt.Orientation.Horizontal)
        splitter.setChildrenCollapsible(False)
        splitter.addWidget(self._build_control_panel())
        splitter.addWidget(self._build_plot_panel())
        splitter.addWidget(self._build_measurement_panel())
        splitter.setStretchFactor(0, 0)
        splitter.setStretchFactor(1, 1)
        splitter.setStretchFactor(2, 0)
        splitter.setSizes([280, 850, 285])
        outer.addWidget(splitter, 1)

        log_panel = QFrame()
        log_panel.setObjectName("Panel")
        log_layout = QVBoxLayout(log_panel)
        log_layout.setContentsMargins(9, 7, 9, 8)
        log_layout.setSpacing(5)
        log_header = QHBoxLayout()
        log_title = QLabel("EVENT TRACE")
        log_title.setStyleSheet("color:#718b99; font:10px 'Bahnschrift'; letter-spacing:1px;")
        log_header.addWidget(log_title)
        log_header.addStretch()
        clear_button = QPushButton("清空")
        clear_button.setMaximumWidth(70)
        clear_button.clicked.connect(lambda: self.log.clear())
        log_header.addWidget(clear_button)
        self.log = QPlainTextEdit()
        self.log.setReadOnly(True)
        self.log.setMaximumHeight(120)
        self.log.document().setMaximumBlockCount(500)
        log_layout.addLayout(log_header)
        log_layout.addWidget(self.log)
        outer.addWidget(log_panel)

    def _build_control_panel(self) -> QWidget:
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.Shape.NoFrame)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        scroll.setMinimumWidth(280)
        scroll.setMaximumWidth(350)
        panel = QFrame()
        panel.setObjectName("Panel")
        panel.setMinimumWidth(260)
        layout = QVBoxLayout(panel)
        layout.setContentsMargins(10, 8, 10, 10)
        layout.setSpacing(7)

        network = QGroupBox("监听接口")
        network.setMinimumHeight(145)
        network.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        self.network_group = network
        grid = QGridLayout(network)
        grid.setVerticalSpacing(6)
        grid.setRowMinimumHeight(0, 31)
        grid.setRowMinimumHeight(1, 31)
        grid.addWidget(QLabel("本机 IPv4"), 0, 0)
        self.bind_combo = QComboBox()
        self.bind_combo.setEditable(True)
        self.bind_combo.addItem("0.0.0.0  ·  全部网卡", "0.0.0.0")
        for address in self._local_ipv4_addresses():
            self.bind_combo.addItem(address, address)
        grid.addWidget(self.bind_combo, 0, 1)
        grid.addWidget(QLabel("UDP 端口"), 1, 0)
        self.port_spin = QSpinBox()
        self.port_spin.setRange(1, 65535)
        self.port_spin.setValue(4000)
        grid.addWidget(self.port_spin, 1, 1)
        self.adapter_hint = QLabel(
            "监听成功只表示端口已绑定；收到合法 DAC24 包后才显示数据活动。"
        )
        self.adapter_hint.setWordWrap(True)
        self.adapter_hint.setMinimumHeight(34)
        self.adapter_hint.setAlignment(
            Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignTop
        )
        self.adapter_hint.setStyleSheet("color:#718b99; font-size:10px;")
        grid.addWidget(self.adapter_hint, 2, 0, 1, 2)
        layout.addWidget(network)

        target = QGroupBox("目标帧过滤")
        target_grid = QGridLayout(target)
        target_grid.addWidget(QLabel("采样率族"), 0, 0)
        self.family_combo = QComboBox()
        self.family_combo.addItem("44.1 kHz", 0)
        self.family_combo.addItem("48 kHz", 1)
        self.family_combo.addItem("任意（仅观察）", None)
        target_grid.addWidget(self.family_combo, 0, 1)
        target_grid.addWidget(QLabel("输出分支"), 1, 0)
        self.mode_combo = QComboBox()
        for code in (3, 2, 1, 0):
            self.mode_combo.addItem(MODE_NAMES[code], code)
        self.mode_combo.addItem("任意（仅观察）", None)
        target_grid.addWidget(self.mode_combo, 1, 1)
        self.follow_board_check = QCheckBox("自动跟随板上 SW 工况（推荐）")
        self.follow_board_check.setChecked(True)
        self.follow_board_check.setToolTip(
            "普通观察时，检测到板上切换到新的采样率/倍率后自动重启过滤；"
            "正式冲激和待执行上传目标不会被自动改写。"
        )
        target_grid.addWidget(self.follow_board_check, 2, 0, 1, 2)
        layout.addWidget(target)

        verify = QGroupBox("RTL 逐位验证")
        verify.setMinimumHeight(175)
        verify.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        self.verify_group = verify
        verify_layout = QVBoxLayout(verify)
        verify_layout.setSpacing(6)
        self.verify_check = QCheckBox("启用 bit-true 比较")
        self.verify_check.setChecked(True)
        self.verify_check.toggled.connect(self._sync_reference_controls)
        verify_layout.addWidget(self.verify_check)
        self.auto_lock_pass_check = QCheckBox(
            "首次 PASS 后锁定结果并自动停止监听（推荐）"
        )
        self.auto_lock_pass_check.setChecked(True)
        self.auto_lock_pass_check.setToolTip(
            "逐位验证第一次完全一致后定格该帧，并安全请求接收线程停止；无需抢按“停止”。"
        )
        verify_layout.addWidget(self.auto_lock_pass_check)
        ref_row = QHBoxLayout()
        self.reference_edit = QLineEdit(str(DEFAULT_REFERENCE))
        self.reference_edit.setToolTip(str(DEFAULT_REFERENCE))
        browse_ref = QPushButton("…")
        browse_ref.setMaximumWidth(35)
        browse_ref.clicked.connect(self._browse_reference)
        self.browse_ref_button = browse_ref
        ref_row.addWidget(self.reference_edit)
        ref_row.addWidget(browse_ref)
        verify_layout.addLayout(ref_row)
        self.reference_info = QLabel(
            "参考会在开始监听时一次加载。推荐保持自动锁定：首次逐位一致后，"
            "界面会定格并停止监听；再次点击“开始监听”才会解锁。"
        )
        self.reference_info.setWordWrap(True)
        self.reference_info.setMinimumHeight(48)
        self.reference_info.setAlignment(
            Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignTop
        )
        self.reference_info.setStyleSheet("color:#718b99; font-size:10px;")
        verify_layout.addWidget(self.reference_info)
        layout.addWidget(verify)

        output = QGroupBox("结果归档")
        output.setMinimumHeight(130)
        output.setSizePolicy(QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed)
        self.output_group = output
        output_layout = QVBoxLayout(output)
        output_layout.setSpacing(6)
        output_row = QHBoxLayout()
        self.output_edit = QLineEdit(str(DEFAULT_OUTPUT))
        browse_output = QPushButton("…")
        browse_output.setMaximumWidth(35)
        browse_output.clicked.connect(self._browse_output)
        output_row.addWidget(self.output_edit)
        output_row.addWidget(browse_output)
        output_layout.addLayout(output_row)
        self.auto_save_check = QCheckBox("完整帧自动保存 CSV / NPY / PNG")
        output_layout.addWidget(self.auto_save_check)
        self.save_button = QPushButton("保存当前帧")
        self.save_button.setEnabled(False)
        self.save_button.clicked.connect(self._save_current_frame)
        output_layout.addWidget(self.save_button)
        layout.addWidget(output)

        button_row = QHBoxLayout()
        self.start_button = QPushButton("开始监听")
        self.start_button.setObjectName("StartButton")
        self.start_button.clicked.connect(self.start_capture)
        self.stop_button = QPushButton("停止")
        self.stop_button.setObjectName("StopButton")
        self.stop_button.setEnabled(False)
        self.stop_button.clicked.connect(self.stop_capture)
        button_row.addWidget(self.start_button, 2)
        button_row.addWidget(self.stop_button, 1)
        layout.addLayout(button_row)

        self.formal_measure_button = QPushButton("一键正式冲激测量")
        self.formal_measure_button.setObjectName("StartButton")
        self.formal_measure_button.setToolTip(
            "自动监听、等待板上目标工况、生成并上传冲激；无需抢按键或手动点 COMMIT"
        )
        self.formal_measure_button.clicked.connect(self._start_formal_impulse_flow)
        layout.addWidget(self.formal_measure_button)

        self.formal_cancel_button = QPushButton("取消一键测量")
        self.formal_cancel_button.setObjectName("StopButton")
        self.formal_cancel_button.setEnabled(False)
        self.formal_cancel_button.clicked.connect(self._cancel_formal_impulse_flow)
        layout.addWidget(self.formal_cancel_button)

        self.formal_flow_status = QLabel(
            "一键测量会自动完成监听 → 等待工况 → 冲激上传 → 正式频响。"
        )
        self.formal_flow_status.setWordWrap(True)
        self.formal_flow_status.setStyleSheet(
            "background:#10232a; border:1px solid #47d7ce; border-radius:3px; "
            "color:#a9c4cd; padding:8px;"
        )
        layout.addWidget(self.formal_flow_status)

        upload_hint = QPushButton("波形源 / 上传…")
        upload_hint.clicked.connect(lambda: self.workspace_tabs.setCurrentWidget(self.upload_page))
        layout.addWidget(upload_hint)
        layout.addStretch()
        panel.setMinimumHeight(panel.sizeHint().height())
        scroll.setWidget(panel)
        self.control_scroll = scroll
        return scroll

    def _build_plot_panel(self) -> QWidget:
        panel = QFrame()
        panel.setObjectName("Panel")
        layout = QVBoxLayout(panel)
        layout.setContentsMargins(7, 7, 7, 7)
        self.workspace_tabs = QTabWidget()
        measurement_page = QWidget()
        measurement_layout = QVBoxLayout(measurement_page)
        measurement_layout.setContentsMargins(0, 0, 0, 0)
        self.plot_tabs = QTabWidget()
        self.time_canvas = PlotCanvas()
        self.full_fft_canvas = PlotCanvas()
        self.local_fft_canvas = PlotCanvas()
        self.impulse_canvas = PlotCanvas()
        self.impulse_canvas.clear(FORMAL_IMPULSE_WAITING_TEXT)
        self.plot_tabs.addTab(self.time_canvas, "时域 · 24 BIT")
        self.plot_tabs.addTab(self.full_fft_canvas, "全频 FFT · 归一化")
        self.plot_tabs.addTab(self.local_fft_canvas, "0–50 kHz · 归一化")
        self.plot_tabs.addTab(self.impulse_canvas, "正式频响 H(f)")
        measurement_layout.addWidget(self.plot_tabs)
        self.preview_notice = QLabel(
            "前两张 FFT 预览采用 Hann 窗，并将本帧最高谱线归一化为 0 dBr；"
            "这是相对输出谱，不是滤波器增益。正式指标请看“正式频响 H(f)”页："
            "该页不加窗，并按 A·L 归一化，通带应接近 0 dB。"
        )
        self.preview_notice.setWordWrap(True)
        self.preview_notice.setStyleSheet(
            "background:#332815; border:1px solid #74592c; color:#f4b860; "
            "padding:7px 10px; border-radius:3px;"
        )
        measurement_layout.addWidget(self.preview_notice)
        self.upload_page = self._build_upload_page()
        self.workspace_tabs.addTab(measurement_page, "板上测量")
        self.workspace_tabs.addTab(self.upload_page, "波形源 / 上传")
        layout.addWidget(self.workspace_tabs)
        return panel

    def _build_upload_page(self) -> QWidget:
        page = QScrollArea()
        page.setWidgetResizable(True)
        page.setFrameShape(QFrame.Shape.NoFrame)
        page.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAsNeeded)
        content = QWidget()
        content.setMinimumWidth(650)
        outer = QVBoxLayout(content)
        outer.setContentsMargins(12, 10, 12, 12)
        outer.setSpacing(9)

        warning = QLabel(
            "上传的是 44.1/48 kHz 的 1x 输入样本，不是插值后的 DAC 输出。"
            "先修改好频率、幅度等参数，再点一次“输入到板卡”；程序会自动量化、上传并等待 ACK。"
            "只有收到板端 ACK 才会显示“已确认”；无 ACK 模式只证明本机完成 UDP sendto。"
            "板端双 bank 每次最多 16384 点。"
        )
        warning.setWordWrap(True)
        warning.setStyleSheet(
            "background:#332815; border:1px solid #74592c; color:#f4b860; "
            "padding:9px 11px; border-radius:3px;"
        )
        outer.addWidget(warning)

        row = QHBoxLayout()
        row.setSpacing(10)
        source_group = QGroupBox("1x 波形源")
        source_group.setMinimumHeight(455)
        source_group.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed
        )
        source_grid = QGridLayout(source_group)
        self.upload_source_combo = QComboBox()
        for label, code in (
            ("单音正弦", "sine"),
            ("双音", "dual_tone"),
            ("冲激", "impulse"),
            ("方波", "square"),
            ("白噪声（固定 seed）", "white_noise"),
            ("CSV / TXT 导入", "csv"),
            ("PCM WAV 导入", "wav"),
        ):
            self.upload_source_combo.addItem(label, code)
        self.upload_source_combo.currentIndexChanged.connect(self._sync_upload_source_controls)
        source_grid.addWidget(QLabel("源类型"), 0, 0)
        source_grid.addWidget(self.upload_source_combo, 0, 1, 1, 2)

        self.upload_family_combo = QComboBox()
        self.upload_family_combo.addItem("44.1 kHz", 0)
        self.upload_family_combo.addItem("48 kHz", 1)
        source_grid.addWidget(QLabel("输入采样率"), 1, 0)
        source_grid.addWidget(self.upload_family_combo, 1, 1, 1, 2)

        self.upload_count_spin = QSpinBox()
        self.upload_count_spin.setRange(1, MAX_UPLOAD_SAMPLES)
        self.upload_count_spin.setValue(4096)
        source_grid.addWidget(QLabel("生成样本数"), 2, 0)
        source_grid.addWidget(self.upload_count_spin, 2, 1, 1, 2)

        self.upload_amp_spin = QDoubleSpinBox()
        self.upload_amp_spin.setRange(-180.0, 0.0)
        self.upload_amp_spin.setDecimals(2)
        self.upload_amp_spin.setValue(-1.0)
        self.upload_amp_spin.setSuffix(" dBFS")
        source_grid.addWidget(QLabel("峰值幅度"), 3, 0)
        source_grid.addWidget(self.upload_amp_spin, 3, 1, 1, 2)

        self.upload_f1_spin = QDoubleSpinBox()
        self.upload_f1_spin.setRange(0.001, 23999.999)
        self.upload_f1_spin.setDecimals(3)
        self.upload_f1_spin.setValue(997.0)
        self.upload_f1_spin.setSuffix(" Hz")
        self.upload_f2_spin = QDoubleSpinBox()
        self.upload_f2_spin.setRange(0.001, 23999.999)
        self.upload_f2_spin.setDecimals(3)
        self.upload_f2_spin.setValue(15000.0)
        self.upload_f2_spin.setSuffix(" Hz")
        source_grid.addWidget(QLabel("频率 1"), 4, 0)
        source_grid.addWidget(self.upload_f1_spin, 4, 1, 1, 2)
        source_grid.addWidget(QLabel("频率 2"), 5, 0)
        source_grid.addWidget(self.upload_f2_spin, 5, 1, 1, 2)

        self.upload_seed_spin = QSpinBox()
        self.upload_seed_spin.setRange(0, 2_147_483_647)
        self.upload_seed_spin.setValue(20260813)
        source_grid.addWidget(QLabel("噪声 seed"), 6, 0)
        source_grid.addWidget(self.upload_seed_spin, 6, 1, 1, 2)

        self.upload_file_edit = QLineEdit()
        self.upload_file_button = QPushButton("选择…")
        self.upload_file_button.clicked.connect(self._browse_upload_file)
        source_grid.addWidget(QLabel("导入文件"), 7, 0)
        source_grid.addWidget(self.upload_file_edit, 7, 1)
        source_grid.addWidget(self.upload_file_button, 7, 2)
        self.upload_csv_normalised = QCheckBox("CSV 数值按 [-1,1] 归一化解释")
        source_grid.addWidget(self.upload_csv_normalised, 8, 1, 1, 2)

        self.upload_headroom_check = QCheckBox(
            "自动防削顶（内置信号峰值最多为 −6.02 dBFS）"
        )
        self.upload_headroom_check.setChecked(True)
        self.upload_headroom_check.setToolTip(
            "默认启用：只限制 GUI 生成的正弦、双音、方波和白噪声；"
            "不会缩放导入文件，也不会改变正式冲激 A=2^22。"
        )
        source_grid.addWidget(self.upload_headroom_check, 9, 0, 1, 3)

        self.upload_auto_apply_check = QCheckBox(
            "参数修改后自动输入到 FPGA（可选，默认关闭）"
        )
        self.upload_auto_apply_check.setChecked(False)
        self.upload_auto_apply_check.setToolTip(
            "编辑完成后自动量化并执行 BEGIN/WAVE/COMMIT；"
            "只切换采样率或倍率时，会等待所提示的 SW 键后自动继续。"
        )
        source_grid.addWidget(self.upload_auto_apply_check, 10, 0, 1, 3)

        self.prepare_upload_button = QPushButton("仅生成预览（手动/调试）")
        self.prepare_upload_button.clicked.connect(self._prepare_upload_waveform)
        source_grid.addWidget(self.prepare_upload_button, 11, 0, 1, 3)
        row.addWidget(source_group, 1)

        transport_group = QGroupBox("UDP 4001 事务")
        transport_group.setMinimumHeight(385)
        transport_group.setSizePolicy(
            QSizePolicy.Policy.Expanding, QSizePolicy.Policy.Fixed
        )
        self.transport_group = transport_group
        transport_grid = QGridLayout(transport_group)
        transport_grid.setVerticalSpacing(5)
        self.upload_target_edit = QLineEdit("192.168.1.10")
        self.upload_port_spin = QSpinBox()
        self.upload_port_spin.setRange(1, 65535)
        self.upload_port_spin.setValue(4001)
        transport_grid.addWidget(QLabel("FPGA IPv4"), 0, 0)
        transport_grid.addWidget(self.upload_target_edit, 0, 1)
        transport_grid.addWidget(QLabel("UDP 端口"), 1, 0)
        transport_grid.addWidget(self.upload_port_spin, 1, 1)

        self.upload_mode_combo = QComboBox()
        for code in (0, 1, 2, 3):
            self.upload_mode_combo.addItem(MODE_NAMES[code], code)
        self.upload_mode_combo.setCurrentIndex(
            self.upload_mode_combo.findData(self.mode_combo.currentData())
        )
        transport_grid.addWidget(QLabel("板端输出模式"), 2, 0)
        transport_grid.addWidget(self.upload_mode_combo, 2, 1)

        self.upload_loop_check = QCheckBox("循环播放")
        self.upload_ack_check = QCheckBox("必须收到板端 ACK（推荐）")
        self.upload_ack_check.setChecked(True)
        transport_grid.addWidget(self.upload_loop_check, 3, 0, 1, 2)
        transport_grid.addWidget(self.upload_ack_check, 4, 0, 1, 2)

        self.upload_board_status = QLabel()
        self.upload_board_status.setWordWrap(True)
        self.upload_board_status.setMinimumHeight(47)
        self.upload_board_status.setAlignment(
            Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter
        )
        transport_grid.addWidget(self.upload_board_status, 5, 0, 1, 2)

        self.upload_progress = QProgressBar()
        self.upload_progress.setRange(0, 1)
        self.upload_progress.setValue(0)
        self.upload_status = StatusPill("可继续修改参数 · 尚未输入板卡", "muted")
        self.upload_detail = QLabel(
            "确认参数后只点一次“输入到板卡”；协议步骤由程序自动完成。"
        )
        self.upload_detail.setWordWrap(True)
        self.upload_detail.setMinimumHeight(32)
        self.upload_detail.setAlignment(
            Qt.AlignmentFlag.AlignLeft | Qt.AlignmentFlag.AlignVCenter
        )
        self.upload_detail.setStyleSheet("color:#718b99; font:11px 'Consolas';")
        transport_grid.addWidget(self.upload_status, 6, 0, 1, 2)
        transport_grid.addWidget(self.upload_progress, 7, 0, 1, 2)
        transport_grid.addWidget(self.upload_detail, 8, 0, 1, 2)

        self.upload_send_button = QPushButton("输入到板卡（自动生成并上传）")
        self.upload_send_button.setObjectName("StartButton")
        self.upload_send_button.setEnabled(True)
        self.upload_send_button.clicked.connect(self._apply_upload_now)
        transport_grid.addWidget(self.upload_send_button, 9, 0, 1, 2)
        row.addWidget(transport_group, 1)
        outer.addLayout(row)

        self.upload_preview = PlotCanvas()
        self.upload_preview.setMinimumHeight(200)
        outer.addWidget(self.upload_preview, 1)
        self._sync_upload_source_controls()
        self.upload_source_combo.currentIndexChanged.connect(self._mark_upload_dirty)
        self.upload_family_combo.currentIndexChanged.connect(self._mark_upload_dirty)
        self.upload_mode_combo.currentIndexChanged.connect(self._mark_upload_dirty)
        self.upload_family_combo.currentIndexChanged.connect(
            self._sync_capture_filter_from_upload
        )
        self.upload_mode_combo.currentIndexChanged.connect(
            self._sync_capture_filter_from_upload
        )
        self.upload_count_spin.valueChanged.connect(self._mark_upload_dirty)
        self.upload_amp_spin.valueChanged.connect(self._mark_upload_dirty)
        self.upload_f1_spin.valueChanged.connect(self._mark_upload_dirty)
        self.upload_f2_spin.valueChanged.connect(self._mark_upload_dirty)
        self.upload_seed_spin.valueChanged.connect(self._mark_upload_dirty)
        self.upload_file_edit.textChanged.connect(self._mark_upload_dirty)
        self.upload_csv_normalised.toggled.connect(self._mark_upload_dirty)
        self.upload_headroom_check.toggled.connect(self._mark_upload_dirty)
        # 只有真实的用户编辑才触发自动应用；程序内部同步family/mode或
        # 更新安全幅度不会意外发起网络事务。
        for spin in (
            self.upload_count_spin,
            self.upload_amp_spin,
            self.upload_f1_spin,
            self.upload_f2_spin,
            self.upload_seed_spin,
        ):
            spin.lineEdit().textEdited.connect(self._schedule_auto_apply)
        self.upload_source_combo.activated.connect(self._schedule_auto_apply)
        self.upload_family_combo.activated.connect(self._schedule_auto_apply)
        self.upload_mode_combo.activated.connect(self._schedule_auto_apply)
        self.upload_loop_check.clicked.connect(self._schedule_auto_apply)
        self.upload_ack_check.clicked.connect(self._schedule_auto_apply)
        self.upload_csv_normalised.clicked.connect(self._schedule_auto_apply)
        self.upload_headroom_check.clicked.connect(self._schedule_auto_apply)
        self.upload_file_edit.editingFinished.connect(self._schedule_auto_apply)
        self.upload_auto_apply_check.clicked.connect(self._schedule_auto_apply)
        self._refresh_upload_board_status()
        content.setMinimumHeight(content.sizeHint().height())
        page.setWidget(content)
        self.upload_scroll = page
        return page

    def _build_measurement_panel(self) -> QWidget:
        scroll = QScrollArea()
        scroll.setWidgetResizable(True)
        scroll.setFrameShape(QFrame.Shape.NoFrame)
        scroll.setHorizontalScrollBarPolicy(Qt.ScrollBarPolicy.ScrollBarAlwaysOff)
        scroll.setMinimumWidth(280)
        scroll.setMaximumWidth(350)
        panel = QFrame()
        panel.setObjectName("Panel")
        panel.setMinimumWidth(260)
        layout = QVBoxLayout(panel)
        layout.setContentsMargins(10, 8, 10, 10)
        heading = QLabel("FRAME TELEMETRY")
        heading.setStyleSheet(
            "color:#718b99; font:10px 'Bahnschrift'; letter-spacing:1.5px;"
        )
        layout.addWidget(heading)

        cards = QGridLayout()
        cards.setSpacing(7)
        self.frame_card = MetricCard("Frame ID")
        self.index_card = MetricCard("Start index")
        self.family_card = MetricCard("Family / mode")
        self.rate_card = MetricCard("Output rate")
        self.source_card = MetricCard("Input source", "ROM / legacy")
        self.txid_card = MetricCard("Input transaction", "—")
        cards.addWidget(self.frame_card, 0, 0)
        cards.addWidget(self.index_card, 0, 1)
        cards.addWidget(self.family_card, 1, 0)
        cards.addWidget(self.rate_card, 1, 1)
        cards.addWidget(self.source_card, 2, 0)
        cards.addWidget(self.txid_card, 2, 1)
        layout.addLayout(cards)

        progress_label = QLabel("网络包完整度")
        progress_label.setStyleSheet("color:#8da2af;")
        self.packet_progress = QProgressBar()
        self.packet_progress.setRange(0, 64)
        self.packet_progress.setValue(0)
        self.packet_detail = QLabel("0 / 16 或 64 · 未收到")
        self.packet_detail.setStyleSheet("color:#718b99; font:11px 'Bahnschrift';")
        layout.addWidget(progress_label)
        layout.addWidget(self.packet_progress)
        layout.addWidget(self.packet_detail)

        bit_group = QGroupBox("BIT-TRUE RESULT")
        bit_layout = QVBoxLayout(bit_group)
        self.bit_status = StatusPill("等待目标帧", "muted")
        self.mismatch_card = MetricCard("Mismatch", "—")
        self.error_card = MetricCard("Max abs error", "—")
        self.compare_range = QLabel("参考区间：—")
        self.compare_range.setStyleSheet("color:#718b99; font:11px 'Consolas';")
        self.compare_range.setWordWrap(True)
        bit_layout.addWidget(self.bit_status)
        bit_layout.addWidget(self.mismatch_card)
        bit_layout.addWidget(self.error_card)
        bit_layout.addWidget(self.compare_range)
        layout.addWidget(bit_group)

        spectrum_group = QGroupBox("频谱预览")
        spectrum_layout = QVBoxLayout(spectrum_group)
        self.resolution_label = QLabel("FFT 分辨率：—")
        self.impulse_result = QLabel(
            "正式冲激频响：等待 GUI 上传“冲激”，并收到板端 ACK 与匹配 txid 的完整回传。"
            "普通 ROM 帧不会触发本项。"
        )
        self.impulse_result.setWordWrap(True)
        self.impulse_result.setStyleSheet("color:#8da2af;")
        self.resolution_label.setStyleSheet("color:#9eb2bd;")
        self.continuity_label = QLabel("单帧 4096/16384 点 · 帧间不保证连续")
        self.continuity_label.setWordWrap(True)
        self.continuity_label.setStyleSheet("color:#f4b860;")
        spectrum_layout.addWidget(self.resolution_label)
        spectrum_layout.addWidget(self.continuity_label)
        spectrum_layout.addWidget(self.impulse_result)
        layout.addWidget(spectrum_group)

        instruction = QLabel(
            "ROM 逐位比较若提示索引超出参考范围：推荐在 Vivado 重新下载位流后"
            "捕获首个目标帧，或使用覆盖该索引的更长 RTL 参考；不要依赖 SW8→SW4 "
            "重置索引。正式通带/阻带测量直接点击左侧“一键正式冲激测量”。"
        )
        instruction.setWordWrap(True)
        instruction.setStyleSheet(
            "background:#10232a; border:1px solid #47d7ce; border-radius:3px; "
            "color:#a9c4cd; padding:9px;"
        )
        self.measurement_instruction = instruction
        layout.addWidget(instruction)
        layout.addStretch()
        panel.setMinimumHeight(panel.sizeHint().height())
        scroll.setWidget(panel)
        self.measurement_scroll = scroll
        return scroll

    @staticmethod
    def _local_ipv4_addresses() -> list[str]:
        values = []
        for address in QNetworkInterface.allAddresses():
            if (
                address.protocol() == QAbstractSocket.NetworkLayerProtocol.IPv4Protocol
                and not address.isLoopback()
            ):
                value = address.toString()
                if value not in values:
                    values.append(value)
        return values

    def _restore_settings(self) -> None:
        bind = str(self.settings.value("bind", "0.0.0.0"))
        match = self.bind_combo.findData(bind)
        if match >= 0:
            self.bind_combo.setCurrentIndex(match)
        else:
            self.bind_combo.setEditText(bind)
        self.port_spin.setValue(int(self.settings.value("port", 4000)))
        self.reference_edit.setText(
            str(self.settings.value("reference", str(DEFAULT_REFERENCE)))
        )
        self.output_edit.setText(str(self.settings.value("output", str(DEFAULT_OUTPUT))))
        self.auto_lock_pass_check.setChecked(
            self.settings.value("auto_lock_first_pass", True, type=bool)
        )
        self.upload_auto_apply_check.setChecked(
            self.settings.value("auto_apply_upload_on_edit_v2", False, type=bool)
        )
        self.follow_board_check.setChecked(
            self.settings.value("follow_board_switch_v1", True, type=bool)
        )

    def _save_settings(self) -> None:
        self.settings.setValue("bind", self._bind_address())
        self.settings.setValue("port", self.port_spin.value())
        self.settings.setValue("reference", self.reference_edit.text().strip())
        self.settings.setValue("output", self.output_edit.text().strip())
        self.settings.setValue(
            "auto_lock_first_pass", self.auto_lock_pass_check.isChecked()
        )
        self.settings.setValue(
            "auto_apply_upload_on_edit_v2", self.upload_auto_apply_check.isChecked()
        )
        self.settings.setValue(
            "follow_board_switch_v1", self.follow_board_check.isChecked()
        )

    def _bind_address(self) -> str:
        data = self.bind_combo.currentData()
        if data is not None and self.bind_combo.currentText().startswith(str(data)):
            return str(data)
        text = self.bind_combo.currentText().split("·", 1)[0].strip()
        return text or "0.0.0.0"

    def _sync_reference_controls(self, enabled: bool) -> None:
        self.reference_edit.setEnabled(enabled)
        self.browse_ref_button.setEnabled(enabled)
        if not enabled:
            self.bit_status.set_status("未启用参考比较", "muted")

    def _browse_reference(self) -> None:
        path, _ = QFileDialog.getOpenFileName(
            self,
            "选择 RTL 参考向量",
            self.reference_edit.text(),
            "参考向量 (*.txt *.csv *.npy);;全部文件 (*)",
        )
        if path:
            self.reference_edit.setText(path)

    def _browse_output(self) -> None:
        path = QFileDialog.getExistingDirectory(
            self, "选择结果目录", self.output_edit.text()
        )
        if path:
            self.output_edit.setText(path)

    def _sync_upload_source_controls(self) -> None:
        source = self.upload_source_combo.currentData()
        generated = source not in ("csv", "wav")
        imported = not generated
        formal_impulse = source == "impulse"
        if formal_impulse:
            # A formal impulse should follow the board state that the receiver
            # has actually observed.  This avoids silently switching the upload
            # description to a different family/mode when the user merely
            # chooses the impulse source.
            self._sync_upload_target_from_observed_board()
            if int(self.upload_mode_combo.currentData()) == 0:
                # 1x has no interpolation image band in which to verify the
                # competition stop-band requirement.  Pick the usual demo
                # target and let the live status name the one SW key needed.
                self.upload_mode_combo.setCurrentIndex(
                    self.upload_mode_combo.findData(3)
                )
            self.upload_count_spin.setValue(FORMAL_CAPTURE_SAMPLES)
            self.upload_amp_spin.setValue(-6.02)
            self.upload_amp_spin.setToolTip(
                "正式冲激不用显示值反算；上传码值固定为 4194304 (2^22)"
            )
            self.upload_loop_check.setChecked(False)
            self.upload_ack_check.setChecked(True)
            self.upload_mode_combo.setToolTip(
                "正式冲激用于验证插值滤波器，支持 4x、8x、128x；若板上当前为 1x，"
                "界面会自动选 128x 并明确提示应按的 SW 键。"
            )
        else:
            self.upload_amp_spin.setToolTip("")
            self.upload_mode_combo.setToolTip("")
        self.upload_count_spin.setEnabled(generated and not formal_impulse)
        self.upload_amp_spin.setEnabled(generated and not formal_impulse)
        self.upload_f1_spin.setEnabled(source in ("sine", "dual_tone", "square"))
        self.upload_f2_spin.setEnabled(source == "dual_tone")
        self.upload_seed_spin.setEnabled(source == "white_noise")
        self.upload_file_edit.setEnabled(imported)
        self.upload_file_button.setEnabled(imported)
        self.upload_csv_normalised.setEnabled(source == "csv")
        self.upload_headroom_check.setEnabled(generated and not formal_impulse)
        self.upload_auto_apply_check.setEnabled(not formal_impulse)
        self.upload_loop_check.setEnabled(not formal_impulse)
        self.upload_ack_check.setEnabled(not formal_impulse)
        self._refresh_upload_board_status()

    @staticmethod
    def _board_key(family: int, mode: int) -> int:
        """Return the only physical SW key for one family/mode pair."""
        return 1 + int(mode) + (4 if int(family) else 0)

    def _observed_board_target(self) -> Optional[tuple[int, int]]:
        """Return the latest complete board frame's actual family/mode."""
        if self.current_frame is None:
            return None
        return int(self.current_frame.family_48k), int(self.current_frame.mode)

    def _displayed_board_target(self) -> Optional[tuple[int, int]]:
        """Return the latest live packet target, falling back to a full frame."""
        return self.live_board_target or self._observed_board_target()

    def _set_formal_flow_stage(self, text: str, tone: str = "cyan") -> None:
        colors = {
            "cyan": ("#10232a", "#47d7ce", "#bceceb"),
            "amber": ("#332815", "#f4b860", "#f7d79b"),
            "green": ("#102a23", "#54d88a", "#b9f2d0"),
            "red": ("#32191b", "#ff6b72", "#ffc4c7"),
            "muted": ("#111f29", "#718b99", "#a9c4cd"),
        }
        background, border, foreground = colors[tone]
        self.formal_flow_status.setText(text)
        self.formal_flow_status.setStyleSheet(
            f"background:{background}; border:1px solid {border}; border-radius:3px; "
            f"color:{foreground}; padding:8px;"
        )

    def _formal_target_from_context(self) -> tuple[int, int]:
        """Use the waveform/upload target selected by the user.

        The running UDP receiver may still be filtering an older family/mode.
        Treating that stale filter as the formal target made a user-selected
        48 kHz measurement wait forever for 44.1 kHz frames.  The formal flow
        already knows how to restart the receiver safely, so the visible
        upload controls are the single source of intent here.
        """
        family = int(self.upload_family_combo.currentData())
        mode = int(self.upload_mode_combo.currentData())
        # 1x has no interpolation image band to assess.  Keep the observed
        # sample-rate family and choose the board's 128x demonstration branch.
        if mode == 0:
            mode = 3
        return family, mode

    @Slot()
    def _start_formal_impulse_flow(self) -> None:
        """Start the no-time-window formal impulse workflow."""
        if self.formal_flow_active or self.upload_thread is not None:
            return
        family, mode = self._formal_target_from_context()
        wanted = f"{48000 if family else 44100} Hz / {MODE_NAMES[mode]}"
        self.formal_flow_active = True
        self.formal_flow_upload_started = False
        self.formal_flow_restart_receiver = False
        self.formal_flow_target = (family, mode)
        self.formal_result_latched = False
        self.formal_measure_button.setEnabled(False)
        self.formal_cancel_button.setEnabled(True)

        # Configure every formal-measurement gate centrally.  Users no longer
        # have to visit the upload page or remember five separate controls.
        self.upload_source_combo.setCurrentIndex(
            self.upload_source_combo.findData("impulse")
        )
        self.upload_family_combo.setCurrentIndex(
            self.upload_family_combo.findData(family)
        )
        self.upload_mode_combo.setCurrentIndex(
            self.upload_mode_combo.findData(mode)
        )
        self.upload_loop_check.setChecked(False)
        self.upload_ack_check.setChecked(True)
        self.family_combo.setCurrentIndex(self.family_combo.findData(family))
        self.mode_combo.setCurrentIndex(self.mode_combo.findData(mode))
        self.workspace_tabs.setCurrentIndex(0)
        self.plot_tabs.setCurrentWidget(self.impulse_canvas)
        self.impulse_canvas.clear("一键正式冲激测量：正在准备监听…")

        receiver_target = (
            (self.receiver.config.expected_family_48k, self.receiver.config.expected_mode)
            if self.receiver is not None
            else None
        )
        if self.receiver_thread is None:
            self._set_formal_flow_stage(
                f"步骤 1/4：正在为 {wanted} 自动开始 UDP4000 监听…"
            )
            self.start_capture()
            # start_capture may reject a bad bind/reference before creating a worker.
            if self.receiver_thread is None:
                self._finish_formal_flow(
                    "未能启动监听，请根据弹窗修正网络或参考文件后重试。", "red"
                )
            return
        if receiver_target != (family, mode):
            self.formal_flow_restart_receiver = True
            self._set_formal_flow_stage(
                f"步骤 1/4：正在把监听目标切换为 {wanted}…", "amber"
            )
            self.stop_capture()
            return
        self._advance_formal_impulse_flow()

    @Slot()
    def _cancel_formal_impulse_flow(self) -> None:
        if not self.formal_flow_active:
            return
        sending = self.upload_thread is not None
        self.formal_flow_active = False
        self.formal_flow_restart_receiver = False
        self.formal_flow_target = None
        self.formal_measure_button.setEnabled(self.upload_thread is None)
        self.formal_cancel_button.setEnabled(False)
        self._set_formal_flow_stage(
            "一键测量已取消。当前上传事务会安全发送完，不会中途破坏板端缓冲区。"
            if sending
            else "一键测量已取消；UDP 监听可继续用于普通板上观察。",
            "muted",
        )
        self._append_log("AUTO", "用户取消一键正式冲激测量。")

    def _finish_formal_flow(self, message: str, tone: str) -> None:
        self.formal_flow_active = False
        self.formal_flow_restart_receiver = False
        self.formal_flow_target = None
        self.formal_measure_button.setEnabled(self.upload_thread is None)
        self.formal_cancel_button.setEnabled(False)
        self._set_formal_flow_stage(message, tone)

    def _advance_formal_impulse_flow(self) -> None:
        """Advance only on persistent facts; there is deliberately no timeout."""
        if (
            not self.formal_flow_active
            or self.formal_flow_upload_started
            or self.formal_flow_target is None
        ):
            return
        family, mode = self.formal_flow_target
        wanted = f"{48000 if family else 44100} Hz / {MODE_NAMES[mode]}"
        observed = self._observed_board_target()
        if self.receiver_thread is None:
            self._set_formal_flow_stage("步骤 1/4：等待 UDP4000 监听启动…", "amber")
            return
        if observed != (family, mode):
            key = self._board_key(family, mode)
            actual = (
                "尚未收到完整帧"
                if observed is None
                else f"{48000 if observed[0] else 44100} Hz / {MODE_NAMES[observed[1]]}"
            )
            message = (
                f"步骤 2/4：板上当前为 {actual}。请按住 SW{key} 约 0.2 秒后松开，切到 {wanted}。\n"
                "程序会一直等待；什么时候按都可以，匹配后会自动上传且只上传一次。"
            )
            self._set_formal_flow_stage(message, "amber")
            self.impulse_canvas.clear(message)
            return

        self._set_formal_flow_stage(
            f"步骤 3/4：已识别 {wanted}，正在自动生成并上传 16384 点冲激…"
        )
        self._prepare_upload_waveform()
        if self.upload_samples is None:
            self._finish_formal_flow("冲激生成失败，请查看弹窗说明。", "red")
            return
        # Set before launching so multiple queued frame_ready events cannot
        # start duplicate transactions.
        self.formal_flow_upload_started = True
        if not self._start_upload():
            self.formal_flow_upload_started = False
            self._finish_formal_flow(
                "上传尚未开始；请按弹窗修正网络设置，然后取消并重新点击一键测量。",
                "red",
            )
            return
        self.formal_cancel_button.setEnabled(True)
        self.impulse_canvas.clear(
            "步骤 3/4：冲激上传中；正在等待板端 ACK。请勿关闭程序。"
        )

    def _sync_upload_target_from_observed_board(self) -> None:
        """On impulse selection, inherit the observed/listening target."""
        observed = self._observed_board_target()
        if observed is None:
            # Before the first complete frame, prefer the active receiver's
            # immutable filter, then the controls from which it is created.
            # Programmatic synchronisation remains valid while the target
            # combos are disabled during listening.
            family = (
                self.receiver.config.expected_family_48k
                if self.receiver is not None
                else self.family_combo.currentData()
            )
            mode = (
                self.receiver.config.expected_mode
                if self.receiver is not None
                else self.mode_combo.currentData()
            )
            if family is None or mode is None:
                return
            observed = int(family), int(mode)
        family, mode = observed
        family_index = self.upload_family_combo.findData(family)
        mode_index = self.upload_mode_combo.findData(mode)
        if family_index >= 0:
            self.upload_family_combo.setCurrentIndex(family_index)
        if mode_index >= 0:
            self.upload_mode_combo.setCurrentIndex(mode_index)

    def _refresh_upload_board_status(self) -> None:
        """Show one actionable board-state hint without protocol jargon."""
        if not hasattr(self, "upload_board_status"):
            return
        family = int(self.upload_family_combo.currentData())
        mode = int(self.upload_mode_combo.currentData())
        wanted = f"{48000 if family else 44100} Hz / {MODE_NAMES[mode]}"
        observed = self._displayed_board_target()
        complete = self._observed_board_target()
        if observed == (family, mode) and complete == (family, mode):
            text = f"板上当前为 {wanted}，完整帧已确认，与本次上传一致，可直接上传。"
            style = (
                "background:#102a23; border:1px solid #54d88a; border-radius:3px; "
                "color:#b9f2d0; padding:8px;"
            )
        elif observed == (family, mode):
            text = (
                f"已从实时数据包识别板上为 {wanted}；正在等待这一工况的完整帧。"
                "完整确认后程序会自动上传，无需再次按键或点击。"
            )
            style = (
                "background:#10232a; border:1px solid #47d7ce; border-radius:3px; "
                "color:#bceceb; padding:8px;"
            )
        elif observed is None:
            key = self._board_key(family, mode)
            text = (
                f"尚未收到完整板上帧，无法自动确认当前工况。请按 SW{key} "
                f"切换到 {wanted}；收到完整帧后这里会自动变为“可直接上传”。"
            )
            style = (
                "background:#332815; border:1px solid #f4b860; border-radius:3px; "
                "color:#f7d79b; padding:8px;"
            )
        else:
            actual_family, actual_mode = observed
            actual = (
                f"{48000 if actual_family else 44100} Hz / "
                f"{MODE_NAMES[actual_mode]}"
            )
            key = self._board_key(family, mode)
            text = (
                f"板上当前为 {actual}，本次上传目标为 {wanted}。"
                f"请按住 SW{key} 约 0.2 秒后松开，等界面显示一致后再上传。"
            )
            style = (
                "background:#32191b; border:1px solid #ff6b72; border-radius:3px; "
                "color:#ffc4c7; padding:8px;"
            )
        self.upload_board_status.setText(text)
        self.upload_board_status.setStyleSheet(style)

    def _sync_capture_filter_from_upload(self, *_args) -> None:
        """空闲时让上传描述和 UDP4000 接收过滤保持一致。"""
        if self.receiver_thread is not None:
            return
        family = self.upload_family_combo.currentData()
        mode = self.upload_mode_combo.currentData()
        family_index = self.family_combo.findData(family)
        mode_index = self.mode_combo.findData(mode)
        if family_index >= 0:
            self.family_combo.setCurrentIndex(family_index)
        if mode_index >= 0:
            self.mode_combo.setCurrentIndex(mode_index)
        self._refresh_upload_board_status()

    def _mark_upload_dirty(self, *_args) -> None:
        if self.upload_samples is not None:
            self.upload_samples = None
        self.upload_send_button.setEnabled(self.upload_thread is None)
        if getattr(self, "upload_auto_apply_check", None) is not None and (
            self.upload_auto_apply_check.isChecked()
        ):
            self.upload_status.set_status("参数已改变 · 即将自动应用", "amber")
            self.upload_detail.setText(
                "编辑完成后自动生成并上传；无需再点击“生成”或 BEGIN/WAVE/COMMIT。"
            )
        else:
            self.upload_status.set_status("参数已改变 · 等待手动应用", "amber")
            self.upload_detail.setText(
                "点击“立即应用到 FPGA”，程序会自动生成并完成上传。"
            )

    def _schedule_auto_apply(self, *_args) -> None:
        """Debounce direct user edits into one safe board transaction."""
        if not self.upload_auto_apply_check.isChecked():
            self.auto_apply_timer.stop()
            self.auto_apply_pending = False
            self.auto_apply_restart_receiver = False
            self.auto_apply_target = None
            self.upload_status.set_status("参数可继续编辑 · 尚未输入板卡", "muted")
            self.upload_detail.setText(
                "确认参数后点击一次“输入到板卡”，生成、上传和 ACK 检查会自动完成。"
            )
            return
        if self.formal_flow_active or self.upload_source_combo.currentData() == "impulse":
            self.auto_apply_timer.stop()
            self.auto_apply_pending = False
            self.auto_apply_restart_receiver = False
            self.auto_apply_target = None
            return
        self.auto_apply_timer.start()
        self.upload_status.set_status("参数已更新 · 0.9 秒后自动应用", "amber")
        self.upload_detail.setText(
            "可继续输入；倒计时会从最后一次编辑重新开始，最终只上传一次最新参数。"
        )

    def _apply_upload_now(self) -> bool:
        """One-click/automatic prepare + mode wait + protocol upload."""
        self.auto_apply_timer.stop()
        if self.formal_flow_active:
            return False
        self.auto_apply_pending = True
        self.auto_apply_target = (
            int(self.upload_family_combo.currentData()),
            int(self.upload_mode_combo.currentData()),
        )
        return self._drive_auto_apply()

    def _drive_auto_apply(self) -> bool:
        if not self.auto_apply_pending or self.formal_flow_active:
            return False
        if self.upload_thread is not None:
            self.upload_status.set_status("当前事务发送中 · 最新参数已排队", "amber")
            return False

        family, mode = self.auto_apply_target or (
            int(self.upload_family_combo.currentData()),
            int(self.upload_mode_combo.currentData()),
        )

        # 接收过滤必须与上传目标一致，才能保留COMMIT后的首个index=0帧。
        if self.receiver_thread is not None and self.receiver is not None:
            receiver_target = (
                self.receiver.config.expected_family_48k,
                self.receiver.config.expected_mode,
            )
            if receiver_target != (family, mode):
                self.auto_apply_restart_receiver = True
                self.upload_status.set_status("正在自动重启目标工况监听…", "amber")
                self.upload_detail.setText(
                    f"目标为 {48000 if family else 44100} Hz / {MODE_NAMES[mode]}；"
                    "监听重启后将等待板上工况，再自动上传。"
                )
                self.stop_capture()
                return False

        if self.receiver_thread is None:
            family_index = self.family_combo.findData(family)
            mode_index = self.mode_combo.findData(mode)
            if family_index >= 0:
                self.family_combo.setCurrentIndex(family_index)
            if mode_index >= 0:
                self.mode_combo.setCurrentIndex(mode_index)
            self.current_frame = None
            self.start_capture()
            if self.receiver_thread is None:
                self.auto_apply_pending = False
                return False
            self.upload_status.set_status("监听已自动启动 · 等待板上目标工况", "amber")
            self.upload_detail.setText(
                f"若板上不是 {48000 if family else 44100} Hz / {MODE_NAMES[mode]}，"
                f"请按住 SW{self._board_key(family, mode)} 约 0.2 秒后松开；匹配后自动上传。"
            )
            return False

        observed = self._observed_board_target()
        if observed != (family, mode):
            self.upload_status.set_status("等待板上工况 · 匹配后自动上传", "amber")
            self.upload_detail.setText(
                f"请按住 SW{self._board_key(family, mode)} 约 0.2 秒后松开，切换到 "
                f"{48000 if family else 44100} Hz / {MODE_NAMES[mode]}；无需再点按钮。"
            )
            return False

        self._prepare_upload_waveform()
        if self.upload_samples is None:
            self.auto_apply_pending = False
            return False
        self.auto_apply_pending = False
        started = self._start_upload()
        if started:
            self._append_log(
                "AUTO",
                "参数已自动量化并启动 BEGIN/WAVE/COMMIT；无需手动生成或发送。",
            )
        return started

    def _set_upload_controls_running(self, running: bool) -> None:
        for widget in (
            self.upload_source_combo,
            self.upload_count_spin,
            self.upload_amp_spin,
            self.upload_f1_spin,
            self.upload_f2_spin,
            self.upload_seed_spin,
            self.upload_file_edit,
            self.upload_file_button,
            self.upload_csv_normalised,
            self.upload_headroom_check,
            self.upload_auto_apply_check,
            self.upload_target_edit,
            self.upload_port_spin,
            self.upload_loop_check,
            self.upload_ack_check,
        ):
            widget.setEnabled(not running)
        filters_editable = not running and self.receiver_thread is None
        self.upload_family_combo.setEnabled(filters_editable)
        self.upload_mode_combo.setEnabled(filters_editable)
        self.prepare_upload_button.setEnabled(not running)
        self.upload_send_button.setEnabled(not running)
        if not running:
            self._sync_upload_source_controls()
        self.formal_measure_button.setEnabled(
            not running and not self.formal_flow_active
        )
        self.formal_cancel_button.setEnabled(self.formal_flow_active)

    def _browse_upload_file(self) -> None:
        source = self.upload_source_combo.currentData()
        file_filter = (
            "PCM WAV (*.wav *.wave);;全部文件 (*)"
            if source == "wav"
            else "数值向量 (*.csv *.txt);;全部文件 (*)"
        )
        path, _ = QFileDialog.getOpenFileName(
            self, "选择 1x 输入波形", self.upload_file_edit.text(), file_filter
        )
        if path:
            self.upload_file_edit.setText(path)
            self._schedule_auto_apply()

    def _prepare_upload_waveform(self) -> None:
        source = self.upload_source_combo.currentData()
        family = int(self.upload_family_combo.currentData())
        sample_rate = 48000 if family else 44100
        try:
            if source == "csv":
                imported = load_csv_waveform(
                    Path(self.upload_file_edit.text().strip()),
                    self.upload_csv_normalised.isChecked(),
                )
                samples = imported.samples
                note = imported.note
            elif source == "wav":
                imported = load_wav_waveform(
                    Path(self.upload_file_edit.text().strip()), sample_rate
                )
                samples = imported.samples
                note = imported.note
            elif source == "impulse":
                samples = np.zeros(FORMAL_CAPTURE_SAMPLES, dtype=np.int32)
                samples[0] = FORMAL_IMPULSE_AMPLITUDE
                note = (
                    f"正式冲激 · {sample_rate} Hz · "
                    f"A={FORMAL_IMPULSE_AMPLITUDE} (2^22) · "
                    f"{FORMAL_CAPTURE_SAMPLES} 点"
                )
            else:
                requested_dbfs = self.upload_amp_spin.value()
                effective_dbfs = requested_dbfs
                headroom_limited = False
                if (
                    self.upload_headroom_check.isChecked()
                    and requested_dbfs > SAFE_GENERATED_PEAK_DBFS
                ):
                    effective_dbfs = SAFE_GENERATED_PEAK_DBFS
                    headroom_limited = True
                    # 让界面显示值与实际上传值一致，同时避免 valueChanged
                    # 把刚生成的向量误标为“参数已改变”。
                    previous_block = self.upload_amp_spin.blockSignals(True)
                    self.upload_amp_spin.setValue(-6.02)
                    self.upload_amp_spin.blockSignals(previous_block)
                samples = generate_waveform(
                    str(source),
                    sample_rate,
                    self.upload_count_spin.value(),
                    effective_dbfs,
                    self.upload_f1_spin.value(),
                    self.upload_f2_spin.value(),
                    self.upload_seed_spin.value(),
                )
                note = (
                    f"{self.upload_source_combo.currentText()} · {sample_rate} Hz · "
                    f"实际峰值 {effective_dbfs:.2f} dBFS"
                )
                if headroom_limited:
                    note += f"（由请求的 {requested_dbfs:.2f} dBFS 自动限幅）"
                    self._append_log(
                        "SAFE",
                        f"自动防削顶已将内置信号峰值从 {requested_dbfs:.2f} dBFS "
                        f"限制为 {effective_dbfs:.2f} dBFS；上传数据保留半满量程余量。",
                    )
        except (OSError, UploadProtocolError, ValueError) as exc:
            self.upload_samples = None
            self.upload_send_button.setEnabled(False)
            self.upload_status.set_status("波形准备失败", "red")
            QMessageBox.critical(self, "波形无法使用", str(exc))
            return

        self.upload_samples = samples
        self.upload_note = note
        self.upload_send_button.setEnabled(self.upload_thread is None)
        self.upload_status.set_status(f"已准备 {samples.size:,} 点 s24", "cyan")
        packet_count = (samples.size + 255) // 256
        self.upload_detail.setText(
            f"{note}；{packet_count} 个 WAVE 包；范围 "
            f"[{int(samples.min())}, {int(samples.max())}]"
        )
        time_axis = np.arange(samples.size, dtype=np.float64) / sample_rate
        display_count = min(samples.size, 8192)
        axis = self.upload_preview.axis
        axis.clear()
        axis.plot(
            time_axis[:display_count] * 1e3,
            samples[:display_count].astype(np.float64) / float(1 << 23),
            color=COLORS["cyan"],
            linewidth=0.8,
        )
        axis.set(
            title=f"待上传 1x 输入预览 · 显示前 {display_count:,}/{samples.size:,} 点",
            xlabel="时间 / ms",
            ylabel="FS",
            ylim=(-1.05, 1.05),
        )
        self.upload_preview._style()
        self.upload_preview.draw_idle()
        self._append_log("UPLOAD", f"波形已准备：{note}，{samples.size} 点")

    def _start_upload(self) -> bool:
        if self.upload_samples is None or self.upload_thread is not None:
            return False
        transaction_id = int(time.time_ns() & 0xFFFFFFFF) or 1
        family = int(self.upload_family_combo.currentData())
        mode = int(self.upload_mode_combo.currentData())
        ack_required = self.upload_ack_check.isChecked()
        if self.receiver_thread is None:
            self._sync_capture_filter_from_upload()
            QMessageBox.warning(
                self,
                "请先开始监听",
                "已将 UDP4000 接收过滤自动同步为本次上传的 "
                "family/mode。请先回到“板上测量”点击“开始监听”，"
                "看到“监听中”后再上传，否则可能错过从索引 0 开始的首帧。",
            )
            return False
        receiver_family = self.receiver.config.expected_family_48k if self.receiver else None
        receiver_mode = self.receiver.config.expected_mode if self.receiver else None
        if receiver_family != family or receiver_mode != mode:
            QMessageBox.critical(
                self,
                "接收过滤与上传不一致",
                "当前 UDP4000 监听过滤与上传 family/mode 不一致。"
                "请停止监听，选好上传参数（界面会自动同步过滤），"
                "再重新开始监听。",
            )
            return False

        target_address = self.upload_target_edit.text().strip()
        target_port = self.upload_port_spin.value()
        # 使用当前监听所选地址。若监听全部网卡，则先让系统完成一次无数据的
        # UDP 路由探测，再把探测出的具体 IPv4 固定给真正的上传套接字。
        selected_bind = self.receiver.config.bind_address if self.receiver else self._bind_address()
        try:
            route = require_direct_fpga_subnet(
                target_address,
                target_port,
                selected_bind,
            )
        except UploadNetworkError as exc:
            message = str(exc)
            self.upload_status.set_status("网络配置不正确 · 未发送", "red")
            self.upload_detail.setText(message)
            self._append_log("NET", message.replace("\n", "；"))
            QMessageBox.critical(self, "上传网络检查未通过", message)
            return False

        config = UploadConfig(
            target_address=route.target_address,
            target_port=route.target_port,
            local_bind_address=route.local_address,
        )
        self._append_log(
            "NET",
            f"上传网络检查通过：本机 {route.local_address} → "
            f"FPGA {route.target_address}:{route.target_port}；发送已固定到该本机地址。",
        )
        observed = self._observed_board_target()
        if observed is not None and observed != (family, mode):
            actual_family, actual_mode = observed
            expected_key = self._board_key(family, mode)
            QMessageBox.warning(
                self,
                "板上工况与上传目标不一致",
                f"最近完整板上帧是 {48000 if actual_family else 44100} Hz / "
                f"{MODE_NAMES[actual_mode]}，上传目标是 "
                f"{48000 if family else 44100} Hz / {MODE_NAMES[mode]}。\n\n"
                f"请按住 SW{expected_key} 约 0.2 秒后松开，等右侧 Family / mode 和绿色状态提示"
                "变为目标工况后，再点击上传。PC 端不会自动切换板上的物理采样率。",
            )
            return False
        if observed is None:
            expected_key = self._board_key(family, mode)
            answer = QMessageBox.question(
                self,
                "尚未识别板上工况",
                f"界面还没有收到完整板上帧，因此无法自动确认当前采样率和模式。\n\n"
                f"目标是 {48000 if family else 44100} Hz / {MODE_NAMES[mode]}；"
                f"如果还没设置，请按住 SW{expected_key} 约 0.2 秒后松开。是否确认板上已经是该工况并继续？",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.No,
            )
            if answer != QMessageBox.StandardButton.Yes:
                return False
        try:
            plan = build_upload_plan(
                self.upload_samples,
                transaction_id=transaction_id,
                family_48k=family,
                output_mode=mode,
                loop=self.upload_loop_check.isChecked(),
                repeat_count=0 if self.upload_loop_check.isChecked() else 1,
                ack_required=ack_required,
            )
        except UploadProtocolError as exc:
            QMessageBox.critical(self, "上传计划无效", str(exc))
            return False

        if not ack_required:
            answer = QMessageBox.warning(
                self,
                "无 ACK 开发模式",
                "该模式只能报告本机 UDP 数据报已发送，无法证明 FPGA 已接收、CRC 通过、"
                "事务已提交或开始播放。是否继续？",
                QMessageBox.StandardButton.Yes | QMessageBox.StandardButton.No,
                QMessageBox.StandardButton.No,
            )
            if answer != QMessageBox.StandardButton.Yes:
                return False

        try:
            self._archive_upload_input(transaction_id, family, mode)
        except OSError as exc:
            QMessageBox.critical(
                self,
                "无法归档上传输入",
                f"为保证 txid 可复现，本次上传未发送。归档失败：{exc}",
            )
            return False

        thread = QThread(self)
        worker = UploadWorker(plan, config)
        worker.moveToThread(thread)
        thread.started.connect(worker.run)
        worker.progress.connect(self._on_upload_progress)
        # Do not connect worker-thread signals to context-free Python lambdas.
        # PySide may execute such lambdas in the sender thread; touching a Qt
        # widget there can corrupt the native Qt heap and terminate python.exe
        # without a Python traceback.  A registered MainWindow slot guarantees
        # that all GUI work is queued onto the GUI thread.
        worker.packet_acknowledged.connect(self._on_upload_packet_acknowledged)
        worker.completed.connect(self._on_upload_completed)
        worker.failed.connect(self._on_upload_failed)
        worker.finished.connect(worker.deleteLater)
        worker.finished.connect(thread.quit)
        thread.finished.connect(self._on_upload_finished)
        self.upload_thread = thread
        self.upload_worker = worker
        self.last_upload_transaction_id = transaction_id
        self.last_upload_confirmed = False
        if (
            self.upload_source_combo.currentData() == "impulse"
            and self.upload_samples.size > 0
        ):
            self.upload_impulses[transaction_id] = int(self.upload_samples[0])
            while len(self.upload_impulses) > 16:
                del self.upload_impulses[next(iter(self.upload_impulses))]
        self.upload_progress.setRange(0, len(plan.datagrams))
        self.upload_progress.setValue(0)
        self.upload_status.set_status(
            "发送并等待板端 ACK…" if ack_required else "无 ACK 开发模式发送中…",
            "amber",
        )
        self._set_upload_controls_running(True)
        self._append_log(
            "UPLOAD",
            f"事务 0x{transaction_id:08X} → {config.target_address}:{config.target_port}；"
            f"{len(plan.datagrams)} 个数据报；ACK={'required' if ack_required else 'disabled'}",
        )
        thread.start()
        return True

    def _archive_upload_input(
        self, transaction_id: int, family_48k: int, mode: int
    ) -> None:
        assert self.upload_samples is not None
        root = Path(self.output_edit.text().strip() or str(DEFAULT_OUTPUT))
        folder = root / "upload_inputs"
        folder.mkdir(parents=True, exist_ok=True)
        stem = folder / f"input_tx_{transaction_id:08X}"
        np.save(stem.with_suffix(".npy"), self.upload_samples)
        kind = str(self.upload_source_combo.currentData())
        amplitude = (
            int(self.upload_samples[0])
            if kind == "impulse" and self.upload_samples.size
            else "not_impulse"
        )
        stem.with_suffix(".meta.txt").write_text(
            "\n".join(
                (
                    f"transaction_id=0x{transaction_id:08X}",
                    f"input_source_kind={kind}",
                    f"family_rate={48000 if family_48k else 44100}",
                    f"output_mode={MODE_NAMES[mode]}",
                    f"sample_count={self.upload_samples.size}",
                    f"input_impulse_amplitude_s24={amplitude}",
                    f"preparation_note={self.upload_note}",
                )
            )
            + "\n",
            encoding="utf-8",
        )
        self._append_log(
            "SAVE", f"已归档上传输入与 txid：{stem}.npy / .meta.txt"
        )

    @Slot(str, int, int)
    def _on_upload_packet_acknowledged(
        self, stage: str, sequence: int, offset: int
    ) -> None:
        self._append_log("ACK", f"{stage} seq={sequence}，next_offset={offset}")

    @Slot(int, int, str)
    def _on_upload_progress(self, current: int, total: int, stage: str) -> None:
        self.upload_progress.setRange(0, total)
        self.upload_progress.setValue(current)
        self.upload_detail.setText(f"{stage} · 数据报 {current}/{total}")

    @Slot(bool, int, int)
    def _on_upload_completed(
        self, confirmed_by_board: bool, sent_datagrams: int, acknowledged: int
    ) -> None:
        self.last_upload_confirmed = confirmed_by_board
        transaction = self.last_upload_transaction_id or 0
        if confirmed_by_board:
            self.confirmed_upload_transactions.add(transaction)
            while len(self.confirmed_upload_transactions) > 16:
                self.confirmed_upload_transactions.pop()
            self.upload_status.set_status("板端 ACK 已确认事务提交", "cyan")
            self.upload_detail.setText(
                f"transaction=0x{transaction:08X}；{acknowledged} 个数据报均收到 OK ACK"
            )
            self._append_log(
                "UPLOAD",
                f"事务 0x{transaction:08X} 已由板端 ACK 确认；等待 UDP4000 回传 txid 对照。",
            )
            if self.formal_flow_active:
                self._set_formal_flow_stage(
                    "步骤 4/4：板端已确认冲激事务。正在等待相同 txid、索引 0、完整 16384 点回传…"
                )
                self.workspace_tabs.setCurrentIndex(0)
                self.plot_tabs.setCurrentWidget(self.impulse_canvas)
                self.impulse_canvas.clear(
                    "步骤 4/4：ACK 已确认，正在等待正式冲激回传帧…"
                )
            else:
                # 普通波形改参的目标是立即观察板端结果。ACK确认后自动回到
                # 板上测量/时域页，用户不必再从上传页手工切回。
                self.workspace_tabs.setCurrentIndex(0)
                self.plot_tabs.setCurrentWidget(self.time_canvas)
        else:
            self.upload_status.set_status("本机已发送 · 板端未确认", "amber")
            self.upload_detail.setText(
                f"transaction=0x{transaction:08X}；sendto 调用 {sent_datagrams} 次；"
                "没有 ACK 证据"
            )
            self._append_log(
                "UPLOAD",
                f"事务 0x{transaction:08X} 仅完成本机发送，板端状态未确认。",
            )

    @Slot(str)
    def _on_upload_failed(self, message: str) -> None:
        self.last_upload_confirmed = False
        self.upload_status.set_status("上传未确认 / 失败", "red")
        self.upload_detail.setText(message)
        self._append_log("ERROR", f"上传：{message}")
        if self.formal_flow_active:
            self._finish_formal_flow(f"冲激上传失败：{message}", "red")

    @Slot()
    def _on_upload_finished(self) -> None:
        thread = self.upload_thread
        self.upload_thread = None
        self.upload_worker = None
        if thread is not None:
            thread.deleteLater()
        self._set_upload_controls_running(False)
        if self.auto_apply_pending:
            QTimer.singleShot(0, self._drive_auto_apply)

    def _set_controls_running(self, running: bool) -> None:
        self.start_button.setEnabled(not running)
        self.stop_button.setEnabled(running)
        for widget in (
            self.bind_combo,
            self.port_spin,
            self.family_combo,
            self.mode_combo,
            self.verify_check,
            self.reference_edit,
            self.browse_ref_button,
        ):
            widget.setEnabled(not running)
        if not running:
            self._sync_reference_controls(self.verify_check.isChecked())
        # 接收过程中仍允许用户选择新的上传family/mode；自动应用状态机
        # 会安全停止并按新过滤条件重启监听，而不是要求用户手动停/启。
        upload_target_editable = (
            self.upload_thread is None and not self.formal_flow_active
        )
        self.upload_family_combo.setEnabled(upload_target_editable)
        self.upload_mode_combo.setEnabled(upload_target_editable)

    def start_capture(self) -> None:
        if self.receiver_thread is not None:
            return
        bind_address = self._bind_address()
        port = self.port_spin.value()
        family = self.family_combo.currentData()
        mode = self.mode_combo.currentData()

        if self.verify_check.isChecked() and (family is None or mode is None):
            QMessageBox.warning(
                self,
                "参考条件不完整",
                "逐位验证必须固定采样率族和输出模式，不能选择“任意”。",
            )
            return
        try:
            self.reference = (
                ReferenceVector.load(Path(self.reference_edit.text().strip()))
                if self.verify_check.isChecked()
                else None
            )
        except (OSError, ReferenceError) as exc:
            QMessageBox.critical(self, "参考文件不可用", str(exc))
            return

        self._save_settings()
        self.bit_true_pass_latched = False
        # Starting a new capture explicitly releases either kind of result
        # lock; otherwise queued frames can never replace completed evidence.
        self.formal_result_latched = False
        self.live_board_target = None
        self.live_board_descriptor = None
        config = ReceiverConfig(bind_address, port, family, mode)
        thread = QThread(self)
        worker = CaptureWorker(config)
        worker.moveToThread(thread)
        thread.started.connect(worker.run)
        worker.listening.connect(self._on_listening)
        worker.valid_packet_seen.connect(self._on_valid_packet_seen)
        worker.board_state_seen.connect(self._on_board_state_seen)
        worker.packet_activity.connect(self._on_packet_activity)
        worker.frame_ready.connect(self._on_frame_ready)
        worker.transition_ignored.connect(self._on_transition_ignored)
        worker.protocol_warning.connect(self._on_protocol_warning)
        worker.failed.connect(self._on_receiver_failed)
        worker.stopped.connect(worker.deleteLater)
        worker.stopped.connect(thread.quit)
        thread.finished.connect(self._on_receiver_finished)
        self.receiver_thread = thread
        self.receiver = worker

        self.listener_pill.set_status("正在绑定端口…", "amber")
        self.last_packet_monotonic = None
        self.last_peer = ""
        self.activity_pill.set_status("尚未收到 FPGA 包", "muted")
        self.bit_status.set_status(
            "等待目标帧" if self.reference is not None else "未启用参考比较",
            "amber" if self.reference is not None else "muted",
        )
        self._set_controls_running(True)
        self._append_log(
            "INFO",
            f"请求监听 {bind_address}:{port}；目标="
            f"{48000 if family else 44100 if family is not None else '任意'} Hz/"
            f"{MODE_NAMES[mode] if mode is not None else '任意'}",
        )
        thread.start()

    def stop_capture(self) -> None:
        if self.receiver is None:
            return
        self.listener_pill.set_status("正在停止…", "amber")
        self.stop_button.setEnabled(False)
        # This method only sets a threading.Event and is intentionally called
        # directly: the worker's long-running receive loop occupies its QThread
        # event loop, so a queued stop slot could not run until reception ended.
        self.receiver.stop()

    def _stop_after_latched_pass(self) -> None:
        """Request a worker stop without waiting in the GUI thread."""
        if not self.bit_true_pass_latched:
            return
        self.stop_button.setEnabled(False)
        if self.receiver is None:
            self.listener_pill.set_status("已停止 · PASS 结果已锁定", "green")
            return
        self.listener_pill.set_status("PASS 已锁定 · 正在自动停止监听…", "green")
        # CaptureWorker.stop() only sets a threading.Event.  Calling it here is
        # safe even though run() owns the worker QThread event loop; importantly,
        # there is no blocking wait and therefore no self-thread deadlock.
        self.receiver.stop()

    def _stop_after_formal_result(self) -> None:
        """Safely stop after a formal PASS/FAIL has been atomically latched."""
        if not self.formal_result_latched:
            return
        self.stop_button.setEnabled(False)
        if self.receiver is None:
            self.listener_pill.set_status("已停止 · 正式冲激结果已锁定", "green")
            return
        self.listener_pill.set_status("正式冲激结果已锁定 · 正在自动停止…", "green")
        self.receiver.stop()

    @Slot(str)
    def _on_protocol_warning(self, message: str) -> None:
        self._append_log("WARN", f"忽略无效数据包：{message}")

    @Slot(str, int)
    def _on_listening(self, address: str, port: int) -> None:
        self.listener_pill.set_status(f"监听中 · {address}:{port}", "cyan")
        self._append_log(
            "LISTEN",
            f"UDP 端口已绑定 {address}:{port}；这不代表 FPGA 已建立连接。",
        )
        if address.startswith("169.254."):
            self._append_log(
                "WARN",
                "当前是 169.254.x.x 自动地址；建议将有线网卡设为 192.168.1.20/24。",
            )
        if self.formal_flow_active:
            self._advance_formal_impulse_flow()

    @Slot(str, int, int, int, int, int, int)
    def _on_packet_activity(
        self,
        peer: str,
        frame_id: int,
        received: int,
        total: int,
        family_48k: int,
        mode: int,
        start_index: int,
    ) -> None:
        if self.bit_true_pass_latched or self.formal_result_latched:
            return
        self.packet_progress.setRange(0, total)
        self.packet_progress.setValue(received)
        self.packet_detail.setText(
            f"{received} / {total} · frame {frame_id} · packet stream"
        )
        self.frame_card.set_value(str(frame_id), "cyan")
        self.index_card.set_value(f"{start_index:,}")
        self.family_card.set_value(
            f"{48000 if family_48k else 44100}\n{MODE_NAMES[mode]}", "blue"
        )
        self._refresh_upload_board_status()

    @Slot(str)
    def _on_valid_packet_seen(self, peer: str) -> None:
        if self.bit_true_pass_latched or self.formal_result_latched:
            return
        self.last_packet_monotonic = time.monotonic()
        self.last_peer = peer
        self.activity_pill.set_status(f"收到 FPGA 包 · {peer}", "cyan")

    @Slot(object)
    def _on_board_state_seen(self, packet) -> None:
        """Update live telemetry even when the receive filter drops the frame."""
        if self.bit_true_pass_latched or self.formal_result_latched:
            return
        descriptor = (
            int(packet.family_48k),
            int(packet.mode),
            int(packet.frame_id),
            int(packet.start_sample_index),
            int(packet.upload_source),
            int(packet.input_transaction_id),
        )
        if descriptor == self.live_board_descriptor:
            return
        self.live_board_descriptor = descriptor
        family, mode, frame_id, start_index, upload_source, transaction_id = descriptor
        self.live_board_target = (family, mode)
        family_rate = 48000 if family else 44100
        output_rate = family_rate * (1, 4, 8, 128)[mode]
        self.frame_card.set_value(str(frame_id), "cyan")
        self.index_card.set_value(f"{start_index:,}")
        self.family_card.set_value(f"{family_rate}\n{MODE_NAMES[mode]}", "blue")
        self.rate_card.set_value(f"{output_rate / 1e6:.4f}\nMS/s")
        self.source_card.set_value(
            "UPLOAD RAM" if upload_source else "ROM / legacy",
            "cyan" if upload_source else "muted",
        )
        self.txid_card.set_value(
            f"0x{transaction_id:08X}\n实时包"
            if upload_source
            else "—\n实时包",
            "cyan" if upload_source else "muted",
        )
        self._refresh_upload_board_status()

    @Slot(int, int, int)
    def _on_transition_ignored(self, family_48k: int, mode: int, frame_id: int) -> None:
        if self.bit_true_pass_latched or self.formal_result_latched:
            return
        self._append_log(
            "FILTER",
            f"已忽略过渡帧 {frame_id}：{48000 if family_48k else 44100} Hz/"
            f"{MODE_NAMES[mode]}。继续等待目标帧。",
        )
        if (
            not self.follow_board_check.isChecked()
            or self.formal_flow_active
            or self.auto_apply_pending
            or self.follow_board_pending is not None
        ):
            return
        self.follow_board_pending = (int(family_48k), int(mode))
        self.listener_pill.set_status("检测到板上 SW 切换 · 正在自动跟随…", "amber")
        self._append_log(
            "FOLLOW",
            f"检测到板上已切换为 {48000 if family_48k else 44100} Hz/"
            f"{MODE_NAMES[mode]}；自动重启目标过滤，无需手工停止/开始监听。",
        )
        self.stop_capture()

    @Slot(object)
    def _on_frame_ready(self, frame: CaptureFrame) -> None:
        if self.bit_true_pass_latched or self.formal_result_latched:
            return
        flow_was_active = self.formal_flow_active
        reference_target = (
            infer_reference_target(self.reference.path)
            if self.reference is not None
            else None
        )
        frame_target = (int(frame.family_48k), int(frame.mode))
        if frame.upload_source and self.reference is not None:
            # The configured reference describes the fixed board ROM.  It is
            # not a valid oracle for arbitrary uploaded input, even when the
            # family and interpolation mode match.
            analysis = analyze_frame(frame, None)
            reference_error = (
                "当前参考向量属于板内 ROM；上传输入需要由同一上传向量生成的匹配 RTL "
                "参考。本帧仅显示和保存，不作 bit-true 判定。"
            )
        elif self.reference is not None and reference_target is not None and (
            reference_target != frame_target
        ):
            analysis = analyze_frame(frame, None)
            ref_family, ref_mode = reference_target
            reference_error = (
                f"参考文件 {self.reference.path.name} 对应 "
                f"{48000 if ref_family else 44100} Hz/{MODE_NAMES[ref_mode]}，"
                f"当前板上帧为 {frame.family_rate} Hz/{frame.mode_name}；"
                "工况不同，已禁止逐位比较以避免假 FAIL"
            )
        else:
            try:
                analysis = analyze_frame(frame, self.reference)
                reference_error = None
            except ReferenceError as exc:
                # The frame is genuine board data and remains useful for display,
                # but it must never be presented as a bit-true PASS.
                analysis = analyze_frame(frame, None)
                reference_error = str(exc)

        self.current_frame = frame
        self.current_analysis = analysis
        self.current_impulse_metrics = None
        self.save_button.setEnabled(self.save_thread is None)
        self.packet_progress.setValue(frame.packet_count)
        self.packet_detail.setText(
            f"{frame.packet_count} / {frame.packet_count} · 完整帧 · "
            f"{frame.total_samples} 点 · duplicate {frame.duplicate_packets}"
        )
        self.frame_card.set_value(str(frame.frame_id), "cyan")
        self.index_card.set_value(f"{frame.start_sample_index:,}")
        self.family_card.set_value(
            f"{frame.family_rate}\n{frame.mode_name}", "blue"
        )
        self._refresh_upload_board_status()
        if self.auto_apply_pending and not self.formal_flow_active:
            # 先完整记录本帧，再在GUI事件队列的下一轮启动上传，避免
            # 在frame_ready槽内部递归更新大量控件。
            QTimer.singleShot(0, self._drive_auto_apply)
        if self.formal_flow_active:
            # The complete frame is the durable board-state proof.  A partial
            # packet is never allowed to trigger the transaction.
            self._advance_formal_impulse_flow()
        self.rate_card.set_value(f"{frame.sample_rate / 1e6:.4f}\nMS/s")
        self.source_card.set_value(
            "UPLOAD RAM" if frame.upload_source else "ROM / legacy",
            "cyan" if frame.upload_source else "muted",
        )
        self.txid_card.set_value(
            f"0x{frame.input_transaction_id:08X}\nstatus 0x{frame.capture_status:04X}"
            if frame.upload_source or frame.input_transaction_id or frame.capture_status
            else "—"
        )
        self.resolution_label.setText(
            f"FFT 分辨率：{analysis.spectrum.resolution_hz:,.3f} Hz/bin"
        )
        _, peak_dbfs = normalize_spectrum_to_peak(analysis.spectrum.dbfs)
        self.preview_notice.setText(
            f"当前为 {frame.total_samples} 点 Hann 窗相对输出谱：本帧原始谱峰 "
            f"{peak_dbfs:.2f} dBFS 已归一化为 0 dBr。该图不是滤波器增益；"
            "±0.05 dB / ≥70 dB 请以“正式频响 H(f)”页为准：无窗、按 A·L 归一化。"
        )
        self._draw_analysis(analysis, frame)

        if frame.upload_source:
            if (
                self.last_upload_transaction_id is not None
                and frame.input_transaction_id == self.last_upload_transaction_id
            ):
                self._append_log(
                    "TRACE",
                    f"回传帧 {frame.frame_id} 对应上传事务 "
                    f"0x{frame.input_transaction_id:08X}；capture_status="
                    f"0x{frame.capture_status:04X}。",
                )
            else:
                self._append_log(
                    "WARN",
                    f"回传为上传源但 txid=0x{frame.input_transaction_id:08X}，"
                    "与本次 GUI 最近事务不一致。",
                )

        impulse_amplitude = self.upload_impulses.get(frame.input_transaction_id)
        transaction_confirmed = (
            frame.input_transaction_id in self.confirmed_upload_transactions
        )
        if frame.upload_source and impulse_amplitude is not None and transaction_confirmed:
            try:
                impulse_metrics = analyze_impulse_response(frame, impulse_amplitude)
            except ValueError as exc:
                self.impulse_result.setText(f"正式冲激频响：未判定 · {exc}")
                self.impulse_result.setStyleSheet(f"color:{COLORS['amber']};")
                self.impulse_canvas.clear(f"正式冲激频响未判定：{exc}")
            else:
                self.current_impulse_metrics = impulse_metrics
                self._draw_impulse_response(impulse_metrics, frame)
                # 正式冲激是板级验收证据：得到可判定结果后总是自动归档，
                # 不依赖“完整帧自动保存”复选框，也不会因保存线程正忙而丢失。
                self._queue_formal_artifact_save(frame, analysis, impulse_metrics)
                if (
                    self.formal_flow_active
                    and self.last_upload_transaction_id == frame.input_transaction_id
                ):
                    # Freeze before returning to Qt's event loop. Queued packet
                    # and frame signals can no longer overwrite this evidence.
                    self.formal_result_latched = True
                    self.workspace_tabs.setCurrentIndex(0)
                    self.plot_tabs.setCurrentWidget(self.impulse_canvas)
                    result = "PASS" if impulse_metrics.passed else "FAIL"
                    self._finish_formal_flow(
                        f"步骤 4/4：正式冲激测量完成 · {result}。结果已显示并锁定在正式冲激频响页。",
                        "green" if impulse_metrics.passed else "red",
                    )
                    self._append_log(
                        "锁定",
                        f"正式冲激 frame {frame.frame_id} 已锁定；后续同 txid 帧不会覆盖。",
                    )
                    QTimer.singleShot(0, self._stop_after_formal_result)
        elif frame.upload_source and impulse_amplitude is not None:
            self.impulse_result.setText(
                "正式冲激频响：未判定 · 本 GUI 会话没有该 txid 的完整板端 ACK 证据"
            )
            self.impulse_result.setStyleSheet(f"color:{COLORS['amber']};")
            self.impulse_canvas.clear("正式冲激频响未判定：事务未经板端 ACK 确认")
        else:
            self.impulse_result.setText(
                "正式冲激频响：本帧不是 GUI 已记录的匹配 txid 上传冲激，未判定"
            )
            self.impulse_result.setStyleSheet(f"color:{COLORS['muted']};")

        if reference_error is not None:
            self.bit_status.set_status("参考不适用于当前帧 · 未判定", "amber")
            self.mismatch_card.set_value("未比较", "amber")
            self.error_card.set_value("未比较", "amber")
            self.compare_range.setText(reference_error)
            self._append_log(
                "WAIT",
                f"帧 {frame.frame_id} 未比较：{reference_error}。继续监听；"
                "请选择匹配当前采样率/倍率的 RTL 参考，或关闭 bit-true 比较。",
            )
        elif analysis.bit_true is None:
            self.bit_status.set_status("板上帧已接收 · 无参考", "cyan")
            self.mismatch_card.set_value("未启用")
            self.error_card.set_value("未启用")
            self.compare_range.setText("参考区间：未启用")
        else:
            result = analysis.bit_true
            self.compare_range.setText(
                f"参考区间：[{result.reference_start}:{result.reference_stop}]"
            )
            if result.passed:
                self.bit_status.set_status(
                    f"PASS · {frame.total_samples} 点逐位一致", "green"
                )
                self.mismatch_card.set_value(f"0 / {frame.total_samples}", "green")
                self.error_card.set_value("0 LSB", "green")
                self._append_log(
                    "PASS",
                    f"帧 {frame.frame_id}：{frame.total_samples} 点逐位一致，"
                    "max_abs_error=0 LSB。",
                )
                if self.auto_lock_pass_check.isChecked() and not flow_was_active:
                    self.bit_true_pass_latched = True
                    self.bit_status.set_status(
                        f"PASS 已锁定 · 帧 {frame.frame_id} · {frame.total_samples} 点逐位一致",
                        "green",
                    )
                    self._append_log(
                        "锁定",
                        f"已锁定首次 PASS 帧 {frame.frame_id}，并请求自动停止监听；"
                        "后续帧不会覆盖本结果，无需抢按“停止”。",
                    )
            else:
                self.bit_status.set_status("FAIL · 数字样本不一致", "red")
                self.mismatch_card.set_value(
                    f"{result.mismatch_count} / {result.compared_samples}", "red"
                )
                self.error_card.set_value(f"{result.max_abs_error} LSB", "red")
                self._append_log(
                    "FAIL",
                    f"帧 {frame.frame_id}：mismatch={result.mismatch_count}，"
                    f"max_abs_error={result.max_abs_error} LSB。",
                )

        if self.auto_save_check.isChecked() and self.current_impulse_metrics is None:
            self._save_current_frame()
        if self.bit_true_pass_latched:
            # Let this frame's cards, plots and optional save request finish
            # before asking the receiver to exit.
            QTimer.singleShot(0, self._stop_after_latched_pass)

    def _draw_analysis(self, analysis: FrameAnalysis, frame: CaptureFrame) -> None:
        axis = self.time_canvas.axis
        axis.clear()
        axis.plot(
            analysis.time_seconds * 1e6,
            analysis.normalized,
            color=COLORS["cyan"],
            linewidth=0.8,
        )
        axis.set(
            title=f"24 位输出时域 · frame {frame.frame_id} · {frame.total_samples} 点",
            xlabel="时间 / µs",
            ylabel="满量程归一化幅度",
        )
        self.time_canvas._style()
        self.time_canvas.draw_idle()

        relative_db, peak_dbfs = normalize_spectrum_to_peak(
            analysis.spectrum.dbfs
        )

        axis = self.full_fft_canvas.axis
        axis.clear()
        axis.plot(
            analysis.spectrum.frequency_hz / 1e6,
            relative_db,
            color=COLORS["blue"],
            linewidth=0.75,
        )
        axis.set(
            title=(
                "全频带相对输出谱 · 峰值=0 dBr · Hann 窗 · "
                f"原始峰值 {peak_dbfs:.2f} dBFS · "
                f"{analysis.spectrum.resolution_hz:,.1f} Hz/bin"
            ),
            xlabel="频率 / MHz",
            ylabel="相对本帧谱峰 / dBr",
            ylim=(-160, 5),
        )
        self.full_fft_canvas._style()
        self.full_fft_canvas.draw_idle()

        local = analysis.spectrum.below(50000.0)
        local_relative_db = relative_db[: local.dbfs.size]
        axis = self.local_fft_canvas.axis
        axis.clear()
        axis.axvspan(0.01, 20.0, color=COLORS["cyan"], alpha=0.08, label="题目通带 10 Hz–20 kHz")
        axis.axvline(20.0, color=COLORS["amber"], linestyle="--", linewidth=0.9)
        axis.plot(
            local.frequency_hz / 1e3,
            local_relative_db,
            color=COLORS["amber"],
            marker="o",
            markersize=2.5,
            linewidth=0.85,
        )
        axis.set(
            title="0–50 kHz 相对输出谱 · 本帧谱峰=0 dBr · 非滤波器增益",
            xlabel="频率 / kHz",
            ylabel="相对本帧谱峰 / dBr",
            xlim=(0, 50),
            ylim=(-160, 5),
        )
        self.local_fft_canvas._style()
        self.local_fft_canvas.draw_idle()

    def _draw_impulse_response(
        self, metrics: ImpulseResponseMetrics, frame: CaptureFrame
    ) -> None:
        axis = self.impulse_canvas.axis
        axis.clear()
        stride = max(1, metrics.frequency_hz.size // 50_000)
        axis.plot(
            metrics.frequency_hz[::stride] / 1e3,
            metrics.gain_db[::stride],
            color=COLORS["cyan"],
            linewidth=0.7,
        )
        stop_start = frame.family_rate - 20_000
        axis.axvspan(0.01, 20.0, color=COLORS["cyan"], alpha=0.08)
        axis.axvspan(
            stop_start / 1e3,
            frame.sample_rate / 2e3,
            color=COLORS["red"],
            alpha=0.05,
        )
        axis.axhline(-70.0, color=COLORS["red"], linestyle="--", linewidth=0.8)
        result_label = (
            "PASS"
            if metrics.passed
            else "FAIL"
            if metrics.capture_complete
            else "未判定"
        )
        tone = (
            "green"
            if metrics.passed
            else "red"
            if metrics.capture_complete
            else "amber"
        )
        family_label = "48 kHz" if frame.family_48k else "44.1 kHz"
        metric_summary = (
            f"正式指标：{result_label}\n"
            f"板端采样率族：{family_label}\n"
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
            color=COLORS[tone],
            fontsize=8.8,
            linespacing=1.35,
            bbox={
                "boxstyle": "round,pad=0.55",
                "facecolor": COLORS["panel"],
                "edgecolor": COLORS[tone],
                "linewidth": 1.0,
                "alpha": 0.96,
            },
            zorder=5,
        )
        axis.set(
            title="正式无窗冲激频响 · 通带 0 dB 归一化 · NFFT=2^20 · H=FFT(y)/(A·L)",
            xlabel="频率 / kHz",
            ylabel="增益 / dB",
            xlim=(0, frame.sample_rate / 2e3),
            ylim=(-140, 2),
        )
        self.impulse_canvas._style()
        self.impulse_canvas.draw_idle()
        determined = metrics.capture_complete
        completion = "完整" if metrics.capture_complete else "不完整（长度/尾16零门限）"
        self.impulse_result.setText(
            f"正式冲激频响：{result_label} · 捕获{completion} · "
            f"通带 max|G|={metrics.passband_max_abs_db:.6f} dB "
            f"({'≤0.05' if metrics.passband_max_abs_db <= 0.05 else '>0.05'}) · "
            f"峰峰纹波={metrics.passband_pp_db:.6f} dB · "
            f"阻带={metrics.stopband_attenuation_db:.3f} dB "
            f"({'≥70' if metrics.stopband_attenuation_db >= 70 else '<70'}) · "
            f"最差点 {metrics.worst_stop_frequency_hz / 1e3:.3f} kHz"
        )
        self.impulse_result.setStyleSheet(f"color:{COLORS[tone]}; font-weight:600;")
        self._append_log(
            "PASS" if metrics.passed else "FAIL" if determined else "WAIT",
            f"正式冲激频响 frame={frame.frame_id}: complete={metrics.capture_complete}, "
            f"pass_abs={metrics.passband_max_abs_db:.6f} dB, "
            f"stop={metrics.stopband_attenuation_db:.3f} dB。",
        )

    def _queue_formal_artifact_save(
        self,
        frame: CaptureFrame,
        analysis: FrameAnalysis,
        metrics: ImpulseResponseMetrics,
    ) -> None:
        key = (frame.frame_id, frame.input_transaction_id)
        if key in self.saved_formal_keys:
            return
        self.saved_formal_keys.add(key)
        request = (frame, analysis, metrics)
        if self.save_thread is not None:
            self.pending_formal_save = request
            self._append_log(
                "SAVE",
                "保存线程正忙；正式冲激证据已进入队列，当前保存结束后自动写入。",
            )
            return
        self._start_artifact_save(*request)

    def _save_current_frame(self) -> None:
        if self.current_frame is None or self.current_analysis is None:
            return
        if self.save_thread is not None:
            self._append_log(
                "SAVE",
                "保存线程仍忙，本次保存请求未执行；当前显示帧未被误报为已保存。",
            )
            return
        self._start_artifact_save(
            self.current_frame,
            self.current_analysis,
            self.current_impulse_metrics,
        )

    def _start_artifact_save(
        self,
        frame: CaptureFrame,
        analysis: FrameAnalysis,
        impulse_metrics: Optional[ImpulseResponseMetrics],
    ) -> None:
        output = Path(self.output_edit.text().strip() or str(DEFAULT_OUTPUT))
        thread = QThread(self)
        worker = ArtifactSaveWorker(
            frame,
            analysis,
            output,
            impulse_metrics,
        )
        worker.moveToThread(thread)
        thread.started.connect(worker.run)
        worker.saved.connect(self._on_save_succeeded)
        worker.failed.connect(self._on_save_failed)
        worker.finished.connect(worker.deleteLater)
        worker.finished.connect(thread.quit)
        thread.finished.connect(self._on_save_finished)
        self.save_thread = thread
        self.save_worker = worker
        self.active_save_formal_key = (
            (frame.frame_id, frame.input_transaction_id)
            if impulse_metrics is not None
            else None
        )
        self.save_button.setEnabled(False)
        thread.start()

    @Slot(str)
    def _on_save_succeeded(self, stem: str) -> None:
        self._append_log(
            "SAVE",
            f"已保存 {stem}.csv / .npy / .png / .meta.txt；"
            "如为正式冲激，同时保存 _formal_impulse.png/.json/.txt、"
            "_formal_impulse_time.csv 和 _formal_impulse_frequency.csv",
        )

    @Slot(str)
    def _on_save_failed(self, message: str) -> None:
        if self.active_save_formal_key is not None:
            self.saved_formal_keys.discard(self.active_save_formal_key)
        self._append_log("ERROR", message)

    @Slot()
    def _on_save_finished(self) -> None:
        thread = self.save_thread
        self.save_thread = None
        self.save_worker = None
        self.active_save_formal_key = None
        if thread is not None:
            thread.deleteLater()
        self.save_button.setEnabled(self.current_frame is not None)
        if self.pending_formal_save is not None:
            frame, analysis, metrics = self.pending_formal_save
            self.pending_formal_save = None
            self._start_artifact_save(frame, analysis, metrics)

    @Slot(str)
    def _on_receiver_failed(self, message: str) -> None:
        if self.bit_true_pass_latched:
            self._append_log("WARN", f"PASS 锁定后的接收线程消息：{message}")
            return
        self.listener_pill.set_status("监听失败", "red")
        self._append_log("ERROR", message)
        if self.formal_flow_active:
            self._finish_formal_flow(f"一键测量未启动：监听失败 · {message}", "red")

    @Slot()
    def _on_receiver_finished(self) -> None:
        thread = self.receiver_thread
        self.receiver_thread = None
        self.receiver = None
        if thread is not None:
            thread.deleteLater()
        if self.formal_result_latched:
            self.listener_pill.set_status("已停止 · 正式冲激结果已锁定", "green")
        elif self.bit_true_pass_latched:
            self.listener_pill.set_status("已停止 · PASS 结果已锁定", "green")
        elif self.listener_pill.text() != "监听失败":
            self.listener_pill.set_status("未监听", "muted")
        self._set_controls_running(False)
        self._append_log(
            "INFO",
            "UDP 监听已停止；已判定结果保持锁定。"
            if self.bit_true_pass_latched or self.formal_result_latched
            else "UDP 监听已停止。",
        )
        if self.formal_flow_active and self.formal_flow_restart_receiver:
            self.formal_flow_restart_receiver = False
            family, mode = self.formal_flow_target or (0, 3)
            self.family_combo.setCurrentIndex(self.family_combo.findData(family))
            self.mode_combo.setCurrentIndex(self.mode_combo.findData(mode))
            self._set_formal_flow_stage("步骤 1/4：正在用正式测量目标重新监听…")
            QTimer.singleShot(0, self.start_capture)
        elif self.auto_apply_pending and self.auto_apply_restart_receiver:
            self.auto_apply_restart_receiver = False
            family, mode = self.auto_apply_target or (0, 3)
            self.family_combo.setCurrentIndex(self.family_combo.findData(family))
            self.mode_combo.setCurrentIndex(self.mode_combo.findData(mode))
            self.current_frame = None
            self.upload_status.set_status("正在按新工况自动恢复监听…", "amber")
            QTimer.singleShot(0, self._drive_auto_apply)
        elif self.follow_board_pending is not None:
            family, mode = self.follow_board_pending
            self.follow_board_pending = None
            self.family_combo.setCurrentIndex(self.family_combo.findData(family))
            self.mode_combo.setCurrentIndex(self.mode_combo.findData(mode))
            self.upload_family_combo.setCurrentIndex(
                self.upload_family_combo.findData(family)
            )
            self.upload_mode_combo.setCurrentIndex(
                self.upload_mode_combo.findData(mode)
            )
            self.current_frame = None
            self.listener_pill.set_status("正在按板上新工况恢复监听…", "amber")
            QTimer.singleShot(0, self.start_capture)

    def _refresh_activity_age(self) -> None:
        if self.last_packet_monotonic is None:
            return
        age = time.monotonic() - self.last_packet_monotonic
        if age < 1.0:
            return
        tone = "amber" if age < 5.0 else "muted"
        self.activity_pill.set_status(
            f"最近收到 FPGA 包 · {age:.1f}s 前", tone
        )

    def _append_log(self, level: str, message: str) -> None:
        stamp = time.strftime("%H:%M:%S")
        self.log.appendPlainText(f"{stamp}  {level:<6}  {message}")

    def closeEvent(self, event: QCloseEvent) -> None:
        self._save_settings()
        if self.upload_thread is not None:
            QMessageBox.warning(
                self,
                "上传事务仍在进行",
                "请等待当前 BEGIN/WAVE/COMMIT 事务结束后再关闭窗口；中途退出可能留下"
                "未提交的板端缓冲区。",
            )
            event.ignore()
            return
        if self.receiver is not None:
            self.receiver.stop()
        if self.receiver_thread is not None:
            self.receiver_thread.quit()
        if self.receiver_thread is not None and not self.receiver_thread.wait(1200):
            QMessageBox.warning(
                self,
                "接收线程仍在停止",
                "网络接收线程尚未退出，请稍后再次关闭窗口。",
            )
            event.ignore()
            return
        if self.save_thread is not None:
            self.save_thread.quit()
        if self.save_thread is not None and not self.save_thread.wait(3000):
            QMessageBox.warning(
                self,
                "结果仍在保存",
                "请等待当前 CSV/NPY/PNG 保存完成后再关闭。",
            )
            event.ignore()
            return
        event.accept()


def _apply_application_style(app: QApplication) -> None:
    app.setStyle("Fusion")
    palette = QPalette()
    palette.setColor(QPalette.ColorRole.Window, QColor(COLORS["bg"]))
    palette.setColor(QPalette.ColorRole.WindowText, QColor(COLORS["text"]))
    palette.setColor(QPalette.ColorRole.Base, QColor("#0a141b"))
    palette.setColor(QPalette.ColorRole.AlternateBase, QColor(COLORS["panel2"]))
    palette.setColor(QPalette.ColorRole.Text, QColor(COLORS["text"]))
    palette.setColor(QPalette.ColorRole.Button, QColor(COLORS["panel2"]))
    palette.setColor(QPalette.ColorRole.ButtonText, QColor(COLORS["text"]))
    palette.setColor(QPalette.ColorRole.Highlight, QColor(COLORS["cyan"]))
    palette.setColor(QPalette.ColorRole.HighlightedText, QColor(COLORS["bg"]))
    app.setPalette(palette)
    app.setStyleSheet(STYLE_SHEET)
    app.setFont(QFont("Microsoft YaHei UI", 9))


def main() -> int:
    # Keep a Python traceback in the VS Code terminal for ordinary unhandled
    # faults.  Native Qt failures are also recorded by Windows CrashDumps.
    faulthandler.enable(all_threads=True)
    app = QApplication(sys.argv)
    app.setApplicationName(APP_NAME)
    app.setOrganizationName("FPGA-Lab")
    _apply_application_style(app)
    window = MainWindow()
    window.show()
    return app.exec()


if __name__ == "__main__":
    raise SystemExit(main())
