# FPGA 高阶数字插值滤波器：后续优化策略与参考文献（修订版）

> 项目：`fir-interpolation-filter-fpga / XC7A35T_interp_audio_pcm_wordlen_opt`  
> 赛题方向：高阶数字插值滤波器设计与验证  
> 目标：在满足音频插值滤波器频响指标的前提下，进一步探索资源、功耗和字长优化策略。

---

## 1. 当前状态判断

当前工程已经不是“仅完成基础功能”的状态，而是已经完成了一轮较完整的结构优化和字长优化探索。已有工作包括：

- 44.1 kHz / 48 kHz 双采样率家族；
- 4× / 8× / 128× 三档输出；
- MATLAB 建模、RTL 实现、功能仿真、板级验证；
- 4× 前级 polyphase 分解；
- 2-lane MAC 时分复用；
- 后级 2× FIR no-DSP 映射；
- 后级 2× FIR 系数字长压缩；
- 前级 ACC_W 扫描；
- halfband / shift-add / no-DSP 等分支探索；
- single-MMCM / clock-power 方向已有分支尝试。

因此，后续优化不应再是盲目“再减一两位”，而应转向：

1. **理论位宽推导**：从扫描式 ACC_W 优化升级为区间分析 / 溢出分析；
2. **分级 mixed precision 搜索**：借鉴 AI 加速器的逐层混合精度思想；
3. **固定系数 multiplierless FIR**：借鉴视频/图像滤波中的 MCM / RAG / CSE；
4. **SAIF 活动率功耗分析**：让功耗优化有真实翻转率证据；
5. **mode-dependent CE gating**：在低倍率模式下关闭未使用后级链路。

---

## 2. 已尝试方向与后续定位

| 方向 | 当前状态 | 后续建议 |
|---|---|---|
| 4× 前级 ACC_W 扫描 | 已做，ACC_W=49 为当前较优点 | 升级为“区间分析 + 理论上界 + 仿真统计” |
| 4× polyphase | 已做，是当前核心成果 | 作为已完成结构创新，不再重复 |
| 2-lane MAC | 已做，显著降低前级 DSP 需求 | 作为已完成结构创新 |
| 后级 no-DSP | 已做，DSP 降到很低 | 可继续结合 CSD / MCM / CSE 优化 LUT/CARRY4 |
| halfband13 | 已尝试，综合结果未优于当前方案 | 写入探索失败但有价值的对照 |
| shift-add | 已尝试一种，未优于当前方案 | 不再机械 shift-add，应改为 CSD/SPT 系数搜索 |
| single-MMCM / clock-power | 已有分支尝试 | 整理报告结果，和 dual-MMCM 做架构取舍 |
| 统一后级字长优化 | 已做 | 升级为“每级不同 tap / Q / ACC_W”的 mixed precision |
| SAIF 功耗分析 | 仍建议补 | 用于证明 CE gating 和真实输入下的功耗差异 |
| MCM / RAG / CSE | 尚未系统做 | 只对一个 2× FIR 做 OOC 验证，不直接大改全工程 |

---

## 3. 新增策略 A：借鉴编译器的区间分析 / 溢出分析

### 3.1 为什么要做

当前 `ACC_W=49` 是通过扫描得到的。这个方法是有效的，但比赛答辩时更高级的说法应该是：

> 不是只靠试出来，而是结合理论上界、仿真统计和综合验证确定每一级所需整数保护位。

这相当于借鉴编译器和定点工具链中的 **range analysis / overflow analysis** 思想。

---

### 3.2 基本公式

对于 FIR 累加器：

```text
y[n] = Σ h_i x[n-i]
```

如果输入最大幅度为：

```text
max_x = max(|x|)
```

则累加器理论绝对值上界可以估计为：

```text
max_acc <= max(|x|) · Σ |h_i|
```

因此整数位宽可以根据：

```text
integer_guard_bits = ceil(log2(max_acc)) + sign_bit + guard_bits
```

其中：

- `sign_bit`：符号位；
- `guard_bits`：额外保护位，防止极端输入、量化误差、级联放大；
- `Σ |h_i|`：当前 FIR 级的系数绝对值和；
- 若是多级级联，还需要逐级考虑前一级输出幅度变化。

---

### 3.3 建议实验流程

