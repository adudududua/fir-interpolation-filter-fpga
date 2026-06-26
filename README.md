# 高阶数字插值滤波器设计与验证

## 1. 项目简介

本项目面向“数字设计域：高阶数字插值滤波器设计与验证”赛题，完成了适用于音频重构与多倍率采样率提升场景的 FPGA 原型系统设计。系统围绕 **24 bit signed 音频 PCM 输入**，完成了 MATLAB 建模、FIR 系数量化、RTL 编码、功能仿真、板级验证、资源利用率评估、功耗评估、时序分析以及多轮结构优化。

系统支持 **44.1 kHz / 48 kHz 两类音频采样率家族**，并支持 **4×、8×、128× 三档插值输出**。主验证平台采用 **Artix-7 XC7A35T-FGG484-2 + AD9708 高速 DAC + 示波器**；辅助展示平台采用 **VS1053 音频解码模块**，用于 A/B 听感对比。

在基础多级 FIR 插值链路之上，本项目进一步完成了以下优化：

1. 后级 2× FIR 字长优化：18 bit Q16 → 14 bit Q12；
2. 后级 2× FIR tap 数修正与定点频响验证：NTAPS2X = 29；
3. 4× FIR 累加器位宽优化：ACC_W = 56 → 49；
4. 4× 前级 FIR polyphase 结构重构；
5. 4× polyphase 采用 2-lane MAC 时分复用结构；
6. 后级 2× FIR 添加 no-DSP 映射约束，避免 29 tap 版本大量占用 DSP48E1；
7. 128× DAC 显示通道增加幅度补偿，用于改善 8 bit DAC 示波器显示效果。

最终验证通过版本在保持 4× / 8× / 128× 三档波形正常、44.1 kHz / 48 kHz 两个采样率家族均可工作的前提下，实现后资源为：

| 资源 | 使用量 | 可用量 | 利用率 |
|---|---:|---:|---:|
| Slice LUTs | 10197 | 20800 | 49.02% |
| Slice Registers | 4640 | 41600 | 11.15% |
| DSP48E1 | 2 | 90 | 2.22% |
| CARRY4 | 2112 | 8150 | 25.91% |
| Total On-Chip Power | 0.272 W | - | - |
| WNS | 17.081 ns | - | Timing met |

---

## 2. 赛题规格对应关系

### 2.1 输入规格

| 项目 | 参数 |
|---|---|
| 输入数据格式 | 24 bit signed |
| 输入采样率 | 44.1 kHz / 48 kHz |
| 输入类型 | 正弦 ROM / 音频 PCM ROM |

### 2.2 输出规格

| 采样率家族 | 插值倍率 | 理论输出采样率 |
|---|---:|---:|
| 44.1 kHz | 4× | 176.4 kHz |
| 44.1 kHz | 8× | 352.8 kHz |
| 44.1 kHz | 128× | 5.6448 MHz |
| 48 kHz | 4× | 192 kHz |
| 48 kHz | 8× | 384 kHz |
| 48 kHz | 128× | 6.144 MHz |

### 2.3 设计指标

| 指标 | 目标 |
|---|---|
| 通带范围 | 10 Hz ~ 20 kHz |
| 通带纹波 | ≤ ±0.05 dB |
| 阻带衰减 | ≥ 70 dB |
| 相位响应 | 严格线性相位 |
| 主验证方式 | AD9708 DAC + 示波器 |
| 辅助展示 | VS1053 A/B 听感对比 |
| 优化目标 | 降低 LUT / DSP / CARRY4，占用资源更均衡 |

---

## 3. 系统总体结构

本项目采用“两条验证线路”。

