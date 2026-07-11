# 全 2× 128× 插值滤波器下一步优化指导 2.0

> 适用分支：`release/regional-final-demo`
> 审阅对象：
>
> - `matlab_fir/alt_all2x/`
> - `XC7A35T_interp_audio_pcm_wordlen_opt/XC7A35T_interp.srcs/sources_1/new/`
> - `XC7A35T_interp_audio_pcm_wordlen_opt/reports_all2x_board/`
> - `all2x_matlab_next_steps_feedback.md`
>
> 审阅日期：2026-07-11

---

## 0. 核心结论

当前版本已经完成了 MATLAB 设计、bit-true、RTL 对拍、综合、布局布线和 bitstream，正确性闭环已经比较完整。下一步若还想获得明显资源下降，重点不应继续放在“把某一级从 Q12 降到 Q10”这种局部字长调整，而应转向 **RTL 结构重构**。

当前最有价值的三个方向是：

1. **Stage 4～7 改成同一个精确 7 tap 半带 polyphase 核**；
2. **7 个 2× 级全部改成真正的 2 相 polyphase，不再显式插 0**；
3. **Stage 1 改成严格半带 + 单 DSP polyphase MAC**。

其中第一项最适合作为下一步：改动范围小、数学依据强、回归风险低，而且当前系数已经非常接近一个可以完全用移位加法实现的标准半带核。

当前独立插值链资源为：

| 指标 | 当前结果 |
|---|---:|
| LUT | 5912 |
| FF | 4218 |
| DSP | 1 |
| BRAM | 0 |

当前板级结果为：

| 指标 | 当前结果 |
|---|---:|
| LUT | 6426 |
| FF | 4416 |
| DSP | 1 |
| WNS | +44.635 ns |

本指导给出的 2.0 阶段目标不是保证值，而是建议探索目标：

| 优化阶段 | 插值链 LUT 目标 | FF 目标 | DSP |
|---|---:|---:|---:|
| Stage 4～7 专用半带核 | 4500～5200 | 3400～4000 | 1 |
| 全链真正 polyphase | 3500～4500 | 2300～3300 | 1～2 |
| 激进共享 MAC 版本 | 2500～3500 | 1800～2800 | 2 |

这些范围必须以 Vivado 实际综合为准，不能提前作为最终结果宣称。

---

# 1. 当前版本做得好的地方

反馈报告表明，以下关键工作已经完成：

- 七级 2× 独立设计；
- 每级 2 倍插值增益；
- 总通带最大绝对误差检查；
- 保守的逐级阻带定义；
- 最小系数位宽和累加器位宽计算；
- 24 bit 逐级舍入、饱和 bit-true；
- 冲激和随机 PCM 的 MATLAB—RTL 0 LSB 对拍；
- Stage 1 单 DSP MAC；
- Stage 2～7 LUT 常数乘法；
- 三种实现结构的 Vivado 对比；
- 板级实现和 bitstream。

因此 2.0 不需要推翻当前版本。正确做法是：

```text
保留当前稳定版
    ↓
按单个结构改动建立实验分支
    ↓
每一步都通过原有 MATLAB/RTL 回归
    ↓
只有资源确实改善才进入下一步
```

---

# 2. 深入读取 RTL 后发现的主要瓶颈

## 2.1 当前 RTL 仍然不是真正的 polyphase

`interp2_top_symm_ce_all2x.v` 中仍然实例化：

```verilog
interp2_ctrl_ce
```

先产生：

```text
真实样点，0，真实样点，0……
```

再送入完整 FIR。

模块注释也明确写着：

```text
复用 interp2_ctrl_ce 产生插零后的 FIR 输入
```

因此，虽然 MATLAB bit-true 文件名包含 `polyphase`，而且数学结果与 polyphase 等价，但 RTL 仍属于：

```text
显式插 0
+
完整零插入序列延时线
+
完整对称 FIR
```

而不是真正的：

```text
只保存真实输入样点
+
偶相直接计算
+
奇相直接计算
```

这是当前最大的结构性优化空间。

---

## 2.2 Stage 1 保存了完整 93 tap 零插入序列

