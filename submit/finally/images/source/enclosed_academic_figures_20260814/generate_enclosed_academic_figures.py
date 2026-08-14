from __future__ import annotations

import math
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont


ROOT = Path(__file__).resolve().parents[5]
OUT = ROOT / "submit" / "finally" / "images" / "generated" / "enclosed_academic_figures"
OUT.mkdir(parents=True, exist_ok=True)

WHITE = "#FFFFFF"
PAPER = "#F8FAFC"
PANEL = "#EEF2F6"
PANEL_2 = "#E4EAF0"
NAVY = "#18324B"
INK = "#273746"
MUTED = "#637487"
LINE = "#8797A8"
BLUE = "#315E89"
GREEN = "#2F6B59"
GREEN_PALE = "#E6F0EC"
ORANGE = "#9A6334"


def font_path(bold: bool = False) -> str:
    candidates = [
        Path(r"C:\Windows\Fonts\msyhbd.ttc") if bold else Path(r"C:\Windows\Fonts\msyh.ttc"),
        Path(r"C:\Windows\Fonts\simhei.ttf"),
        Path(r"C:\Windows\Fonts\simsun.ttc"),
    ]
    for path in candidates:
        if path.exists():
            return str(path)
    raise FileNotFoundError("No Chinese-capable font found")


def ft(size: int, bold: bool = False) -> ImageFont.FreeTypeFont:
    return ImageFont.truetype(font_path(bold), size)


def canvas(size: tuple[int, int], margin: int = 24) -> tuple[Image.Image, ImageDraw.ImageDraw]:
    image = Image.new("RGB", size, WHITE)
    draw = ImageDraw.Draw(image)
    draw.rounded_rectangle(
        (margin, margin, size[0] - margin, size[1] - margin),
        radius=26,
        fill=PAPER,
        outline=NAVY,
        width=3,
    )
    return image, draw


def rounded(draw: ImageDraw.ImageDraw, xy, fill=PANEL, outline=LINE, width=2, radius=20):
    draw.rounded_rectangle(xy, radius=radius, fill=fill, outline=outline, width=width)


def center_text(draw, xy, text, font, fill=INK, spacing=6):
    bbox = draw.multiline_textbbox((0, 0), text, font=font, spacing=spacing, align="center")
    w, h = bbox[2] - bbox[0], bbox[3] - bbox[1]
    x = (xy[0] + xy[2] - w) / 2
    y = (xy[1] + xy[3] - h) / 2 - 2
    draw.multiline_text((x, y), text, font=font, fill=fill, spacing=spacing, align="center")


def title(draw, headline: str, subtitle: str, width: int, *, y: int = 55) -> None:
    draw.text((70, y), headline, font=ft(45, True), fill=NAVY)
    draw.text((72, y + 62), subtitle, font=ft(24), fill=MUTED)


def arrow(draw, start, end, color=NAVY, width=5):
    draw.line((start, end), fill=color, width=width)
    angle = math.atan2(end[1] - start[1], end[0] - start[0])
    length, spread = 18, 0.55
    p1 = (end[0] - length * math.cos(angle - spread), end[1] - length * math.sin(angle - spread))
    p2 = (end[0] - length * math.cos(angle + spread), end[1] - length * math.sin(angle + spread))
    draw.polygon([end, p1, p2], fill=color)


def metric_card(draw, box, label: str, value: str, detail: str, *, status: bool = False) -> None:
    x0, y0, x1, y1 = box
    fill = GREEN_PALE if status else PANEL
    outline = GREEN if status else LINE
    rounded(draw, box, fill=fill, outline=outline, width=3, radius=18)
    draw.text((x0 + 26, y0 + 22), label, font=ft(22, True), fill=GREEN if status else BLUE)
    draw.text((x0 + 26, y0 + 61), value, font=ft(35, True), fill=NAVY)
    draw.multiline_text((x0 + 26, y0 + 112), detail, font=ft(19), fill=INK, spacing=6)


