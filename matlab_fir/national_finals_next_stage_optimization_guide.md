# 国赛双时钟插值滤波器下一阶段修改与优化指导

> 适用对象：最新双采样率、双 MMCM、三级 `2× FIR + 16× CIC` 工程  
> 目标器件：Xilinx Artix-7 `XC7A35T-FGG484-2`  
> DAC：AD9708，8 bit 并行输入  
> 文档日期：2026-07-31  
> 核心原则：先修正确性和验证闭环，再做严格等效资源优化，最后开展性能与研究型探索。

---

## 0. 先给结论：下一步不要继续直接压资源

当前版本已经从上一阶段的 `472 LUT / 564 FF / 8 DSP / 3 BRAM Tile` 优化到：

| 指标 | 当前最新实现结果 |
|---|---:|
| Slice LUT | 436 |
| Slice FF | 471 |
| DSP48E1 | 5 |
| BRAM Tile | 3（6 个 RAMB18E1） |
| WNS | +45.662 ns |
| WHS | +0.116 ns |
| TNS / THS | 0 / 0 |
| Vivado 总功耗估计 | 0.271 W |
| MMCM 功耗项 | 0.197 W（两颗合计） |
| 功耗置信度 | Medium，未使用 SAIF |

这组资源数据是真实的，但它还不能作为最终国赛结果，原因有四个：

1. Stage3 的 Q 格式存在实质错误，8× 和 128× 相对 4× 会低约 6.02 dB；
2. 最新整链路仿真缺少输入和 golden `.mem`，当前 `mismatch=43776` 属于测试文件缺失导致的无效回归；
3. 模式总线、复位、DSP/BRAM 控制仍有成组 DRC/Methodology 警告；
4. AD9708 数据输出还没有形成完整的外部建立/保持时间签核。

因此建议把后续工作严格拆成以下六个阶段：

| 阶段 | 内容 | 性质 | 是否允许与其他阶段混改 |
|---|---|---|---|
| P0 | 冻结当前基线和统一构建配置 | 工程管理 | 否 |
| P1 | 修复 Stage3 Q14/Q15 与绝对增益 | 必须修复 | 否 |
| P2 | 恢复 MATLAB/位真/RTL 六组合回归 | 必须修复 | 可与 P1 同分支，不与结构优化混合 |
| P3 | 修复 CDC、复位、DRC 和 DAC I/O 时序 | 工程闭环 | 否 |
| P4 | N3 CIC Hold 严格等效 + 两项 BRAM 复用 | 低风险资源主线 | 两项分别提交、联合验收 |
| P5 | MMCM 功耗、N4 性能版、TPE、256× 调度 | 性能/研究支线 | 必须从已验证标签分别开分支 |

国赛最终建议至少保留两个可独立下载的版本：

- **资源优化版**：N3 Hold CIC，目标 `≤4 DSP、≤2 BRAM Tile`，频响与修正后的 N3 基线不变；
- **性能优化版**：N4 Hold CIC，目标 `≤5 DSP、≤2 BRAM Tile`，128× 最差阻带预期由约 72.37 dB 提升到约 78.6 dB。

N4 的 78.6 dB 目前只是基于当前参数的预筛选结果，必须经过重新设计、定点化、RTL 和实现后才能写入最终成果。

---

## 1. 当前工程真实配置

### 1.1 生效顶层和构建参数

当前 Vivado 工程的综合顶层为：

```text
board_demo_competition_dac8_top
```

正式实现不是按 Verilog 顶层中的参数默认值综合，而是由 XPR/Synth Run 中的 Generic 覆盖：

```text
USE_PHASE7_LUTRAM_STAGE23=1
USE_COMPACT_KEYPAD=1
COMPACT_KEYPAD_SCAN_DIV=20000
USE_SHARED_KEYPAD_SCAN_TICK=1
USE_PHASE7_BRAM_STAGE23_HISTORY=1
USE_PHASE7_BRAM_STAGE23_COEFF=1
USE_PHASE8_PACKED_BRAM_STAGE23=0
USE_PHASE7_CIC_BURST_COUNTER_DSP=0
USE_NATIONAL_FINALS_DATAPATH=1
USE_NATIONAL_FINALS_SERIAL_CIC_COMB=1
USE_NATIONAL_FINALS_CIC_COMB_DSP=0
USE_NATIONAL_FINALS_STAGE1_DSP48_PREADDER=0
USE_NATIONAL_FINALS_NARROW_STAGE23=1
```

这件事必须先规范化。否则只复制 RTL、不复制 XPR，或重新创建 Vivado 工程时，会综合出另一套结构。

建议新增唯一构建入口：

```text
scripts/build_nf_release.tcl
config/nf_release_config.tcl
```

其中显式写入：

- FPGA 型号；
- 顶层；
- 源文件列表；
- XDC；
- 全部 Generic；
- Vivado 版本；
- 综合/实现策略；
- 输出报告列表。

RTL 顶层参数默认值也应改成与国赛正式构建一致，或者在注释中明确写出“默认值不是正式配置”。不应继续依赖仅存在于 XPR 中的隐含状态。

### 1.2 当前数据通路

当前正式结构为：

```text
24 bit PCM
  │
  ├─ Stage1：105-tap 严格半带 2× FIR，单 DSP，24 bit 输出
  │
  ├─ 24 → 22 bit，右移 2 bit
  │
  ├─ Stage2：17-tap 多相 2× FIR
  │            与 Stage3 共用一颗串行 DSP
  ├─ 22 → 20 bit，右移 2 bit
  │
  ├─ Stage3：11-tap 多相 2× FIR，当前整数系数实际为 Q14
  │
  ├─ 三抽头 CIC 补偿器 [-1, 10, -1]/8，输出 21 bit
  │
  ├─ CIC16，N=3
  │     低速 3 级 comb：单运算单元、3 拍串行
  │     高速 3 级 integrator：3 个 DSP
  │
  └─ 20 bit → 左移 4 bit → 24 bit → 8 bit AD9708
```

当前 5 个 DSP 的构成为：

```text
Stage1 FIR                 1
Stage2/Stage3 共享 MAC     1
CIC 高速积分器             3
--------------------------------
合计                       5
```

当前 6 个 RAMB18E1 的构成为：

```text
Stage1 历史缓存            2
Stage2 历史缓存            1
Stage3 历史缓存            1
统一 FIR 系数 ROM          1
双采样率测试正弦 ROM       1
--------------------------------
合计                       6 = 3 BRAM Tile
```

### 1.3 双时钟结构的准确表述

当前不是“两条滤波器链并行运行”，而是：

```text
20 MHz 控制域
   ├─ MMCM-A：5.6448 MHz（44.1 kHz × 128）
   └─ MMCM-B：6.1440 MHz（48 kHz × 128）
             ↓
        BUFGMUX_CTRL
             ↓
      一套共享滤波数据通路
```

这个表述应统一用于技术文档和 PPT。其创新点是“双采样率时钟家族无毛刺切换 + 单数据通路复用”，不是双通道并行滤波。

### 1.4 当前报告不能混用的旧数据

压缩包中同时包含早期全 FIR、Phase 6、Phase 7、字长优化、板级版本和最新国赛版本的报告。后续文档必须给每组数据附带：

```text
配置 ID + Git commit + Vivado run + 报告生成日期
```

建议把报告分成两套：

- `filter_core`：只统计滤波算法核心，不含按键、测试 ROM、MMCM 和 DAC 包装；
- `board_demo`：统计完整可下载顶层。

这样既能说明算法优化效果，也不会把测试正弦 ROM 等演示资源伪装成滤波器核心资源。

---

## 2. P0：先冻结一个可回退基线

### 2.1 推荐分支和标签

先完整保留当前未修复版本：

```text
baseline/nf-dualclock-436lut-5dsp-pre-fix
```

建议保存：

- 当前 bitstream；
- XPR 和正式构建 Generic；
- utilization/timing/power/DRC/methodology 报告；
- 当前板级波形；
- 当前失败仿真日志；
- 当前系数表；
- 一份 `baseline_manifest.json`。

`baseline_manifest.json` 至少应记录：

