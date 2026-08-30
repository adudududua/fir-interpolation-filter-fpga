#!/usr/bin/env python3
"""接收并验证 FPGA 通过 UDP 发送的 DAC24 抓取数据。

FPGA 将每帧 4096 个样本拆成 16 个网络包，并广播到 UDP 4000 端口。
本程序会重组完整帧、检查网络包连续性、导出 CSV/NPY、绘制时域图和 FFT 图，
还可以选择与文本、CSV 或 NPY 格式的 RTL 参考向量进行逐位一致性比较。
"""
from __future__ import annotations

import argparse
import csv
import socket
import struct
import sys
import time
from dataclasses import dataclass, field
from pathlib import Path

MAGIC = b"DAC2"
HEADER = struct.Struct("<4sBBBBIIHBBHI6s")
MODE_NAMES = {0: "1x", 1: "4x", 2: "8x", 3: "128x"}
MODE_CODES = {name: code for code, name in MODE_NAMES.items()}


class ChineseHelpFormatter(argparse.HelpFormatter):
    """将 argparse 自动生成的用法标题改为中文。"""

    def _format_usage(self, usage, actions, groups, prefix):
        return super()._format_usage(usage, actions, groups, prefix or "用法：")


@dataclass
class CaptureFrame:
    frame_id: int
    flags: int
    packet_count: int
    total_samples: int
    start_sample_index: int
    packets: dict[int, list[int]] = field(default_factory=dict)
    duplicate_packets: int = 0

    @property
    def complete(self) -> bool:
        return set(self.packets) == set(range(self.packet_count))

    def samples(self) -> list[int]:
        out: list[int] = []
        for index in range(self.packet_count):
            if index not in self.packets:
                raise ValueError(f"缺少编号为 {index} 的网络包")
            out.extend(self.packets[index])
        if len(out) != self.total_samples:
            raise ValueError(
                f"实际样本数 {len(out)} 与包头声明的 {self.total_samples} 不一致")
        return out


def decode_s24le(payload: bytes) -> list[int]:
    if len(payload) % 3:
        raise ValueError("24 位数据区的字节数不是 3 的整数倍")
    values: list[int] = []
    for offset in range(0, len(payload), 3):
        value = payload[offset] | payload[offset + 1] << 8 | payload[offset + 2] << 16
        if value & 0x800000:
            value -= 1 << 24
        values.append(value)
    return values


def parse_packet(data: bytes) -> tuple[dict[str, int], list[int]]:
    if len(data) < HEADER.size:
        raise ValueError("DAC24 网络包长度不足")
    fields = HEADER.unpack_from(data)
    magic, version, flags, packet_index, packet_count, frame_id, sample_offset, \
        samples_in_packet, sample_bits, sample_format, total_samples, \
        start_sample_index, _ = fields
    if magic != MAGIC or version != 1:
        raise ValueError("不是 DAC24 v1 网络包")
    if sample_bits != 24 or sample_format != 1:
        raise ValueError("不支持的样本格式")
    if packet_count != 16 or packet_index >= packet_count:
        raise ValueError("DAC24 v1 网络包编号或总包数无效")
    if samples_in_packet != 256 or total_samples != 4096:
        raise ValueError("DAC24 v1 帧的样本数量配置无效")
    if sample_offset != packet_index * 256:
        raise ValueError("DAC24 v1 样本偏移量无效")
    samples = decode_s24le(data[HEADER.size:])
    if len(samples) != samples_in_packet:
        raise ValueError("数据区的样本数与包头不一致")
    return {
        "flags": flags,
        "packet_index": packet_index,
        "packet_count": packet_count,
        "frame_id": frame_id,
        "sample_offset": sample_offset,
        "samples_in_packet": samples_in_packet,
        "total_samples": total_samples,
        "start_sample_index": start_sample_index,
    }, samples


