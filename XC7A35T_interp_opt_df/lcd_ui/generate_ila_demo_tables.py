#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
=============================================================
文件名       : generate_ila_demo_tables.py
功能简述     : 生成 ILA 镜像抑制演示所需的相干测试信号与参考表。
              输入表为 44.1kHz 下 4.1kHz+15kHz、441 点周期；
              参考表为 88.2kHz 下 15kHz/40kHz 正交参考、441 点周期。

设计作者     : kafeizizi
创建日期     : 2026-07-19
版本         : V2018.3
开发工具     : Python 3
修订记录     :
              2026-07-19：新增 ILA 镜像抑制演示查找表。
=============================================================
"""

from math import pi, sin, cos
from pathlib import Path


INPUT_FS = 44_100
STAGE1_FS = 88_200
INPUT_DEPTH = 441
REFERENCE_DEPTH = 441
DATA_WIDTH = 24
REFERENCE_WIDTH = 16

# 两个输入分量各为 0.20FS，叠加峰值不超过 0.40FS。
TONE_PEAK = round(((1 << (DATA_WIDTH - 1)) - 1) * 0.20)
REFERENCE_PEAK = (1 << (REFERENCE_WIDTH - 1)) - 1


def twos(value: int, width: int) -> int:
    return value & ((1 << width) - 1)


def main() -> None:
    output_dir = (
        Path(__file__).resolve().parents[1]
        / "XC7A35T_interp.srcs"
        / "sources_1"
        / "new"
    )
    output_dir.mkdir(parents=True, exist_ok=True)

    input_path = output_dir / "ila_demo_mix_4k1_15k_441.mem"
    reference_path = output_dir / "ila_demo_refs_15k_40k_441.mem"

    input_samples = []
    for index in range(INPUT_DEPTH):
        sample = round(
            TONE_PEAK * sin(2.0 * pi * 4_100 * index / INPUT_FS)
            + TONE_PEAK * sin(2.0 * pi * 15_000 * index / INPUT_FS)
        )
        input_samples.append(sample)

    input_path.write_text(
        "\n".join(f"{twos(value, DATA_WIDTH):06X}" for value in input_samples)
        + "\n",
        encoding="ascii",
    )

    reference_words = []
    for index in range(REFERENCE_DEPTH):
        cos_15k = round(
            REFERENCE_PEAK * cos(2.0 * pi * 15_000 * index / STAGE1_FS)
        )
        sin_15k = round(
            REFERENCE_PEAK * sin(2.0 * pi * 15_000 * index / STAGE1_FS)
        )
        cos_40k = round(
            REFERENCE_PEAK * cos(2.0 * pi * 40_000 * index / STAGE1_FS)
        )
        sin_40k = round(
            REFERENCE_PEAK * sin(2.0 * pi * 40_000 * index / STAGE1_FS)
        )
        word = (
            (twos(cos_15k, REFERENCE_WIDTH) << 48)
            | (twos(sin_15k, REFERENCE_WIDTH) << 32)
            | (twos(cos_40k, REFERENCE_WIDTH) << 16)
            | twos(sin_40k, REFERENCE_WIDTH)
        )
        reference_words.append(word)

    reference_path.write_text(
        "\n".join(f"{value:016X}" for value in reference_words) + "\n",
        encoding="ascii",
    )

    assert len(input_samples) == INPUT_DEPTH
    assert len(reference_words) == REFERENCE_DEPTH
    assert max(input_samples) <= (1 << (DATA_WIDTH - 1)) - 1
    assert min(input_samples) >= -(1 << (DATA_WIDTH - 1))

    print(f"Generated {input_path} ({len(input_samples)} samples)")
    print(f"Generated {reference_path} ({len(reference_words)} references)")
    print(
        f"Input range={min(input_samples)}..{max(input_samples)}, "
        f"component peak={TONE_PEAK}"
    )


if __name__ == "__main__":
    main()