```json
{
  "config_id": "nf_dualclock_pre_fix_436lut_5dsp",
  "device": "xc7a35tfgg484-2",
  "vivado": "2018.3",
  "top": "board_demo_competition_dac8_top",
  "git_commit": "<commit_sha>",
  "stage3_coeff_format": "Q14 integers interpreted as Q15 - known issue",
  "rtl_bittrue_status": "invalid: golden files missing",
  "lut": 436,
  "ff": 471,
  "dsp": 5,
  "bram_tile": 3
}
```

### 2.2 基线冻结后的分支顺序

建议按下面顺序创建分支：

```text
fix/nf-stage3-qformat
fix/nf-verification-closure
fix/nf-cdc-reset-io
opt/nf-cic-n3-hold
opt/nf-bram2
opt/nf-mmcm-power
exp/nf-cic-n4-performance
research/nf-wordlength-tpe
research/nf-256x-two-dsp
```

每个分支只解决一个可清晰验收的问题。不要把系数、CDC、BRAM、MMCM 和 CIC 阶数同时改在一次提交中。

---

## 3. P1：必须先修复 Stage3 Q14/Q15 错配

### 3.1 错误原理

对于 2× 多相插值 FIR，直流输入时，每个输出相位都应重构为相同的直流值。因此两个相位各自的系数和都应接近 1：

\[
G_p=\sum_k h_p[k]\approx1,\qquad p\in\{0,1\}
\]

当前 Stage3 两相整数系数和均为：

\[
\sum_k c_p[k]=16382
\]

按原来的 Q14 解释：

\[
G_p=\frac{16382}{2^{14}}\approx0.999878
\]

是正确的。

但当前共享 MAC 统一按 Q15 右移：

\[
G_p=\frac{16382}{2^{15}}\approx0.499939
\]

因此 Stage3 产生：

\[
20\log_{10}(0.499939)\approx-6.022\ \mathrm{dB}
\]

这会导致：

- 4× 输出不经过 Stage3，幅度正常；
- 8× 输出经过 Stage3，低约 6.02 dB；
- 128× 输出同样低约 6.02 dB；
- 将频响各自做 DC 归一化后，纹波和阻带看起来仍正常，因此这个错误很容易被掩盖。

### 3.2 推荐修复：把 Stage3 统一改成真正的 Q15

不要修改最终 `<<4` 为 `<<5`。正确方法是将 Stage3 整数系数乘 2，使其与共享 MAC 的 Q15 小数位一致。

#### Phase 0

| 顺序 | 当前 Q14 整数 | 修复后 Q15 整数 | 16 bit 十六进制 |
|---:|---:|---:|---:|
| 0 | 202 | 404 | `0x0194` |
| 1 | -1636 | -3272 | `0xF338` |
| 2 | 9625 | 19250 | `0x4B32` |
| 3 | 9625 | 19250 | `0x4B32` |
| 4 | -1636 | -3272 | `0xF338` |
| 5 | 202 | 404 | `0x0194` |

#### Phase 1

| 顺序 | 当前 Q14 整数 | 修复后 Q15 整数 | 16 bit 十六进制 |
|---:|---:|---:|---:|
| 0 | -74 | -148 | `0xFF6C` |
| 1 | 261 | 522 | `0x020A` |
| 2 | 16008 | 32016 | `0x7D10` |
| 3 | 261 | 522 | `0x020A` |
| 4 | -74 | -148 | `0xFF6C` |

修复后两相系数和为：

\[
32764/2^{15}\approx0.999878
\]

中心系数 `32016` 仍小于 16 bit 正数上限 `32767`，因此统一系数 BRAM 的 16 bit 物理宽度不需要增加。

### 3.3 必须同步修改的 RTL 位置

当前正式工程至少存在两套系数来源，必须保持一致：

1. `XC7A35T_interp.srcs/sources_1/new/national_finals/nf_unified_fir_coeff_bram.v`
   - 综合路径：`RAMB18E1.INIT_02/INIT_03`；
   - 仿真路径：`coeff_mem[32..37]` 和 `coeff_mem[48..52]`。
2. `XC7A35T_interp.srcs/sources_1/new/all2x_v7/interp2_stage23_lutram_cic_dsp_ce.v`
   - `STAGE3_FLAT != 0` 分支下的 `coeff_rom`；
   - `coeff_sequence_bram[32..37]`；
   - `coeff_sequence_bram[48..52]`。

旧文件 `XC7A35T_interp.srcs/sources_1/new/all2x_v4/interp2_stage23_shared_dsp_ce.v` 中已经保留了上述正确 Q15 系数，可用作交叉核对，但不能直接把旧模块替换回当前数据通路。

不能只修改 `ifndef SYNTHESIS` 的数组，也不能只改 RAMB18 的 INIT。否则 RTL 行为仿真和综合后硬件会使用不同系数。

建议不要继续手工维护长 INIT 十六进制字符串，而是新增系数生成脚本，由同一份整数数组同时生成：

```text
generated/nf_fir_coeffs.vh
generated/nf_unified_coeff_init.vh
verification/vectors/coeff_manifest.json
```

生成后自动检查：

- 两相系数严格对称；
- 每相系数和；
- 十进制、十六进制和 RAMB18 INIT 一致；
- Q 格式；
- SHA-256。

### 3.4 系数乘二后，累加器必须从“35 bit 必然够”改成 36 bit 边界

当前 `interp2_stage23_lutram_cic_dsp_ce.v` 中有一条专门针对国赛 Stage3 的快速路径：

```text
NF_STAGE3_ACC_W = 35
dsp_mac_full[34:15] 直接作为 20 bit 输出
```

修复系数后，这个证明不再成立。

对 20 bit 有符号输入：

\[
|x|_{\max}=2^{19}-1=524287
\]

修复后 Phase 0 的绝对系数和为：

\[
\sum|c_k|=45852
\]

最坏累加绝对值上界为：

\[
524287\times45852=24039607524
\]

而 35 bit 有符号数最大值只有：

\[
2^{34}-1=17179869183
\]

因此至少需要 36 bit 有符号范围：

\[
2^{35}-1=34359738367
\]

Phase 1 同样越过 35 bit 边界：

\[
\sum|c_k|=33356,
\quad524287\times33356=17488117172>2^{34}-1
\]

推荐修改方式：

1. 保留共享 DSP 的 48 bit `P` 寄存器；
2. 保留当前共享 `STAGE23_ACC_W=38`，不需要增加 DSP；
3. 删除或关闭 `gen_national_finals_stage3_proven_width` 的直接截取快速路径；
4. Stage3 统一走通用的算术右移 + 符号扩展检查 + 20 bit 饱和路径；
5. 新增断言，检查有效累加结果的高位是否符合声明范围；
6. 在位真模型中统计 Stage3 的最大/最小累加值和 saturation 次数。

如果为了省少量 LUT 重新建立“无需饱和”的证明，也必须以全输入范围的形式化上界或穷举可达范围为依据，不能继续沿用旧的 35 bit 常数。

### 3.5 P1 验收门槛

先只验证修复，不做 CIC/BRAM/CDC 结构改造。

必须通过：

- 每相 Q15 系数和为 `32764`；
- 4×、8×、128× 的绝对增益不再相差约 6.02 dB；
- 997 Hz 或 1 kHz、−1 dBFS 正弦的模式间数字幅度差 `≤0.01 dB`；
- RTL 与修复后的独立位真模型逐点 `0 LSB`；
- Stage3 普通输入无意外饱和；
- 资源目标建议 `≤500 LUT、≤550 FF、≤5 DSP、≤3 BRAM Tile`；
- 重新生成实现报告，不再引用修复前的 436 LUT 作为最终结果。

P1 完成后建立第一个可信标签：

```text
baseline/nf-dualclock-qformat-fixed
```

---

## 4. P2：重建完整 MATLAB—位真—RTL 验证闭环

### 4.1 四层证据链

下一阶段必须明确区分四种比较：

