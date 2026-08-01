# 全国赛 P4-B 最新工程 RTL 审计与下一阶段优化指导

> 审计日期：2026-08-01  
> 审计输入：`next_stage_optimization_guide_execution.md`、`XC7A35T_interp_audio_pcm_wordlen_opt(1).zip`  
> 目标器件：XC7A35T-2 / Vivado 2018.3  
> 当前工具侧基线：504 LUT / 493 FF / 4 DSP48E1 / 4 RAMB18E1（2 BRAM Tile）/ 2 MMCM  
> 说明：本文只给出下一阶段修改与验收指导，不直接修改本次压缩包中的 RTL。

## 1. 结论先行

本轮执行方向总体正确：Stage3 真 Q15、原子模式 CDC、N3 Hold 严格等效和两项历史 RAM 调度都已真实反映在当前 post-route 结果中。当前工程已不再是旧的 436 LUT / 5 DSP / 3 BRAM 版本，而是一个确实实现到 4 DSP、2 BRAM Tile 的 P4-B 候选。

但当前压缩包还不应标成最终发布版。最先要处理的不是继续换滤波算法，而是三个签核问题：

1. 48 kHz 家族复位后，测试 ROM 的第一笔地址仍会从 0 开始，而不是 147；目前仅因两个地址的样点恰好都为 0 而被掩盖。
2. XPR 默认 `sim_1` 没有定义全国赛编译宏，GUI 直接运行的主 TB 会落回旧结构，不是综合所用的 P4-B 结构。
3. 本次 ZIP 没有 MATLAB 模型、golden MEM、发布 runner 和 14 项 PASS 日志；包内唯一主仿真日志仍是因 MEM 缺失导致的 `FAIL mismatch=43776`。

修复这些问题后，下一轮最值得做的不是高风险的 256×多泵，而是以下四项：

| 顺序 | 路线 | 性质 | 主要目标 |
|---:|---|---|---|
| 1 | 删除 Stage2/3 永不使用的历史写队列 | 固定调度下严格安全 | 约减少 25 FF 和少量 LUT |
| 2 | 启用现有 Stage1 DSP48 预加器 | 算术严格等效 | 预计减少约一个 25-bit LUT 加法器 |
| 3 | CIC 状态解析收窄到 26/29 bit，并做 CARRY4 A/B | 先证明、再严格等效 | 4 DSP → 3 DSP → 2 DSP |
| 4 | 未选 MMCM `PWRDWN` + SAIF | 时钟架构不变 | 解决当前最主要功耗来源 |

比较稳妥的下一代资源目标是：

```text
约 530～570 LUT
约 450～480 FF
2 DSP
2 BRAM Tile
1 颗 MMCM 处于活动状态
```

这些是待综合目标，不是已实现结果。若继续开展研究型结构，可再形成：

- 约 1 DSP / 2 BRAM Tile 的统一 RAMB36 双读、三级 FIR 单 DSP 版本；
- 约 2～4 DSP、128×阻带约 78.6 dB 的 N4 Hold 性能版本；
- 1.5 BRAM Tile，甚至 1 BRAM Tile 的测试 ROM/历史 RAM 联合存储版本。

## 2. 本次压缩包中真正生效的工程

### 2.1 当前顶层与 Generic

综合顶层为 `board_demo_competition_dac8_top`，器件为 `xc7a35tfgg484-2`。当前 XPR 中生效的关键 Generic 为：

```text
USE_NATIONAL_FINALS_DATAPATH=1
USE_NATIONAL_FINALS_SINGLE_BRAM_STAGE1=1
USE_PHASE7_UNIFIED_BRAM_STAGE23_HISTORY=1
USE_PHASE7_BRAM_STAGE23_COEFF=1
USE_NATIONAL_FINALS_SERIAL_CIC_COMB=1
USE_NATIONAL_FINALS_N3_HOLD_EQUIV=1
USE_NATIONAL_FINALS_NARROW_STAGE23=1
USE_PHASE8_PACKED_BRAM_STAGE23=0
USE_NATIONAL_FINALS_STAGE1_DSP48_PREADDER=0
```

因此当前真实数据通路是：

```text
双采样率 24-bit 测试 ROM
→ Stage1：105-tap 半带、单历史 BRAM、串行 MAC、1 DSP
→ 24→22 bit 舍入饱和
→ Stage2/3：统一历史 BRAM、统一系数 BRAM、共享 MAC、1 DSP
→ 22→20 bit 舍入饱和
→ 三抽头 [-1,10,-1]/8 CIC 补偿
→ C² → Hold16 → I²，2 DSP
→ 1×/4×/8×/128×节点选择
→ 24→8 bit AD9708 输出
```

当前四颗 DSP 分别用于 Stage1、Stage2/3、CIC 积分器 1、CIC 积分器 2。当前四个 RAMB18E1 分别用于测试 PCM ROM、统一系数 ROM、Stage1 历史、Stage2/3 统一历史。

按当前整数系数独立重建等效小信号响应，结果与执行反馈接近：

| 输入家族 | 输出 | 通带峰峰纹波 | 相对阻带 |
|---:|---:|---:|---:|
| 44.1 kHz | 4× | 0.005709 dB | 78.568 dB |
| 44.1 kHz | 8× | 0.006201 dB | 78.609 dB |
| 44.1 kHz | 128× | 0.008196 dB | 72.370 dB |
| 48 kHz | 4× | 0.005709 dB | 78.568 dB |
| 48 kHz | 8× | 0.005678 dB | 78.609 dB |
| 48 kHz | 128× | 0.005563 dB | 72.370 dB |

量化系数严格对称，因此未饱和的小信号结构保持严格线性相位；不能把这句话扩大成“含舍入和饱和的整套系统对任意输入仍是全局线性系统”。128×阻带只比 70 dB 门槛高约 2.37 dB，是后续停止机械减位、把 N4 作为独立性能版的主要原因。

### 2.2 当前 post-route 证据

| 项目 | 当前包内结果 | 审计判断 |
|---|---:|---|
| LUT | 504 | 可由实现报告确认 |
| FF | 493 | 可由实现报告确认 |
| Slice | 202 | 可由反馈和报告确认 |
| DSP48E1 | 4 | 层次结构与资源报告一致 |
| RAMB18E1 | 4 | 等效 2 BRAM Tile |
| MMCM | 2 | 两颗当前都常开 |
| WNS / TNS | +45.637 ns / 0 | 内部 setup 通过 |
| WHS / THS | +0.119 ns / 0 | 内部 hold 通过 |
| 功耗 | 0.271 W | vectorless、Medium confidence |

包内 bitstream 的 SHA-256 为 `da0665e43a8da5230ab93fc786ab0eed47bd83fe393c9b1416ba3360b8de5e85`，与执行反馈一致。

