# Phase 7 FIR-CIC 混合插值器验证补全指导

> 适用版本：`codex/phase7-fir-cic-hybrid` 最终折叠补偿 N=3 候选  
> 依据：最新压缩包中的 MATLAB、RTL、XSim、Vivado 报告和板级顶层  
> 目标：把现有“分段 0 LSB + 数学频响 + 板级实现”补成完整的端到端验证闭环

---

# 0. 当前正式候选及其验收基线

当前推荐结构是：

```text
44.1 kHz / 24 bit 输入
        ↓
Stage 1：2× strict-halfband，24 bit，BRAM + DSP
        ↓
24 → 22 bit 舍入缩位
        ↓
Stage 2：2× true-polyphase，22 bit
        ↓
22 → 20 bit 舍入缩位
        ↓
Stage 3：2× folded-compensation FIR，20 bit
        ↓
CIC16：N=3，M=1，R=16
        ↓
20 bit CIC 输出左移4位恢复24 bit PCM标度
        ↓
5.6448 MHz / 24 bit 输出
```

CIC 数据流为：

\[
\boxed{
\text{低速 comb}
\rightarrow
\uparrow16
\rightarrow
\text{高速 integrator}
}
\]

当前正式候选参数：

```text
CIC_ORDER       = 3
DIFF_DELAY      = 1
RATE            = 16
CIC_INPUT_W     = 20
CIC_FULL_W      = 32
FINAL_PRUNE_LSB = 0
OUTPUT_SHIFT    = 8
```

Stage 3 折叠补偿系数为 Q15：

```text
561, 137, -4234, -1555, 20057, 35604,
20057, -1555, -4234, 137, 561
```

当前结果：

| 项目 | 结果 |
|---|---:|
| 总通带最大绝对误差 | 0.00303062 dB |
| 总阻带衰减 | 72.349 dB |
| 随机 PCM Delta-SNR | 96.403 dB |
| 15 kHz SINAD | 78.550 dB |
| 20 kHz SINAD | 70.912 dB |
| 独立链 LUT / FF | 957 / 791 |
| 完整板级 LUT / FF | 1135 / 962 |
| DSP / BRAM Tile | 2 / 1 |
| MATLAB/RTL分段对拍 | 0 LSB |

硬性赛题门槛：

```text
10 Hz～20 kHz：±0.05 dB
24.1 kHz～Nyquist：≥70 dB
严格线性相位
```

建议内部发布门槛：

```text
最终通带最大误差 ≤0.01 dB
最终阻带 ≥72 dB；低于72 dB时给出工程余量警告
所有位真测试 0 LSB
无非预期饱和、任务覆盖和时序错误
```

---

# 1. 当前已经完成的验证

最新版已经完成：

1. CIC 阶数 N=3/4/5 浮点搜索；
2. 独立低速补偿 FIR 搜索；
3. Stage 3 折叠补偿系数搜索；
4. N=3/N=4 bit-true：
   - 冲激；
   - 固定随机 PCM；
   - 15 kHz；
   - 20 kHz；
5. Hogenauer 风格剪枝搜索；
6. 前三级 N=3/N=4 的 RTL 0 LSB；
7. CIC 核 N=3/N=4 的 RTL 0 LSB；
8. 四档板级公共模块 XSim：
   - 1×；
   - 4×；
   - 8×；
   - 128×；
9. 独立综合、完整板级实现、bitstream；
10. pending overwrite 基本断言。

这些证据已经证明：

```text
前三级折叠 FIR数值正确；
CIC comb→插零→integrator数值正确；
N=3/N=4候选与MATLAB分段模型一致；
最终N=3架构具有明确资源收益。
```

---

# 2. 当前验证体系仍缺少什么

当前最大的缺口不是滤波器设计，而是以下验证还没有形成正式闭环：

1. **实际 Phase 7 完整顶层的一次性端到端 0 LSB 对拍**；
2. **最终 N=3 候选的长序列、多随机种子测试**；
3. **CIC 16输出 burst 的逐拍节拍和数量断言**；
4. **comb、integrator、归一化缩放的定向单元测试**；
5. **CIC 补码模运算 wrap 的明确统计与解释**；
6. **从 RTL 完整冲激输出直接计算最终频响**；
7. **运行过程中复位，尤其是 CIC burst 中途复位**；
8. **动态档位切换和 DA_CLK 毛刺测试**；
9. **Phase 7 bitstream 的人工实板四档复测**；
10. **8×输出是预加重节点，不应误按最终±0.05 dB验收**。