`fir_core_symm_interp2_stage1_mac.v` 中：

```verilog
reg signed [DATA_W-1:0] x_reg [0:NTAPS-1];
```

其中：

```text
NTAPS = 93
DATA_W = 24
```

因此仅延时线理论存储量就是：

\[
93\times24=2232\text{ bit}
\]

综合报告中 Stage 1 FIR 核使用：

```text
2295 FF
```

与完整 93×24 延时线非常接近。

当前 Stage 1 每收到一个补零后的 `fir_in_valid`，执行 47 周期 MAC：

```text
46 对对称 tap
+
1 个中心 tap
```

由于一半 `fir_in` 本身就是人为插入的 0，当前结构仍在为零插入序列维护完整状态。

真正 2 相 polyphase 后，只需要保存约 47 个真实输入历史样点，而不是 93 个补零样点。

---

## 2.3 Stage 2～7 是大组合常数乘加结构

`fir_core_symm_interp2_all2x.v` 中使用：

```verilog
always @(*) begin
    acc_comb = 0;
    for (...) begin
        acc_comb = acc_comb + sample_sum * coeff_half[k];
    end
end
```

并设置：

```verilog
(* use_dsp = "no" *)
```

这意味着：

- 所有对称项乘法同时在 LUT 中展开；
- 累加在一个组合过程里完成；
- Vivado 根据具体系数自行构造常数乘法网络；
- 不同系数的二进制复杂度会显著影响 LUT，而不仅由 tap 数决定。

层次资源报告已经证明这一点：

| Stage | tap | FIR 核 LUT | FIR 核 FF |
|---:|---:|---:|---:|
| 1 | 93 | 970 | 2295 |
| 2 | 17 | 436 | 451 |
| 3 | 11 | 711 | 306 |
| 4 | 7 | 538 | 211 |
| 5 | 7 | 625 | 209 |
| 6 | 7 | 454 | 208 |
| 7 | 7 | 147 | 200 |

Stage 3 只有 11 tap，却比 17 tap 的 Stage 2 多用 275 LUT；Stage 5 和 Stage 4 都是 7 tap，但 Stage 5 更高。这说明当前优化目标不能只看 tap 数、非零系数数目和 `FRAC_W`。

---

## 2.4 当前所有移位寄存器都使用 FF

层次报告中：

```text
LUTRAM = 0
SRL    = 0
BRAM   = 0
```

所有历史样点均由普通 FF 实现。

原因之一是每个 FIR 在复位时都逐项清零：

```verilog
for (i = 0; i < NTAPS; i = i + 1)
    x_reg[i] <= 0;
```

这种写法通常不利于综合器推断 SRL。

但是注意：

> 当前首先应该通过真正 polyphase 减少历史样点数量，而不是直接把现有完整零插入延时线强行映射成 SRL。

因为 SRL 会用 LUT 换 FF。如果比赛重点是降低 LUT，贸然使用 SRL 不一定更优。

---

## 2.5 六个 bridge 增加了状态和控制复杂度

顶层使用六个：

```verilog
bridge_to_interp2_ce
```

每个约占：

```text
2 LUT + 26 FF
```

单个资源不大，但它的存在来源于当前“显式插 0 + phase 对齐”的接口结构。

bridge 只有一个数据缓存和一个 `pending` 标志。代码中只要 `in_valid` 到来就覆盖：

```verilog
data_buf <= in_data;
```

在当前固定速率下不会发生数据丢失，但应补充断言，确保不存在：

```text
pending=1
且本拍没有消费
但又有新输入到来
```

真正 polyphase 后，可以将“一个输入产生两个输出”的相位调度直接放入每一级内部，从而删除大部分 bridge 和 `interp2_ctrl_ce`。

---

## 2.6 顶层仍有 1754 LUT 未归属到子模块

层次报告中：

```text
interp128_all2x_top_ce 总 LUT = 5912
其中顶层自身归属 LUT          = 1754
```

而所有明确子模块加起来仍有较大差额。

这部分可能来自：

- 跨层次优化后被归属到顶层的组合逻辑；
- 常数乘法和加法网络被打平；
- 连接和控制逻辑；
- debug 输出或层级边界优化。