def evidence_card(filename: str, domain: str, headline: str, metrics: list[tuple[str, str]], footer: str) -> None:
    image, draw = canvas((1400, 760), 26)
    rounded(draw, (55, 52, 1345, 708), fill=WHITE, outline=NAVY, width=3, radius=24)
    rounded(draw, (78, 76, 1322, 205), fill=PANEL_2, outline=PANEL_2, width=1, radius=18)
    draw.text((110, 96), domain, font=ft(29, True), fill=BLUE)
    draw.text((110, 145), headline, font=ft(43, True), fill=NAVY)
    box_width = 374
    for i, (value, label) in enumerate(metrics):
        x0 = 88 + i * 410
        rounded(draw, (x0, 250, x0 + box_width, 490), fill=PANEL, outline=LINE, width=2, radius=18)
        center_text(draw, (x0 + 12, 272, x0 + box_width - 12, 368), value, ft(34, True), NAVY)
        center_text(draw, (x0 + 12, 368, x0 + box_width - 12, 466), label, ft(22), INK)
    rounded(draw, (88, 548, 1312, 668), fill=GREEN_PALE, outline=GREEN, width=2, radius=18)
    center_text(draw, (112, 562, 1288, 654), footer, ft(23, True), GREEN)
    image.save(OUT / filename, dpi=(180, 180))


def preview_cards() -> None:
    evidence_card(
        "01_matlab_fixed_point_enclosed.png",
        "MATLAB / 定点模型",
        "双采样率六工况均满足判据",
        [("0.007844 dB", "最大绝对通带偏差"), ("0.006190 dB", "最大通带峰峰纹波"), ("72.355 dB", "最小阻带衰减")],
        "44.1/48 kHz × 4×/8×/128×；线性相位，六工况 6/6",
    )
    evidence_card(
        "02_rtl_regression_enclosed.png",
        "RTL 位精确回归",
        "快速与完整回归均为 17/17 项",
        [("14 组", "完整全链输入"), ("0 LSB", "4×/8×/128×逐样本误差"), ("1200 次", "CDC事务；另含复位与切档")],
        "24/20/20 位配置；有效点数、valid时序与数据同时满足判据",
    )
    evidence_card(
        "03_implementation_enclosed.png",
        "Vivado 2025.2 / 完整板级 post-route",
        "218 LUT / 365 FF",
        [("4", "DSP48E1"), ("2 Tile", "4个RAMB18E1"), ("+45.279 ns", "WNS；WHS为+0.079 ns")],
        "XC7A35T-FGG484-2；TNS/THS=0；DRC Error=0；bitstream已生成",
    )
    evidence_card(
        "04_board_validation_enclosed.png",
        "物理板功能验证",
        "双采样率六模式功能得到验证",
        [("2 族", "44.1 kHz / 48 kHz"), ("6 档", "4×/8×/128×输出"), ("已确认", "DA_CLK采样率与DAC波形")],
        "218-LUT配置；结论限于用户确认的功能现象，不外推仪器级音频指标",
    )