---

# 3. 建议新增目录

MATLAB：

```text
matlab_fir/alt_all2x_v7/verification/
├── config/
│   └── phase7_verify_config.m
├── vectors/
├── rtl_outputs/
├── reports/
├── figures/
│
├── phase7_analyze_full_rtl_impulse.m
├── phase7_compare_full_chain_multiseed.m
├── phase7_analyze_cic_wrap.m
├── phase7_analyze_valid_cadence.m
├── phase7_analyze_reset_recovery.m
└── phase7_generate_final_verification_report.m
```

RTL仿真：

```text
sim_1/new/all2x_v7/verification/
├── tb_phase7_full_chain_bittrue.v
├── tb_phase7_cic_comb_directed.v
├── tb_phase7_cic_burst_cadence.v
├── tb_phase7_cic_integrator_modulo.v
├── tb_phase7_multiseed_pcm.v
├── tb_phase7_reset_recovery.v
├── tb_phase7_mode_switch_dynamic.v
└── phase7_assertions.vh
```

---

# 4. 集中管理验证参数

新增：

```matlab
% phase7_verify_config.m

CFG.FS_IN      = 44100;
CFG.FS_4X      = 176400;
CFG.FS_8X      = 352800;
CFG.FS_128X    = 5644800;

CFG.FPASS_LOW  = 10;
CFG.FPASS_HIGH = 20000;
CFG.FSTOP      = 24100;

CFG.SPEC_PASS_DB    = 0.05;
CFG.RELEASE_PASS_DB = 0.01;
CFG.SPEC_STOP_DB    = 70;
CFG.WARN_STOP_DB    = 72;

CFG.CIC_R = 16;
CFG.CIC_M = 1;
CFG.CIC_N = 3;
CFG.CIC_INPUT_W = 20;
CFG.CIC_FULL_W = 32;
CFG.CIC_PRUNE_LSB = 0;
CFG.CIC_OUTPUT_SHIFT = 8;

CFG.IR_LEN_4X   = 225;
CFG.IR_LEN_8X   = 459;
CFG.IR_LEN_128X = 7374;

CFG.GAIN_4X   = 4;
CFG.GAIN_8X   = 8;
CFG.GAIN_128X = 128;

CFG.NUM_SEEDS_DAILY   = 4;
CFG.NUM_INPUT_DAILY   = 1024;
CFG.NUM_SEEDS_NIGHTLY = 10;
CFG.NUM_INPUT_NIGHTLY = 4096;
```

最终 Phase 7 等效冲激响应长度为：

\[
(459-1)\times16+46=7374
\]

其中 N=3 CIC 等效冲激响应长度为：

\[
3(16-1)+1=46
\]

最终群延迟是：

\[
\frac{7374-1}{2}=3686.5
\]

个5.6448 MHz输出样点。半样点延迟是偶长度对称 FIR 的正常性质。

---

# 5. 必须新增：完整 Phase 7 顶层端到端 0 LSB

当前验证将链路拆为：

```text
24bit输入 → folded Stage3
folded Stage3 → CIC16
```

分段测试很利于定位，但不能完全替代实际顶层端到端测试。

新增：

```text
tb_phase7_full_chain_bittrue.v
```

DUT必须是正式模块：

```text
interp128_all2x_v7_folded_fir_cic_top_ce
```

不要用手工拼接的简化模块。

---

## 5.1 必测节点

```text
dbg_y4：4× / 22bit恢复24bit标度
dbg_y8：8× folded-compensation节点
y_out ：128× CIC最终输出
```

输入：

1. 半满幅冲激；
2. 固定随机 PCM；
3. 15 kHz / -6或-12 dBFS；
4. 20 kHz / -6或-12 dBFS。

---

## 5.2 固定延迟

4×与8×沿用已证明值：

```text
4×：3个对应有效输出样点
8×：7个对应有效输出样点
```

128×的完整链固定偏移必须由事件时序推导并固化到配置文件。

正确流程：

```text
先从RTL事件顺序推导EXPECTED_SHIFT_128X；
只允许该固定值；
禁止在正式回归中搜索“最佳shift”。
```

如果修改流水或CIC burst启动时序，必须显式更新版本化常量。