不能仅凭层次表直接断定来源。建议增加一次诊断综合：

```tcl
report_utilization -hierarchical -hierarchical_depth 10
report_utilization -hierarchical -hierarchical_percentages
report_high_fanout_nets
report_schematic
```

并在“仅用于诊断”的综合中临时给关键模块加：

```verilog
(* keep_hierarchy = "yes" *)
```

注意 `keep_hierarchy` 只用于定位，不建议直接用于最终实现，因为它可能阻止跨层优化。

---

# 3. 第一优先级：Stage 4～7 统一成精确 7 tap 半带核

这是 2.0 中最推荐先做的工作。

## 3.1 当前 Stage 4～7 系数非常接近同一个标准结构

当前半系数为：

| Stage | Q 格式 | 当前半系数 |
|---:|---:|---|
| 4 | Q15 | `[-2061, 116, 18447, 32543]` |
| 5 | Q13 | `[-513, 7, 4609, 8178]` |
| 6 | Q12 | `[-256, 1, 2304, 4094]` |
| 7 | Q12 | `[-256, 0, 2304, 4096]` |

它们都非常接近：

\[
h=
\left[
-\frac1{16},\ 0,\ \frac9{16},\ 1,\
\frac9{16},\ 0,\ -\frac1{16}
\right]
\]

其总和为：

\[
2
\]

两个 polyphase 分支分别为：

\[
E_0=
\left[
-\frac1{16},\frac9{16},\frac9{16},-\frac1{16}
\right]
\]

\[
E_1=[0,1,0]
\]

因此：

\[
\sum E_0=1,\qquad \sum E_1=1
\]

奇相分支完全退化成一个纯延迟，不需要乘法器。

---

## 3.2 基于当前系数重新计算得到的结果

使用仓库当前七级系数，按照现有最终等效频响计算方法，将 Stage 4～7 全部替换为上述精确 7 tap 核，得到：

| 指标 | 当前基线 | Stage 4～7 精确核 |
|---|---:|---:|
| 通带最大绝对误差 | 0.00729793 dB | 0.00755141 dB |
| 总阻带衰减 | 77.67936 dB | 77.67636 dB |
| 总 FIR 直流增益 | 128.01855 | 127.99706 |

变化极小，仍远高于赛题要求。

这只是基于量化系数的系统级频响重算，还不是最终 bit-true 和 RTL 验收。但是它已经说明：

> Stage 4～7 目前分别使用四套不同的复杂系数，没有明显必要。

---

## 3.3 精确 7 tap 核的时域公式

设最近四个真实输入为：

\[
x[m],x[m-1],x[m-2],x[m-3]
\]

偶相输出为：

\[
\begin{aligned}
y[2m]
=&-\frac1{16}x[m]
+\frac9{16}x[m-1]\\
&+\frac9{16}x[m-2]
-\frac1{16}x[m-3]
\end{aligned}
\]

整理：

\[
\boxed{
y[2m]
=
\frac{
-\left(x[m]+x[m-3]\right)
+9\left(x[m-1]+x[m-2]\right)
}{16}
}
\]

奇相输出：

\[
\boxed{
y[2m+1]=x[m-1]
}
\]

其中：

\[
9a=8a+a
\]

因此偶相只需要：

- 两个预加法；
- 一个左移 3 位；
- 少量加减法；
- 一次带舍入的右移 4 位。

不需要通用乘法器，也不需要保存七个补零样点。

---

## 3.4 建议新建专用 RTL

建议新建：

```text
interp2_halfband7_shiftadd_ce.v
```

不要继续通过 `STAGE_ID` 走通用乘法 FIR。

概念接口：

```verilog
module interp2_halfband7_shiftadd_ce #(
    parameter integer DATA_W = 24
)(
    input  wire                     clk,
    input  wire                     rst_n,
    input  wire signed [DATA_W-1:0] x_in,
    input  wire                     x_in_valid,

    output reg  signed [23:0]        y_out,
    output reg                      y_out_valid
);
```

内部只保存真实样点：