```text
线路 1：主验证线路
正弦 ROM / 音频 PCM ROM
        ↓
24 bit signed 输入采样
        ↓
FPGA FIR 插值链
        ↓
4× / 8× / 128× 插值输出
        ↓
AD9708 高速 DAC
        ↓
示波器观察 dac_clk 与 DAC 模拟输出波形

线路 2：辅助听感线路
48 kHz / 24 bit signed 音频 ROM
        ↓
FPGA 内部 A/B 实时处理
        ├─ A 路：保持重构
        └─ B 路：FIR 插值重构
        ↓
VS1053 播放 48 kHz / 16 bit PCM
        ↓
耳机 / 喇叭听感对比
```

其中，**AD9708 + 示波器**是 4× / 8× / 128× 高采样率插值输出的主验证证据；**VS1053**仅作为辅助听感展示，不作为高采样率输出的主验证证据。

---

## 4. FIR 插值链路

### 4.1 多级插值结构

系统没有采用单级 128× 直接插值，而是采用 **4× 前级 + 多级 2× 后级**的级联结构：

```text
24 bit signed 输入
        ↓
4× FIR 插值
        ↓
8× 输出 / 继续插值
        ↓
2× FIR 级联
        ↓
16× / 32× / 64× / 128×
        ↓
AD9708 DAC 输出
```

### 4.2 最终验证通过版结构

最终验证通过版采用如下结构：

```text
4× 前级：
    4-phase polyphase FIR
    2-lane MAC 时分复用计算
    DSP48E1 = 2

后级 2× FIR：
    NTAPS2X = 29
    COEFF_W = 14
    FRAC_W  = 12
    ACC_W   = 48
    no-DSP 映射
    DSP48E1 = 0 / 每级

最终 128× DAC 显示：
    由于多级 2× 插值后幅度降低，
    128× 档在 DAC 显示通道中采用左移 4 位的显示补偿。
```

---

## 5. 文件结构

当前仓库主要文件结构如下：

```text
fir_interpolation/
├── README.md
├── .gitignore
├── audio_data/
│   └── 音频 PCM ROM 与测试数据
│
├── FIR_interp_final_demo/
│   ├── bit/
│   ├── reports/
│   ├── screenshots/
│   └── source_backup/
│
├── interp4_ctrl/
│   └── 4× 插值控制相关实验文件
│
├── matlab_fir/
│   └── FIR 设计、系数量化、频响验证脚本
│
├── need/
│   └── 赛题材料、板卡资料或辅助文档
│
├── XC7A35T_interp/
│   └── 早期 XC7A35T 插值工程
│
├── XC7A35T_interp_audio_pcm_version/
│   └── 音频 PCM 输入基准工程
│
├── XC7A35T_interp_audio_pcm_wordlen_opt/
│   └── 当前主要优化工程
│
├── XC7A35T_interp_dual_family_scope_OK_20260621/
│   └── 双采样率家族示波器验证工程
│
└── XC7A35T_vs1053_speaker_test/
    └── VS1053 辅助听感展示工程
```

---

## 6. 主要工程版本说明

### 6.1 `sine_rom_dual_family_ad9708_ok.bit`

用途：正弦 ROM 输入下的主验证版本。

该版本用于验证 FPGA 内部插值链路、采样率家族切换和插值倍率切换是否正确。输入为内部正弦 ROM，输出经 AD9708 接入示波器。

### 6.2 `audio_pcm_dual_family_ad9708_ok.bit`

用途：音频 PCM ROM 输入下的主验证基准版本。

该版本输入源为 24 bit signed 音频 PCM ROM，支持 44.1 kHz / 48 kHz 两类采样率家族和 4× / 8× / 128× 三档插值输出。

### 6.3 `audio_pcm_dual_family_ad9708_acc_opt.bit`

用途：字长优化与累加器位宽优化版本。

该版本完成后级 2× FIR 字长优化和累加器位宽优化，是早期主要优化版本。

### 6.4 `polyphase_mac2_ntaps29_nodsp_verified.bit`

用途：当前最终验证通过的结构优化版本。

该版本在 `acc_opt / accw49_opt` 基础上进一步完成：