```text
MATLAB 浮点模型
  ↓ 判断算法频响、绝对增益、线性相位
MATLAB/整数位真模型
  ↓ 判断字长、舍入、饱和、模运算是否满足指标
RTL
  ↓ 与当前位真模型逐点 0 LSB
FPGA + AD9708
  ↓ 判断时钟、I/O、模式切换和实物功能
```

原则：

- RTL 与当前位真模型必须 0 LSB；
- 只有严格等效优化才要求新旧版本 0 LSB；
- 修改系数、字长或 CIC 阶数后，新模型不应再与旧模型强行 0 LSB；
- golden 必须由独立位真模型生成，禁止用 RTL 输出反向生成 golden；
- 任一 `.mem` 文件打不开时立即 `$fatal`，不能继续让 `X` 值进入比较。

当前 `mismatch=43776` 是因为以下文件未找到：

```text
impulse_input_24bit.mem
impulse_y4_golden_24bit.mem
impulse_y8_golden_24bit.mem
impulse_y128_golden_24bit.mem
```

这次结果应标记为“测试无效”，既不能证明 RTL 错，也不能证明 RTL 对。

### 4.2 六种正式组合

| 输入家族 | 模式 | 输出采样率 | 128×基准时钟 |
|---|---:|---:|---:|
| 44.1 kHz | 4× | 176.4 kHz | 5.6448 MHz |
| 44.1 kHz | 8× | 352.8 kHz | 5.6448 MHz |
| 44.1 kHz | 128× | 5.6448 MHz | 5.6448 MHz |
| 48 kHz | 4× | 192 kHz | 6.144 MHz |
| 48 kHz | 8× | 384 kHz | 6.144 MHz |
| 48 kHz | 128× | 6.144 MHz | 6.144 MHz |

1× 旁路也应测试，但它属于板级控制和 DAC 接口测试，不计入插值滤波器频响验收。

### 4.3 统一激励集

| 编号 | 激励 | 建议配置 | 主要目的 |
|---|---|---|---|
| T00 | 全零 | 4096 个输入样点 | 复位、零状态、DAC 中点码 |
| T01 | 正冲激 | `2^22` 后接零 | 冲激响应、固定时延、频响 |
| T02 | 负冲激 | `-2^22` 后接零 | 符号扩展、负数舍入 |
| T03 | 正/负直流 | `±2^20、±2^22` | DC 增益、Stage3 Q 格式 |
| T04 | 正负阶跃 | `0→正→负→0` | 过冲、状态清除 |
| T05 | 最大码 | `0x7FFFFF` | 正向边界 |
| T06 | 最小码 | `0x800000` | 负向边界 |
| T07 | 最大/最小交替 | 连续 4096 点 | 最坏翻转、累加范围 |
| T08 | 低频正弦 | 997 Hz，−1 dBFS | 绝对增益、量化噪声 |
| T09 | 展示正弦 | 15 kHz，当前 ROM 幅度 | 六组合板测一致性 |
| T10 | 通带边缘 | 19.9/20 kHz，−6 dBFS | 最差通带误差 |
| T11 | 多音 | 1/5/10/15/20 kHz | 综合通带检查 |
| T12 | 随机 PCM | 10 个固定 seed × 4096 点 | 发布级逐点回归 |
| T13 | 随机 valid 间隔 | 0～7 拍空隙 | 串行 comb/调度健壮性 |
| T14 | 运行中复位 | 各 MAC 和 CIC burst 相位 | 恢复、旧数据泄漏 |
| T15 | 模式/家族切换 | 随机相位、每方向 100 次 | CDC、锁定、窄脉冲 |

建议三级回归规模：

```text
提交前：冲激 + 1 seed × 256 点
每日：  冲激 + 4 seed × 1024 点
发布：  全部极端输入 + 10 seed × 4096 点
```

### 4.4 浮点模型验收

#### 绝对增益

禁止只画归一化频响。必须额外计算：

\[
G_M=\frac{A_{\text{out},M}}{A_{\text{in}}},
\qquad E_{G,M}=20\log_{10}G_M
\]

其中 `M = 4, 8, 128`。

硬门槛：

- 每种模式 `|E_G| ≤ 0.01 dB`；
- 任意两种模式的绝对增益差 `≤0.01 dB`；
- 每个 2× FIR 的两个多相分支系数和都分别接近 1。

#### 频率指标

正式指标建议统一为：

| 指标 | 硬门槛 | 发布建议 |
|---|---:|---:|
| 10 Hz～20 kHz 通带峰峰纹波 | ≤0.010 dB | ≤0.009 dB |
| 最差相对阻带 | ≥70 dB | ≥72 dB |
| 模式间绝对增益差 | ≤0.010 dB | ≤0.005 dB |

44.1 kHz 家族的第一镜像阻带从 `44.1−20=24.1 kHz` 开始；48 kHz 家族从 `28 kHz` 开始。128× 模式要搜索全部镜像带，不能只检查第一段阻带。

当前 N3 128× 最差阻带约 72.37 dB，只有约 2.37 dB 裕量，因此在修正 Stage3 后，不要立即继续机械减系数字长。

#### 严格线性相位

必须同时使用结构证明和数值检查：

- 浮点系数严格对称；
- 整数量化后仍逐项完全对称；
- 半带零系数位置不被破坏；
- 三抽头补偿器首尾相等；
- 浮点冲激响应镜像相对误差 `≤1e-12`；
- 通带相位直线拟合最大残差建议 `≤1e-6 rad`。

### 4.5 位真模型必须显式定义的规则

每一级必须记录：

```text
输入位宽
系数位宽和小数位
乘积位宽
累加器位宽
算术右移
舍入方法及负数规则
饱和或回绕
CIC 模 2^W 运算
输出取位
```

每个内部节点输出以下监测量：

```text
min_value
max_value
max_abs
declared_width
headroom_bits
overflow_count
wrap_count
saturation_count
rounding_count
```

普通 FIR、桥接和补偿器中的意外 overflow/wrap 必须为 0。CIC 积分器如果明确采用模 `2^W` 运算，可以发生 wrap，但 MATLAB 和 RTL 必须逐次完全一致，最终输出不能出现未定义回绕。

### 4.6 RTL 回归验收

模块级至少覆盖：

| 模块 | 建议 TB | 验收重点 |
|---|---|---|
| 舍入/饱和 | `tb_nf_round_sat_exhaustive.sv` | 正负边界、tie、最大最小码 |
| Stage1 | `tb_nf_stage1_bittrue.sv` | 两相、BRAM 延迟、截止时间 |
| Stage2/3 | `tb_nf_stage23_bittrue.sv` | 共享调度、Q 格式、绝对增益 |
| 系数 BRAM | 现有 primitive TB | 全地址、全系数、读延迟 |
| CIC 补偿 | 现有补偿器 TB | 连续/空隙输入、边界 |
| 串行 comb | 现有等效 TB | 与并行参考 0 LSB |
| N3 Hold | `tb_nf_cic_n3_hold_equiv.sv` | 与原 N3 样点 0 LSB |
| 模式 CDC | `tb_nf_mode_cdc_handshake.sv` | 原子提交、ack、抖动 |
| 顶层复位 | `tb_nf_reset_recovery.sv` | 各状态中断、无旧数据 |

整链路回归必须同时检查：

- `dbg_y4`；
- `dbg_y8`；
- `y128`；
- 样本值；
- 第一个 valid 延迟；
- valid 间隔和总数；
- X/Z；
- overflow/saturation/assertion。

稳态 valid 间隔应为：

| 节点 | 128×基准时钟间隔 |
|---|---:|
| 4× | 32 拍 |
| 8× | 16 拍 |
| 128× | 1 拍 |

允许结构优化改变固定延迟，但延迟必须写入 manifest。比较脚本只能去除 manifest 声明的固定前导延迟，不能自动搜索任意对齐量来掩盖错误。

### 4.7 推荐验证目录