```verilog
reg signed [23:0] x_d1;
reg signed [23:0] x_d2;
reg signed [23:0] x_d3;
```

每个输入样点产生：

```text
phase 0：移位加法计算偶相
phase 1：直接输出延迟样点
```

必须使用与当前 `round_sat_q16_to24` 一致的负数舍入和饱和规则，不能简单使用 `>>> 4` 后就认为 bit-true 一致。

---

## 3.5 这一阶段的验收门槛

只有同时满足以下条件才合并：

```text
总通带最大绝对误差 ≤ 0.01 dB
总阻带衰减 ≥ 75 dB
所有常规 bit-true 测试通过
冲激 RTL 对拍 0 LSB
随机 PCM RTL 对拍 0 LSB
LUT 低于当前 5912
FF 低于当前 4218
DSP 仍为 1
```

---

# 4. 第二优先级：全链改成真正 2 相 polyphase

## 4.1 普通 2× FIR 的直接 polyphase 公式

对任意系数：

\[
h[0],h[1],\ldots,h[N-1]
\]

分为：

\[
h_e[k]=h[2k]
\]

\[
h_o[k]=h[2k+1]
\]

则：

\[
y[2m]=\sum_k h_e[k]x[m-k]
\]

\[
y[2m+1]=\sum_k h_o[k]x[m-k]
\]

不再生成插入的 0。

MATLAB 中导出：

```matlab
phase0_coeff_int = coeff_int(1:2:end);
phase1_coeff_int = coeff_int(2:2:end);
```

当前脚本只导出了“对称半系数”，还没有把偶相和奇相作为 RTL 的直接输入文件。

---

## 4.2 polyphase 后的历史样点规模

当前显式零插入 FIR 总 tap 数：

\[
93+17+11+7+7+7+7=149
\]

即：

\[
149\times24=3576\text{ bit}
\]

真正 polyphase 后，各级真实输入历史长度约为：

\[
47+9+6+4+4+4+4=78
\]

即：

\[
78\times24=1872\text{ bit}
\]

理论上历史状态接近减半。

实际 FF 还包含：

- 累加器；
- valid；
- phase；
- 控制状态；
- 输出寄存器；

因此总 FF 不会严格减半，但 Stage 1 的下降应比较明显。

---

## 4.3 对称性在 polyphase 中仍然可利用

以 17 tap 为例：

```text
偶相长度：9
奇相长度：8
```

对于整体对称的奇长度 FIR：

- 偶相通常自身对称；
- 奇相通常自身对称。

因此 Stage 2 每个真实输入样点的独立乘法数仍约为：

```text
偶相 5 次
+
奇相 4 次
=
9 次
```

而不是两个输出分别跑完整 9 次对称 FIR。

---

## 4.4 新的模块分层建议

建议替换当前：

```text
bridge_to_interp2_ce
    ↓
interp2_ctrl_ce
    ↓
完整 FIR
```

为：

```text
interp2_polyphase_stage
    ├── 输入历史
    ├── phase0 计算
    ├── phase1 计算
    ├── 舍入/饱和
    └── 两相输出调度
```

建议接口增加明确握手：

```verilog
input  wire x_in_valid;
output wire x_in_ready;

output wire y_out_valid;
input  wire y_out_ready;
```

如果不希望增加完整 ready/valid，也至少加入内部断言，保证固定 CE 关系下不会覆盖数据。

---

# 5. 第三优先级：Stage 1 严格半带 polyphase

## 5.1 Stage 1 满足严格半带频率条件

Stage 1：

```text
Fs,out = 88.2 kHz
通带边缘 = 20 kHz
阻带边缘 = 24.1 kHz
```

满足：

\[
20+24.1=44.1=\frac{88.2}{2}
\]

所以通带和阻带关于 22.05 kHz 对称，具备严格半带设计条件。

当前 Stage 1 虽然是 93 tap，但系数并不是严格“每隔一个系数为 0”，所以仍需要 47 个独立半系数 MAC。

---

## 5.2 严格半带后的结构

对于 93 tap 严格半带、且总插值增益为 2：