- 4× 前级 FIR polyphase 重构；
- 4× 前级 2-lane MAC 时分复用；
- 后级 2× FIR 使用 29 tap 优化系数；
- 后级 2× FIR 添加 no-DSP 映射，避免大量 DSP 消耗；
- 128× DAC 显示通道增加幅度补偿；
- 44.1 kHz / 48 kHz 家族下 4×、8×、128× 三档均完成板级验证。

### 6.5 `vs1053_fpga_48k_interp_ab_ok.bit`

用途：辅助听感展示。

该版本读取 48 kHz / 24 bit signed 音频 ROM，在 FPGA 内部实时生成两路音频：

- `sw0 = 0`：A 路，保持重构；
- `sw0 = 1`：B 路，FIR 插值重构。

VS1053 只负责播放 FPGA 输出的 48 kHz / 16 bit PCM 音频流，A/B 差异由 FPGA 内部实时产生。

---

## 7. 主要 RTL 模块

| 文件 / 模块 | 功能 |
|---|---|
| `board_demo_competition_dac8_top.v` | AD9708 主验证顶层 |
| `demo_interp_dac8_audio_pcm_common.v` | 音频 PCM 输入、模式选择和 DAC 显示控制 |
| `audio_pcm_rom_source.v` | 24 bit signed 音频 PCM ROM 输入源 |
| `interp128_top_ce.v` | 128× 多级插值顶层，包含 4× 与多个 2× 级 |
| `interp4_top_symm_ce.v` | 当前最终版为 4-phase polyphase + 2-lane MAC 结构 |
| `interp4_ctrl_ce.v` | 4× 插值插零控制模块 |
| `fir_core_symm.v` | 早期 4× 对称 FIR 核心 |
| `interp2_top_symm_ce.v` | 2× FIR 插值顶层 |
| `interp2_ctrl_ce.v` | 2× 插值控制，产生真实样本 / 插零序列 |
| `fir_core_symm_interp2.v` | 2× FIR 核心，最终版添加 no-DSP 映射 |
| `bridge_to_interp2_ce.v` | 级间 CE 桥接模块 |
| `round_sat_q16_to24.v` | 大位宽累加结果舍入饱和到 24 bit |
| `vs1053_fpga_48k_interp_ab_top.v` | VS1053 A/B 听感辅助展示顶层 |
| `vs1053_spi_byte_master_48k_ab.v` | VS1053 SPI 单字节发送模块 |

---

## 8. 板级连接与拨码说明

### 8.1 AD9708 主验证线路

AD9708 主要接口：

| 信号 | 说明 |
|---|---|
| `dac_clk` | AD9708 采样时钟输出 |
| `dac_data[7:0]` | AD9708 8 bit 并行数据输出 |
| `sw0` | 插值倍率选择位 0 |
| `sw1` | 插值倍率选择位 1 |
| `sw2` | 44.1 kHz / 48 kHz 采样率家族选择 |

拨码说明：

```text
sw2 = 0：44.1 kHz 家族
sw2 = 1：48 kHz 家族

sw1 sw0 = 00：4× 插值输出
sw1 sw0 = 01：8× 插值输出
sw1 sw0 = 10：128× 插值输出
sw1 sw0 = 11：128× 插值输出
```

### 8.2 VS1053 辅助听感线路

VS1053 接口：

| 信号 | 说明 |
|---|---|
| `vs_rst_n` | VS1053 复位，低有效 |
| `vs_xcs_n` | SCI 控制接口片选 |
| `vs_xdcs_n` | SDI 音频数据接口片选 |
| `vs_sclk` | SPI 时钟 |
| `vs_mosi` | FPGA 到 VS1053 的 SPI 数据 |
| `vs_dreq` | VS1053 数据请求输入 |
| `sw0` | A/B 听感选择 |

拨码说明：

```text
sw0 = 0：A 路，保持重构
sw0 = 1：B 路，FPGA FIR 插值重构
```

---

## 9. 优化探索过程

### 9.1 基准版本

