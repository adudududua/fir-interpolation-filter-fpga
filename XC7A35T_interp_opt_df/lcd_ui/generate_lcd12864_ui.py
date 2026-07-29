#=============================================================
# 文件名       : generate_lcd12864_ui.py
# 脚本名       : generate_lcd12864_ui
# 功能简述     : 生成 12864T 液晶使用的单色图形界面 ROM。
#                输出 1x/4x/8x/128x 四档页面和一个 ILA 镜像
#                抑制页面，共 5 x 1024 byte、逐行 MSB first。
#
# 设计作者     : kafeizizi
# 创建日期     : 2026-07-18
# 版本         : V2018.3
# 开发工具     : Python / Pillow
# 修订记录     :
#                2026-07-18：新增四档倍率、采样率、路径节点与
#                            SW1～SW8 映射界面生成。
#                2026-07-18：针对液晶倒装，输出 ROM 前将整屏
#                            旋转 180°，物理观看方向保持正向。
#                2026-07-18：更新 SW1～SW8 功能说明，并为控制器
#                            动态叠加输入频率与 AUTO 状态预留区域。
#                2026-07-19：新增 4.1kHz+15kHz ILA 镜像抑制页面，
#                            预留四条幅值柱和衰减数值动态区域。
#=============================================================

from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[1]
OUT_MEM = ROOT / "XC7A35T_interp.srcs" / "sources_1" / "new" / "lcd12864_ui.mem"
PREVIEW_DIR = Path(__file__).resolve().parent / "previews"

FONT_CN = Path(r"C:\Windows\Fonts\msyh.ttc")
FONT_CN_BOLD = Path(r"C:\Windows\Fonts\msyhbd.ttc")
FONT_MONO = Path(r"C:\Windows\Fonts\consola.ttf")
FONT_MONO_BOLD = Path(r"C:\Windows\Fonts\consolab.ttf")

# 场景功能板的12864液晶为180°倒装。此开关只旋转写入ROM的数据，
# 设计源图和正常观看预览仍保持正向，便于后续修改界面。
ROTATE_180_FOR_PANEL = True

MODES = (
    {"badge": "1X", "name": "原始直通", "rate": "44.1 kHz", "nodes": 1},
    {"badge": "4X", "name": "二级FIR", "rate": "176.4 kHz", "nodes": 2},
    {"badge": "8X", "name": "补偿FIR", "rate": "352.8 kHz", "nodes": 3},
    {"badge": "128X", "name": "FIR+CIC", "rate": "5.6448 MHz", "nodes": 4},
)

GLYPHS_5X7 = {
    "0": ("01110", "10001", "10011", "10101", "11001", "10001", "01110"),
    "1": ("00100", "01100", "00100", "00100", "00100", "00100", "01110"),
    "2": ("01110", "10001", "00001", "00010", "00100", "01000", "11111"),
    "3": ("11110", "00001", "00001", "01110", "00001", "00001", "11110"),
    "4": ("00010", "00110", "01010", "10010", "11111", "00010", "00010"),
    "5": ("11111", "10000", "10000", "11110", "00001", "00001", "11110"),
    "6": ("01110", "10000", "10000", "11110", "10001", "10001", "01110"),
    "7": ("11111", "00001", "00010", "00100", "01000", "01000", "01000"),
    "8": ("01110", "10001", "10001", "01110", "10001", "10001", "01110"),
    "9": ("01110", "10001", "10001", "01111", "00001", "00001", "01110"),
    "A": ("01110", "10001", "10001", "11111", "10001", "10001", "10001"),
}


def font(path: Path, size: int) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(str(path), size=size)


def text_width(draw: ImageDraw.ImageDraw, text: str, selected_font: ImageFont.ImageFont) -> int:
    box = draw.textbbox((0, 0), text, font=selected_font)
    return box[2] - box[0]


def centered_text(
    draw: ImageDraw.ImageDraw,
    y: int,
    text: str,
    selected_font: ImageFont.ImageFont,
    fill: int,
    left: int = 0,
    right: int = 127,
) -> None:
    x = left + ((right - left + 1) - text_width(draw, text, selected_font)) // 2
    draw.text((x, y), text, font=selected_font, fill=fill, stroke_width=0)