```text
1. 对每一级 FIR 读取定点系数；
2. 计算 sum_abs_h = Σ |h_i|；
3. 根据输入满幅 24 bit 有符号数计算理论 max_acc；
4. 得到理论整数位宽；
5. 用 MATLAB 生成多种输入：
   - 满幅正弦；
   - 多频正弦；
   - 白噪声；
   - 接近满幅的音频片段；
   - 交替最大/最小值极端序列；
6. 统计每一级真实 max_acc_sim；
7. 比较：
   - 理论上界；
   - 仿真最大值；
   - 99.999% 分位值；
8. 再确定每一级 ACC_W；
9. 用 Vivado 综合验证 LUT / CARRY4 / DSP / WNS；
10. 用 RTL 仿真确认没有溢出。
```

---

### 3.4 推荐展示表格

| Stage | tap 数 | COEFF_W | FRAC_W | Σ\|h_i\| | 理论整数位 | 仿真峰值位 | 最终 ACC_W | 是否溢出 |
|---|---:|---:|---:|---:|---:|---:|---:|---|
| 4× FIR | ? | ? | ? | ? | ? | ? | 49 | No |
| 8× FIR | 29 | 14 | 12 | ? | ? | ? | ? | No |
| 16× FIR | 29 | 14 | 12 | ? | ? | ? | ? | No |
| 32× FIR | 29 | 14 | 12 | ? | ? | ? | ? | No |
| 64× FIR | 29 | 14 | 12 | ? | ? | ? | ? | No |
| 128× FIR | 29 | 14 | 12 | ? | ? | ? | ? | No |

---

### 3.5 推荐比赛表述

> 在字长优化方面，设计不仅采用 ACC_W 参数扫描，还引入区间分析与溢出分析。通过输入幅度上界和 FIR 系数绝对值和估计每一级累加器最大可能值，并结合 MATLAB 定点仿真统计真实峰值，最终确定整数保护位和 guard bits。该方法相比单纯试探式扫描更具可解释性，也能避免过度压缩字长造成溢出风险。

---

## 4. 新增策略 B：借鉴 AI 加速器的 mixed precision 搜索

### 4.1 为什么可以迁移

AI 加速器中常用 mixed precision：

```text
不同层使用不同 bit-width；
敏感层高精度；
不敏感层低精度。
```

插值滤波器链路也可以类比为多层结构：

```text
4× FIR   = layer 1
8× FIR   = layer 2
16× FIR  = layer 3
32× FIR  = layer 4
64× FIR  = layer 5
128× FIR = layer 6
```

因此可以把“统一字长”升级为：

```text
每一级不同 COEFF_W；
每一级不同 ACC_W；
每一级不同 OUT_SHIFT；
每一级不同 tap 数。
```

这就是：

```text
mixed precision interpolation filter
```

它非常适合赛题里的“字长优化策略”创新指标。

---

### 4.2 推荐搜索变量

对每一级 2× FIR，可以搜索：

```text
tap 数：29, 27, 25, 23, 21, 19, 17, 15, 13
COEFF_W：14, 13, 12, 11, 10
FRAC_W：12, 11, 10, 9
ACC_W：48, 46, 44, 42, 40, 38
OUT_SHIFT：根据 FRAC_W 和级联增益调整
```

不建议暴力全组合，可先用分级约束：

```text
越靠前的级保守一些；
越靠后的级逐渐降低 tap / 字长；
整体频响必须统一验证。
```

---

### 4.3 搜索目标函数

可以定义一个近似硬件代价函数：

```text
Cost = Σ_stage ( α·tap_stage·COEFF_W_stage
               + β·ACC_W_stage
               + γ·activity_weight_stage )
```

其中：

```text
activity_weight_stage ∝ stage_output_rate
```

因为越后面的级输出采样率越高，动态翻转对功耗更敏感。

更工程化的版本是：

```text
先用 MATLAB 频响筛选；
再对少数候选方案做 Vivado OOC 综合；
最后选择资源和频响都最优的组合。
```

---

### 4.4 推荐实验路线

```text
第一步：只优化后级 5 个 2× FIR，不动 4× 前级；
第二步：每一级设置候选 tap / Q / ACC_W；
第三步：对每个组合计算整体 128× 级联频响；
第四步：筛掉不满足：
        通带纹波 <= ±0.05 dB
        阻带衰减 >= 70 dB
        线性相位
        的组合；
第五步：对候选方案生成 Verilog 参数；
第六步：OOC 综合比较资源；
第七步：选出 LUT/CARRY4/功耗更优版本。
```

---

### 4.5 推荐展示图

1. 不同 stage 的最终 bit-width 柱状图；
2. mixed precision 前后的频响对比；
3. mixed precision 前后的资源对比；
4. 每一级对频响误差的敏感性分析；
5. 每一级的 activity-weighted cost 对比。