---

## 5.3 验收

```text
4×输出最大误差 = 0 LSB
8×输出最大误差 = 0 LSB
128×输出最大误差 = 0 LSB
输出数量严格匹配
固定延迟严格匹配
不得出现X
```

---

# 6. CIC comb 定向单元测试

新增：

```text
tb_phase7_cic_comb_directed.v
```

当前 N=3、M=1 的低速 comb 等价于：

\[
(1-z^{-1})^3
\]

对冲激 \(A\delta[n]\)，低速comb输出必须为：

\[
[A,-3A,3A,-A]
\]

随后全零。

这是非常强的定向测试。

---

## 6.1 测试向量

1. 单位/适当幅度冲激；
2. 常数序列；
3. 线性斜坡；
4. 正负交替；
5. 最大正、最大负附近；
6. 随机20 bit。

---

## 6.2 需要检查

```text
每级comb delay更新顺序；
M=1延迟；
三级差分符号；
补码截断位宽；
复位后comb_delay全零。
```

建议在验证编译宏下暴露：

```text
comb_stage0_dbg
comb_stage1_dbg
comb_stage2_dbg
```

或使用 testbench 层次引用。调试端口必须在综合版本中关闭。

---

# 7. 插零与16输出 burst 节拍测试

新增：

```text
tb_phase7_cic_burst_cadence.v
```

当前核心实现不是显式输出一个零数组，而是：

```text
第一个ce_out：high_rate_input = burst_sample
后15个ce_out：high_rate_input = 0
```

---

## 7.1 正常节拍必须断言

每个 `x_in_valid`：

```text
必须产生恰好16个 y_out_valid；
第1个高率输入为comb结果；
后15个高率输入为0；
16个输出之间不得有valid空洞；
下一个输入不得覆盖未开始的pending。
```

最终板级中 `ce128_out=1`，稳态时：

```text
y_out_valid应每个5.6448 MHz时钟为1。
```

---

## 7.2 精确输出数量

若输入有效样点数为 \(N\)：

\[
N_{\mathrm{CIC,out}}=16N
\]

包括“值为0但valid=1”的低速输入。

当前 standalone testbench 会输入若干flush零样点，因此必须区分：

```text
实际低速valid输入数量
期望高率valid输出数量=16×实际输入数量
非零golden长度
尾部有效零输出
```

不能只检查“非零golden已经比较完”。

---

## 7.3 负向测试

建立单独的预期失败测试：

```text
输入间隔短于16个高率CE，持续发送；
最终应触发pending overwrite或明确错误标志。
```

该测试不进入正常PASS回归，可作为“设计速率约束正确生效”的证据。

---

# 8. Integrator 与补码模运算测试

新增：

```text
tb_phase7_cic_integrator_modulo.v
```

当前 CIC 各级使用有限位宽二进制补码模运算：

```text
N=3：FULL_W=32
```

这与普通 FIR 的“绝不允许累加器溢出”不同。

---

## 8.1 必须区分两种情况

### 非预期位宽不足

```text
因为错误缩位、错误符号扩展导致输出错误
```

这是失败。

### 二进制补码模回绕

```text
固定FULL_W寄存器自然回绕；
MATLAB模型按相同模运算；
最终结果仍0 LSB。
```

这是CIC允许的数学实现方式，不能简单把任何wrap都判定失败。

---

## 8.2 新增统计

MATLAB当前已经输出：

```text
modulo_wrap_count
stage_width
stage_max_abs
```

最终报告应明确列出：

| 激励 | comb wrap | integrator wrap | 最终误差 | 判定 |
|---|---:|---:|---:|---|
| 冲激 | | | 0 LSB | PASS |
| 直流 | | | 0 LSB | PASS |
| 15 kHz | | | 0 LSB | PASS |
| 20 kHz | | | 0 LSB | PASS |
| 满幅交替 | | | 0 LSB | PASS |
| 完整20 bit随机 | | | 0 LSB | PASS |

若wrap为0，也要报告；若非0，要说明这是模运算且结果与golden一致。

---

## 8.3 定向测试

1. 正常小信号；
2. 最大正直流；
3. 最大负直流；
4. 正负满幅交替；
5. comb最坏差分模式；
6. 可预期发生回绕的构造向量；
7. 回绕前后1 LSB边界。

---

# 9. CIC直流增益与归一化测试