- 一个相位只保留中心系数 1；
- 该相位成为纯延迟；
- 另一个相位包含非零 FIR 系数；
- 利用对称性后，有效乘法次数大约进一步减半。

当前 Stage 1：

```text
每个补零 FIR 输出：47 次 MAC
两个相位都走同一个完整 FIR
```

严格半带 polyphase 后：

```text
一个相位：纯延迟
另一个相位：约 23～24 次 MAC
```

一个 DSP 仍然完全足够。

---

## 5.3 MATLAB 设计不能只调用普通 firpm

建议建立独立脚本：

```text
design_stage1_strict_halfband.m
```

候选方式：

1. 本机若支持 `firhalfband`，先用专用半带函数；
2. 若 MATLAB 2018.3 环境不支持合适语法，则自行构造半带约束；
3. 只优化非零奇偶一侧系数；
4. 强制中心系数为 1；
5. 强制另一组非中心系数为 0；
6. 量化后重新做总链路检查。

使用前先确认：

```matlab
which firhalfband
help firhalfband
```

不要直接假设不同 MATLAB 版本的函数接口完全相同。

---

## 5.4 Stage 1 的位宽和相位和约束

当前 Stage 1 两相整数和为：

```text
phase0 sum = 65547
phase1 sum = 65562
理想值     = 65536
```

因此两相分别高出：

```text
+11 LSB
+26 LSB
```

严格半带设计应尽量强制：

```matlab
sum(coeff_int(1:2:end)) == 2^FRAC_W
sum(coeff_int(2:2:end)) == 2^FRAC_W
```

这样：

- 直流输出不再出现奇偶相轻微交替；
- 总增益更接近精确 1；
- 高频相位不平衡杂散进一步降低。

---

# 6. DSP 分配不应只追求“越少越好”

当前仅使用 1 个 DSP，XC7A35T 共有 90 个 DSP。

Stage 2、Stage 3 的 LUT 合计：

\[
436+711=1147
\]

Stage 4 FIR 核还使用 538 LUT。

因此值得建立 DSP 数量 Pareto：

| 方案 | DSP | 目标 |
|---|---:|---|
| A | 1 | 最少 DSP，当前方向 |
| B | 2 | Stage 1 一个 DSP，Stage 2～4 共享一个 DSP |
| C | 3 | Stage 1、Stage 2、Stage 3 分别 MAC |
| D | 2 | Stage 1 严格半带后，与 Stage 2～4 共享调度 |

## 6.1 共享一个 DSP 处理 Stage 2～4

以一个 44.1 kHz 输入周期对应 128 个 5.6448 MHz 时钟为预算，真正 polyphase、利用对称性后，大致乘法需求为：

| Stage | 每个上一级输入的独立乘法 | 每个基带输入对应数量 | 乘法/128 周期 |
|---:|---:|---:|---:|
| 2 | 9 | 2 | 18 |
| 3 | 6 | 4 | 24 |
| 4 | 4 | 8 | 32 |

总计约：

\[
18+24+32=74
\]

理论上一个 DSP 在 128 周期内可以完成，但还必须考虑：

- 输出截止时间；
- 加载系数；
- 累加清零；
- 舍入；
- 不同级之间的调度冲突。

因此不要直接实现。先建立周期级调度表：

```text
shared_mac_schedule.csv
```

然后再写共享 MAC。

更稳妥的第一版是：

```text
Stage 1：1 DSP
Stage 2：1 DSP
Stage 3～7：专用移位加法/LUT
```

用 2 个 DSP 换取明显 LUT 下降，可能比极限压到 1 DSP 更符合“总资源优化”。

---

# 7. MATLAB 优化目标 2.0：从单级频响变成架构感知搜索

## 7.1 增加候选类型

每一级不再只生成普通 `firpm` 候选，应至少包括：

```text
generic_equiripple
strict_halfband
canonical_halfband7
hardware_friendly_local_search
```

其中：

- Stage 1 优先 strict halfband；
- Stage 2～3 优先普通等波纹 + 局部整数优化；
- Stage 4～7 优先 canonical halfband7。

---

## 7.2 强制两相整数和精确

为每个候选增加：