基准版本采用 4× FIR + 多级 2× FIR 级联结构，资源占用如下：

| 资源类型 | 使用量 | 可用量 | 利用率 |
|---|---:|---:|---:|
| Slice LUTs | 17572 | 20800 | 84.48% |
| Slice Registers | 4518 | 41600 | 10.86% |
| Slice | 5055 | 8150 | 62.02% |
| DSP48E1 | 6 | 90 | 6.67% |
| CARRY4 | 4043 | 8150 | 49.61% |

基准版本能够完成板级功能验证，但 LUT 使用率较高，因此需要进一步优化。

### 9.2 后级 2× FIR 字长优化

针对后级 2× FIR，本项目完成 MATLAB 定点字长搜索，对 `COEFF_W`、`FRAC_W` 和裁剪阈值进行联合搜索。

最终后级 2× FIR 选择：

```text
COEFF_W = 14
FRAC_W  = 12
ACC_W   = 48
NTAPS   = 29
```

后级 2× FIR 优化后频响性能如下：

| 模式 | 通带峰峰纹波 | 通带 ±纹波 | 阻带衰减 | 群延迟 | 是否满足 |
|---|---:|---:|---:|---:|---|
| 176.4 kHz → 352.8 kHz | 0.00201752 dB | 0.00100876 dB | 80.42743153 dB | 14 samples | 是 |
| 192 kHz → 384 kHz | 0.00132787 dB | 0.00066393 dB | 83.21212199 dB | 14 samples | 是 |

### 9.3 acc_opt 版本

`acc_opt` 版本完成后级字长优化与累加器优化，最终实现结果为：

| 资源类型 | 使用量 |
|---|---:|
| Slice LUTs | 14852 |
| Slice Registers | 5190 |
| DSP48E1 | 1 |
| CARRY4 | 3383 |
| Total On-Chip Power | 0.272 W |
| WNS | 17.084 ns |

该版本是早期稳定优化版，功能和时序均通过。

### 9.4 accw49_opt 版本

在 `acc_opt` 基础上，进一步针对 4× 前级 FIR 的累加器位宽进行扫描：

```text
ACC_W = 52 / 50 / 49 / 48 / 45
```

结果表明：

- `ACC_W = 49` 时，DSP 仍保持为 1，LUT 降至 13823；
- `ACC_W = 48` 时，Vivado 会将大量乘加结构重新映射到 DSP，DSP 使用量显著增加。

因此 `accw49_opt` 选择 `ACC_W = 49` 作为较优折中点。

| 资源类型 | 使用量 |
|---|---:|
| Slice LUTs | 13823 |
| Slice Registers | 5185 |
| DSP48E1 | 1 |
| CARRY4 | 3179 |
| Total On-Chip Power | 0.272 W |
| WNS | 16.929 ns |

### 9.5 halfband13 后级 2× FIR 探索

本项目进一步尝试将后级 2× FIR 改造成 13 tap halfband 结构。MATLAB 频响验证表明，该结构在 Q12 系数量化下能够满足通带纹波和阻带衰减要求。

但是 RTL 综合结果表明：

| 实现方式 | LUT | FF | DSP | 结论 |
|---|---:|---:|---:|---|
| halfband13 普通乘法 | 13453 | 5851 | 16 | LUT 降低但 DSP 增加过多 |
| halfband13 shift-add | 15393 | 5851 | 1 | DSP 保持低，但 LUT 高于 accw49 |

因此 halfband13 结构未作为最终版本采用。

### 9.6 4× polyphase + MAC2 结构优化

最终结构优化针对资源占用最高的 4× 前级 FIR。原结构为补零后进入 155 tap FIR；优化后改为 4 相 polyphase 结构：

```text
y[4n+p] = Σ h[p+4j] · x[n-j], p = 0,1,2,3
```

由于 128× 时钟域下，每个 4× 输出周期之间有 32 个 128× 时钟周期，而每相约 39 tap，因此采用 2-lane MAC 时分复用计算：