```text
verification/
├── config/
│   ├── nf_filter_config.json
│   ├── nf_latency_manifest.json
│   └── schema.json
├── matlab/
│   ├── nf_design_float.m
│   ├── nf_build_bittrue.m
│   ├── nf_generate_coeffs.m
│   ├── nf_generate_vectors.m
│   ├── nf_check_absolute_gain.m
│   ├── nf_check_frequency_response.m
│   ├── nf_check_phase.m
│   ├── nf_check_overflow.m
│   └── nf_run_model_regression.m
├── vectors/
│   ├── fs44100/{mode4,mode8,mode128}/
│   ├── fs48000/{mode4,mode8,mode128}/
│   └── manifest.json
├── rtl/
│   ├── unit/
│   ├── chain/
│   ├── cdc_reset/
│   └── assertions/
├── tcl/
│   ├── run_unit_regression.tcl
│   ├── run_chain_regression.tcl
│   ├── run_cdc_report.tcl
│   ├── run_synth_impl.tcl
│   ├── run_power_saif.tcl
│   └── collect_reports.tcl
└── results/<config_id>_<git_sha>_<date>/
```

P2 完成后建立标签：

```text
baseline/nf-dualclock-qformat-bittrue-verified
```

---

## 5. P3：CDC、复位、DRC 和 AD9708 I/O 闭环

### 5.1 当前警告应按规则 ID 管理

当前直接 DRC：

| 规则 | 数量 | 含义 |
|---|---:|---|
| DPOR-1 | 33 | DSP 异步负载/控制问题 |
| DPREG-4 | 1 | 动态 OPMODE 相关反馈风险 |
| REQP-1840 | 20，已达报告上限 | RAMB18 异步控制检查 |
| DPIP-1 | 7 | DSP 输入未流水化建议 |
| DPOP-1 | 3 | DSP 输出未流水化建议 |

当前 Methodology DRC：

| 规则 | 数量 | 含义 |
|---|---:|---|
| DPIR-1 | 96 | 异步复位寄存器阻碍 DSP 吸收 |
| LUTAR-1 | 1 | LUT 驱动异步复位 |
| SYNTH-4 | 2 | 浅深度 BRAM |
| TIMING-18 | 4 | 缺少输入/输出延迟 |
| TIMING-28 | 4 | 约束引用自动派生时钟 |

最终发布门槛建议：

- Error/Critical Warning 为 0；
- `DPOR-1、DPREG-4、REQP-1840、DPIR-1、LUTAR-1` 为 0；
- `TIMING-18、TIMING-28` 为 0，或对矩阵键盘这类非同步外设使用明确、有理由的 false path；
- `DPIP-1/DPOP-1` 可以在时序裕量充分时书面 waiver，不必为了清警告增加无意义流水；
- `SYNTH-4` 可以保留，但应说明使用浅 BRAM 是为了降低 BRAM Tile，而不是误推断；
- 不允许通过降低 DRC 严重级别伪装清零。

### 5.2 两位模式总线必须改为原子握手

当前 `mode_sel[1:0]` 两个位分别经过两级同步。单个位不会亚稳扩散，但 `00→11` 时两个 bit 可能在不同音频时钟拍到达，音频域可能短暂看到 `01` 或 `10`。

推荐结构：

```text
20 MHz 控制域
  mode_shadow[1:0] 保持稳定
  mode_req_toggle 翻转
          │
          ├── mode_shadow 总线在握手期间禁止修改
          └── req toggle 两级同步
                         ↓
音频域检测 req 改变
  等待 2～3 拍总线稳定
  原子锁存 mode_shadow
  在安全边界提交 mode_state
  mode_ack_toggle 返回控制域
```

建议音频域提交顺序：

```text
检测请求
→ 输出静音为 0x80
→ 等待当前 MAC/CIC burst 到安全点，或同步清空数据通路
→ 原子锁存新模式
→ 清空下游无效状态
→ 预热规定样点数
→ 恢复输出
→ 返回 ack
```

硬门槛：

- 音频域只观察旧模式或新模式；
- 不出现第三种中间编码；
- 每个请求都有且只有一个 ack；
- 随机相位、每个切换方向 100 次均通过；
- 切换期间 `dac_data=8'h80`，不输出旧模式残留。

### 5.3 数据通路改成同步复位，异步复位只保留在同步器入口

当前大量数据通路寄存器采用：

```verilog
always @(posedge clk or negedge rst_n)
```

这些寄存器又直接驱动 DSP/BRAM 地址、控制和数据输入，造成 DPIR、REQP 和 DPOR 警告。

推荐改成两层复位：

```text
外部/控制域 reset request
       ↓ 异步置位、同步释放
仅复位同步器使用异步复位
       ↓
audio_reset_sync（音频域同步有效）
       ↓
所有 FIR/CIC/BRAM 指针/调度状态采用同步复位
```

注意：BRAM 内容不需要逐项清零。继续使用：

- 清指针；
- 清 `fill_count`；
- 未写历史由 mask 当零；
- ROM 不复位；
- DSP `RSTP` 由寄存后的同步控制驱动。

家族切换前，先保证旧时钟域至少执行若干个同步复位时钟边沿，再切换 BUFGMUX。这样既能消除警告，也不会因为时钟停止而使同步复位来不及执行。

### 5.4 家族切换状态机不要只靠固定倒计时

当前 `family_switch_cnt` 在固定计数值处直接切 `family_active`。两颗 MMCM 常开时一般能工作，但后续加入 MMCM 掉电或 DRP 后必须改为基于状态和 `LOCKED` 的握手。

推荐状态：

```text
IDLE
→ MUTE_AND_RESET
→ WAKE_TARGET_MMCM
→ WAIT_TARGET_LOCK
→ SWITCH_BUFGMUX
→ WAIT_NEW_CLOCK_EDGES
→ RESET_PIPELINE
→ WARM_UP
→ RELEASE_MUTE
→ ACK
```

必须增加：

- `LOCKED` 连续稳定计数；
- 目标锁定超时；
- 切换过程中重复请求处理；
- MMCM 失锁自动静音；
- 当前家族和请求家族的独立状态；
- 切换完成 ack。

### 5.5 AD9708 输出应使用 IOB 数据寄存器和专用时钟输出

AD9708 在 CLOCK 上升沿锁存数据，官方手册给出的数字接口最坏要求为：

| 参数 | 数值 |
|---|---:|
| 输入建立时间 `tS` | 2.0 ns |
| 输入保持时间 `tH` | 1.5 ns |
| 最小时钟脉宽 `tLPW` | 3.5 ns |

当前 `dac_data_r` 在 `clk_audio_128x` 下降沿更新，这个方向是正确的；6.144 MHz 时半周期约：

\[
T/2=\frac{1}{2\times6.144\ \mathrm{MHz}}\approx81.38\ \mathrm{ns}
\]

但目前：

- `dac_data_r` 未明确约束进 IOB；
- `dac_clk` 是 counter bit/根时钟的组合选择；
- 12 个输出端口没有 output delay；
- 内部 WNS 通过不能证明 DAC 引脚建立/保持时间通过。

推荐：

1. 8 bit 数据在根音频时钟下降沿更新；
2. 对数据寄存器设置 `IOB=TRUE`；
3. `dac_clk` 使用 ODDR 或等价专用输出寄存器产生；
4. 128× 模式用 ODDR 输出 50% 占空比时钟；
5. 低倍率模式用同步慢时钟状态驱动 ODDR 的 D1/D2，不再直接用大组合 mux 驱动时钟引脚；
6. 模式切换只在所有候选输出为低时提交；
7. 为 4×、8×、128× 各建立可追踪的 generated/virtual clock 约束。

输出延迟不要随意填写 0。设 PCB 数据/时钟最小最大延迟分别为 `ddata_min/max`、`dclk_min/max`，则应按下面的外部需求建立约束：

\[
t_{out,max}=t_S+ddata_{max}-dclk_{min}
\]

\[
t_{out,min}=-t_H+ddata_{min}-dclk_{max}
\]

如果暂时没有 PCB 走线数据，可先给数据/时钟相对偏差预留保守预算，例如 0.5 ns，但必须把它写成假设，并在板级测量中确认。

建议验收：

- 8 bit bus skew `≤1 ns`；
- post-route setup/hold slack 均 `≥0.5 ns`；
- 板测数据在 DAC 上升沿前后各保持足够裕量；
- `dac_clk` 占空比 45%～55%；
- 切换时无多次阈值穿越和窄脉冲；
- walking-one/walking-zero 验证 8 根线全部正确。