```matlab
target_phase_sum = 2^frac_w;

phase0_sum_int = sum(coeff_int(1:2:end));
phase1_sum_int = sum(coeff_int(2:2:end));

phase0_err_lsb = phase0_sum_int - target_phase_sum;
phase1_err_lsb = phase1_sum_int - target_phase_sum;
```

候选通过条件增加：

```matlab
pass_phase_gain = ...
    abs(phase0_err_lsb) <= PHASE_SUM_TOL_LSB && ...
    abs(phase1_err_lsb) <= PHASE_SUM_TOL_LSB;
```

对于 Stage 4～7 的精确半带核，建议：

```text
PHASE_SUM_TOL_LSB = 0
```

---

## 7.3 建立整数邻域搜索

对 Stage 2～3 当前整数系数，在附近搜索：

```text
±1、±2、±4、±8 LSB
```

约束：

- 保持整体对称；
- 两相和接近或等于目标；
- 总链路通带和阻带通过；
- 优先接近 \(2^a\) 或 \(2^a\pm2^b\) 的数。

硬件成本可定义为：

```matlab
cost = ...
    W_CSD  * csd_nonzero_digits + ...
    W_ADD  * estimated_adders + ...
    W_W    * coeff_width + ...
    W_ACC  * acc_width + ...
    W_MEM  * history_bits;
```

但最终仍要用 Vivado 验证。

---

## 7.4 Stage 3 和 Stage 5 应优先做系数局部搜索

根据层次资源：

```text
Stage 3：11 tap，711 LUT
Stage 2：17 tap，436 LUT
```

Stage 3 是最明显的“系数复杂度异常高”级。

Stage 5 当前会被 canonical halfband7 替换，因此无需继续对旧系数做 Q 格式微调。

推荐顺序：

```text
Stage 4～7 精确半带替换
    ↓
Stage 3 整数系数局部搜索
    ↓
Stage 2 是否改 DSP MAC
```

---

## 7.5 Pareto/beam search 应放在结构确定之后

之前未做 beam search 是合理的，因为当时 RTL 结构尚未确定。

2.0 中先确定以下候选架构：

```text
Stage 1：普通 MAC / 严格半带 MAC
Stage 2：LUT / DSP MAC
Stage 3：LUT / DSP MAC / 硬件友好系数
Stage 4～7：精确半带移位加法
```

然后再做组合搜索。

建议每一级保留：

```text
5～10 个候选
```

beam width：

```matlab
BEAM_WIDTH = 20;
```

最终只对前 5～10 个组合运行 Vivado 批量综合。

---

# 8. 建议新增的 MATLAB 文件

```text
matlab_fir/alt_all2x_v2/
├── 01_extract_current_baseline.m
├── 02_test_canonical_halfband7.m
├── 03_design_stage1_strict_halfband.m
├── 04_search_stage23_hw_friendly.m
├── 05_build_v2_candidate_chains.m
├── 06_validate_v2_float.m
├── 07_validate_v2_bittrue.m
├── 08_export_v2_polyphase_rtl.m
├── 09_compare_v2_rtl.m
├── 10_collect_vivado_results.m
│
├── common/
│   ├── build_multistage_ir.m
│   ├── check_total_chain.m
│   ├── split_polyphase.m
│   ├── enforce_phase_sum.m
│   ├── estimate_csd_cost.m
│   └── estimate_acc_width.m
│
└── candidates/
    ├── stage1/
    ├── stage2/
    ├── stage3/
    └── stage4_7/
```

不要直接修改当前 `alt_all2x` 稳定结果。

---

# 9. 建议新增的 RTL 文件

```text
sources_1/new/all2x_v2/
├── interp128_all2x_v2_top_ce.v
├── interp2_polyphase_generic_ce.v
├── interp2_stage1_halfband_mac.v
├── interp2_stage2_mac.v
├── interp2_stage3_shiftadd.v
├── interp2_halfband7_shiftadd_ce.v
├── round_shift_sat_signed.v
├── all2x_v2_coeff_pkg.vh
└── all2x_v2_assertions.vh
```

当前稳定模块保留，不要覆盖：