功耗报告中的两颗 MMCM 合计约 0.197 W，而逻辑、DSP 和 BRAM 各项都很小。因此后续功耗工作应优先处理 MMCM，而不是先为几颗寄存器增加复杂 CE。

### 2.3 当前 DRC 应如何解释

当前已经不是旧版 66 条 DRC。现有 routed DRC 为：

- 5 条 `DPIP-1`：Stage1、Stage2/3 和 CIC DSP 输入未流水；
- 2 条 `DPOP-1`：两个 CIC DSP 的 `PREG=0`；
- 1 条 `AVAL-4`：Stage2/3 DSP 未使用 D 口时的寄存器配置建议。

这些警告在当前约 45 ns 的 WNS 下不是功能阻塞项。不要只为了“Warning 归零”盲目增加延迟；应优先选择能同时改善资源、功耗或结构清晰度的修改。本文后面给出了 `PREG` 版和 CARRY4 版两个不同 Pareto 方向。

## 3. P0：继续优化前必须先修的两个 RTL/签核问题

### 3.1 48 kHz 切换后的首样点地址错误

当前 `board_demo_competition_dac8_top.v` 中：

```verilog
always @(posedge clk_audio_128x) begin
    if (!rst_audio_n) begin
        family_audio_meta <= 1'b0;
        family_audio_sync <= 1'b0;
    end
    else begin
        family_audio_meta <= family_active;
        family_audio_sync <= family_audio_meta;
    end
end
```

而测试 ROM 在复位期间用 `family_48k` 选择首地址：

```verilog
rd_addr <= family_48k ? 8'd147 : 8'd0;
```

44.1→48 kHz 切换时，数据通路复位会把 `family_audio_sync` 固定为 0，导致 ROM 地址被反复装载为 0。复位释放后，同步值虽会变成 1，但 `rd_addr` 直到第一次 `sample_ce` 才重新判断家族，所以第一笔仍报告地址 0，随后才跳到 147。

当前地址 0 和 147 的样点都恰好为 0，因此数值波形没有暴露问题。换成任意非零首样点或真实 PCM 文件后就会显错。

推荐修改：

```verilog
(* ASYNC_REG = "TRUE" *) reg family_audio_meta = 1'b0;
(* ASYNC_REG = "TRUE" *) reg family_audio_sync = 1'b0;

always @(posedge clk_audio_128x) begin
    // 不受数据通路复位清零；切换静音期间持续跟踪稳定的 family_active
    family_audio_meta <= family_active;
    family_audio_sync <= family_audio_meta;
end
```

同时让 ROM 在 `!rst_n` 期间每拍依据已经同步的家族值重装首地址。更长期的版本应把“采样率家族＋输出模式”合并为一次原子命令，由家族切换 FSM 在目标时钟锁定、家族同步稳定后再释放 ROM 和滤波器复位。

验收门槛：

- 44.1→48 kHz 后第一次 `sample_update` 必须满足 `sample_addr_dbg==147`；
- 48→44.1 kHz 后第一次必须为 0；
- 在随机 `ce_cnt` 相位发起两个方向各至少 100 次切换；
- TB 专门把地址 0、147 改成不同的非零哨兵值；
- 切换期间 DAC 始终为 `8'h80`，无 X、无窄脉冲。

### 3.2 综合配置与默认仿真配置发生漂移

当前主 TB `tb_phase7_full_chain_bittrue.v` 依赖多组编译宏选择全国赛结构，例如：

```text
NATIONAL_FINALS
NATIONAL_FINALS_UNIFIED_STAGE23_HISTORY
NATIONAL_FINALS_SINGLE_BRAM_STAGE1
NATIONAL_FINALS_USE_N3_HOLD
NATIONAL_FINALS_NARROW_STAGE23
```

但本次 XPR 的默认 `sim_1` 没有这些 `verilog_define`。因此直接点击 GUI 仿真时，TB 会选择旧 Stage3、旧 CIC 或旧 RAM 分支，而不是综合得到 504/493/4/2 的结构。

应新建一个无宏歧义的固定签核包装器，例如：

```verilog
module nf_signedoff_filter_core (...);
    interp128_all2x_v7_folded_fir_cic_top_ce #(
        .STAGE1_ACC_W(41),
        .STAGE23_ACC_W(38),
        .FINAL_PRUNE_LSB(0),
        .STAGE3_FLAT(1),
        .USE_SINGLE_BRAM_STAGE1(1),
        .USE_UNIFIED_BRAM_STAGE23_HISTORY(1),
        .USE_BRAM_STAGE23_COEFF(1),
        .USE_CIC3_SHIFTADD_COMPENSATOR(1),
        .USE_N3_HOLD_EQUIV(1),
        .USE_NATIONAL_FINALS_NARROW_STAGE23(1)
    ) u_core (...);
endmodule
```

板级顶层和主位真 TB 必须共同实例化这个 wrapper。实验分支可另建 wrapper，不要继续依靠十余个宏拼出“当前版本”。

同时增加以下门禁：

1. 任一输入或 golden 文件 `$fopen` 失败时立即 `$fatal`；
2. 向量长度和 SHA-256 不匹配时立即失败；
3. 日志必须包含唯一的 `NF_SIGNEDOFF_CONFIG_ID`；
4. 综合 Tcl、GUI XPR 和仿真日志中的配置 ID 必须相同；
5. 故意把 Stage3 一个系数改回旧 Q14 时，负测试必须失败。

### 3.3 当前 ZIP 的可复现性缺口

本次收到的压缩包是 Vivado 工程目录，不包含反馈文档中提到的完整仓库资产。包内没有：

- MATLAB 浮点/位真模型；
- daily/release golden MEM；
- 10 个随机 seed；
- 一键回归 runner；
- 14 项独立 PASS 日志；
- 当前配置/延迟/向量 manifest；
- `report_cdc` 及 waiver 文档。

因此现阶段最严谨的表述是：

> 当前 P4-B post-route 实现候选成立；504 LUT、493 FF、4 DSP、2 BRAM 等实现结果可信，但本次交付包不能独立复现反馈中声明的 14/14 RTL 和 MATLAB 位真闭环。

最终发布包建议只保留：

```text
rtl/
constraints/
matlab/
vectors/daily/
vectors/release/
sim/
scripts/build/
scripts/regression/
reports/signedoff/
manifest.json
SHA256SUMS
README.md
```

不要提交 `.Xil`、cache、旧 run、crash log、WDB、旧版本分支源码和未使用 IP。当前旧 `clk_wiz_audio_48k` XCI 仍保存着较差的 33.375/108.625 参数，而真正生效的手写 `dual_family_audio_clock.v` 已使用 36.25/118；保留两套同名时钟方案很容易再次误用。

## 4. P1：把验证闭环补成真正的发布门禁

### 4.1 历史 RAM 必须增加 primitive-vs-behavioral 测试