标准 CIC 原始直流增益为：

\[
(RM)^N=16^3=4096
\]

但插零使样点密度降低到原来的 \(1/16\)。为了保持插值前后样值幅度一致，最终只需除以：

\[
\frac{(RM)^N}{R}=16^{N-1}=256
\]

所以当前：

```text
OUTPUT_SHIFT = 8
```

是正确的。

---

## 9.1 直流测试

输入连续固定20 bit常数，经过启动过渡后检查：

```text
16个输出相位幅值一致；
稳态平均值等于输入值，误差在规定LSB内；
不存在16相周期性增益波动；
正直流和负直流均测试。
```

建议输出：

```text
phase0_mean ... phase15_mean
max_phase_difference_lsb
dc_gain_error_db
```

---

## 9.2 输出标度

CIC输出20 bit后，顶层：

```verilog
assign y_out = {y128_w, 4'b0};
```

必须测试：

```text
20→24bit左移4位符号正确；
负数补码扩展正确；
最大正负边界不发生意外反号；
DAC取位与Phase6保持一致。
```

---

# 10. Hogenauer剪枝测试

最终选择 N=3：

```text
FINAL_PRUNE_LSB = 0
```

因此正式比赛版本实际上是：

```text
全精度CIC内部路径，无末级剪枝。
```

验证重点：

1. `FINAL_PRUNE_LSB=0` generate直通路径；
2. 不得实例化 `SHIFT_N=0` 的不合法通用舍入器；
3. `OUTPUT_SHIFT=8`；
4. FULL_W必须为32。

N=4、prune7仅保留为候选回归：

```text
参数化编译；
冲激/随机0 LSB；
不得影响正式N=3资源和逻辑。
```

不要在正式报告中把“N=3全精度”描述成已经使用了Hogenauer剪枝。

准确说法应是：

> 完成了Hogenauer风格剪枝搜索；最终N=3候选经Pareto判断选择0 LSB剪枝，而N=4候选可丢弃7 LSB。

---

# 11. 最终 N=3 长随机与多种子测试

当前最终链的随机输入规模仍偏小。

新增：

```text
tb_phase7_multiseed_pcm.v
```

---

## 11.1 日常回归

```text
4个种子 × 1024个24 bit输入
```

## 11.2 夜间/发布回归

```text
10个种子 × 4096个24 bit输入
```

每个种子均比较：

```text
4×输出；
8×折叠补偿输出；
128×最终输出。
```

---

## 11.3 两种幅度范围

### 正常音频范围

```text
20～21 bit随机；
要求前端无饱和；
CIC最终无输出饱和；
全链0 LSB。
```

### 压力范围

```text
完整24 bit随机；
0、±1、最大正、最大负、接近满幅、正负交替；
允许预期的级间/最终饱和；
要求MATLAB和RTL饱和位置及数值0 LSB一致。
```

报告区分：

```text
functional_match_pass
front_fir_overflow_pass
cic_modulo_match_pass
saturation_logic_pass
no_clipping_pass
```

---

# 12. 完整 RTL 冲激频谱验收

新增：

```text
phase7_analyze_full_rtl_impulse.m
```

必须从正式 Phase 7 顶层的 RTL 输出CSV读取，而不是只用设计系数。

---

## 12.1 4×节点

采样率：

\[
176.4\text{ kHz}
\]

有效冲激长度：

```text
225
```

归一化增益：

```text
4
```

4×仍是正常插值输出，可以检查：

```text
10 Hz～20 kHz：±0.05 dB
24.1 kHz～88.2 kHz：≥70 dB
```

---

## 12.2 8×节点的特殊说明

当前 `dbg_y8` 不是普通独立8×滤波器输出，而是：

\[
\boxed{\text{为CIC通带下垂预加重后的内部节点}}
\]

其高频通带会故意上扬。

按当前量化系数，8×节点大约表现为：

```text
15 kHz：约 +0.076 dB
20 kHz：约 +0.134 dB
```

因此：

> 不应把最终输出的 ±0.05 dB 指标直接用于8×折叠补偿节点。

8×应验证：

```text
RTL与folded Stage3 MATLAB golden一致；
系数与预加重目标一致；
阻带镜像抑制正确；
作为CIC前置补偿节点功能正确。
```

如果评委要求“8×档本身也必须满足±0.05 dB”，当前折叠补偿架构需要额外处理：