---

### 4.6 推荐比赛表述

> 受 AI 加速器中逐层 mixed precision 量化策略启发，本设计将多级插值链路视为级联计算层，对不同插值级分配不同 tap 数、系数字长、累加位宽和输出截位策略。在满足整体频响指标的前提下，对后级高采样率链路进行更激进的低位宽设计，从而降低资源和动态功耗。

---

## 5. 新增策略 C：借鉴视频/图像滤波的 MCM / RAG / CSE

### 5.1 为什么适合

视频、图像和通信系统中大量使用固定系数 FIR，因此常见优化包括：

```text
MCM：Multiple Constant Multiplication，多常数乘法；
CSE：Common Subexpression Elimination，公共子表达式消除；
RAG：Reduced Adder Graph，减少加法器图；
CSD / SPT：Canonical Signed Digit / Signed-Power-of-Two。
```

你的后级 2× FIR 是固定系数、线性相位、no-DSP 映射，因此非常适合尝试 multiplierless FIR 方法。

---

### 5.2 和之前 shift-add 失败的区别

之前尝试过 shift-add，不代表这个方向完全失败。

两者区别如下：

| 方法 | 思路 | 问题 |
|---|---|---|
| 机械 shift-add | 已有系数 → 直接移位加法实现 | 可能加法器很多，LUT 反而上升 |
| CSD/SPT 搜索 | 直接寻找少非零项的系数 | 更适合硬件 |
| MCM/CSE | 多个系数共享中间表达式 | 可减少重复加法 |
| RAG | 从全局图角度最小化加法器 | 更接近论文级优化 |

所以后续不能再简单把原系数翻译成移位加法，而应从“系数设计 + 硬件实现”一起优化。

---

### 5.3 建议实验流程

只对一个 29 tap 2× FIR 做 OOC：

```text
1. 利用线性相位，把 29 tap 变成约 15 个有效乘法；
2. 对 15 个系数做 CSD/SPT 表示；
3. 限制每个系数最多 2 或 3 个 signed-power-of-two 项；
4. 检查单级和级联频响是否满足指标；
5. 找多个系数之间重复出现的中间项；
6. 用 CSE 共享表达式；
7. 用 RAG / 最少加法器思路减少加法树；
8. OOC 综合比较：
   - 当前 Q12 no-DSP；
   - CSD-3；
   - CSD-2；
   - CSD + CSE；
   - CSD + CSE + RAG。
```

---

### 5.4 推荐对照表

| 版本 | DSP | LUT | CARRY4 | WNS | 通带纹波 | 阻带衰减 | 是否采用 |
|---|---:|---:|---:|---:|---:|---:|---|
| 当前 Q12 no-DSP | 0 | ? | ? | ? | pass | pass | baseline |
| CSD-3 | 0 | ? | ? | ? | ? | ? | 待定 |
| CSD-2 | 0 | ? | ? | ? | ? | ? | 待定 |
| CSD+CSE | 0 | ? | ? | ? | ? | ? | 待定 |
| RAG | 0 | ? | ? | ? | ? | ? | 待定 |

---

### 5.5 推荐比赛表述

> 针对固定系数 FIR 中普通常数乘法带来的 LUT 和进位链开销，设计进一步借鉴视频/图像滤波器中的 MCM、CSE 和 RAG 思想，将多个常系数乘法转化为共享移位加法结构，以减少后级 no-DSP FIR 的加法器数量。该方法不再是简单 shift-add，而是从系数形式和硬件加法图两个层面联合优化。

---

## 6. 推荐参考文献与资料

### 6.1 多速率滤波 / polyphase / 多级插值

1. R. E. Crochiere, L. R. Rabiner, **Interpolation and Decimation of Digital Signals — A Tutorial Review**, Proceedings of the IEEE, 1981.  
   https://web.ece.ucsb.edu/Faculty/Rabiner/ece259/Reprints/179_interpolation_decimation.pdf

2. AMD FIR Compiler PG149, **Polyphase Interpolator**.  
   https://docs.amd.com/r/en-US/pg149-fir-compiler/Polyphase-Interpolator

3. AMD FIR Compiler PG149, **FIR Compiler Product Guide**.  
   https://docs.amd.com/r/en-US/pg149-fir-compiler

---

### 6.2 功耗分析 / SAIF / 时钟优化

4. AMD Vivado UG907, **Power Analysis and Optimization**.  
   https://docs.amd.com/r/en-US/ug907-vivado-power-analysis-optimization