当前两个历史 RAM 在综合时使用 `RAMB18E1`，普通 RTL 仿真时使用行为数组。综合出 4 个 RAMB18E1，只能证明资源映射成功，不能证明 primitive 的地址、符号扩展、同步读延迟和同址读写语义正确。

至少增加：

- Stage1 history RAM primitive 对行为模型；
- Stage2/3 unified history RAM primitive 对行为模型；
- 全地址遍历、地址回卷、正负边界码；
- 连续读、读写不同址、同址 `READ_FIRST`；
- 复位前后第一笔读；
- 当前真实 `COEFF_W=16`、`STAGE3_FLAT=1`、统一系数 BRAM 直连测试。

不要在整个工程全局定义 `SYNTHESIS` 来跑 primitive TB。建议给 RAM wrapper 增加专用 `SIM_USE_PRIMITIVE` 参数，或单独建立 primitive 测试 wrapper。

另一个休眠风险是 packed Stage2/3 分支的 RAM 初始化依赖从另一个数组复制的 `initial` 赋值，综合日志会忽略非恒定初始化。当前 `USE_PHASE8_PACKED_BRAM_STAGE23=0` 不受影响；今后启用前必须改成生成后的常量 `INIT_xx`、MEM 文件或直接常量表。

### 4.2 发布级 T00～T15

每个测试必须同时检查 y4、y8、y128；若 1×仍保留在正式 UI 中，也应检查 1×。

| 编号 | 激励 | 主要目的 |
|---:|---|---|
| T00 | 全零 | 零输入、无自激、复位残留 |
| T01/T02 | 正/负冲激 | 系数、延迟、相位、符号 |
| T03/T04 | ±1 LSB DC | 小信号、舍入偏置 |
| T05/T06 | 正/负半幅 DC | 绝对增益、稳态 |
| T07/T08 | 最大/最小常量 | 饱和和解析范围 |
| T09 | 最大/最小交替 | 最坏切换、CIC状态界 |
| T10 | 正负阶跃 | 暂态和恢复 |
| T11 | 上升/下降 ramp | 单调性、截位 |
| T12 | 997 Hz 正弦 | 音频幅度、SNR |
| T13 | 15 kHz 正弦 | 当前板级演示点 |
| T14 | 19.9/20 kHz、多音 | 通带边缘和互调 |
| T15 | 10 seed × 4096 | 长随机位真、状态覆盖 |

每项再叠加：valid 停顿、处理中复位、模式切换、家族切换。

统一门槛：

- RTL 与独立整数位真模型所有有效样点 0 LSB；
- 固定首 valid 周期和固定延迟，不允许相关搜索自动对齐；
- 无 X/Z、无丢样、无重复样；
- 输出计数严格满足倍率；
- 正常音频无意外饱和；
- 极端输入中的受控饱和必须与 golden 一致；
- CIC 合法 modulo wrap 与非法溢出分开统计。

每个节点输出：`min/max/max_abs/headroom_bits/saturation_count/modulo_wrap_count`。当前 Stage2 最坏相位的保守解析余量只有约 0.34 bit，因此不要再机械减少 Stage2 的 38-bit 累加器。

### 4.3 六工况之外还要明确 1×

赛题主指标若只要求 4×/8×/128×，应在发布说明中明确 1×是演示模式、非正式频响验收项。否则就按：

```text
44.1/48 kHz × 1×/4×/8×/128× = 8 种组合
```

完整回归。不要让 UI 中可选但从未签核的 1×成为答辩现场风险。

## 5. P2：低风险 RTL 精简

### 5.1 删除 Stage2/3 统一历史 RAM 的死写队列

当前统一历史 RAM 保留：

```text
stage3_write_queued             1 bit
stage3_queued_write_addr        4 bit
stage3_queued_write_data       20 bit
```

约 25 个状态 FF。但在当前复位相位和固定二次幂 CE 下，两级写请求永不重合：

```text
Stage2 phase0 写：ce_cnt = 32 mod 64
Stage3 phase0 写：ce_cnt = 16 或 48 mod 64
```

两个集合不相交。建议只在签核固定 CE 配置中增加 fast path：

```verilog
wire stage23_write_collision =
    stage2_history_write_event && stage3_history_write_event;

assign unified_write_enable =
    stage2_history_write_event || stage3_history_write_event;
assign unified_write_addr = stage2_history_write_event ?
    {1'b0, stage2_write_addr} : {1'b1, stage3_write_addr};
assign unified_write_data = stage2_history_write_event ?
    stage2_x_current : {{2{stage3_x_current[19]}}, stage3_x_current};

`ifndef SYNTHESIS
always @(posedge clk)
    if (rst_n && stage23_write_collision)
        $fatal(1, "signed-off Stage2/3 history write collision");
`endif
```

若该模块仍要作为支持任意 CE 停顿/相位的通用 IP，应保留原队列，用参数 `ASSUME_ALIGNED_POW2_CE` 区分，不能无条件删除。

Go 条件：

- 与 P4-B 全回归 0 LSB；
- 形式或至少长仿真证明写冲突不可达；
- post-route FF 实际下降；
- 地址回卷、复位、家族切换不改变相位关系。

### 5.2 启用现有 Stage1 DSP48E1 预加器

当前单 BRAM Stage1 已经提供 `USE_DSP48_PREADDER` 分支，但顶层 Generic 仍为 0。关闭时，`left_sample + read_data` 先在 LUT 中形成 25-bit 对称和，再送 DSP 乘法器；打开后可直接使用 DSP48E1 的 25-bit `D+A` 预加器。

对称项满足：

\[
x_i c+x_j c=(x_i+x_j)c
\]