### 方案A：文档明确说明8×是内部补偿节点

适用于分赛区只验收最终128×。

### 方案B：增加Stage3系数模式

```text
8×展示时使用Phase6普通Stage3系数；
128×模式使用Phase7折叠补偿系数。
```

切换后必须重新填充历史并等待稳定，避免运行中直接换系数产生瞬态。

这是比赛前必须向老师确认的验收边界。

---

## 12.3 128×最终节点

采样率：

\[
5.6448\text{ MHz}
\]

有效冲激长度：

```text
7374
```

归一化增益：

```text
128
```

必须输出：

```text
pass_abs_max_db
pass_peak_db
pass_min_db
ripple_pp_db
stop_attn_db
dc_gain
impulse_symmetry_lsb
group_delay_mean
group_delay_pp
phase_fit_residual
```

验收：

```text
硬门槛：±0.05 dB / 70 dB
内部发布：≤0.01 dB / ≥72 dB
```

---

# 13. 线性相位验证

Phase 7 由：

```text
对称 Stage1
对称 Stage2
对称 folded Stage3
对称 CIC等效FIR
```

级联组成，理论上保持线性相位。

N=3 CIC等效响应长度46，是偶长度对称FIR，因此最终总响应长度7374，群延迟为半整数：

\[
3686.5
\]

这不是错误。

---

## 13.1 三层证据

1. 整数FIR系数逐级严格对称；
2. CIC等效冲激响应严格对称；
3. RTL最终冲激响应：
   - 对称误差；
   - 通带相位线性拟合；
   - 群延迟峰峰值。

阻带零点附近不要计算群延迟，只在10 Hz～20 kHz通带统计。

---

# 14. 中途复位与恢复测试

新增：

```text
tb_phase7_reset_recovery.v
```

CIC版本比Phase6更需要复位测试，因为积分器状态会长期影响输出。

---

## 14.1 必测时刻

1. 空闲时复位；
2. Stage1 BRAM MAC运行时复位；
3. Stage2 pending时复位；
4. Stage3 job运行时复位；
5. CIC `burst_pending=1`时复位；
6. `burst_remaining=15/8/1`时复位；
7. comb状态非零时复位；
8. integrator状态非零时复位；
9. 128×连续输出时复位；
10. 复位解除后立即输入。

---

## 14.2 必须清零的CIC状态

```text
comb_delay[]
integrator_state[]
final_integrator_state
burst_sample
burst_pending
burst_remaining
y_out_valid
```

与Stage1 BRAM不同，CIC积分器和comb状态必须确定性清零。

---

## 14.3 验收

```text
复位期间所有valid=0；
无X；
无旧burst继续输出；
无旧integrator尾巴；
恢复后的第一组输出固定延迟；
恢复后重复同一冲激/随机向量，与cold start结果0 LSB一致。
```

---

# 15. Stage2/3共享DSP调度回归

Phase 7仍沿用Stage3优先调度，但Stage3系数已改变并使用中心系数拆分：

\[
35604x=(-29932)x+2^{16}x
\]

新增定向测试：

```text
x=0、±1、最大正、最大负、随机边界；
验证拆分式与17bit直接乘法严格相等；
验证预装2^16x不增加MAC次数；
验证ACC_W=38不溢出。
```

继续检查：

```text
stage2_pending overwrite = 0
stage3_pending overwrite = 0
deadline miss = 0
Stage2无长期饥饿
每64拍：Stage2完成2个job，Stage3完成4个job
```

---

# 16. 四档动态切换测试

当前四档静态XSim已经通过。新增：

```text
tb_phase7_mode_switch_dynamic.v
```

切换序列：

```text
1× → 4× → 8× → 128× → 8× → 1× → 128×
```

每档保持至少20个15 kHz周期。

检查：

```text
mode_sel同步；
DA_CLK无runt pulse；
切换后频率稳定；
DAC数据无X；
128×重新选择时CIC内部已持续运行或按设计重新稳定；
8×节点预加重属性在文档中明确。
```

建议模式只切换DAC观察节点，不暂停插值核心，使CIC状态持续稳定。

---

# 17. 板级实测清单

Phase 7 bitstream已生成，但执行报告仍要求人工复测。

必须记录：