def make_page(mode_index: int) -> Image.Image:
    cfg = MODES[mode_index]
    image = Image.new("1", (128, 64), 0)
    draw = ImageDraw.Draw(image)

    # Inverted title bar.
    draw.rectangle((0, 0, 127, 10), fill=1)
    centered_text(draw, -1, "FIR 插值滤波演示", font(FONT_CN_BOLD, 10), 0)

    # Current-mode badge.
    draw.rounded_rectangle((2, 13, 50, 41), radius=4, outline=1, width=1)
    badge_size = 21 if len(cfg["badge"]) <= 2 else 16
    centered_text(
        draw,
        14 if badge_size == 21 else 17,
        cfg["badge"],
        font(FONT_MONO_BOLD, badge_size),
        1,
        3,
        49,
    )

    # Exact output rate and a blank dynamic input-frequency field. The two
    # digits at x=72/80 and AUTO marker at x=120 are overlaid by RTL so the
    # LCD follows key presses and automatic sweeping without rebuilding ROM.
    draw.text((55, 13), cfg["rate"], font=font(FONT_MONO, 9), fill=1)
    draw.text((55, 25), "IN:", font=font(FONT_MONO_BOLD, 8), fill=1)
    draw.text((88, 25), "kHz", font=font(FONT_MONO_BOLD, 8), fill=1)

    # Four-node signal-path indicator. Filled nodes show the selected endpoint.
    node_x = (60, 79, 98, 117)
    draw.line((node_x[0], 39, node_x[-1], 39), fill=1, width=1)
    for index, x in enumerate(node_x):
        if index < cfg["nodes"]:
            draw.ellipse((x - 2, 37, x + 2, 41), outline=1, fill=1)
        else:
            draw.ellipse((x - 2, 37, x + 2, 41), outline=1, fill=0)

    # All eight keys are visible on every page.
    draw.line((0, 44, 127, 44), fill=1, width=1)
    key_font = font(FONT_MONO_BOLD, 7)
    centered_text(draw, 45, "1=1X 2=4X 3=8X 4=128X", key_font, 1)
    centered_text(draw, 54, "5=+1 6=-1 7=15 8=AUTO", key_font, 1)
    return image


def make_ila_demo_page() -> Image.Image:
    image = Image.new("1", (128, 64), 0)
    draw = ImageDraw.Draw(image)

    draw.rectangle((0, 0, 127, 10), fill=1)
    centered_text(draw, -1, "ILA 镜像抑制演示", font(FONT_CN_BOLD, 10), 0)
    centered_text(draw, 11, "SRC 4.1K + 15K", font(FONT_MONO_BOLD, 8), 1)

    label_font = font(FONT_MONO_BOLD, 7)
    for label, top in (("15I", 21), ("15O", 29), ("40I", 37), ("40O", 45)):
        draw.text((2, top), label, font=label_font, fill=1)
        draw.rectangle((27, top, 124, top + 6), outline=1, fill=0)

    draw.text((2, 54), "SUPP:", font=label_font, fill=1)
    draw.text((52, 54), "dB", font=label_font, fill=1)
    draw.text((78, 54), "9=EXIT", font=label_font, fill=1)
    return image


def add_dynamic_preview(
    image: Image.Image, tone_khz: int = 15, auto_sweep: bool = False
) -> Image.Image:
    """叠加与RTL相同的5x7动态字符，仅用于正向观看预览。"""
    preview = image.copy()

    def draw_glyph(x: int, y: int, glyph: str) -> None:
        for row_index, row_bits in enumerate(GLYPHS_5X7[glyph]):
            for column_index, pixel in enumerate(row_bits):
                if pixel == "1":
                    preview.putpixel((x + column_index, y + row_index), 1)

    draw_glyph(72, 25, f"{tone_khz:02d}"[0])
    draw_glyph(80, 25, f"{tone_khz:02d}"[1])
    if auto_sweep:
        draw_glyph(120, 25, "A")
    return preview