AD9708 官方数据手册：<https://www.analog.com/media/en/technical-documentation/data-sheets/ad9708.pdf>

### 5.6 P3 验收门槛

| 类别 | 门槛 |
|---|---|
| CDC | Critical/Unsafe/Unknown 为 0；模式总线原子提交 |
| 复位 | 各 MAC/CIC 状态中断后恢复，无旧数据 |
| 时钟 | 六组合频率正确；无小于约 65 ns 的异常窄脉冲 |
| DRC | 必清规则为 0；其余有书面 waiver |
| STA | WNS/WHS/WPWS 非负；无未约束内部路径；DAC 外部时序已约束 |
| 板级 | 100 次模式/家族切换无死钟、锁死和满幅异常毛刺 |

完成 P3 后再建立真正的国赛稳定基线：

```text
baseline/nf-dualclock-correct-verified
```

后续所有创新分支都从这个标签创建。

---

## 6. P4-A：N3 CIC 严格 Hold 等效，目标 5 DSP → 4 DSP

### 6.1 数学依据

普通 N 阶 CIC 插值器为：

\[
C^N\rightarrow\uparrow R\rightarrow I^N
\]

其中一对“低速 comb + 插零 + 高速 integrator”对 `M=1` 可严格等效为长度 `R` 的样值保持器：

\[
C\rightarrow\uparrow R\rightarrow I
\equiv\mathrm{Hold}_R
\]

因此当前 `R=16、N=3`：

\[
C^3\rightarrow\uparrow16\rightarrow I^3
\]

可严格改写为：

\[
C^2\rightarrow\mathrm{Hold}_{16}\rightarrow I^2
\]

这不是“一阶保持器近似三级 CIC”，而是删除一对可被 Hold 精确替换的 comb/integrator。