```text
每拍计算 2 个 tap
39 tap / 2 ≈ 20 拍
20 拍 < 32 拍
```

这样可以用少量 DSP 完成 4× 前级 polyphase FIR。

### 9.7 后级 2× FIR no-DSP 映射

当 `NTAPS2X = 29` 后，后级 5 个 2× FIR 若由 Vivado 自动映射，会消耗大量 DSP48E1。为避免 DSP 占用过高，最终对 `fir_core_symm_interp2.v` 添加 no-DSP 映射约束，使后级 2× FIR 的常系数乘法使用 LUT 实现。

最终资源分配为：

```text
4× polyphase MAC2 前级：2 个 DSP
5 个 2× FIR 后级：0 个 DSP
系统总 DSP：2 个
```

---

## 10. 最终验证通过版实现结果

最终验证通过版配置如下：

```text
4× 前级：
    interp4_top_symm_ce.v = polyphase + 2-lane MAC v2b

128× 顶层：
    interp128_top_ce.v = 正常输出 y128_w / y128_valid_w

后级 2× FIR：
    NTAPS2X = 29
    fir_core_symm_interp2.v = no-DSP 版本

DAC 显示：
    128× 档左移 4 位做显示补偿
```

### 10.1 资源利用率

目标器件：Artix-7 XC7A35T-FGG484-2  
顶层设计：`board_demo_competition_dac8_top`  
设计状态：Routed

| 资源类型 | 使用量 | 可用量 | 利用率 |
|---|---:|---:|---:|
| Slice LUTs | 10197 | 20800 | 49.02% |
| LUT as Logic | 10077 | 20800 | 48.45% |
| LUT as Shift Register | 120 | 9600 | 1.25% |
| Slice Registers | 4640 | 41600 | 11.15% |
| Slice | 3201 | 8150 | 39.28% |
| CARRY4 | 2112 | 8150 | 25.91% |
| DSP48E1 | 2 | 90 | 2.22% |
| Bonded IOB | 13 | 250 | 5.20% |
| BUFGCTRL | 2 | 32 | 6.25% |
| MMCME2_ADV | 2 | 5 | 40.00% |

### 10.2 层级资源分布

最终版本层级资源显示，主要 DSP 仅由 4× polyphase MAC2 前级使用：

| 层级 | LUT | FF | DSP |
|---|---:|---:|---:|
| `u_interp128_top_ce` | 7866 | 4487 | 2 |
| `u_interp4_top_symm_ce` | 559 | 1098 | 2 |
| `u_interp2_top_8x` | 1423 | 652 | 0 |
| `u_interp2_top_16x` | 1422 | 652 | 0 |
| `u_interp2_top_32x` | 1422 | 652 | 0 |
| `u_interp2_top_64x` | 1422 | 651 | 0 |
| `u_interp2_top_128x` | 1416 | 652 | 0 |

这说明最终版本实现了“4× 前级使用少量 DSP，后级 2× FIR 不占用 DSP”的资源分配目标。

### 10.3 功耗结果

| 项目 | 数值 |
|---|---:|
| Total On-Chip Power | 0.272 W |
| Dynamic Power | 0.201 W |
| Device Static Power | 0.072 W |
| Junction Temperature | 25.8 °C |
| Confidence Level | Medium |

功耗结果由 Vivado `report_power` 估算得到，置信度为 Medium。总功耗主要由两个 Clock Wizard / MMCM 贡献，FIR 逻辑与 DSP 部分功耗占比较低。

### 10.4 时序结果

| 时序指标 | 数值 |
|---|---:|
| WNS | 17.081 ns |
| TNS | 0.000 ns |
| WHS | 0.033 ns |
| THS | 0.000 ns |
| Timing 结论 | All user specified timing constraints are met |

时钟摘要：