只要预加前后都保留 25-bit signed 结果，且乘法前不截位，数值严格等效。DSP48E1 原生提供 25-bit 预加器，[AMD UG479](https://docs.amd.com/v/u/en-US/ug479_7Series_DSP48E1) 可作为实现依据。

实施步骤：

1. 先只把 `USE_NATIONAL_FINALS_STAGE1_DSP48_PREADDER` 改为 1；
2. 单独运行 Stage1 正/负冲激、最大最小交替、随机和复位测试；
3. 对比 P4-B Stage1 输出与全链输出 0 LSB；
4. 检查 DSP 数仍为 4；
5. 检查 LUT 是否下降、DRC 的 Stage1 A/B 警告是否变化；
6. 若 LUT 没有下降或出现 primitive 时序问题，立即回退，不与其他修改绑定提交。

预期可删除一个约 25-bit 的 fabric 加法器，但具体 LUT 数必须以综合结果为准。

### 5.3 修正 `SETTLE_CYCLES` 参数宽度并增加独立暖机静音

`nf_mode_cdc_handshake` 的 `SETTLE_CYCLES` 是整数参数，但 `settle_count` 固定只有 2 bit。当前值 3 正常；以后把参数改到 4 以上会被静默截断。

改为：

```verilog
localparam integer SETTLE_W =
    (SETTLE_CYCLES < 1) ? 1 : $clog2(SETTLE_CYCLES + 1);
reg [SETTLE_W-1:0] settle_count;
```

CDC 的 2～3 拍稳定等待与滤波器暖机不是一回事。家族切换会清空 105-tap Stage1 及后级历史，解除复位后仍有零填充暂态。建议另设：

```text
warmup_input_samples = 64
```

只按 `x_in_update_ce` 计数；64 个输入样点约为 1.33～1.45 ms。更严谨的实现可由各级 `history_full`、CIC burst idle 和模式握手 ACK 联合释放静音。

## 6. P3：CIC 解析收窄与 4→3→2 DSP Pareto

这是本轮最值得实现的新资源路线。

### 6.1 为什么当前两个积分器不一定需要 33 bit

当前 N3 Hold 路径为：

\[
C^2\rightarrow \operatorname{Hold}_{16}\rightarrow I^2
\]

输入补偿器输出为 21-bit signed。33 bit 是沿用传统 CIC 总增长上界，安全但不是本结构每个状态的最紧界。

设低速输入为 \(x[m]\)，二阶 comb 输出：

\[
v[m]=x[m]-2x[m-1]+x[m-2]
\]

在第 \(m\) 个 Hold 块内，令相位 \(q=1,\dots,16\)。第一积分器状态可写成：

\[
a[m,q]=q x[m]+(16-2q)x[m-1]+(q-16)x[m-2]
\]

其系数绝对值和最大为：

\[
\max_q\left(q+|16-2q|+|q-16|\right)=32
\]

对 21-bit signed 输入，最坏范围可由 26-bit signed 容纳，包括负端的 \(-2^{25}\)。

第二积分器的每个高率相位等效为原 N3 CIC FIR 的一个多相分支；系数非负，每相系数和为：

\[
16^{3-1}=256
\]

因此最终状态对 21-bit 输入的解析范围为：

\[
-2^{20}\times256=-2^{28}
\]

到：

\[
(2^{20}-1)\times256=2^{28}-256
\]

29-bit signed 可容纳该范围。

所以可建立：

```text
第一积分器：33 → 26 bit
最终积分器：33 → 29 bit
```

这不是“随意删除反馈 LSB”。它依赖当前 R=16、N=3、补偿输出 21 bit、零初态和完整 Hold/comb 结构的解析证明。任何参数改变后都必须重新推导。[Hogenauer CIC 经典论文](https://doi.org/10.1109/TASSP.1981.1163535) 仍是 modulo 运算和字长分析的基础。

### 6.2 三个实现版本

当前模块级 `(* use_dsp="yes" *)` 强制两个加法器使用 DSP。AMD 说明 `USE_DSP=no` 可以阻止加法器/累加器进入 DSP，而 7 系列 CLB 提供专用高速 carry logic。[UG901 `USE_DSP`](https://docs.amd.com/r/2022.1-English/ug901-vivado-synthesis/USE_DSP)、[UG474 Carry Logic](https://docs.amd.com/r/en-US/ug474_7Series_CLB/Carry-Logic-Applications)

建议去掉模块级强制属性，按积分器分别参数化：

| 版本 | 第一积分器 | 第二积分器 | 全机目标 DSP | 预估 fabric 代价 |
|---|---|---|---:|---:|
| P3-R | 33-bit DSP | 33-bit DSP | 4 | 当前参考 |
| P3-A | 26-bit CARRY | 29-bit DSP | 3 | 约 +26 LUT |
| P3-B | 26-bit CARRY | 29-bit CARRY | 2 | 约 +55～70 LUT |

当前 DRC 已证明两个 DSP 的 `PREG=0`，积分器状态本来就在外部 FF 中，因此 CARRY 版不应再机械估计“额外增加 55 个 FF”；更合理的预期是 FF 近似不变，并因 33→26/29 收窄减少约 11 个状态位。最终仍以层次综合为准。

### 6.3 验证要求

先建立独立数学/位真参考，再做 RTL 对拍，不能只让“新 RTL 对旧 RTL”互相比，因为两者可能共享同一个归一化错误。

必须覆盖：

- 21-bit 最大、最小、最大/最小交替；
- 正负 DC、正负阶跃；
- 10 个长随机 seed；
- `x_in_valid` 停顿；
- burst 中途复位；
- 状态接近 26/29-bit 边界的定向序列；
- 解析状态 min/max 与公式界对比；
- P3-A/P3-B 与 33-bit 参考所有输出 0 LSB；
- post-route WNS/WHS、LUT/FF/DSP、SAIF 功耗。

Go 条件：

- 任一有效样点 0 LSB；
- 解析界不被突破；
- P3-A 确认 3 DSP，P3-B 确认 2 DSP；
- P3-B LUT 增量不超过约 80，且时序仍有充足裕量；
- 功耗只引用 SAIF 或实板数据，不根据 DSP 数量直接下结论。

## 7. P4：保留 4 DSP 时的低 FF / 低功耗替代路线

如果比赛更看重 LUT/FF，而不要求继续降低 DSP，可把两个积分器显式实例化成带 `PREG=1` 的 DSP48E1，并使用 `PCOUT→PCIN` 级联。

当前 look-ahead 递推为：

\[
A[n]=A[n-1]+x[n]
\]

\[
B[n]=B[n-1]+A[n]
\]

标准寄存级联为：

\[
A_p[n]=A_p[n-1]+x[n]
\]

\[
B_p[n]=B_p[n-1]+A_p[n-1]
\]

零初态下：

\[
B_p[n+1]=B[n]
\]

即数值序列相同，只多一个高速输出事件延迟。DSP48E1 的 `PCIN/PCOUT` 是相邻 DSP 专用 48-bit 级联路径，[DSP48E1 primitive 说明](https://docs.amd.com/r/en-US/ug953-vivado-7series-libraries/DSP48E1) 可作为实现依据。

该版本可能：

- 消除 2 条 `DPOP-1`；
- 把约 55～66 个状态 FF 吸收到 DSP PREG；
- 改善 DSP 内部功耗/布局；
- 保持总 DSP 为 4。

但它会改变固定延迟，并且有限流结束前后需要正确处理首个零和最后一个管线样点。建议把它视为与 CARRY4 路线并列的另一个 Pareto 分支，不要在一次提交中同时实现。

限制条件：

- 首版只允许 `FINAL_PRUNE_LSB=0`；
- 输出 valid 和 latency manifest 同步增加一个事件；
- 连续流、停顿、复位和有限长度尾部全部显式测试；
- 只取 P 的低 26/29 或 33 bit，并证明 modulo 行为一致。

## 8. P5：BRAM 2 Tile 之后还能怎样压

### 8.1 最低风险：测试 PCM 与 Stage1 历史共用 RAMB18

当前 Stage1 history 只用 64×24，而一个 RAMB18E1 在 SDP 模式可提供 512×36；测试 PCM 只有 163×24。两者可以按地址空间合并：

```text
地址   0..63   Stage1 环形历史
地址  64..210  44.1 kHz 147 点测试音
地址 211..226  48 kHz 16 点测试音
```

Stage1 每个 128-cycle 输入周期约占用 51 次历史读，测试音只需 1 次同步预取，读端口时隙充足。写端口只写历史区。RAMB18E1 的 SDP 容量和同步端口行为见 [AMD RAMB18E1](https://docs.amd.com/r/en-US/ug953-vivado-7series-libraries/RAMB18E1)。

实施要点：

- 地址扩展到至少 8 bit；
- 为历史读和 PCM 预取建立显式 owner；
- 只在 Stage1 idle 时发 PCM 读；
- PCM 数据预取后保持到下一次 `x_in_update_ce`；
- 增加 `history_read && pcm_read` 冲突断言；
- primitive TB 同时验证动态历史区和常量 ROM 区。

成功后：4 RAMB18E1 → 3 RAMB18E1，即 Vivado 等效资源 2 → 1.5 BRAM Tile。过滤算法不变。

### 8.2 备选：统一系数 ROM 的空闲地址存测试音

当前统一系数 ROM 仅使用 0..89 共 90 个 18-bit word。把每个 24-bit PCM 拆成两个 18-bit word，只需 326 word，总占用 416/1024，也能放进同一 RAMB18E1。

该方案需要两次读和 24-bit 重组，但不会把可写历史区与常量 ROM 混在一起。Stage1 系数端口每 128-cycle 有大量空闲周期，可用于两次预取。两种方案只选一种做 A/B，不要同时增加两套仲裁器。

### 8.3 1 BRAM Tile 极限版本

若赛题特别强调 BRAM 数，可在“Stage1 history＋PCM 共用一颗 RAMB18”基础上，把 32×22 Stage2/3 history 改成约 22 个 LUT 的 distributed RAM。此时只剩：

```text
Stage1 history + PCM：1 RAMB18
统一 FIR coefficient：1 RAMB18
总计：2 RAMB18 = 1 BRAM Tile
```

这是资源展示分支，不一定是面积或功耗最优。Go 条件应是：增加 LUT 不超过约 30、2 RAMB18 确实映射为 1 Tile、全链 0 LSB、SAIF 功耗不恶化超过 5%。

## 9. P6：双 MMCM 功耗管理

### 9.1 当前真正生效的时钟参数

本次顶层实际实例化的是 `national_finals/dual_family_audio_clock.v`，不是旧 Clocking Wizard IP：

| 家族 | D / M / O | 实际 128×时钟 | 基频误差 |
|---|---|---:|---:|
| 44.1 kHz | 2 / 62.375 / 110.5 | 5.644796 MHz | −0.641 ppm |
| 48 kHz | 1 / 36.25 / 118 | 6.144068 MHz | +11.035 ppm |

这两个值已经比包内旧 `clk_wiz_audio_48k.xci` 的 +161.8 ppm 配置更好。应删除或明确禁用旧 IP，避免 GUI 再次选错。

### 9.2 先做未选 MMCM `PWRDWN`

AMD 的 `MMCME2_ADV` 明确提供 `PWRDWN`，用于关闭未使用的 MMCM；`LOCKED` 失效后需要按规范复位和重新锁定。[MMCME2_ADV 官方说明](https://docs.amd.com/r/en-US/ug953-vivado-7series-libraries/MMCME2_ADV)

固定倒计时必须先改为锁定驱动 FSM：

```text
IDLE
→ 收到新家族请求
→ DAC_MUTE，断言数据通路复位
→ WAKE_TARGET：target PWRDWN=0，给目标MMCM复位脉冲
→ WAIT_TARGET_LOCK：LOCKED连续稳定N个sys周期，带超时
→ SWITCH_CLOCK：改变BUFGMUX_CTRL选择
→ WAIT_HEARTBEAT：确认目标音频域时钟确实运行
→ SYNC_FAMILY：等待family同步器稳定并重装ROM首地址
→ WARMUP：64个输入样点
→ POWER_DOWN_OLD
→ RELEASE_MUTE，ACK
```

超时必须保持 DAC 中点码，并回退旧家族或点亮错误指示，不能无条件释放复位。

功耗签核：

1. 为 44.1/48 kHz × 1/4/8/128× 分别生成 post-route SAIF；
2. 报告 P4-B、双 MMCM 单活动、单 MMCM DRP 三版；
3. 记录 Total on-chip、Dynamic、Clocks、MMCM、Logic、DSP、BRAM；
4. 实板测对应电源轨电流和器件温度；
5. 不把当前 0.197 W 简单除以 2 当成结果。

AMD 的功耗指南明确区分 vectorless 与 SAIF 活动率，并要求核对时钟、复位和 enable 的真实活动。[AMD UG907](https://docs.amd.com/r/en-US/ug907-vivado-power-analysis-optimization/Vivado-Power-Optimization)

### 9.3 单 MMCM 应走 DRP，不要固定同时出两路

按 7 系列 MMCM 合法的 1/8 分数参数枚举，若一颗固定 MMCM 同时输出 5.6448 和 6.144 MHz，且只有一个输出可用分数分频，最好的共同配置仍约有 181 ppm 的最坏误差。因此不推荐“单 MMCM、两路静态输出”。这是根据当前 20 MHz 输入和 7 系列参数网格做的工程推导，不是器件手册的直接结论。

若要只实例化一颗 MMCM，应使用 DRP 在两套已验证参数间重配置。XAPP888 给出了 7 系列 MMCM/PLL 的 DRP 寄存器表和参考状态机。[AMD XAPP888](https://docs.amd.com/v/u/en-US/xapp888_7Series_DynamicRecon)

建议先完成双 MMCM `PWRDWN` 版本，再做单 MMCM DRP。两者的活动功耗可能接近；DRP 的额外价值主要是少占一颗时钟硬核和形成更完整的动态重配置创新点。

### 9.4 模式 CE 和 BRAM EN 放到 SAIF 之后

当前报告中逻辑、DSP、BRAM各自不足 1 mW，MMCM才是主项。1×暂停全部滤波、4×暂停 Stage3/CIC、8×暂停 CIC 会引入从低倍率切高倍率时的预热和状态一致性问题。

因此只有当 SAIF 显示数据通路动态功耗占比已经明显时才实施。优先使用 DSP/BRAM/寄存器原生 CE，不要用普通逻辑门控时钟。

## 10. P7：N4 Hold 性能版

当前 N3 Hold 是与旧 N3 CIC 严格等效的资源优化：

\[
C^3\rightarrow\uparrow16\rightarrow I^3
\equiv
C^2\rightarrow\operatorname{Hold}_{16}\rightarrow I^2
\]

Losada 与 Lyons 给出了这种降低 CIC 复杂度的等效关系。[Reducing CIC Filter Complexity](https://doi.org/10.1109/MSP.2006.1657825)

N4 路线则是新的传递函数：

\[
C^4\rightarrow\uparrow16\rightarrow I^4
\equiv
C^3\rightarrow\operatorname{Hold}_{16}\rightarrow I^3
\]

先前预筛选的三抽头补偿为：

\[
[-11,86,-11]/64
\]

初步目标是把 128×相对阻带从约 72.37 dB 提高到约 78.6 dB，同时保持通带峰峰纹波不超过 0.01 dB。这个数值是工程预筛选，不是论文直接结果，也不是与当前 N3 逐点等效。

建议形成：

| N4版本 | CIC积分器实现 | 全机目标DSP | 定位 |
|---|---|---:|---|
| N4-P | 3个DSP | 5 | 性能参考 |
| N4-B | 2个DSP + 1个CARRY | 4 | 与当前DSP数相同的性能版 |
| N4-F | 3个CARRY | 2 | 高LUT、低DSP性能版 |

必须重新建立：

- 浮点 N4 频响；
- 整数补偿系数搜索；
- 37-bit 或重新解析后的内部位宽；
- 新版位真 golden；
- 新固定延迟；
- 六/八工况频响和绝对增益；
- 新版 RTL 与新版位真模型 0 LSB。

不应要求 N4 与 N3 旧 golden 0 LSB。无乘法 CIC 补偿器可参考 [Fernández-Vázquez 与 Doleček](https://doi.org/10.1109/TCSII.2011.2180093)，但当前三抽头结构已经很小，文献方案不保证继续减少资源。

## 11. P8：RAMB36 双读＋预加器＋三级 FIR 一颗 DSP

当前“三级 FIR 一颗 DSP”的 72>64 No-Go 只证明了单读历史 RAM 的原方案不可行，不等于所有单 DSP FIR 都不可行。

现有 Stage2/3 虽使用对称系数，但每拍只读一个历史样本，仍逐项乘法。若改成一个 RAMB36E1 TDP 统一保存 Stage1/2/3 历史，两端口可同拍读取一对对称样本，再用 DSP48E1 预加器，最忙的 64-cycle 窗口可由：

| 工作 | 当前单读 | 双读对称折叠 |
|---|---:|---:|
| Stage1 | 27 | 27 |
| Stage2 | 19 | 11 |
| Stage3 | 26 | 16 |
| 合计 | 72 | 54 |

降到 54。RAMB36E1 TDP 支持 36-bit×1K，足以容纳 24/22/20-bit 历史。[AMD RAMB36E1](https://docs.amd.com/r/en-US/ug953-vivado-7series-libraries/RAMB36E1)

这条路线的理论资源点为：

```text
1颗 FIR DSP + 2颗 CIC DSP = 3 DSP / 2 BRAM Tile
```

叠加一个或两个 CARRY CIC 后可形成 2 DSP 或约 1 DSP / 2 BRAM Tile 的研究版本。

但 54 只是算术下界，不是已经证明可调度。实施前必须先写 cycle-exact 64-slot 表，覆盖：

- BRAM 同步读启动延迟；
- Stage1/2/3 的 7 类输出任务；
- 历史写入与双读端口冲突；
- 系数预取；
- DSP P 上下文切换；
- 舍入和提交；
- 每个 job 的 deadline；
- reset、valid 停顿和模式切换。

建议用外部上下文寄存器保存 Stage1/2/3 累加状态，调度器采用固定时隙或 earliest-deadline-first，并增加：

```text
assert(job_finish_cycle <= job_deadline)
assert(no_history_port_collision)
assert(no_context_alias)
assert(no_pending_overwrite)
```

多端口/多 bank FPGA 存储结构可参考 [LaForest 与 Steffan](https://doi.org/10.1145/1723112.1723122)，DSP 共享的调度代价可参考 [Improved Resource Sharing for FPGA DSP Blocks](https://ieeexplore.ieee.org/document/7577373/)。

Go 条件：

- 形式或穷举相位证明所有 deadline；
- 与 P4-B y4/y8 及整链输出 0 LSB；
- 总 DSP 确认降到 3；
- BRAM不超过 2 Tile；
- LUT/FF增量可接受；
- 若调度需要超过 64 cycle，立即 No-Go，不靠扩大 FIFO 掩盖硬截止期。

## 12. P9：联合整数系数、字长与“时隙成本”搜索

当前映射下，单纯把 16-bit 系数减到 15/14 bit 通常不会减少 DSP 数，也不会让 18-bit BRAM word 变小。因此下一轮搜索目标不应只是“更少位”，而应包含真实结构成本：

- 非零对称系数对数量；
- 每相 DSP MAC 时隙；
- 可变成 2 的幂或少量移位加法的系数；
- Stage1/2/3 输出和累加器宽度；
- 补偿器整数系数；
- CIC解析状态位宽；
- 最终 post-route LUT/FF/DSP/BRAM/WNS；
- SAIF 功耗。

硬约束：

```text
通带峰峰纹波 ≤ 0.010 dB
128×相对阻带建议 ≥ 71.5～72 dB，不能只贴着70 dB
模式间绝对增益差 ≤ 0.010 dB
结构/小信号严格线性相位
正常音频无饱和
若用于单DSP FIR：最忙窗口总时隙 ≤ 64
```

Kodek 的有限字长 FIR 研究强调直接优化整数系数，而不是只把浮点系数统一四舍五入。[Kodek 2024](https://doi.org/10.1016/j.dsp.2023.104275)

2025 年的 TPE WLO 工作展示了用黑盒精度评价和综合代价做搜索的思路，但论文的面积评价使用 ASIC Genus/ASAP7，不能直接当成 Vivado 资源预测。[ISCAS 2025 全文](https://research.chalmers.se/publication/547551/file/547551_Fulltext.pdf)

本工程建议：

1. Python/MATLAB 位真模型评估数千候选；
2. TPE 目标包含频响、绝对增益、饱和、MAC时隙和估算资源；
3. 只对前 10～20 个 Pareto 候选运行 Vivado；
4. 最终只保留资源版和性能版各一个；
5. 若真实资源或功耗改善不足 5%，停止该方向。

## 13. P10：AD9708 数字输出的两个改进

### 13.1 24→8 bit 改为舍入饱和

当前：

```verilog
sample_s8_w = display_sample_sat[23:16];
```

等价于有符号向负无穷截断，对均匀小数余数约有 −0.5 个 8-bit LSB 的平均偏差。可复用 `round_sat_shift_compact`：

```verilog
round_sat_shift_compact #(
    .IN_W(24), .OUT_W(8), .SHIFT_N(16)
) u_dac_round (...);
```

现有模块采用中点远离 0 的对称舍入。它不改变 24-bit 滤波 golden，只改变板端量化。均匀误差假设下，舍入相对截断可把量化误差功率降低约 6 dB；实际收益应以 DC 偏置、RMS 误差、SNR/THD 测试为准。

### 13.2 可选：只在 128×启用一阶误差反馈

若希望增加音频创新点，可在 128×模式加入一阶 error-feedback 8-bit 量化器，把部分量化噪声推到 20 kHz 以上；4×/8×旁路。代价约为一个 24-bit 误差状态和加法器。

风险：空闲音、满幅稳定性、带外能量和模拟重建滤波要求。建议加可关闭参数和可选 TPDF dither，只作为独立性能支线。

AD9708 只有 8 bit，理想满幅量化 SNR 也约 50 dB；半幅演示再损失约 6 dB。因此模拟 DAC 频谱不能可信证明数字滤波器的 70 dB 阻带。70 dB 指标应由内部 24-bit ILA 捕获、位真模型或数字接口证明，AD9708 用于验证功能、时钟、切换和模拟波形。[AD9708 数据手册](https://www.analog.com/media/en/technical-documentation/data-sheets/ad9708.pdf)

## 14. CDC、时序约束和板级签核修正

### 14.1 家族时钟应标记逻辑互斥

当前两颗 MMCM 经 BUFGMUX_CTRL 进入同一音频网络。建议在 XDC 中对两组 master/generated clock 增加逻辑互斥关系，并分别用 44.1、48 kHz `set_case_analysis` 场景生成签核报告，避免 TIMING-18 和多时钟路径口径不清。

每个场景保存：

```text
check_timing
report_clock_interaction
report_cdc
report_timing_summary -delay_type min_max
report_route_status
report_drc
report_methodology
report_datasheet
DAC setup/hold 明细
```

### 14.2 不要把 `set_bus_skew` 用在 DAC 输出端口

AMD UG903 明确说明 `set_bus_skew` 的 endpoint 必须是顺序单元数据引脚或单元本身，输出端口不受支持；它主要用于异步多 bit CDC，而不是外部 DAC 总线。[UG903 `set_bus_skew`](https://docs.amd.com/r/en-US/ug903-vivado-using-constraints/Syntax-of-the-set_bus_skew-Command)

因此：

- 模式 bundled-data CDC 可使用合适的 `set_max_delay -datapath_only` 和 `set_bus_skew`；
- AD9708 继续使用 `set_output_delay`，并用 `report_datasheet`/逐 bit timing 统计数据间差值；
- 数据更新在音频时钟下降沿，DAC 在 `dac_clk` 上升沿采样，应在报告中明确半周期关系；
- 当前 `+2.5/-2.0 ns` 包含 0.5 ns 经验 PCB/package 预算，最终应根据实际板线长和测量重算。

AD9708 要求输入 setup 2.0 ns、hold 1.5 ns，并在上升沿锁存。[AD9708 官方规格](https://www.analog.com/media/en/technical-documentation/data-sheets/ad9708.pdf)；输出约束方法见 [AMD UG903 Output Delay](https://docs.amd.com/r/en-US/ug903-vivado-using-constraints/Output-Delay)。

### 14.3 实物板门禁

1. 固定 `00/80/FF`、walking-one、walking-zero、ramp，先在 DAC 数字引脚检查 D0～D7；
2. 测 1×/4×/8×/128×时钟频率、占空比、最短高/低脉宽；
3. 两个家族和所有模式方向至少各 100 次切换；
4. 记录静音中点码持续时间、恢复时间和最大瞬态；
5. ILA 捕获 24-bit y4/y8/y128，与 golden 逐点比较；
6. 再测 Vpp、DC、997 Hz、15 kHz、20 kHz、镜像和噪声；
7. P4-A 与 P4-B 均下载，确认资源优化没有板级副作用。

## 15. 256×多泵应降为后备路线

已有研究说明多泵可减少 DSP，但会增加调度、上下文、LUT 和时钟功耗。[Ronak 与 Fahmy](https://doi.org/10.1109/TCAD.2016.2629421)

对本工程，先后顺序应是：

1. 26/29-bit CARRY CIC，直接达到 2 DSP；
2. RAMB36 双读＋预加器，在当前 128×时钟尝试单 FIR DSP；
3. 只有前两项 LUT/FF代价不可接受或调度失败时，才做 256×；
4. 不建议直接做 4×多泵。

如果 CARRY CIC 和单 FIR DSP 都成功，全机研究目标已接近 1 DSP，此时 256×不再有足够收益证明其复杂度合理。

## 16. 推荐分支与提交顺序

每个步骤只做一类变化，完成 0 LSB、post-route 和报告后再合并。

| 分支建议 | 内容 | 合入条件 |
|---|---|---|
| `nf-p4b-hotfix-release` | 首样点、固定签核wrapper、MEM fail-fast、报告补齐 | 全发布回归与板级通过 |
| `nf-p4c-deadqueue` | 删除固定CE下25-bit写队列 | 0 LSB、FF实际下降 |
| `nf-p4d-stage1-preadder` | Stage1 DSP预加器 | 0 LSB、LUT下降 |
| `nf-p5a-cic-3dsp` | 26-bit第一积分器CARRY | 3 DSP、范围证明通过 |
| `nf-p5b-cic-2dsp` | 26/29-bit双CARRY | 2 DSP、LUT增量可接受 |
| `nf-p5c-cic-preg` | DSP PREG级联替代Pareto | FF/功耗改善、延迟已登记 |
| `nf-p6-mmcm-pwrdwn` | LOCKED FSM、单活动MMCM、SAIF | 切换和功耗门禁通过 |
| `nf-p7-bram-pack` | Stage1 history＋PCM或coeff＋PCM | 1.5 Tile、0 LSB |
| `nf-p8-n4-performance` | N4 Hold＋新补偿 | ≥77 dB、纹波/增益通过 |
| `nf-research-one-fir-dsp` | RAMB36双读、三级FIR共享DSP | 64-slot形式证明、3 DSP |

不要覆盖现有 P3、P4-A、P4-B 回退点。

## 17. 每个候选必须填写的结果表

```markdown
### build_id / git_commit / tool_version

- config_id:
- source_sha256:
- vector_sha256:
- golden_sha256:
- fixed_latency_1x/4x/8x/128x:

| 指标 | 44.1k-1x | 44.1k-4x | 44.1k-8x | 44.1k-128x | 48k-1x | 48k-4x | 48k-8x | 48k-128x |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 绝对增益 dB | | | | | | | | |
| 通带峰峰纹波 dB | | | | | | | | |
| 相对阻带 dB | | | | | | | | |
| saturation_count | | | | | | | | |
| RTL mismatch | | | | | | | | |

| 实现项 | 结果 |
|---|---:|
| LUT / FF / Slice | |
| DSP / RAMB18 / BRAM Tile / MMCM | |
| WNS/TNS/WHS/THS | |
| DRC / Methodology / CDC未waive数 | |
| Total/Dynamic/MMCM/DSP/BRAM power | |
| bitstream SHA-256 | |
| 板测结论 | |
```

## 18. 最终推荐路线

### 稳定主线

```text
P4-B
→ 修复48k首样点
→ 固定签核wrapper＋完整release包
→ 删除Stage2/3死队列
→ 启用Stage1预加器
→ 26/29-bit CIC
→ 3 DSP A/B
→ 2 DSP A/B
→ 未选MMCM掉电
```

这条线最有希望得到一个“2 DSP / 2 BRAM Tile / 低功耗双采样率”的稳定版本，同时保留当前滤波传递函数和 0 LSB 验收条件。

### 性能主线

```text
修正后的P4-B
→ N4 Hold
→ [-11,86,-11]/64 或重新搜索的整数补偿
→ 至少一个积分器映射CARRY
→ 目标约78 dB阻带、≤4 DSP
```

### 研究主线

```text
RAMB36统一历史双读
→ 三级FIR对称预加
→ 64-slot deadline scheduler
→ 1颗FIR DSP
→ 与CARRY CIC组合
→ 研究目标约1 DSP / 2 BRAM Tile
```

只有稳定主线完成发布包和实物板闭环后，后两条路线才应进入答辩主结果。当前最重要的工程标签应写成：

> P4-B implementation candidate，资源结果成立；尚待修复首样点、统一仿真配置、补齐可复现资产和完成实物板签核。

## 19. 主要审计依据

### 工程文件

- [板级顶层](sandbox:/workspace/scratch/720d0e94a3e1/work/latest_audit/XC7A35T_interp_audio_pcm_wordlen_opt/XC7A35T_interp.srcs/sources_1/new/board_demo_competition_dac8_top.v)
- [公共数据通路与DAC输出](sandbox:/workspace/scratch/720d0e94a3e1/work/latest_audit/XC7A35T_interp_audio_pcm_wordlen_opt/XC7A35T_interp.srcs/sources_1/new/demo_interp_dac8_audio_pcm_common.v)
- [Stage1单BRAM核](sandbox:/workspace/scratch/720d0e94a3e1/work/latest_audit/XC7A35T_interp_audio_pcm_wordlen_opt/XC7A35T_interp.srcs/sources_1/new/national_finals/interp2_stage1_single_bram_serial_ce.v)
- [Stage2/3共享核](sandbox:/workspace/scratch/720d0e94a3e1/work/latest_audit/XC7A35T_interp_audio_pcm_wordlen_opt/XC7A35T_interp.srcs/sources_1/new/all2x_v7/interp2_stage23_lutram_cic_dsp_ce.v)
- [N3 Hold CIC](sandbox:/workspace/scratch/720d0e94a3e1/work/latest_audit/XC7A35T_interp_audio_pcm_wordlen_opt/XC7A35T_interp.srcs/sources_1/new/national_finals/cic_interp16_n3_hold2_dsp_ce.v)
- [模式CDC](sandbox:/workspace/scratch/720d0e94a3e1/work/latest_audit/XC7A35T_interp_audio_pcm_wordlen_opt/XC7A35T_interp.srcs/sources_1/new/national_finals/nf_mode_cdc_handshake.v)
- [双家族时钟](sandbox:/workspace/scratch/720d0e94a3e1/work/latest_audit/XC7A35T_interp_audio_pcm_wordlen_opt/XC7A35T_interp.srcs/sources_1/new/national_finals/dual_family_audio_clock.v)
- [XDC](sandbox:/workspace/scratch/720d0e94a3e1/work/latest_audit/XC7A35T_interp_audio_pcm_wordlen_opt/XC7A35T_interp.srcs/constrs_1/new/board_demo_competition_dac8_top.xdc)
- [资源报告](sandbox:/workspace/scratch/720d0e94a3e1/work/latest_audit/XC7A35T_interp_audio_pcm_wordlen_opt/XC7A35T_interp.runs/impl_1/board_demo_competition_dac8_top_utilization_placed.rpt)
- [时序报告](sandbox:/workspace/scratch/720d0e94a3e1/work/latest_audit/XC7A35T_interp_audio_pcm_wordlen_opt/XC7A35T_interp.runs/impl_1/board_demo_competition_dac8_top_timing_summary_routed.rpt)
- [功耗报告](sandbox:/workspace/scratch/720d0e94a3e1/work/latest_audit/XC7A35T_interp_audio_pcm_wordlen_opt/XC7A35T_interp.runs/impl_1/board_demo_competition_dac8_top_power_routed.rpt)
- [当前失败仿真日志](sandbox:/workspace/scratch/720d0e94a3e1/work/latest_audit/XC7A35T_interp_audio_pcm_wordlen_opt/XC7A35T_interp.sim/sim_1/behav/xsim/simulate.log)

### 官方资料与论文

- [AMD UG479：7 Series DSP48E1](https://docs.amd.com/v/u/en-US/ug479_7Series_DSP48E1)
- [AMD UG901：USE_DSP](https://docs.amd.com/r/2022.1-English/ug901-vivado-synthesis/USE_DSP)
- [AMD UG474：7 Series CLB/Carry](https://docs.amd.com/r/en-US/ug474_7Series_CLB)
- [AMD UG472：7 Series Clocking](https://docs.amd.com/v/u/en-US/ug472_7Series_Clocking)
- [AMD XAPP888：MMCM/PLL DRP](https://docs.amd.com/v/u/en-US/xapp888_7Series_DynamicRecon)
- [AMD UG903：Timing Constraints](https://docs.amd.com/v/u/en-US/ug903-vivado-using-constraints)
- [AMD UG907：Power Analysis](https://docs.amd.com/r/en-US/ug907-vivado-power-analysis-optimization/Vivado-Power-Optimization)
- [Hogenauer：CIC Filter](https://doi.org/10.1109/TASSP.1981.1163535)
- [Losada/Lyons：Reducing CIC Complexity](https://doi.org/10.1109/MSP.2006.1657825)
- [Kodek：Optimal Finite Wordlength FIR](https://doi.org/10.1016/j.dsp.2023.104275)
- [ISCAS 2025：FPGA-Based Wordlength Optimization](https://doi.org/10.1109/ISCAS56072.2025.11043696)
- [LaForest/Steffan：Efficient Multi-ported Memories](https://doi.org/10.1145/1723112.1723122)
- [Ronak/Fahmy：FPGA DSP Resource Sharing](https://doi.org/10.1109/TCAD.2016.2629421)