| 档位 | 理论DA_CLK | 实测DA_CLK | 波形截图 | 备注 |
|---|---:|---:|---|---|
| 1× | 44.1 kHz | | | 原始阶梯最明显 |
| 4× | 176.4 kHz | | | 正常插值输出 |
| 8× | 352.8 kHz | | | CIC预补偿节点 |
| 128× | 5.6448 MHz | | | 最终FIR-CIC输出 |

继续使用：

```text
15 kHz正弦
单DAC
矩阵按键
示波器
```

同时记录：

```text
按键切换是否稳定；
波形是否有异常跳变；
复位后是否恢复；
128×模式是否连续稳定运行。
```

---

# 18. 综合、实现和功耗

每次验证修改后运行：

```tcl
report_utilization -hierarchical
report_timing_summary
report_clock_interaction
report_drc
report_power
report_dsp_utilization
```

验收：

```text
WNS ≥0
WHS ≥0
TNS/THS=0
DSP=2
BRAM Tile=1
Phase7 generate分支确实被综合
无旧Phase6链误接
```

当前功耗为vectorless估计。建议最终增加：

```text
静音
15 kHz
20 kHz
随机PCM
```

四种SAIF/VCD活动功耗；否则必须继续标注Low confidence。

---

# 19. 自动化回归

建议新增：

```text
run_phase7_verification.tcl
run_phase7_verification.m
```

执行：

```text
1. 生成golden
2. Stage3中心系数拆分定向测试
3. CIC comb定向测试
4. CIC burst节拍测试
5. CIC integrator模运算测试
6. 完整顶层冲激0 LSB
7. 完整顶层多种子随机0 LSB
8. valid与输出数量
9. reset recovery
10. mode switch
11. RTL冲激FFT
12. 生成最终报告
```

任何失败返回非零退出码。

---

# 20. 最终汇总报告建议

生成：

```text
phase7_verification_final_summary.md
```

| 类别 | 测试 | 规模 | 最大误差/异常 | 结果 |
|---|---|---:|---:|---|
| 前端 | 完整顶层冲激 | 256输入 | 0 LSB | PASS |
| 前端 | 多种子PCM | 10×4096 | 0 LSB | PASS |
| Comb | 冲激/直流/随机 | — | 0 LSB | PASS |
| Burst | 16输出/输入 | 长流 | 0计数误差 | PASS |
| Integrator | 模运算边界 | — | 0 LSB | PASS |
| CIC增益 | 正负直流 | 16相 | 相位差≤规定LSB | PASS |
| 频谱 | RTL 4× | — | ±0.05/70 | PASS |
| 频谱 | RTL 8×预补偿 | — | golden一致 | PASS |
| 频谱 | RTL 128× | — | ±0.05/70 | PASS |
| 相位 | RTL 128× | — | 群延迟平坦 | PASS |
| 调度 | 1000超周期 | — | 0 miss | PASS |
| 复位 | 10场景 | — | 0旧状态泄漏 | PASS |
| 模式 | 动态多轮 | — | 0毛刺/X | PASS |
| 板级 | 四档15 kHz | — | 全部稳定 | PASS |

---

# 21. 实施优先级

## P0：Phase 7发布前必须完成

1. 正式顶层端到端0 LSB；
2. CIC burst数量和逐拍valid；
3. 中途复位与恢复；
4. RTL最终冲激FFT；
5. 最终N=3多种子长随机；
6. Phase7 bitstream实板四档复测；
7. 明确8×是CIC预补偿节点。

## P1：强烈建议

8. comb定向单测；
9. integrator模运算边界；
10. Stage3中心系数拆分定向测试；
11. 动态档位切换；
12. 自动回归。

## P2：完善材料

13. SAIF功耗；
14. post-synthesis功能仿真；
15. post-route timing simulation；
16. N=4候选参数化回归。

---

# 22. 最终可以形成的严谨结论

完成上述测试后，可以准确表述：

> 本设计采用前级严格半带/多相FIR与后级16倍CIC相结合的混合多速率架构。CIC按低速comb、16倍插零和高速integrator的标准顺序实现，Stage3同时承担镜像抑制与CIC通带补偿。设计已完成浮点频响、有限字长、补码模运算、完整顶层冲激、长随机PCM、任务调度、CIC burst节拍、中途复位和动态模式切换验证；并直接由RTL冲激响应提取最终频率和相位指标，MATLAB与RTL保持0 LSB一致。