def architecture() -> None:
    image, draw = canvas((1800, 820), 26)
    title(draw, "双采样率128×插值系统与218-LUT硬件映射", "Vivado 2025.2 · XC7A35T-FGG484-2 · 218 LUT / 365 FF / 4 DSP / 2 BRAM Tile", 1800)
    # Control plane in one enclosed area.
    rounded(draw, (70, 185, 940, 342), fill=PANEL, outline=LINE, width=2, radius=20)
    control = [
        (92, 213, 270, 315, "20 MHz", "板载时钟"),
        (336, 202, 590, 326, "双 MMCM", "5.6448 / 6.1440 MHz"),
        (658, 202, 915, 326, "原子切换", "request/ack CDC\n静音与锁定确认"),
    ]
    for x0, y0, x1, y1, head, body in control:
        rounded(draw, (x0, y0, x1, y1), fill=WHITE, outline=BLUE, width=2, radius=16)
        center_text(draw, (x0 + 8, y0 + 8, x1 - 8, y0 + 57), head, ft(28, True), NAVY)
        center_text(draw, (x0 + 8, y0 + 55, x1 - 8, y1 - 8), body, ft(18), MUTED)
    arrow(draw, (270, 264), (336, 264)); arrow(draw, (590, 264), (658, 264))

    y0, y1 = 420, 598
    modules = [
        (70, 300, "24-bit PCM", "44.1/48 kHz", "测试ROM与输入"),
        (350, 650, "Stage1 ×2", "105抽头；52项串行MAC", "1 DSP + 历史BRAM"),
        (700, 1010, "Stage2 / Stage3", "17/11抽头；共享MAC", "1 DSP + 统一历史BRAM"),
        (1060, 1370, "CIC16，N=3", "三级comb + 三级积分", "2 DSP；32-bit模运算"),
        (1420, 1730, "观察与DAC", "4× / 8× / 128×", "AD9708 + ODDR/IOB"),
    ]
    for index, (x0, x1, head, body1, body2) in enumerate(modules):
        fill = WHITE if index in (0, 4) else PANEL
        rounded(draw, (x0, y0, x1, y1), fill=fill, outline=NAVY, width=3, radius=18)
        center_text(draw, (x0 + 10, y0 + 22, x1 - 10, y0 + 75), head, ft(28, True), NAVY)
        center_text(draw, (x0 + 10, y0 + 80, x1 - 10, y0 + 125), body1, ft(20), INK)
        center_text(draw, (x0 + 10, y0 + 128, x1 - 10, y1 - 16), body2, ft(19), MUTED)
        if index < len(modules) - 1:
            arrow(draw, (x1, 509), (modules[index + 1][0], 509), width=4)

    rounded(draw, (100, 650, 1700, 755), fill=GREEN_PALE, outline=GREEN, width=2, radius=18)
    center_text(draw, (125, 662, 1675, 706), "同一RTL支持44.1 kHz与48 kHz输入族；正式输出为4×、8×和128×", ft(24, True), GREEN)
    center_text(draw, (125, 706, 1675, 746), "P3补偿折叠至Stage3系数；滤波系数、定点字长和输出相位保持一致", ft(20), INK)
    image.save(OUT / "05_system_architecture_enclosed.png", dpi=(180, 180))


def stage1_serial() -> None:
    image, draw = canvas((1500, 1480), 26)
    title(draw, "Stage1：105抽头顺序BRAM微引擎", "52项顺序MAC · 1 DSP48E1 · 1 RAMB18E1 · Q15尾拍舍入与饱和", 1500)
    steps = [
        (70, 245, 335, 430, "历史样本BRAM", "52字循环历史\n逐地址同步读"),
        (390, 245, 655, 430, "顺序地址发生器", "tap 0…51\n相位与中心样本"),
        (710, 245, 975, 430, "统一系数BRAM", "52项展开系数\nPort A同步读"),
        (1030, 245, 1430, 430, "DSP48E1串行MAC", "每主时钟1项乘加\nROUND/CLAMP回写PREG"),
    ]
    for i, (x0, y0, x1, y1, head, body) in enumerate(steps):
        rounded(draw, (x0, y0, x1, y1), fill=PANEL if i in (0, 2) else WHITE, outline=NAVY, width=3, radius=18)
        center_text(draw, (x0 + 12, y0 + 22, x1 - 12, y0 + 88), head, ft(25, True), NAVY)
        center_text(draw, (x0 + 12, y0 + 90, x1 - 12, y1 - 18), body, ft(21), INK)
        if i < len(steps) - 1:
            arrow(draw, (x1, 337), (steps[i + 1][0], 337), width=4)

    rounded(draw, (90, 515, 1410, 820), fill=WHITE, outline=LINE, width=2, radius=20)
    draw.text((130, 555), "单相位扫描窗口", font=ft(31, True), fill=NAVY)
    x_start, y_bar = 140, 660
    for i in range(52):
        x0 = x_start + i * 23
        fill = NAVY if i % 4 in (0, 1) else "#9AA8B6"
        draw.rectangle((x0, y_bar, x0 + 16, y_bar + 72), fill=fill)
    draw.text((140, 748), "tap 0", font=ft(18), fill=MUTED)
    draw.text((1250, 748), "tap 51", font=ft(18), fill=MUTED)
    center_text(draw, (350, 742, 1170, 792), "52个主时钟MAC周期：每周期一次BRAM读与一次乘加", ft(22, True), INK)

    stats = [(90, 395, "52", "顺序项/单乘积MAC"), (430, 735, "1", "DSP48E1"), (770, 1075, "1", "RAMB18E1历史"), (1110, 1410, "Q15", "DSP尾拍格式化")]
    for x0, x1, value, label in stats:
        rounded(draw, (x0, 900, x1, 1135), fill=PANEL, outline=NAVY, width=2, radius=18)
        center_text(draw, (x0, 925, x1, 1025), value, ft(47, True), NAVY)
        center_text(draw, (x0 + 10, 1030, x1 - 10, 1110), label, ft(20, True), INK)

    rounded(draw, (90, 1225, 1410, 1385), fill=GREEN_PALE, outline=GREEN, width=2, radius=18)
    center_text(draw, (125, 1242, 1375, 1368), "扫描、累加、中心延时和DSP尾拍均在下一相位到达前完成；\n行为RAM与RAMB18E1的1400点逐样本比较最大误差为0 LSB", ft(22, True), GREEN)
    image.save(OUT / "06_stage1_serial_bram_enclosed.png", dpi=(180, 180))