| 时钟 | 频率 |
|---|---:|
| `clk_50M` | 50.000 MHz |
| `clk_audio_128x_44k1` | 5.645 MHz |
| `clk_audio_128x_48k` | 6.144 MHz |

---

## 11. 板级验证结果

最终验证通过版已完成 AD9708 DAC 板级下载测试，4×、8×、128× 三档 DAC 输出波形均正常。

### 11.1 44.1 kHz 家族

| 开关状态 | 理论输出采样率 | 实测输出频率 |
|---|---:|---:|
| `sw2=0, sw1 sw0=00` | 176.4 kHz | 176.3 kHz |
| `sw2=0, sw1 sw0=01` | 352.8 kHz | 352.61 kHz |
| `sw2=0, sw1 sw0=10/11` | 5.6448 MHz | 5.65 MHz |

### 11.2 48 kHz 家族

| 开关状态 | 理论输出采样率 | 实测输出频率 |
|---|---:|---:|
| `sw2=1, sw1 sw0=00` | 192 kHz | 192.01 kHz |
| `sw2=1, sw1 sw0=01` | 384 kHz | 384.02 kHz |
| `sw2=1, sw1 sw0=10/11` | 6.144 MHz | 6.15 MHz |

实测结果表明，最终版本在两类采样率家族和三档输出倍率下均能够产生正确的输出采样时钟，说明 polyphase MAC2、后级 29 tap no-DSP FIR 以及 DAC 显示补偿没有破坏系统板级运行功能。

---

## 12. 主要版本资源对比

| 版本 | 关键优化 | LUT | FF | DSP | CARRY4 | Power | WNS |
|---|---|---:|---:|---:|---:|---:|---:|
| baseline | 基准多级 FIR | 17572 | 4518 | 6 | 4043 | 0.272 W | 16.959 ns |
| acc_opt | 后级字长 + 累加器优化 | 14852 | 5190 | 1 | 3383 | 0.272 W | 17.084 ns |
| accw49_opt | 4× ACC_W 56→49 | 13823 | 5185 | 1 | 3179 | 0.272 W | 16.929 ns |
| polyphase_mac2_nodsp_verified | 4× polyphase MAC2 + 2× no-DSP | 10197 | 4640 | 2 | 2112 | 0.272 W | 17.081 ns |

相对 `accw49_opt`，最终 polyphase 版本：

```text
LUT：13823 → 10197，减少 3626，约下降 26.23%
FF ：5185  → 4640，减少 545，约下降 10.51%
DSP：1 → 2，仅增加 1 个 DSP
CARRY4：3179 → 2112，减少 1067，约下降 33.56%
```

相对基准版本，最终 polyphase 版本：

```text
LUT：17572 → 10197，减少 7375，约下降 41.97%
DSP：6 → 2，减少 4 个，约下降 66.67%
CARRY4：4043 → 2112，减少 1931，约下降 47.76%
```

---

## 13. 演示步骤

### 13.1 主验证：正弦 ROM + AD9708

1. 下载正弦 ROM 主验证 bit 文件。
2. 示波器 CH1 接 AD9708 模拟输出。
3. 示波器 CH2 接 `dac_clk`。
4. 切换 `sw2` 选择 44.1 kHz / 48 kHz 家族。
5. 切换 `sw1 sw0` 选择 4× / 8× / 128× 插值倍率。
6. 观察 `dac_clk` 是否对应理论输出采样率。

### 13.2 主验证：音频 PCM ROM + AD9708

1. 下载最终验证通过版本 bit 文件。
2. 输入源为 24 bit signed 音频 PCM ROM。
3. 示波器观察复杂音频波形与 `dac_clk`。
4. 验证真实音频输入下系统仍能完成采样率家族和插值倍率切换。

### 13.3 辅助听感：VS1053 A/B

1. 下载 `vs1053_fpga_48k_interp_ab_ok.bit`。
2. 连接 VS1053 模块耳机输出。
3. `sw0 = 0`，播放保持重构版本。
4. `sw0 = 1`，播放 FIR 插值重构版本。
5. 对比 A/B 听感差异。

