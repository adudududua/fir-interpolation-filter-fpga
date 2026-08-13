from __future__ import annotations

import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


def load_font(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    candidates = [
        Path("C:/Windows/Fonts/msyhbd.ttc" if bold else "C:/Windows/Fonts/msyh.ttc"),
        Path("C:/Windows/Fonts/simhei.ttf" if bold else "C:/Windows/Fonts/simsun.ttc"),
    ]
    for candidate in candidates:
        if candidate.exists():
            return ImageFont.truetype(str(candidate), size=size)
    return ImageFont.load_default()


def draw_text(draw, xy, value, font, fill="#202020", anchor="la") -> None:
    draw.text(xy, value, font=font, fill=fill, anchor=anchor)


def bar(draw, left, y, width, value, maximum, color, font) -> None:
    draw.rounded_rectangle((left, y, left + width, y + 54), radius=12, fill="#E9EEF5")
    filled = round(width * value / maximum)
    draw.rounded_rectangle((left, y, left + filled, y + 54), radius=12, fill=color)
    draw_text(draw, (left + filled - 16, y + 27), str(value), font, fill="#FFFFFF", anchor="rm")


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit("usage: create_matched_ooc_comparison_figure.py <output.png>")
    output = Path(sys.argv[1])
    output.parent.mkdir(parents=True, exist_ok=True)

    width, height = 2400, 1420
    image = Image.new("RGB", (width, height), "#FFFFFF")
    draw = ImageDraw.Draw(image)
    title = load_font(50, True)
    subtitle = load_font(27)
    panel_title = load_font(35, True)
    label = load_font(28, True)
    body = load_font(25)
    small = load_font(22)

    draw_text(draw, (1200, 58), "218-LUT与239-LUT板测版本的同口径资源比较", title, anchor="ma")
    draw_text(
        draw,
        (1200, 118),
        "核心：精确参数快照的Vivado 2025.2 OOC post-route；完整系统：对应板级routed checkpoint",
        subtitle,
        fill="#4D4D4D",
        anchor="ma",
    )

    variants = [
        {
            "x": 120,
            "name": "218-LUT / 4-DSP板测版",
            "mode": "CIC_INTEGRATOR_DSP_MODE=2",
            "core": (190, 279, 4, 3),
            "board": (218, 365, 4, 4),
            "timing": "+150.943 / +0.069 ns",
            "color": "#4472C4",
        },
        {
            "x": 1230,
            "name": "239-LUT / 3-DSP板测版",
            "mode": "CIC_INTEGRATOR_DSP_MODE=1",
            "core": (212, 302, 3, 3),
            "board": (239, 388, 3, 4),
            "timing": "+151.611 / +0.099 ns",
            "color": "#ED7D31",
        },
    ]
    for item in variants:
        left = item["x"]
        right = left + 1050
        draw.rounded_rectangle((left, 190, right, 905), radius=24, fill="#F8FAFD", outline="#B7C9E2", width=3)
        draw_text(draw, ((left + right) // 2, 235), item["name"], panel_title, anchor="ma")
        draw_text(draw, ((left + right) // 2, 285), item["mode"], small, fill="#555555", anchor="ma")

        draw_text(draw, (left + 60, 350), "独立滤波器核心OOC", label, anchor="ls")
        core_lut, core_ff, core_dsp, core_ram = item["core"]
        bar(draw, left + 60, 390, 700, core_lut, 240, item["color"], body)
        draw_text(draw, (left + 790, 417), "LUT", body, anchor="lm")
        bar(draw, left + 60, 475, 700, core_ff, 400, item["color"], body)
        draw_text(draw, (left + 790, 502), "FF", body, anchor="lm")
        draw_text(draw, (left + 60, 575), f"DSP48E1：{core_dsp}", body, anchor="ls")
        draw_text(draw, (left + 360, 575), f"RAMB18E1：{core_ram}", body, anchor="ls")
        draw_text(draw, (left + 60, 625), f"内部WNS/WHS：{item['timing']}", body, anchor="ls")
        draw_text(draw, (left + 60, 670), "DRC Error：0；重复实现2/2一致", body, anchor="ls")

        board_lut, board_ff, board_dsp, board_ram = item["board"]
        draw.line((left + 60, 725, right - 60, 725), fill="#CED7E2", width=2)
        draw_text(draw, (left + 60, 775), "完整板级post-route", label, anchor="ls")
        draw_text(
            draw,
            (left + 60, 830),
            f"{board_lut} LUT / {board_ff} FF / {board_dsp} DSP / {board_ram} RAMB18E1",
            body,
            anchor="ls",
        )

    callout_top = 950
    draw.rounded_rectangle((120, callout_top, 2280, 1370), radius=24, fill="#EEF5EA", outline="#70AD47", width=3)
    draw_text(draw, (170, callout_top + 55), "同口径结论", panel_title, fill="#2F612B", anchor="ls")
    lines = [
        "核心OOC（239−218）：+22 LUT、+23 FF、−1 DSP、0 RAMB18E1。",
        "完整系统（239−218）：+21 LUT、+23 FF、−1 DSP、0 RAMB18E1；两版均已通过物理板功能验证。",
        "两组数字边界独立：OOC用于核心面积；板级routed checkpoint用于完整系统面积，不以二者相减推导外围资源。",
        "整板扁平化网表的物理单元归属仅用于定位差异集中于CIC映射，不作为模块独立面积。",
        "时序限定：上列为内部寄存器路径；零I/O延迟OOC边界各有1条−0.845 ns端口到寄存器hold，完整接口以整板签核为准。",
    ]
    for index, line in enumerate(lines):
        draw_text(draw, (180, callout_top + 105 + index * 55), line, small, fill="#263A25", anchor="ls")

    image.save(output, format="PNG", optimize=True, dpi=(220, 220))
    print(output)


if __name__ == "__main__":
    main()