def cic_mapping() -> None:
    image, draw = canvas((1800, 820), 26)
    title(draw, "CIC16数据通路与218-LUT资源映射", "N=3 · R=16 · M=1 · 32-bit二补码模运算 · CIC使用2个DSP48E1", 1800)
    boxes = [
        (70, 345, "低速三级comb", "16倍周期余量\n串行差分"),
        (410, 705, "16倍保持", "pending / burst\n事件控制"),
        (770, 1110, "高速积分器", "DSP与CARRY4\n受控资源映射"),
        (1175, 1510, "末端格式化", "增益恢复、舍入\n24-bit饱和"),
        (1575, 1730, "输出", "4× / 8×\n128×"),
    ]
    for i, (x0, x1, head, body) in enumerate(boxes):
        rounded(draw, (x0, 245, x1, 455), fill=PANEL if i not in (1, 4) else WHITE, outline=NAVY, width=3, radius=18)
        center_text(draw, (x0 + 10, 270, x1 - 10, 335), head, ft(25, True), NAVY)
        center_text(draw, (x0 + 10, 338, x1 - 10, 432), body, ft(20), INK)
        if i < len(boxes) - 1:
            arrow(draw, (x1, 350), (boxes[i + 1][0], 350), width=4)
    rounded(draw, (100, 545, 1700, 730), fill=WHITE, outline=LINE, width=2, radius=18)
    draw.text((140, 575), "资源闭环", font=ft(29, True), fill=NAVY)
    labels = [(420, "Stage1", "1 DSP"), (760, "Stage2/3", "1 DSP"), (1110, "CIC", "2 DSP")]
    for x, head, value in labels:
        rounded(draw, (x, 570, x + 280, 650), fill=PANEL, outline=LINE, width=2, radius=14)
        center_text(draw, (x + 8, 578, x + 272, 612), head, ft(19, True), BLUE)
        center_text(draw, (x + 8, 610, x + 272, 642), value, ft(23, True), NAVY)
    center_text(draw, (145, 660, 1655, 714), "完整插值链共4 DSP；连续、停顿、随机停顿与中途复位测试均达到逐样本0 LSB", ft(23, True), GREEN)
    image.save(OUT / "07_cic_resource_mapping_enclosed.png", dpi=(180, 180))


