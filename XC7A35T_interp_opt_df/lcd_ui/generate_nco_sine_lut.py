#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
=============================================================
文件名       : generate_nco_sine_lut.py
功能简述     : 生成可调音频 NCO 使用的 256 点、24bit 正弦查找表。
              查找表峰值为 0.50FS，输出为 24bit 二进制补码十六进制。
设计作者     : kafeizizi
创建日期     : 2026-07-18
版本         : V2018.3
开发工具     : Python 3 / Vivado 2018.3
修订记录     :
              2026-07-18：新增 1kHz～20kHz 可调 NCO 正弦查找表生成脚本。
=============================================================
"""

from math import pi, sin
from pathlib import Path


LUT_DEPTH = 256
DATA_WIDTH = 24
PEAK_VALUE = 4_194_303


def to_twos_complement_hex(value: int) -> str:
    """把有符号整数转换成 DATA_WIDTH 位补码十六进制字符串。"""
    mask = (1 << DATA_WIDTH) - 1
    return f"{value & mask:0{DATA_WIDTH // 4}X}"


def main() -> None:
    output_path = (
        Path(__file__).resolve().parents[1]
        / "XC7A35T_interp.srcs"
        / "sources_1"
        / "new"
        / "nco_sine_0p50fs_256.mem"
    )

    samples = [
        round(PEAK_VALUE * sin(2.0 * pi * index / LUT_DEPTH))
        for index in range(LUT_DEPTH)
    ]
    output_path.write_text(
        "\n".join(to_twos_complement_hex(sample) for sample in samples) + "\n",
        encoding="ascii",
    )

    print(f"Generated {output_path}")
    print(f"Samples={len(samples)}, min={min(samples)}, max={max(samples)}")


if __name__ == "__main__":
    main()