```text
interp128_all2x_top_ce.v
fir_core_symm_interp2_stage1_mac.v
fir_core_symm_interp2_all2x.v
```

---

# 10. 系数应改成单一数据源

当前 MATLAB 已经导出：

```text
all2x_rtl_stage_params.vh
```

但 `fir_core_symm_interp2_all2x.v` 中仍手工写死整套系数。

2.0 应改成：

```text
MATLAB 生成
    ↓
all2x_v2_coeff_pkg.vh
    ↓
RTL include
    ↓
testbench 同一份配置
```

并生成：

```text
coefficient_manifest.csv
```

包含：

```text
stage
tap
phase
integer_value
frac_w
sha256/hash
```

仿真开始时输出系数版本号，避免 MATLAB 和 RTL 系数漂移。

---

# 11. 验证 2.0

## 11.1 增加固定延迟和数量断言

当前已有 0 LSB 对拍，但还应检查控制行为：

```text
Stage 1 输出数 = 输入数 × 2
Stage 2 输出数 = 输入数 × 4
……
Stage 7 输出数 = 输入数 × 128
```

增加：

```verilog
if (stage1_busy && stage1_fir_in_valid)
    $fatal("Stage 1 input arrived while MAC busy");
```

bridge 版本增加：

```verilog
if (pending && !consume_now && in_valid)
    $fatal("bridge input overwrite");
```

真正 polyphase 后仍应保留相同性质的断言。

---

## 11.2 增加流式场景

除当前冲激和随机 PCM 外，增加：

```text
连续输入 4096 点
输入中途停顿
随机 valid 空洞
处理中途复位
复位释放后立即输入
正负满幅交替
随机完整 24 bit
多个随机种子
```

其中完整 24 bit 输入允许饱和，但 MATLAB 和 RTL 必须逐点一致。

---

## 11.3 增加频谱失真指标

建议增加：

```text
THD
SINAD
SFDR
镜像峰值
奇偶相增益不平衡产生的 Fs/2 杂散
```

测试频率：

```text
1 kHz，-1 dBFS
19 kHz，-6 dBFS
20 kHz，-6 dBFS
双音 1 kHz + 19 kHz
```

---

## 11.4 保留两类判定

满幅测试不要只输出一个 `pass`：

```text
functional_match_pass
accumulator_overflow_pass
saturation_logic_pass
no_clipping_pass
```

满幅饱和时：

```text
functional_match_pass = 1
saturation_logic_pass = 1
no_clipping_pass      = 0
```

这比统一显示“通过”更严谨。

---

# 12. 存储和复位优化

真正 polyphase 完成后再尝试：

1. 延时数据本身不复位；
2. 只复位 `fill_count`、`valid` 和状态机；
3. 填充完成前屏蔽输出；
4. 对长历史尝试 SRL；
5. 分别综合“FF 历史”和“SRL 历史”。

建议准备两套参数：

```text
HISTORY_IMPL = "FF"
HISTORY_IMPL = "SRL"
```

选择标准：

- 若 LUT 是主要限制，优先 FF；
- 若 FF/时钟功耗是主要限制，考虑 SRL；
- 以实际实现功耗和资源为准。

---

# 13. 功耗优化的正确重点

当前 0.168 W 是无活动文件的低置信度估算。

报告中 MMCM 和时钟网络通常会占据较大固定部分，因此即使 FIR LUT 下降，板级总功耗未必同比下降。

应生成：

```text
静音 SAIF
1 kHz 正弦 SAIF
20 kHz 正弦 SAIF
随机 PCM SAIF
```

并分别报告：

```text
Clock
Logic
Signals
DSP
MMCM
Static
Total
```

2.0 结构层面的动态功耗收益主要来自：

- 不再移动插入的 0；
- 历史寄存器约减半；
- Stage 4～7 不再使用复杂常数乘法网络；
- 仅在有效相位更新算术逻辑；
- 减少大组合网络切换。

---

# 14. 详细实施顺序

## Phase 0：冻结稳定基线

建立 tag：

```text
regional-final-all2x-baseline
```

保存：