def dual_clock() -> None:
    image, draw = canvas((1800, 700), 26)
    title(draw, "双采样率时钟与六个正式输出档位", "20 MHz输入 · 双MMCM · 原子切换 · ODDR/IOB转发DA_CLK", 1800)
    nodes = [
        (70, 245, 270, 375, "20 MHz", "板载时钟"),
        (350, 185, 650, 325, "MMCM 44.1k", "5.6448 MHz\n4× / 8× / 128×"),
        (350, 375, 650, 515, "MMCM 48k", "6.1440 MHz\n4× / 8× / 128×"),
        (745, 270, 1060, 430, "BUFGMUX_CTRL", "request / ack CDC\nMUTE → LOCK → UNMUTE"),
        (1150, 245, 1730, 455, "正式输出采样率", "176.4 / 352.8 kHz / 5.6448 MHz\n192 / 384 kHz / 6.144 MHz"),
    ]
    for i, (x0, y0, x1, y1, head, body) in enumerate(nodes):
        rounded(draw, (x0, y0, x1, y1), fill=PANEL if i in (1, 2, 3) else WHITE, outline=NAVY, width=3, radius=18)
        center_text(draw, (x0 + 10, y0 + 15, x1 - 10, y0 + 70), head, ft(27, True), NAVY)
        center_text(draw, (x0 + 10, y0 + 68, x1 - 10, y1 - 14), body, ft(20), INK)
    arrow(draw, (270, 310), (350, 255)); arrow(draw, (270, 310), (350, 445))
    arrow(draw, (650, 255), (745, 330)); arrow(draw, (650, 445), (745, 380)); arrow(draw, (1060, 350), (1150, 350))
    rounded(draw, (110, 565, 1690, 650), fill=GREEN_PALE, outline=GREEN, width=2, radius=16)
    center_text(draw, (130, 575, 1670, 640), "布局布线后六模式时序均满足约束；44.1 kHz与48 kHz切换采用受控静音和锁定确认", ft(22, True), GREEN)
    image.save(OUT / "08_dual_clock_enclosed.png", dpi=(180, 180))


def resource_utilization() -> None:
    image, draw = canvas((1700, 920), 26)
    title(draw, "Vivado 2025.2完整板级资源利用率", "218-LUT正式配置 · post-route · results/20260811_231722", 1700)
    rows = [
        ("Slice LUT", 218, 20800), ("Slice Register", 365, 41600), ("DSP48E1", 4, 90),
        ("BRAM Tile", 2, 50), ("RAMB18E1", 4, 100), ("MMCME2_ADV", 2, 5),
    ]
    y = 205
    for label, used, total in rows:
        pct = used / total
        rounded(draw, (75, y, 1625, y + 84), fill=WHITE, outline="#C3CCD5", width=1, radius=14)
        draw.text((105, y + 24), label, font=ft(23, True), fill=INK)
        draw.text((390, y + 24), f"{used} / {total}", font=ft(22), fill=MUTED)
        draw.rounded_rectangle((610, y + 27, 1455, y + 59), radius=14, fill=PANEL_2)
        visible = max(10, int(845 * pct))
        draw.rounded_rectangle((610, y + 27, 610 + visible, y + 59), radius=14, fill=BLUE if label != "MMCME2_ADV" else ORANGE)
        draw.text((1480, y + 21), f"{pct * 100:.2f}%", font=ft(22, True), fill=NAVY)
        y += 94
    rounded(draw, (75, 790, 1625, 875), fill=GREEN_PALE, outline=GREEN, width=2, radius=16)
    center_text(draw, (95, 800, 1605, 865), "218 LUT · 365 FF · 4 DSP48E1 · 4 RAMB18E1（2 BRAM Tile）· 17 I/O · 2 MMCM", ft(23, True), GREEN)
    image.save(OUT / "09_resource_utilization_enclosed.png", dpi=(180, 180))


def implementation_signoff() -> None:
    image, draw = canvas((1700, 870), 26)
    title(draw, "218-LUT实现签核与证据边界", "XC7A35T-FGG484-2 · Vivado 2025.2", 1700)
    cards = [
        (75, 205, 525, 455, "Setup", "+45.279 ns", "TNS=0\n失败端点=0", False),
        (625, 205, 1075, 455, "Hold", "+0.079 ns", "THS=0\n失败端点=0", False),
        (1175, 205, 1625, 455, "路由与DRC", "0 Error", "858/858可路由网络完成\nDRC Error=0", True),
        (75, 505, 525, 750, "模式总线CDC", "+49.556 ns", "实际skew 0.444 ns\n约束50.000 ns", False),
        (625, 505, 1075, 750, "功耗估计", "0.271 W", "动态0.199 W\n静态0.072 W；Medium", False),
        (1175, 505, 1625, 750, "发布产物", "board-verified", "bitstream与DCP哈希\n按实物文件复核", True),
    ]
    for values in cards:
        metric_card(draw, values[:4], *values[4:7], status=values[7])
    image.save(OUT / "10_implementation_signoff_enclosed.png", dpi=(180, 180))