5. AMD Vivado UG907, **Specifying Switching Activity for Power Analysis**.  
   https://docs.amd.com/r/en-US/ug907-vivado-power-analysis-optimization/Specifying-Switching-Activity-for-Power-Analysis

6. AMD / Xilinx UG472, **7 Series FPGAs Clocking Resources User Guide**.  
   https://docs.amd.com/v/u/en-US/ug472_7Series_Clocking

---

### 6.3 有限字长 / mixed precision / 定点优化

7. D. M. Kodek, **Design of Optimal Finite Wordlength FIR Digital Filters Using Integer Programming Techniques**, IEEE Transactions on Acoustics, Speech, and Signal Processing, 1980.  
   https://ui.adsabs.harvard.edu/abs/1980ITASS..28..304K/abstract

8. D. M. Kodek, **Length Limit of Optimal Finite Wordlength FIR Filters**, Digital Signal Processing, 2013.  
   https://laps.fri.uni-lj.si/~duke/HPpapers/dsp13.pdf

9. **An algorithm for the design of optimal finite wordlength FIR filters**, Digital Signal Processing, 2023.  
   https://doi.org/10.1016/j.dsp.2023.104275

10. N. P. Pandey et al., **A Practical Mixed Precision Algorithm for Post-Training Quantization**, arXiv, 2023.  
    https://arxiv.org/abs/2302.05397

---

### 6.4 CSD / SPT / MCM / CSE / RAG / multiplierless FIR

11. M. Kumm, A. Volkova, S.-I. Filip, **Design of Optimal Multiplierless FIR Filters**, arXiv, 2019.  
    https://arxiv.org/abs/1912.04210

12. S. Mirzaei, A. Hosangadi, R. Kastner, **FPGA Implementation of High Speed FIR Filters Using Add and Shift Method**, 2006.  
    https://cseweb.ucsd.edu/~kastner/papers/tech-fir_add_shift.pdf

13. O. Gustafsson, H. Johansson, L. Wanhammar, **An MILP Approach for the Design of Linear-Phase FIR Filters with Minimum Number of Signed-Power-of-Two Terms**, 2001.  
    https://lib.tkk.fi/Books/2001/isbn9512263378/papers/1381.pdf

14. K.-H. Chen, T.-D. Chiueh, **A Low-Power Digit-Based Reconfigurable FIR Filter**, IEEE TCAS-II, 2006.  
    https://scholars.lib.ntu.edu.tw/server/api/core/bitstreams/23cd25ec-929f-425f-a4be-73b8a964251d/content

---

## 7. 建议下一步只开两个主分支

不要继续开太多分支，否则容易发散。建议只开两个：

```text
exp/range-mixed-precision
exp/mcm-cse-ooc
```

### 7.1 `exp/range-mixed-precision`

目标：

```text
区间分析 + 溢出分析 + 每级 mixed precision。
```

要产出：

- 每一级 `Σ|h_i|`；
- 理论 max_acc；
- 仿真 max_acc；
- 最终 ACC_W；
- 每一级 tap / COEFF_W / FRAC_W / OUT_SHIFT；
- 整体频响；
- 资源和功耗对照。

### 7.2 `exp/mcm-cse-ooc`

目标：

```text
只对一个后级 2× FIR 做 multiplierless OOC 实验。
```

要产出：

- 当前 no-DSP 单级资源；
- CSD-2 / CSD-3 资源；
- CSD+CSE 资源；
- 是否值得推广到全链路。

---

## 8. 最适合写进比赛材料的创新点

最终可以把创新点写成三层：

### 第一层：结构优化

- 多级插值结构；
- 4× 前级 polyphase 分解；
- 2-lane MAC 时分复用；
- 后级 no-DSP 映射。

### 第二层：理论字长优化

- 区间分析；
- 溢出分析；
- 理论上界 + 仿真统计 + 综合验证；
- 每一级 mixed precision。

### 第三层：硬件感知固定系数优化

- CSD / SPT；
- MCM / CSE；
- Reduced Adder Graph；
- OOC 综合筛选；
- 不盲目采用论文结构，而是以 FPGA 实际综合结果为准。

---

## 9. 总结

后续优化重点不应再是简单地把 `ACC_W=49` 改成 `48` 或者把统一 `Q12` 改成 `Q11`，而应升级为：

```text
理论区间分析 + 分级 mixed precision + 固定系数 multiplierless OOC 探索
```

这三条路线既能延续当前工程，又能明显增强比赛材料中的“创新指标”说服力。