---

## 14. 注意事项

1. VS1053 支路仅用于听感辅助，不作为 4× / 8× / 128× 输出采样率的主验证证据。
2. 4× / 8× / 128× 输出采样率验证应以 AD9708 + 示波器结果为准。
3. 128× 档 DAC 波形由于输出采样率达到 5.6448 MHz / 6.144 MHz，示波器采样率、时基设置和 DAC 后级低通滤波都会明显影响显示效果。
4. 128× 档中的左移 4 位仅用于 8 bit DAC 示波器显示补偿，不改变内部 FIR 插值算法。
5. 功耗报告置信度为 Medium，若需要更高精度功耗结果，可进一步导入 SAIF/VCD 活动文件。
6. 4× FIR 前级过渡带较窄，固定 155 tap 条件下对小系数裁剪非常敏感，因此最终不采用 4× FIR 稀疏裁剪方案。
7. 若现场只允许 FPGA 开发平台与示波器，优先演示 AD9708 主验证支路；VS1053 为额外辅助展示。

---

## 15. 版本记录

| 日期 | 版本 | 内容 |
|---|---|---|
| 2026-06-20 | V1.0 | 完成正弦 ROM 输入下 AD9708 示波器主验证 |
| 2026-06-21 | V1.1 | 完成音频 PCM ROM 输入下 AD9708 主验证 |
| 2026-06-21 | V1.2 | 完成 VS1053 sine test 与 PCM ROM 播放 |
| 2026-06-22 | V1.3 | 完成 VS1053 FPGA 内部实时 A/B 听感对比 |
| 2026-06-23 | V1.4 | 完成基准版本资源利用率、功耗与时序报告导出 |
| 2026-06-24 | V1.5 | 完成后级 2× FIR 字长优化 |
| 2026-06-24 | V1.6 | 完成累加器位宽优化并确定 acc_opt 版本 |
| 2026-06-24 | V1.7 | 完成 4× FIR 固定 155 tap 稀疏裁剪可行性分析 |
| 2026-06-25 | V1.8 | 完成 ACC_W=49 优化，Slice LUT 降至 13823 |
| 2026-06-26 | V1.9 | 完成 4× polyphase MAC2 结构探索 |
| 2026-06-26 | V2.0 | 完成 NTAPS2X=29 修正与后级 2× FIR no-DSP 版本 |
| 2026-06-26 | V2.1 | 完成最终 polyphase_mac2_nodsp_verified 版本，三档波形和双采样率家族均通过板级验证 |

---

## 16. 最终结论

本项目已完成高阶数字插值滤波器的 MATLAB 建模、RTL 实现、功能仿真、FPGA 板级验证和实现后资源 / 功耗 / 时序评估。系统能够处理 24 bit signed、44.1 kHz / 48 kHz 音频采样输入，并输出 4×、8×、128× 三档插值结果。

在结构优化方面，项目从基准多级 FIR 结构出发，依次完成后级 2× FIR 字长优化、累加器位宽优化、4× 前级 ACC_W=49 优化、halfband13 可行性分析以及 4× polyphase MAC2 时分复用结构探索。最终验证通过版本采用 **4× polyphase + 2-lane MAC** 作为前级，并将后级 2× FIR 固定为 **29 tap Q12 no-DSP** 结构，在保证功能、时序和板级输出正常的前提下，将 Slice LUTs 从基准版本的 17572 降低到 10197，将 DSP48E1 从 6 个降低到 2 个，将 CARRY4 从 4043 降低到 2112。

最终版本在 44.1 kHz 与 48 kHz 两类采样率家族下，4×、8×、128× 三档输出频率均与理论值一致，AD9708 DAC 输出波形正常，Vivado 实现后时序满足约束，证明该多级插值结构与资源优化策略能够有效降低 FPGA 资源消耗并保持稳定的板级运行能力。