def add_ila_demo_dynamic_preview(image: Image.Image) -> Image.Image:
    """给预览图加入一组典型测量值，实际屏幕由RTL动态绘制。"""
    preview = image.copy()
    draw = ImageDraw.Draw(preview)
    for top, units in ((21, 14), (29, 14), (37, 14), (45, 1)):
        if units > 0:
            draw.rectangle((29, top + 2, 29 + units * 6 - 1, top + 4), fill=1)

    def draw_glyph(x: int, y: int, glyph: str) -> None:
        for row_index, row_bits in enumerate(GLYPHS_5X7[glyph]):
            for column_index, pixel in enumerate(row_bits):
                if pixel == "1":
                    preview.putpixel((x + column_index, y + row_index), 1)

    draw_glyph(34, 54, "5")
    draw_glyph(42, 54, "4")
    return preview


def image_bytes(image: Image.Image) -> list[int]:
    result: list[int] = []
    for y in range(64):
        for byte_x in range(16):
            value = 0
            for bit in range(8):
                value = (value << 1) | (1 if image.getpixel((byte_x * 8 + bit, y)) else 0)
            result.append(value)
    return result


def main() -> None:
    PREVIEW_DIR.mkdir(parents=True, exist_ok=True)
    OUT_MEM.parent.mkdir(parents=True, exist_ok=True)

    pages = [make_page(i) for i in range(4)]
    demo_page = make_ila_demo_page()
    preview_pages = [add_dynamic_preview(page) for page in pages]
    demo_preview = add_ila_demo_dynamic_preview(demo_page)
    rom_pages = [page.rotate(180) if ROTATE_180_FOR_PANEL else page for page in pages]
    demo_rom_page = (
        demo_page.rotate(180) if ROTATE_180_FOR_PANEL else demo_page
    )
    all_bytes: list[int] = []
    for index, (page, preview_page, rom_page) in enumerate(
        zip(pages, preview_pages, rom_pages)
    ):
        preview_page.save(
            PREVIEW_DIR / f"lcd12864_mode_{MODES[index]['badge'].lower()}.png"
        )
        rom_page.save(
            PREVIEW_DIR / f"lcd12864_mode_{MODES[index]['badge'].lower()}_rom_180.png"
        )
        if ROTATE_180_FOR_PANEL:
            assert rom_page.rotate(180).tobytes() == page.tobytes()
        all_bytes.extend(image_bytes(rom_page))

    demo_preview.save(PREVIEW_DIR / "lcd12864_ila_demo.png")
    demo_rom_page.save(PREVIEW_DIR / "lcd12864_ila_demo_rom_180.png")
    if ROTATE_180_FOR_PANEL:
        assert demo_rom_page.rotate(180).tobytes() == demo_page.tobytes()
    all_bytes.extend(image_bytes(demo_rom_page))

    with OUT_MEM.open("w", encoding="ascii", newline="\n") as mem_file:
        for value in all_bytes:
            mem_file.write(f"{value:02X}\n")

    contact = Image.new("1", (128, 64 * 5), 0)
    for index, page in enumerate(preview_pages):
        contact.paste(page, (0, index * 64))
    contact.paste(demo_preview, (0, 4 * 64))
    contact.resize((512, 1280), resample=Image.Resampling.NEAREST).save(
        PREVIEW_DIR / "lcd12864_all_modes_4x.png"
    )

    rom_contact = Image.new("1", (128, 64 * 5), 0)
    for index, page in enumerate(rom_pages):
        rom_contact.paste(page, (0, index * 64))
    rom_contact.paste(demo_rom_page, (0, 4 * 64))
    rom_contact.resize((512, 1280), resample=Image.Resampling.NEAREST).save(
        PREVIEW_DIR / "lcd12864_all_modes_rom_180_4x.png"
    )

    assert len(all_bytes) == 5120
    print(f"Generated {OUT_MEM} ({len(all_bytes)} bytes)")


if __name__ == "__main__":
    main()