def receive_frame(bind: str, port: int, timeout: float,
                  max_reference_samples: int | None = None,
                  expected_family_48k: int | None = None,
                  expected_mode: int | None = None) -> CaptureFrame:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_RCVBUF, 1 << 20)
    try:
        sock.bind((bind, port))
    except OSError as exc:
        if getattr(exc, "winerror", None) == 10049:
            shown = bind or "0.0.0.0"
            raise OSError(
                f"电脑当前没有配置可绑定的地址 {shown}。请把有线网卡设置为 "
                "192.168.1.20/24，或改用 --bind 0.0.0.0 监听全部网卡"
            ) from exc
        raise
    sock.settimeout(0.5)
    deadline = time.monotonic() + timeout
    # 把来源和完整帧描述也纳入键值，避免 FPGA 重新下载后
    # frame_id 从零开始时，与上一个运行周期的残留包混合。
    frames: dict[tuple[str, int, int, int, int, int], CaptureFrame] = {}
    print(f"正在监听 {bind or '0.0.0.0'}:{port}，等待 FPGA 数据……")
    if expected_family_48k is not None or expected_mode is not None:
        wanted_family = (48000 if expected_family_48k else 44100
                         if expected_family_48k is not None else "任意")
        wanted_mode = (MODE_NAMES[expected_mode]
                       if expected_mode is not None else "任意")
        print(f"目标帧：{wanted_family} Hz/{wanted_mode}")
    while time.monotonic() < deadline:
        try:
            data, peer = sock.recvfrom(2048)
        except socket.timeout:
            continue
        try:
            header, samples = parse_packet(data)
        except ValueError:
            continue
        frame_id = header["frame_id"]
        frame_key = (peer[0], frame_id, header["flags"], header["packet_count"],
                     header["total_samples"], header["start_sample_index"])
        frame = frames.setdefault(
            frame_key,
            CaptureFrame(frame_id, header["flags"], header["packet_count"],
                         header["total_samples"], header["start_sample_index"]),
        )
        # UDP 中途接入时可能留下不完整帧；只保留最近的少量描述符。
        while len(frames) > 64:
            oldest_key = next(iter(frames))
            if oldest_key == frame_key:
                break
            del frames[oldest_key]
        index = header["packet_index"]
        descriptor = (header["flags"], header["packet_count"],
                      header["total_samples"], header["start_sample_index"])
        expected_descriptor = (frame.flags, frame.packet_count,
                               frame.total_samples, frame.start_sample_index)
        if descriptor != expected_descriptor:
            raise ValueError(f"帧 {frame_id}：各网络包的描述信息不一致")
        if index in frame.packets:
            if frame.packets[index] != samples:
                raise ValueError(f"帧 {frame_id}：重复包 {index} 的内容发生冲突")
            frame.duplicate_packets += 1
        else:
            frame.packets[index] = samples
        print(f"帧号={frame_id}，网络包={index + 1}/{frame.packet_count}，来源={peer[0]}")
        if frame.complete:
            frame_family_48k = (frame.flags >> 2) & 1
            frame_mode = frame.flags & 0x3
            if ((expected_family_48k is not None
                 and frame_family_48k != expected_family_48k)
                    or (expected_mode is not None
                        and frame_mode != expected_mode)):
                actual_family = 48000 if frame_family_48k else 44100
                wanted_family = (48000 if expected_family_48k else 44100
                                 if expected_family_48k is not None else "任意")
                wanted_mode = (MODE_NAMES[expected_mode]
                               if expected_mode is not None else "任意")
                print(
                    f"已跳过帧 {frame_id}：当前是 {actual_family} Hz/"
                    f"{MODE_NAMES[frame_mode]}，正在等待 "
                    f"{wanted_family} Hz/{wanted_mode}……"
                )
                del frames[frame_key]
                continue
            reference_stop = frame.start_sample_index + frame.total_samples
            if (max_reference_samples is not None
                    and reference_stop > max_reference_samples):
                print(
                    f"已跳过帧 {frame_id}：它需要参考区间 "
                    f"[{frame.start_sample_index}:{reference_stop}]，但参考向量只有 "
                    f"{max_reference_samples} 个样本。请用按键先切到另一个采样率族，"
                    "再切回目标采样率族，程序会继续等待新起始的帧……"
                )
                del frames[frame_key]
                continue
            return frame
    raise TimeoutError(f"在 {timeout:g} 秒内没有收到完整数据帧")


def load_reference(path: Path) -> list[int]:
    if path.suffix.lower() == ".npy":
        import numpy as np
        return np.load(path).astype(np.int64).reshape(-1).tolist()
    values: list[int] = []
    for line_number, line in enumerate(
            path.read_text(encoding="utf-8").splitlines(), start=1):
        if line.lstrip().startswith("#"):
            continue
        token = line.strip().split(",")[-1].strip()
        if not token:
            continue
        try:
            value = int(token, 0)
        except ValueError as exc:
            if not values and line_number == 1:
                continue
            raise ValueError(
                f"{path}:{line_number}：参考样本 {token!r} 不是有效整数") from exc
        if not -(1 << 23) <= value < (1 << 23):
            raise ValueError(
                f"{path}:{line_number}：样本 {value} 超出 24 位有符号数范围")
        values.append(value)
    return values