def experiment_summary() -> None:
    image, draw = canvas((1800, 960), 26)
    title(draw, "218-LUT正式配置的补充实验与实现证据", "NF-P3-STAGE123-24-20-20-CANDIDATE-R1 · 2026-08-12", 1800)
    cards = [
        (70, 200, 485, 450, "有限字长误差", "114.974 dB", "−1 dBFS正常正弦\n最低定点SQNR", False),
        (510, 200, 925, 450, "六工况频响", "6 / 6", "通带最大偏差0.007844 dB\n阻带最小72.355 dB", True),
        (950, 200, 1365, 450, "定点单音频谱", "18 / 18", "最小镜像抑制\n74.546 dBc", True),
        (1390, 200, 1730, 450, "RTL回归", "17 / 17", "4×/8×/128×节点\n稳定向量0 LSB", True),
        (70, 485, 485, 735, "完整板级资源", "218 / 365", "LUT / FF\n4 DSP · 2 BRAM Tile", False),
        (510, 485, 925, 735, "实现时序", "+45.279 ns", "WNS；WHS +0.079 ns\nTNS/THS均为0", True),
        (950, 485, 1365, 735, "线性相位", "< 1e−13 rad", "最大相位拟合残差\n冲激对称误差0 LSB", True),
        (1390, 485, 1730, 735, "物理板验证", "已确认", "双采样率功能验证\n不外推仪器级音频指标", True),
    ]
    for values in cards:
        metric_card(draw, values[:4], *values[4:7], status=values[7])
    rounded(draw, (70, 790, 1730, 900), fill=PANEL_2, outline=NAVY, width=2, radius=16)
    center_text(draw, (95, 804, 1705, 886), "证据边界：频响、相位、SQNR和镜像抑制属于数字域证据；0.271 W为无活动向量估计；\n物理板结论限于用户确认的功能现象。", ft(21, True), NAVY)
    image.save(OUT / "11_release_experiment_summary_enclosed.png", dpi=(180, 180))


def fingerprint() -> None:
    image, draw = canvas((1800, 520), 26)
    title(draw, "218-LUT正式发布指纹", "Vivado 2025.2 · board-verified · 2026-08-11", 1800, y=48)
    rounded(draw, (75, 185, 1725, 315), fill=PANEL, outline=NAVY, width=2, radius=18)
    draw.text((108, 208), "bitstream SHA-256", font=ft(21, True), fill=BLUE)
    draw.text((108, 252), "E7A22AF459C03D9F63BBE558BE5197A99CACDFE5C456D2C3E8C4787A1DB8C742", font=ft(24, True), fill=NAVY)
    rounded(draw, (75, 340, 1725, 465), fill=GREEN_PALE, outline=GREEN, width=2, radius=18)
    draw.text((108, 365), "正式标签", font=ft(21, True), fill=GREEN)
    draw.text((108, 407), "nf-vivado2025.2-218lut-365ff-4dsp-2bram-24-20-20-board-pass", font=ft(23, True), fill=INK)
    image.save(OUT / "12_release_fingerprint_enclosed.png", dpi=(180, 180))


def main() -> None:
    preview_cards()
    architecture()
    stage1_serial()
    cic_mapping()
    dual_clock()
    resource_utilization()
    implementation_signoff()
    experiment_summary()
    fingerprint()
    for path in sorted(OUT.glob("*.png")):
        print(f"{path.name}: {path.stat().st_size} bytes")


if __name__ == "__main__":
    main()