参考：Losada 与 Lyons，[Reducing CIC Filter Complexity](https://doi.org/10.1109/MSP.2006.1657825)。

### 6.2 新模块建议

不要直接覆盖当前已验证模块，新增：

```text
national_finals/cic_interp16_n3_hold2_dsp_ce.v
```

建议接口与当前 `cic_interp16_serial_comb_dsp_ce.v` 保持一致，以参数选择新旧结构：

```text
USE_N3_HOLD_EQUIV = 0/1
```

新内部结构：

```text
21 bit 输入
→ 低速 comb1
→ 低速 comb2
→ 保存 hold_sample
→ 连续 16 个 ce_out 周期重复 hold_sample
→ 高速 integrator1
→ 高速 integrator2
→ 原有归一化舍入/饱和
→ 20 bit 输出
```

### 6.3 位宽和缩放

原 N3 CIC 的完整内部增长仍按：

\[
B_{full}=B_{in}+N\log_2R=21+3\times4=33\ \mathrm{bit}
\]

等效变换不改变总传递函数，因此：

- 两个高速积分器仍建议保留 33 bit 模运算；
- 不在反馈积分器内部随意删除 LSB；
- 输出幅度归一化仍为：

\[
R^{N-1}=16^2=256=2^8
\]

- 当前输出右移 8 bit 的标度原则不变；
- 最后仍由统一舍入/饱和模块量化到 20 bit。

### 6.4 时序和对齐

当前串行 comb 需要 3 拍，新结构只需要 2 拍，首次输出 valid 可能提前 1 拍。两种选择都可以：

1. 接受固定延迟改变，在 manifest 中更新延迟；
2. 人为补 1 拍，使新旧模块 valid 对齐，便于等效对拍。

数值序列必须完全相同。严格等效测试应允许一个明确、固定的延迟差，但不允许自动搜索对齐。

### 6.5 验收

- 原 N3 与 Hold N3：冲激、极端输入、随机 PCM 的有效输出逐点 `0 LSB`；
- CIC 内部模回绕次数与位真模型一致；
- 频响与修正后的 N3 基线数值一致；
- DSP 目标从 5 降到 4；
- LUT/FF 可适度增加，但建议不超过 `550/600`；
- WNS/WHS 非负；
- 新结构 DRC 必清规则为 0；
- 板级六组合均通过。

如果综合后仍使用 5 个 DSP，则该结构不能宣称 DSP 优化成功，应检查：

- Hold 是否被误综合为额外加法器；
- 两个 integrator 是否仍各占一颗 DSP；
- comb 是否被 `use_dsp` 属性推回 DSP；
- 计数器/减法器是否误用 DSP。

可额外做一组资源对照：将其中一个 33 bit integrator 明确映射到 LUT 进位链。若 LUT 增量较小、时序仍满足，可形成 `3 DSP` 的极限资源候选；但国赛主线优先保留两个 DSP 积分器的低风险结构。

---

## 7. P4-B：联合两项 BRAM 调度，目标 3 Tile → 2 Tile

只做其中一项时，`RAMB18E1` 数量从 6 降到 5，Vivado 报告仍可能是 3 个 BRAM Tile。因此两项应分别验证、最后联合实施。

### 7.1 Stage1：双读历史改为单 BRAM 串行双样本读取

#### 当前结构

Stage1 的 64×24 bit 历史需要：

- 每拍同时读出一对对称样本；
- 26 对样本完成 26 次 MAC；
- 24 bit 宽度在 RAMB18 真双口模式下导致两颗 RAMB18E1。

#### 修改结构

使用一颗 RAMB18E1 的 36 bit Simple Dual Port 模式：

```text
Port A：24 bit 写
Port B：24 bit 单读
```

每一对样本改为两拍读取：

```text
第 0 拍：发出 left 地址，同时发出 coeff 地址
第 1 拍：left 返回，暂存；发出 right 地址
第 2 拍：right 返回，与 left 相加，执行一次 MAC；同时发下一对 left
```

26 对样本约需要 52 个读周期，加上启动、同步读延迟、末次 MAC 和舍入提交，目标总周期约 55～58 拍。

Stage1 相邻 `ce2_out` 之间有 64 个 128×时钟周期，因此理论上仍有约 6～9 拍余量。

#### 关键细节

- 当前输入样本写入和读取同地址时，建议用 `x_current` 旁路，不依赖 BRAM 同地址读写模式；
- 外部统一系数 BRAM 的读延迟必须与第二个样本返回对齐；
- 系数每对只读取一次并保持两拍；
- 保留 `fill_count` 零屏蔽，不复位 BRAM 内容；
- 增加 deadline assertion：下一个 Stage1 phase 到来时，前一个结果必须已完成；
- 旧 Vivado 对浅深 RAM 推断不稳定，建议用独立 RAMB18E1 SDP wrapper 明确约束 36 bit 模式。

AMD RAMB18E1 参考：<https://docs.amd.com/r/en-US/ug953-vivado-7series-libraries/RAMB18E1>

#### 验收

- 与修正后的 Stage1 参考逐点 0 LSB；
- `deadline_miss=0`；
- RAMB18E1 数量减少 1；
- Stage1 DSP 仍为 1；
- 44.1/48 kHz 均通过随机 valid 和复位测试。

### 7.2 Stage2/Stage3：合并历史 BRAM

#### 目标布局

```text
bank=0，地址 0..15  ：Stage2，22 bit
bank=1，地址 16..31 ：Stage3，20 bit 符号扩展到 22 bit
```

物理上使用一颗 `32×22 bit` Simple Dual Port RAMB18E1。

#### 为什么可行

Stage2 和 Stage3 已共享一颗 MAC，同一时刻只会有一个 active job，因此历史读端口天然可复用。

#### 隐藏风险：同一拍可能出现两个写请求

Stage2 和 Stage3 的 `ce_out` 可能在同一 128×时钟拍对齐，不能假设永远只有一个写请求。

推荐增加两项写入缓冲：

```text
stage2_write_pending + data + addr
stage3_write_pending + data + addr
```

或使用深度 2 的小型 write queue，由单写端口在后续空闲拍依次提交。必须保证历史写入在对应 job 读取前完成。

不要简单用 `if/else` 丢弃低优先级写请求。

#### 验收

- Stage2/Stage3 所有历史读取与独立 BRAM 版本 0 LSB；
- 同拍双写不丢失；
- write queue 不溢出；
- pending job 不被下一次 CE 覆盖；
- RAMB18E1 数量减少 1；
- 共享 MAC 调度 deadline 全部满足。

### 7.3 两项联合结果目标

```text
Stage1 history     2 → 1 RAMB18
Stage2/3 history  2 → 1 RAMB18
Coeff ROM         1 → 1 RAMB18
Test ROM          1 → 1 RAMB18
--------------------------------
总计              6 → 4 RAMB18
BRAM Tile         3 → 2
```

联合版本的资源验收建议：

| 资源 | 目标 |
|---|---:|
| DSP | ≤4（与 N3 Hold 合并后） |
| BRAM Tile | ≤2 |
| LUT | ≤600 |
| FF | ≤650 |

如果为合并 BRAM 增加的队列、地址 mux 和控制逻辑使 LUT 大幅增加，仍应保留实验结果，但不必强行作为最终主线。BRAM Tile 的减少是主要目标，LUT 增量需要透明报告。

---

## 8. P5-A：双 MMCM 功耗优化

当前 0.271 W 总功耗中，MMCM 项约 0.197 W。继续减少几十个 LUT 几乎不会显著改变总功耗，因此低功耗重点必须转向时钟系统。

### 8.1 先做低风险版本：关闭未选中的 MMCM

给两颗 `MMCME2_ADV` 的 `PWRDWN` 接入控制状态机：

```text
正常运行：只保持当前家族 MMCM 工作
切换请求：唤醒目标 MMCM
等待 LOCKED 连续稳定
静音并复位数据通路
切 BUFGMUX
等待新时钟边沿
释放数据通路
关闭旧 MMCM
```

必须有：

- 上电默认家族；
- 目标锁定超时；
- 失锁保护；
- 切换期间不同时关闭两颗；
- 测试模式下可强制两颗常开，便于 A/B 对照。

### 8.2 再做单 MMCM + DRP

当前两组配置分别为：

| 家族 | `DIVCLK_DIVIDE` | `CLKFBOUT_MULT_F` | `CLKOUT0_DIVIDE_F` |
|---|---:|---:|---:|
| 44.1 kHz | 2 | 62.375 | 110.500 |
| 48 kHz | 1 | 36.250 | 118.000 |

单 MMCM 方案需要在静音/复位期间通过 DRP 更新反馈倍频、输入分频、输出分频和对应的 lock/filter 参数，然后等待重新锁定。

建议新增独立模块：

```text
national_finals/single_mmcm_drp_audio_clock.v
national_finals/mmcm_drp_profile_rom.v
```

该方案的优点：

- MMCM 从 2 颗减到 1 颗；
- 不需要 BUFGMUX 在两颗 MMCM 之间选择；
- 理论上进一步减少时钟静态/动态功耗。

风险：

- DRP 寄存器配置复杂；
- 每次家族切换必然失锁并停钟；
- 需要更完整的超时、恢复和静音状态机；
- 配置值与 Vivado/器件相关，必须由官方流程生成并板测。

参考：[AMD XAPP888，7 Series MMCM Dynamic Reconfiguration](https://docs.amd.com/v/u/en-US/xapp888_7Series_DynamicRecon)。

### 8.3 模式相关 CE 门控

当前低倍率模式下，后续级仍持续运行。可按模式关闭无用计算：

| 模式 | 必须运行的模块 | 可暂停的模块 |
|---|---|---|
| 1× | 输入 ROM/旁路 | 全部 FIR、补偿、CIC |
| 4× | Stage1、Stage2 | Stage3、补偿、CIC |
| 8× | Stage1、Stage2、Stage3 | 补偿、CIC |
| 128× | 全部 | 无 |

注意 Stage2/3 共用 DSP，4× 模式只能禁止 Stage3 job，不能关闭整颗共享 DSP。

由低倍率切回高倍率时，下游历史已过期。最简单可靠的策略是：

```text
切换请求 → 静音 → 同步清空/重启相关级 → 预热 → 恢复
```

不要直接恢复旧状态。

### 8.4 功耗验收方法

当前功耗报告没有 SAIF，Confidence 只有 Medium，只能作为线索。

正式比较要求：

- 相同 FPGA、实现策略、电压、温度；
- 相同输入数据和测试时长；
- 分别覆盖两家族 × 4×/8×/128×/空闲；
- 从代表性仿真导出 SAIF；
- 预热至少 2 ms，再统计至少 10 ms；
- SAIF 网表匹配率建议 `≥95%`；
- 分别记录 Clock/MMCM/Logic/BRAM/DSP/IO 功耗；
- 动态功耗下降 `≥5%` 才宣称有显著改善。

不能把 `0.197 W / 2` 直接当成单 MMCM 的节省量，必须重新实现和报告。

---

## 9. P5-B：N4 Hold 性能版

### 9.1 结构

利用相同的严格等效关系：

\[
C^4\rightarrow\uparrow16\rightarrow I^4
\equiv
C^3\rightarrow\mathrm{Hold}_{16}\rightarrow I^3
\]

因此 N4 Hold 只需要 3 个高速积分器，和当前普通 N3 一样。配合两颗 FIR DSP，整机仍有机会保持 5 DSP。

### 9.2 初步补偿器

当前预筛选的对称三抽头补偿器为：

\[
[-11,\ 86,\ -11]/64
\]

其直流增益为：

\[
\frac{-11+86-11}{64}=1
\]

初步预筛选结果：

| 指标 | 预期值，尚待验证 |
|---|---:|
| 通带峰峰纹波 | 约 0.00812 dB |
| 最差相对阻带 | 约 78.62 dB |
| 相比当前 N3 的阻带提升 | 约 6.25 dB |

### 9.3 位宽

N4 完整内部位宽：

\[
B_{full}=21+4\times4=37\ \mathrm{bit}
\]

归一化幅度因子：

\[
R^{N-1}=16^3=4096=2^{12}
\]

因此必须重新定义：

- 三个 comb 的渐进位宽；
- Hold 输出位宽；
- 三个 37 bit integrator；
- 输出右移 12 bit；
- 负数舍入和最终饱和；
- 补偿器自然峰值余量。

### 9.4 N4 不是 N3 的位真等效替换

N4 的滤波响应与 N3 不同，因此：

- N4 RTL 必须与 N4 位真模型 0 LSB；
- N4 位真模型与 N4 浮点模型比较指标；
- 不能要求 N4 输出与 N3 旧 golden 0 LSB；
- 不能为了复用旧 golden 而调整输出取位掩盖差异。

### 9.5 Go/No-Go

Go 条件：

- 六组合全部满足通带、阻带、绝对增益和线性相位；
- 最差阻带实际 `≥77 dB`，且明显优于 N3；
- DSP `≤5`；
- 与 BRAM 优化合并后 Tile `≤2`；
- LUT `≤650`、FF `≤700`；
- 板级切换和输出正常。

No-Go 条件：

- 阻带提升不足 3 dB；
- 需要额外独立乘法器；
- 内部 37 bit 控制导致 LUT/时序显著恶化；
- 补偿峰值导致正常满幅输入频繁饱和。

N4 失败不影响 N3 资源主线，必须保持独立分支。

---

## 10. P5-C：联合整数系数与混合字长搜索

### 10.1 不再使用“全链路一起减一位”

建议把以下变量独立参数化：

- Stage1/2/3 系数字长和小数位；
- Stage1/2/3 累加器有效位宽；
- 24→22、22→20 桥接位宽和右移量；
- 补偿器整数系数和分母；
- CIC 输入、内部、输出位宽；
- 最终舍入/饱和方式。

有限字长下的最优整数系数，不等于浮点最优系数直接四舍五入。每个候选字长都应重新搜索整数系数，同时强制：

- 系数严格对称；
- 半带零系数位置；
- 直流增益约束；
- 线性相位；
- 系数取值范围；
- 六组合整体频响。

参考：[Kodek 2024，有限字长 FIR 系数优化](https://doi.org/10.1016/j.dsp.2023.104275)。

### 10.2 推荐搜索流程

```text
1. MATLAB/Python 位真模型快速评价数千个候选
2. 硬约束筛除不满足增益/纹波/阻带/溢出的方案
3. TPE 或 Bayesian 搜索 Pareto 前沿
4. 只对前 10～20 个候选运行 Vivado 综合
5. 对前 3～5 个候选运行布局布线和 SAIF 功耗
6. 选择资源版和性能版各一个
```

目标函数不要只用 LUT：

\[
J=w_1LUT+w_2FF+w_3DSP+w_4BRAM+w_5P_{dyn}-w_6Margin_{stop}
\]

硬约束优先于目标函数：

```text
绝对增益
通带纹波
阻带衰减
线性相位
无意外溢出
RTL 0 LSB
时序通过
```

相关方法：

- [Multiple-Wordlength Optimization](https://doi.org/10.1109/TCAD.2003.818119)
- [Simulation-Based Word-Length Optimization](https://doi.org/10.1109/78.476465)
- [2025 TPE/Bayesian FPGA DSP 字长搜索](https://doi.org/10.1109/ISCAS56072.2025.11043696)

### 10.3 何时停止

当前逻辑资源已经很低，不能为了少几十个 LUT 牺牲 70 dB 阻带和绝对增益。出现以下情况时停止该候选：

- 128× 阻带低于 72 dB 发布建议；
- 模式间增益差超过 0.01 dB；
- 资源减少不足 5%；
- 需要引入复杂补偿使最终控制资源反而增加；
- 板级输出饱和概率上升。

---

## 11. P5-D：256×计算时钟、两 DSP 研究版

这是高创新、也最高风险的路线，只适合作为论文型支线。

### 11.1 原理

把内部计算时钟提高到：

```text
44.1 kHz × 256 = 11.2896 MHz
48.0 kHz × 256 = 12.2880 MHz
```

而 DAC 仍以每两个计算时钟一次的 128×节拍更新。

这样：

- 一个微码 DSP 可调度三级 FIR 的全部 MAC；
- N3 Hold 只剩两个高速积分器；
- 在 256×时钟下，每个 128×输出样点有两个计算周期；
- 第 1 拍计算 `I1_next`，第 2 拍计算 `I2_next`；
- 第二颗 DSP 可时分计算两个积分器。

理论目标：

```text
三级 FIR            1 DSP
N3 Hold 两级积分器  1 DSP
-------------------------
总计                2 DSP
```

### 11.2 必须重新设计的内容

- 全局微码调度器；
- FIR 三个级的上下文寄存器；
- Stage1/2/3 BRAM 地址和端口冲突；
- DSP 系数、输入、累加器上下文切换；
- 两级积分器的先后依赖；
- 128×输出 CE；
- DAC ODDR；
- 44.1/48 kHz 双配置时钟；
- 调度 deadline 形式化断言。

### 11.3 Go/No-Go

Go：

- 所有 deadline assertion 通过；
- 与修正后的 N3 Hold 位真输出 0 LSB；
- DSP `≤2`；
- WNS/WHS 通过；
- LUT/FF 增量可接受；
- 板级六组合正常。

No-Go：

- 任一级 deadline 只有极小余量；
- BRAM 端口导致复制存储，抵消资源收益；
- 微码控制显著增加 LUT/功耗；
- 切换/复位后上下文难以可靠恢复。

该路线不应在临近比赛时替换已稳定主线。

参考：

- [Improved Resource Sharing for FPGA DSP Blocks](https://ieeexplore.ieee.org/document/7577373/)
- [作者公开全文](https://sfahmy.github.io/publications/2016-fpl-ronak.pdf)

---

## 12. 完整验证与发布门禁

### 12.1 算法门禁

| 项目 | 发布要求 |
|---|---|
| 六组合 | 全部覆盖 |
| 绝对增益 | 每模式及模式间差 `≤0.01 dB` |
| 通带峰峰纹波 | `≤0.010 dB` |
| 最差阻带 | `≥70 dB`，建议 `≥72 dB` |
| 线性相位 | 结构严格对称，数值检查通过 |
| RTL vs 当前位真 | 所有有效样点 `0 LSB` |
| X/Z | 0 |
| assertion/fatal | 0 |

### 12.2 CDC/时钟/复位门禁

| 项目 | 发布要求 |
|---|---|
| CDC Critical/Unsafe/Unknown | 0 |
| 两位模式总线 | 原子提交，不撕裂 |
| 模式/家族随机切换 | 每方向至少 100 次 |
| MMCM 未锁定 | 禁止有效数据输出 |
| 复位 | 无旧数据，无 pending/burst 残留 |
| 异常窄脉冲 | 0 |
| 切换静音 | DAC 保持 `0x80` |

### 12.3 实现门禁

| 项目 | 发布要求 |
|---|---|
| Error/Critical Warning | 0 |
| WNS/TNS | WNS≥0，TNS=0 |
| WHS/THS | WHS≥0，THS=0 |
| WPWS/TPWS | 非负/0 |
| 未约束内部端点 | 0 |
| DAC 输出约束 | 完整 |
| 必清 DRC | 0 |
| 其余 Warning | 有书面 waiver |

### 12.4 各版本资源目标

| 版本 | LUT 建议上限 | FF 建议上限 | DSP 目标 | BRAM Tile 目标 |
|---|---:|---:|---:|---:|
| 修正后的 N3 基线 | 500 | 550 | ≤5 | ≤3 |
| N3 Hold | 550 | 600 | ≤4 | ≤3 |
| N3 Hold + BRAM 合并 | 600 | 650 | ≤4 | ≤2 |
| N4 Hold 性能版 | 650 | 700 | ≤5 | ≤2 |

某项优化如果没有改善它声明的主要指标，就不能在报告中宣称成功。例如：

- N3 Hold 后仍是 5 DSP：DSP 优化失败；
- BRAM 合并后仍是 3 Tile：Tile 优化未实现；
- MMCM 掉电后动态功耗下降不足 5%：不能宣称显著低功耗；
- N4 阻带只提升 1 dB：性能收益不足。

### 12.5 AD9708 板级门禁

先做固定码测试：

```text
0x00, 0x01, 0x02, 0x04, 0x08,
0x10, 0x20, 0x40, 0x80, 0xFF,
walking-one, walking-zero, 0→255 ramp
```

再做六组合测试，记录：

- `dac_clk` 频率和占空比；
- 最短高/低脉宽；
- 15 kHz 输出频率；
- Vpp 和 DC 偏置；
- 三倍率模拟幅度差；
- 切换恢复时间；
- 最大瞬态；
- 示波器截图和原始 CSV/WFM。

门槛建议：

- 时钟误差 `≤200 ppm`，或不超过晶振规格和仪器误差之和；
- 占空比 45%～55%；
- 15 kHz 基波误差 `≤0.1%`；
- 同一家族 4×/8×/128× 模拟幅度差 `≤0.2 dB`；
- 数字 24 bit 节点模式间增益差仍 `≤0.01 dB`；
- 100 次切换无死钟、窄脉冲、锁死和满幅毛刺。

AD9708 只有 8 bit，模拟端不能直接证明 70 dB 阻带。阻带指标以 MATLAB 和 24 bit RTL 数据为正式证据，板测用于证明接口、时钟、幅度一致性和实物功能。

---

## 13. 实验记录模板

每次实验建议记录以下字段。

### 13.1 版本与环境

```text
Run ID
日期/执行人
分支、commit SHA、tag
worktree 是否 clean
配置 ID、配置 SHA
MATLAB 版本
Vivado 版本和器件
板卡编号
供电/温度
示波器和探头型号
```

### 13.2 算法与位真

```text
采样率家族
倍率
输入类型/幅度/长度/seed
输入和 golden SHA-256
绝对增益
通带峰峰纹波
最差阻带及频率
相位残差/群时延
各级 max_abs/headroom
overflow/wrap/saturation 次数
浮点—位真最大误差/SNR
```

### 13.3 RTL

```text
首输出延迟
valid 间隔
期望/实际输出数量
mismatch 数
最大 LSB 误差
X/Z 数量
assertion/fatal 数量
仿真耗时
PASS/FAIL 日志
```

### 13.4 实现和板级

```text
CDC Critical/Unsafe/Unknown/Safe
LUT/FF/CARRY4/DSP/RAMB18/BRAM Tile/MMCM
WNS/TNS/WHS/THS/WPWS/TPWS
未约束端点
各 DRC 规则数量
总/动态/静态/MMCM 功耗
SAIF 匹配率和置信度
dac_clk 频率/占空比/最短脉宽
DAC setup/hold/bus skew
Vpp/DC 偏置/模式间幅度差
切换最大瞬态/恢复时间
截图与原始波形路径
```

建议最终生成一张总对比表：

| Config ID | 功能 | 纹波 | 阻带 | 增益差 | LUT | FF | DSP | BRAM | WNS | 功耗 | 板测 |
|---|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---|
| N3 修正基线 | — | — | — | — | — | — | — | — | — | — | — |
| N3 Hold | — | — | — | — | — | — | — | — | — | — | — |
| N3 Hold+BRAM2 | — | — | — | — | — | — | — | — | — | — | — |
| N3 低功耗 | — | — | — | — | — | — | — | — | — | — | — |
| N4 性能版 | — | — | — | — | — | — | — | — | — | — | — |

---

## 14. 回退规则

出现以下任一情况，停止合入并退回最近已验证标签：

- 浮点或位真模型不满足指标；
- 任一模式绝对增益误差超过 0.01 dB；
- RTL 与当前 golden 出现任意 1 个 LSB 不一致；
- valid 丢失、重复、错位或出现 X/Z；
- 普通 FIR 出现未定义溢出；
- CIC 模运算与模型不一致；
- 模式总线出现撕裂；
- 时钟切换出现异常窄脉冲；
- 复位后泄漏旧数据；
- CDC 存在 Unsafe/Unknown；
- WNS/WHS/WPWS 为负或存在未约束路径；
- 必清 DRC 未归零；
- AD9708 存在错位、缺失数据位或约 6 dB 模式幅度差；
- 优化没有实现其声明的目标资源；
- 功耗下降不足 5% 却声称有显著收益。

各路线回退：

| 失败路线 | 回退方式 |
|---|---|
| Stage3 修复 | 回到 pre-fix 仅用于定位，不能作为最终发布 |
| N3 Hold | 关闭 Hold 参数，回到修正 N3 |
| BRAM 合并 | 恢复独立历史 RAM |
| MMCM 掉电/DRP | 回到双 MMCM 常开 |
| N4 | 不影响 N3 资源主线 |
| 新字长 | 恢复上一套系数和 Q 格式，不能只重做 golden |
| 板级 I/O 失败 | 优先回退 ODDR/IOB/XDC 改动，不动已通过位真的算法 |

---

## 15. 建议的实际执行清单

### 第一批：今天就应开始

- [ ] 冻结当前 436 LUT/5 DSP pre-fix 基线；
- [ ] 新建 `fix/nf-stage3-qformat`；
- [ ] 将 Stage3 两相整数系数乘 2，统一为 Q15；
- [ ] 同步修改 RAMB18 INIT、仿真数组和备用系数路径；
- [ ] 删除 35 bit 直接截取快速路径，恢复通用饱和检查；
- [ ] 加 Stage3 累加范围断言；
- [ ] 用 DC 和 997 Hz 正弦验证 4×/8×/128× 绝对幅度；
- [ ] 重新综合，得到“修复后资源基线”。

### 第二批：修复验证基础设施

- [ ] 恢复 MATLAB 浮点模型；
- [ ] 恢复整数位真模型；
- [ ] 建立单一配置文件；
- [ ] 自动生成系数、向量、golden、manifest；
- [ ] 修复 `.mem` 相对路径；
- [ ] 六组合整链路回归；
- [ ] 发布级 10 seed × 4096 点 0 LSB。

### 第三批：工程闭环

- [ ] 模式总线改 request/ack 原子握手；
- [ ] 数据通路全部改同步复位；
- [ ] 清理 DPIR/DPOR/REQP/LUTAR；
- [ ] 家族切换改 LOCKED 驱动状态机；
- [ ] DAC 数据放 IOB，时钟改 ODDR；
- [ ] 添加 AD9708 output delay 和 bus skew 检查；
- [ ] 六组合板级和 100 次切换测试。

### 第四批：资源主线

- [ ] N3 `2 comb + Hold16 + 2 integrator`；
- [ ] 与修正 N3 逐点 0 LSB；
- [ ] DSP 5→4；
- [ ] Stage1 单 BRAM 串行双读；
- [ ] Stage2/3 历史合并；
- [ ] BRAM Tile 3→2；
- [ ] 完整回归和板测。

### 第五批：性能与研究支线

- [ ] 未使用 MMCM 掉电；
- [ ] SAIF 功耗对比；
- [ ] 单 MMCM + DRP；
- [ ] N4 Hold + `[-11,86,-11]/64` 补偿；
- [ ] 混合字长/TPE 搜索；
- [ ] 256×计算时钟两 DSP 调度。

---

## 16. 推荐优先级与预期成果

| 排名 | 工作 | 预期价值 | 风险 | 最终成果定位 |
|---:|---|---|---|---|
| 1 | Stage3 Q 格式修复 | 修复 6.02 dB 功能错误 | 低 | 必须完成 |
| 2 | 位真/六组合验证闭环 | 让所有结果可信 | 中 | 必须完成 |
| 3 | CDC/复位/DAC I/O | 提高工程完整性 | 中 | 必须完成 |
| 4 | N3 Hold | DSP 5→4，频响不变 | 低 | 资源版核心创新 |
| 5 | 两项 BRAM 调度 | Tile 3→2 | 中 | 资源版核心创新 |
| 6 | 未用 MMCM 掉电 | 最大的功耗优化机会 | 中 | 低功耗创新 |
| 7 | N4 Hold | 阻带约 72.4→78.6 dB | 中 | 性能版创新 |
| 8 | 整数字长/TPE | Pareto 自动搜索 | 中 | 方法创新 |
| 9 | 256×两 DSP | 理论 DSP 5→2 | 高 | 论文型探索 |

最合理的国赛叙事不是“又少了几十个 LUT”，而是：

```text
发现并修复定点格式隐患
→ 建立双采样率、三倍率的位真验证体系
→ 用严格数学等效减少 CIC 高速积分器
→ 利用多速率空闲周期复用 BRAM 和 DSP
→ 对双 MMCM 进行状态化功耗管理
→ 构建资源版与性能版 Pareto 对照
```

这样才能形成完整的“算法—定点—RTL—时钟—资源—功耗—板级”闭环。

---

## 17. 主要参考资料

1. E. B. Hogenauer, [An Economical Class of Digital Filters for Decimation and Interpolation](https://doi.org/10.1109/TASSP.1981.1163535)
2. R. A. Losada and R. G. Lyons, [Reducing CIC Filter Complexity](https://doi.org/10.1109/MSP.2006.1657825)
3. Kodek, [Finite-word-length FIR coefficient optimization](https://doi.org/10.1016/j.dsp.2023.104275)
4. [Multiple-Wordlength Optimization of DSP Systems](https://doi.org/10.1109/TCAD.2003.818119)
5. [Simulation-Based Word-Length Optimization](https://doi.org/10.1109/78.476465)
6. [Multiplierless CIC Compensation Filter](https://doi.org/10.1109/TCSII.2011.2180093)
7. [AMD RAMB18E1 Library Guide](https://docs.amd.com/r/en-US/ug953-vivado-7series-libraries/RAMB18E1)
8. [AMD XAPP888: 7 Series MMCM Dynamic Reconfiguration](https://docs.amd.com/v/u/en-US/xapp888_7Series_DynamicRecon)
9. [AD9708 Official Data Sheet](https://www.analog.com/media/en/technical-documentation/data-sheets/ad9708.pdf)
10. [Improved Resource Sharing for FPGA DSP Blocks](https://ieeexplore.ieee.org/document/7577373/)