```text
MATLAB summary
bit-true summary
0 LSB 对拍
5912 LUT / 4218 FF / 1 DSP
6426 LUT / 4416 FF / 1 DSP
bitstream
```

---

## Phase 1：Stage 4～7 精确半带核

分支：

```text
opt/v2-canonical-halfband-tail
```

工作：

1. MATLAB 替换 Stage 4～7；
2. 浮点总链路检查；
3. bit-true；
4. 编写 `interp2_halfband7_shiftadd_ce.v`；
5. 对拍；
6. 综合；
7. 记录每一级资源。

这是最先应做的实验。

---

## Phase 2：Stage 2～7 真正 polyphase

分支：

```text
opt/v2-true-polyphase-tail
```

工作：

1. 导出 phase0/phase1 系数；
2. 删除显式插零；
3. 删除对应 bridge/ctrl；
4. 只保存真实输入历史；
5. 逐级 0 LSB 对拍；
6. 比较 FF 和 LUT。

---

## Phase 3：Stage 1 严格半带

分支：

```text
opt/v2-stage1-strict-halfband
```

工作：

1. 专用半带 MATLAB 设计；
2. 精确相位和；
3. 单 DSP filtered phase；
4. delay phase 直接输出；
5. 总链路频响；
6. bit-true；
7. RTL 对拍；
8. 资源和时序。

---

## Phase 4：DSP Pareto

分支：

```text
opt/v2-dsp-pareto
```

综合：

```text
1 DSP
2 DSP
3 DSP
```

比较：

```text
LUT
FF
DSP
WNS
功耗
代码复杂度
```

不要只以 DSP 数最少作为唯一指标。

---

## Phase 5：Stage 3 硬件友好系数搜索

分支：

```text
opt/v2-stage3-csd-search
```

目标：

```text
Stage 3 FIR 核 LUT 从 711 明显下降
总阻带仍 ≥75 dB
总通带误差仍 ≤0.01 dB
```

---

## Phase 6：功耗、THD、文档

最后完成：

```text
SAIF 功耗
THD/SINAD/SFDR
上板频谱
README 更新
最终资源 Pareto 表
```

---

# 15. 每一步必须填写的结果表

```markdown
| 版本 | LUT | FF | DSP | WNS | 通带误差 | 阻带 | SNR | THD | 0 LSB |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| baseline | 5912 | 4218 | 1 | +165.930 ns | 0.00730 | 77.679 | ... | ... | 是 |
| halfband tail | | | | | | | | | |
| true polyphase | | | | | | | | | |
| strict HB Stage1 | | | | | | | | | |
| DSP Pareto | | | | | | | | | |
```

---

# 16. 推荐的立即下一步

不要先做 Q6～Q10，也不要先写 beam search。

立即执行：

```text
1. 新建 opt/v2-canonical-halfband-tail
2. MATLAB 中用精确 7 tap 半带核替换 Stage 4～7
3. 跑现有总频响和 bit-true
4. 编写一个专用 shift-add polyphase RTL
5. 只替换 Stage 7，对拍和综合
6. 再依次替换 Stage 6、Stage 5、Stage 4
7. 每替换一级都保存资源增量
```

这样可以准确回答：

```text
Stage 7 精确核节省多少
Stage 6 精确核节省多少
Stage 5 精确核节省多少
Stage 4 精确核节省多少
```

而不是一次改四级后无法判断收益来源。

---

# 17. 最终判断

当前版本的主要冗余不在 MATLAB 的 0.007 dB 与 77.7 dB 指标，而在 RTL 仍采用：

```text
显式插 0
+
完整零插入延时线
+
通用常系数乘法
+
六级 bridge
```

最有把握的优化突破口是：

\[
\boxed{
\text{Stage 4～7 精确半带移位加法}
}
\]

随后是：

\[
\boxed{
\text{全链真正 2 相 polyphase}
}
\]

最后是：

\[
\boxed{
\text{Stage 1 严格半带 + 单 DSP MAC}
}
\]

这三步完成后，再讨论 Q6、CSD、beam search才有意义。否则只是在当前并不理想的 RTL 架构上继续压缩字长，收益会被结构性冗余掩盖。
