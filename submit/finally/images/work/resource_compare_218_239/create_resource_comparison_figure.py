from __future__ import annotations

import csv
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


COLORS = {
    "FIR1级": "#4472C4",
    "FIR2/3级": "#5B9BD5",
    "FIR共享系数存储": "#A5A5A5",
    "2→4倍桥接量化": "#ED7D31",
    "16倍CIC插值": "#70AD47",
    "滤波器核心跨级/共享逻辑": "#FFC000",
    "核心—外围接口共享逻辑": "#8064A2",
    "测试音频ROM": "#9E480E",
    "音频公共封装/DAC": "#00B0F0",
    "按键与模式控制": "#C00000",
    "板级顶层控制": "#7F7F7F",
    "外围跨模块共享逻辑": "#BFBFBF",
}

DRAW_ORDER = list(COLORS)


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    candidates = [
        Path("C:/Windows/Fonts/msyhbd.ttc" if bold else "C:/Windows/Fonts/msyh.ttc"),
        Path("C:/Windows/Fonts/simhei.ttf" if bold else "C:/Windows/Fonts/simsun.ttc"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size=size)
    return ImageFont.load_default()


def read_data(path: Path) -> dict[str, dict[str, dict[str, int]]]:
    data: dict[str, dict[str, dict[str, int]]] = {}
    with path.open("r", encoding="utf-8-sig", newline="") as handle:
        for row in csv.DictReader(handle):
            data.setdefault(row["variant"], {})[row["module"]] = {
                key: int(row[key]) for key in ("LUT", "FF", "DSP48E1", "RAMB18E1")
            }
    return data


def text(draw: ImageDraw.ImageDraw, xy: tuple[int, int], value: str, font, fill="#222222", anchor="la") -> None:
    draw.text(xy, value, font=font, fill=fill, anchor=anchor)


def main() -> None:
    if len(sys.argv) != 3:
        raise SystemExit("usage: create_resource_comparison_figure.py <distribution.csv> <output.png>")
    data = read_data(Path(sys.argv[1]))
    output = Path(sys.argv[2])
    output.parent.mkdir(parents=True, exist_ok=True)

    width, height = 2400, 1460
    image = Image.new("RGB", (width, height), "#FFFFFF")
    draw = ImageDraw.Draw(image)
    title_font = load_font(50, True)
    subtitle_font = load_font(28)
    section_font = load_font(32, True)
    label_font = load_font(27, True)
    value_font = load_font(24)
    small_font = load_font(21)

    text(draw, (1200, 62), "218-LUT与239-LUT板测版本的实现后资源归属", title_font, anchor="ma")
    text(
        draw,
        (1200, 122),
        "Vivado 2025.2 routed checkpoint；LUT按物理BEL计数，跨层次共享逻辑单列",
        subtitle_font,
        fill="#4D4D4D",
        anchor="ma",
    )

    variants = [("LUT218", "218 LUT / 365 FF / 4 DSP / 4 RAMB18"), ("LUT239", "239 LUT / 388 FF / 3 DSP / 4 RAMB18")]
    panel_top = 205
    panel_width = 1035
    for index, (variant, headline) in enumerate(variants):
        left = 120 + index * 1125
        right = left + panel_width
        draw.rounded_rectangle((left, panel_top, right, 900), radius=24, outline="#B7C9E2", width=3, fill="#F8FAFD")
        text(draw, ((left + right) // 2, panel_top + 44), headline, section_font, anchor="ma")

        bar_left, bar_right = left + 55, right - 55
        bar_width = bar_right - bar_left
        for bar_index, resource in enumerate(("LUT", "FF")):
            y = panel_top + 130 + bar_index * 165
            total = sum(values[resource] for values in data[variant].values())
            text(draw, (bar_left, y - 20), f"{resource}模块分布（总计{total}）", label_font, anchor="ls")
            cursor = bar_left
            for module in DRAW_ORDER:
                value = data[variant].get(module, {}).get(resource, 0)
                if value <= 0:
                    continue
                segment = round(bar_width * value / total)
                if module == DRAW_ORDER[-1]:
                    segment = bar_right - cursor
                draw.rectangle((cursor, y, cursor + segment, y + 70), fill=COLORS[module], outline="#FFFFFF", width=2)
                if segment >= 62:
                    text(draw, (cursor + segment // 2, y + 35), str(value), small_font, fill="#FFFFFF" if module not in {"滤波器核心跨级/共享逻辑", "外围跨模块共享逻辑"} else "#333333", anchor="mm")
                cursor += segment

        core = data[variant]
        y0 = panel_top + 475
        rows = [
            ("FIR1级", core.get("FIR1级", {})),
            ("FIR2/3级", core.get("FIR2/3级", {})),
            ("2→4倍桥接量化", core.get("2→4倍桥接量化", {})),
            ("16倍CIC插值", core.get("16倍CIC插值", {})),
        ]
        text(draw, (bar_left, y0 - 12), "滤波器核心主要子模块", label_font, anchor="ls")
        for row_index, (module, values) in enumerate(rows):
            y = y0 + 36 + row_index * 45
            draw.rectangle((bar_left, y - 10, bar_left + 18, y + 8), fill=COLORS[module])
            text(draw, (bar_left + 30, y), module, value_font, anchor="lm")
            text(
                draw,
                (bar_left + 330, y),
                f"{values.get('LUT', 0)} LUT / {values.get('FF', 0)} FF / {values.get('DSP48E1', 0)} DSP / {values.get('RAMB18E1', 0)} RAMB18",
                value_font,
                fill="#333333",
                anchor="lm",
            )

    legend_y = 960
    text(draw, (120, legend_y), "模块颜色", label_font, anchor="ls")
    x, y = 120, legend_y + 38
    for module in DRAW_ORDER:
        label_width = draw.textlength(module, font=small_font) + 64
        if x + label_width > width - 120:
            x = 120
            y += 46
        draw.rectangle((x, y - 13, x + 24, y + 11), fill=COLORS[module])
        text(draw, (x + 34, y), module, small_font, anchor="lm")
        x += int(label_width)

    callout_top = 1095
    draw.rounded_rectangle((120, callout_top, 2280, 1385), radius=24, fill="#EEF5EA", outline="#70AD47", width=3)
    text(draw, (170, callout_top + 52), "定量差分与结构解释", section_font, fill="#2F612B", anchor="ls")
    lines = [
        "239→218：整板LUT减少21、Slice Register减少23，同时DSP增加1；4个RAMB18E1保持不变。",
        "核心变化位于16倍CIC：LUT 57→34、FF 132→109、DSP 1→2，正好解释−23 LUT、−23 FF与+1 DSP。",
        "FIR1/2/3的DSP与BRAM配置保持不变；其LUT仅出现−1/+0的布局映射微差，桥接量化出现+1 LUT，",
        "核心—外围接口共享逻辑出现+2 LUT，最终形成整板−21 LUT；WNS仍分别为+45.279 ns与+44.703 ns。",
    ]
    for i, line in enumerate(lines):
        text(draw, (180, callout_top + 102 + i * 47), line, value_font, fill="#263A25", anchor="ls")

    image.save(output, format="PNG", optimize=True, dpi=(220, 220))
    print(output)


if __name__ == "__main__":
    main()