def export(frame: CaptureFrame, samples: list[int], out_dir: Path,
           reference: Path | None) -> int:
    import numpy as np

    out_dir.mkdir(parents=True, exist_ok=True)
    mode = frame.flags & 0x3
    family_48k = (frame.flags >> 2) & 1
    base_rate = 48000 if family_48k else 44100
    rate = base_rate * (128 if mode == 3 else 8 if mode == 2 else 4 if mode == 1 else 1)
    stem = (f"frame_{frame.frame_id:08d}_start_{frame.start_sample_index}_"
            f"{base_rate}_{MODE_NAMES[mode]}")
    array = np.asarray(samples, dtype=np.int32)
    np.save(out_dir / f"{stem}.npy", array)
    with (out_dir / f"{stem}.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream)
        writer.writerow(["sample_index", "signed_24bit"])
        writer.writerows((frame.start_sample_index + index, value)
                         for index, value in enumerate(samples))

    mismatch_count = 0
    if reference:
        expected = np.asarray(load_reference(reference), dtype=np.int64)
        start = frame.start_sample_index
        stop = start + len(array)
        if stop > len(expected):
            raise ValueError(
                f"RTL 参考文件只有 {len(expected)} 个样本，但当前帧需要区间 [{start}:{stop}]")
        aligned = expected[start:stop]
        count = len(array)
        errors = array.astype(np.int64) - aligned
        mismatch_count = int(np.count_nonzero(errors))
        max_error = int(np.max(np.abs(errors))) if count else 0
        print(f"逐位比较：参考区间[{start}:{stop}]，比较样本数={count}，"
              f"不一致样本数={mismatch_count}，最大绝对误差={max_error} LSB")

    try:
        import matplotlib
        # 上位机只需把图保存为 PNG，不需要创建桌面窗口。强制使用无界面
        # 后端，可避免 Miniconda/远程环境缺少 Tk 时导出失败。
        matplotlib.use("Agg")
        import matplotlib.pyplot as plt
        plt.rcParams["font.sans-serif"] = ["Microsoft YaHei", "SimHei", "DejaVu Sans"]
        plt.rcParams["axes.unicode_minus"] = False
        normalized = array.astype(np.float64) / (1 << 23)
        window = np.hanning(len(normalized))
        spectrum = np.fft.rfft((normalized - normalized.mean()) * window)
        coherent_gain = window.sum() / len(window)
        dbfs = 20 * np.log10(np.maximum(np.abs(spectrum) / (len(window) * coherent_gain / 2), 1e-15))
        frequency = np.fft.rfftfreq(len(normalized), 1.0 / rate)
        fig, axes = plt.subplots(2, 1, figsize=(11, 7))
        axes[0].plot(np.arange(min(512, len(array))) / rate, normalized[:512])
        axes[0].set(xlabel="时间（秒）", ylabel="满量程归一化幅度", title=f"DAC24 {base_rate} Hz {MODE_NAMES[mode]}")
        axes[0].grid(True)
        axes[1].plot(frequency, dbfs)
        axes[1].set(xlabel="频率（Hz）", ylabel="dBFS", ylim=(-160, 5))
        axes[1].grid(True)
        fig.tight_layout()
        fig.savefig(out_dir / f"{stem}.png", dpi=150)
        plt.close(fig)
    except ImportError:
        print("未安装 matplotlib；CSV/NPY 数据已经正常导出，但不会生成图片")

    print(f"已将 {len(samples)} 个样本保存到 {out_dir.resolve()} "
          f"（起始样本索引={frame.start_sample_index}，重复包数={frame.duplicate_packets}）")
    return mismatch_count


def main() -> int:
    parser = argparse.ArgumentParser(
        add_help=False,
        formatter_class=ChineseHelpFormatter,
        description="接收 FPGA 广播的 DAC24 UDP 数据，并可与 RTL 参考数据逐位比较")
    parser._optionals.title = "选项"
    parser.add_argument("-h", "--help", action="help", help="显示本帮助信息并退出")
    parser.add_argument("--bind", default="", help="本机有线网卡 IPv4 地址；默认监听所有网卡")
    parser.add_argument("--port", type=int, default=4000, help="UDP 监听端口（默认：4000）")
    parser.add_argument("--timeout", type=float, default=30.0, help="等待完整数据帧的超时时间，单位为秒（默认：30）")
    parser.add_argument("--output", type=Path, default=Path("capture_results"), help="结果保存目录（默认：capture_results）")
    parser.add_argument("--reference", type=Path, help="RTL 参考向量文件，支持 .txt/.csv/.npy")
    parser.add_argument("--expected-family", type=int, choices=(44100, 48000),
                        help="只接收指定的采样率族：44100 或 48000")
    parser.add_argument("--expected-mode", choices=tuple(MODE_CODES),
                        help="只接收指定模式：1x、4x、8x 或 128x")
    args = parser.parse_args()
    try:
        reference_samples = len(load_reference(args.reference)) if args.reference else None
        expected_family_48k = (None if args.expected_family is None
                               else int(args.expected_family == 48000))
        expected_mode = (None if args.expected_mode is None
                         else MODE_CODES[args.expected_mode])
        frame = receive_frame(args.bind, args.port, args.timeout, reference_samples,
                              expected_family_48k, expected_mode)
        mismatches = export(frame, frame.samples(), args.output, args.reference)
        return 2 if mismatches else 0
    except ModuleNotFoundError as exc:
        print("错误：缺少 Python 依赖，请执行 "
              "'python -m pip install -r network_capture/host/requirements.txt' "
              f"({exc})", file=sys.stderr)
        return 1
    except (OSError, ValueError, TimeoutError) as exc:
        print(f"错误：{exc}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    raise SystemExit(main())
