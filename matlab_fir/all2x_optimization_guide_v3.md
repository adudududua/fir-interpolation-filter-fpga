# 全 2× 128× 插值滤波器下一步优化指导 3.0

> 适用分支：`release/regional-final-demo`  
> 当前实验目录：`matlab_fir/alt_all2x_v2/`、`sources_1/new/all2x_v2/`  
> 当前最新基线：Phase 2 true-polyphase + canonical halfband tail  
> 日期：2026-07-11

## 1. 当前最新状态

反馈文件记录的是 Phase 1，但最新仓库已经继续完成 Phase 2：

```text
Stage 1：93 tap 显式插零，单 DSP 时分复用 MAC
Stage 2：共享数据通路 true-polyphase，LUT 常系数乘法
Stage 3：共享数据通路 true-polyphase，LUT 常系数乘法
Stage 4～7：canonical halfband7，true-polyphase + shift-add
级间桥：valid-only
```

当前独立插值链：

```text
3975 LUT / 3103 FF / 1 DSP
WNS = +156.988 ns
```

功能指标：

```text
通带最大绝对误差 = 0.00715181 dB
总阻带衰减       = 77.67735619 dB
随机 PCM 对拍     = 0 LSB
冲激响应对拍      = 0 LSB
```

因此，下一步主要空间已转移到：

1. Stage 1 的显式插零和 93×24 bit 历史状态；
2. Stage 1 每个补零输出执行 47 次 MAC；
3. Stage 2、Stage 3 的组合 LUT 常数乘法网络；
4. Stage 1～3 没有做系统级联合设计。

Stage 4～7 已经是精确 Q4 移位加法结构，不再是主要目标。

---

## 2. Stage 1 是当前最大瓶颈

现有 Stage 1 保存：

```verilog
reg signed [23:0] x_reg [0:92];
```

仅历史数据约为：

\[
93\times24=2232\text{ bit}
\]

层次综合中 Stage 1 FIR 核约使用 2295 FF，几乎占当前 3103 FF 的大部分。

当前每个补零 FIR 输出执行：

```text
46 对对称 tap + 1 个中心 tap = 47 次 MAC
```

一个原始输入对应两个 Stage 1 输出，因此约为：

\[
47\times2=94\text{ 次乘法/基带输入}
\]

严格半带 true-polyphase 后：

- 一个相位只有中心系数 1，相当于纯延迟；
- 另一个相位为 52 tap 对称 FIR；
- 只需 26 次乘法；
- 历史只保存约 52 个真实输入样点。

也就是：

```text
乘法次数：约 94 -> 26
历史样点：93 -> 约 52
```

这比继续压后级字长更有价值。

---

## 3. 仓库已有的 Stage 1 严格半带候选

当前 MATLAB 已找到：

| 参数 | 结果 |
|---|---:|
| order | 104 |
| taps | 105 |
| FRAC_W | 15 |
| COEFF_W | 17 |
| ACC_W | 42 |
| 非零半系数 | 27 |
| phase0 整数和 | 32768 |
| phase1 整数和 | 32768 |
| Stage 1 阻带 | 77.4749 dB |
| 总通带最大误差 | 0.00508556 dB |
| 总阻带 | 78.6197 dB |

常规 bit-true 无溢出、无饱和；满幅压力输入存在预期的 24 bit 输出饱和，但功能匹配正确。

该候选已经可以进入 RTL，但建议先把 MATLAB 搜索再优化一轮。

---

# 4. Phase 3A：改进 Stage 1 MATLAB 搜索

## 4.1 不要只保留单级 76 dB 约束

当前通过条件近似为：

```matlab
total_pass_abs <= 0.01
total_stop     >= 75
stage1_stop    >= 76
```

赛题验收的是最终 128× 链路。`stage1_stop >= 76 dB` 可能排除更短 Stage 1，而这些候选可能由 Stage 2、Stage 3 补偿后仍满足总指标。

建议生成三套候选：

### Profile A：保守版

```text
总通带误差 <= 0.01 dB
总阻带     >= 75 dB
Stage1阻带 >= 76 dB
```

### Profile B：系统级版

```text
总通带误差 <= 0.01 dB
总阻带     >= 75 dB
不单独限制 Stage1 阻带
```

### Profile C：比赛余量版

```text
总通带误差 <= 0.02 dB
总阻带     >= 73 dB
不单独限制 Stage1 阻带
```

Profile C 仍优于赛题的 ±0.05 dB / 70 dB。

## 4.2 扩展小数位宽

将：

```matlab
FRAC_W_LIST = [16 15 14];
```

扩展为：

```matlab
FRAC_W_LIST = [16 15 14 13 12];
```

## 4.3 以真实架构成本排序

对严格半带候选增加：

```text
FILTER_PHASE_LEN
MAC_PAIR_COUNT
REAL_HISTORY_LEN
COEFF_W
ACC_W
```

排序建议：

```text
1. MAC_PAIR_COUNT
2. REAL_HISTORY_LEN
3. COEFF_W
4. ACC_W
5. 总阻带余量
6. 总通带误差
```

## 4.4 输出 Pareto 集

不要只输出一个候选，至少保留：

```text
最短 taps
最低 FRAC_W
最低 ACC_W
最大阻带余量
当前 105 tap Q15 保守候选
```

导出：

```text
stage1_strict_halfband_pareto.csv
stage1_strict_halfband_candidates.mat
```

---

# 5. Phase 3B：Stage 1 严格半带 true-polyphase RTL

105 tap 的中心下标为 52，是偶数。严格半带且总增益为 2 时：

```text
偶相：只有中心系数 1
奇相：52 tap 非零对称 FIR
```

数学形式：

\[
y[2m]=x[m-26]
\]

\[
y[2m+1]=\sum_{r=0}^{25}
c[r]\left(x[m-r]+x[m-(51-r)]\right)
\]

滤波相只需 26 次乘法。

建议新建：

```text
interp2_stage1_strict_halfband_mac_ce.v
```

模块内部完成：

```text
真实输入历史
纯延迟相
26 周期 MAC
Q15 舍入与 24 bit 饱和
两相输出调度
```

不要再经过：

```text
interp2_ctrl_ce
+
显式插零 FIR
```

> 哪个 CE 输出纯延迟相、哪个输出滤波相，必须通过 MATLAB 冲激序列确定，不能只根据“偶相/奇相”的名字猜测。

---

## 5.1 利用 DSP48E1 预加器

数据宽度适合 DSP48E1：

```text
24 bit + 24 bit -> 25 bit 预加
17 bit 系数
42 bit 累加
```

先用可推断写法：

```verilog
pair_sum <= sample_a + sample_b;
product  <= pair_sum * coeff;
acc      <= acc + product;
```

然后检查综合是否真正使用 DSP 预加器和 P 累加。若没有，再考虑显式 DSP48E1 实例。

---

# 6. Phase 3C：历史存储的三种实现

## 6.1 FF 版

只保存约 52 个真实样点：

\[
52\times24=1248\text{ FF}
\]

相对当前历史状态理论减少约 984 FF。

优点是最容易做 0 LSB 对拍。建议第一版先做 FF。

## 6.2 BRAM 循环缓冲版

探索：

```text
64 深度 × 24 bit
1 个 true dual-port BRAM
```

流程：

1. 新输入写入 `wr_ptr`；
2. 下一拍开始 MAC；
3. 两个端口读取一对对称样点；
4. 26 对样点依次完成；
5. 输入间隔足够长，不会与下一输入冲突。

BRAM 同步读会增加流水延迟，但 26 次 MAC 加流水仍远小于 64 周期预算。

这是最可能大幅降低 FF 的版本。

## 6.3 SRL 版

只在 true-polyphase 后尝试。SRL 用 LUT 换 FF，若评分重点是 LUT，未必有利。

SRL/BRAM 版本应取消历史数据逐项复位，只复位：

```text
wr_ptr
fill_count
valid
状态机
```

填满前屏蔽输出。

---

## 6.4 Phase 3 Stop/Go 门槛

以当前 Phase 2：

```text
3975 LUT / 3103 FF / 1 DSP
```

为基准。

建议：

| 版本 | 实验合并条件 |
|---|---|
| strict-HB + FF | LUT、FF 均下降；FF 建议低于 2300 |
| strict-HB + BRAM | LUT 不高于 FF 版；FF 建议低于 1500；BRAM ≤1 |
| strict-HB + SRL | LUT 增幅很小，且 FF 或功耗有明确收益 |

这些是停止线，不是资源预测。

---

# 7. Phase 4：Stage 2、Stage 3 仍有较大 LUT 空间

当前 Stage 2、Stage 3 已经 true-polyphase，但仍是：

```verilog
(* use_dsp = "no" *)
always @(*) begin
    acc = sample_sum * constant_coeff + ...
end
```

也就是大组合 LUT 常数乘法网络。

不要盲目坚持 DSP 必须为 1。XC7A35T 有 90 个 DSP，增加 1 个 DSP 若能减少数百 LUT，是合理的资源交换。

---

## 7.1 Stage 2/3 共享一个 DSP 的吞吐预算

Stage 2：

```text
phase0：对称后 5 次乘法
phase1：对称后 4 次乘法
每个 Stage2 输入共 9 次
每个基带输入有 2 个 Stage2 输入
合计 18 次
```

Stage 3：

```text
phase0：3 次
phase1：3 次
每个 Stage3 输入共 6 次
每个基带输入有 4 个 Stage3 输入
合计 24 次
```

总计：

\[
18+24=42<128
\]

从总吞吐量看，一个共享 DSP 足够，但还要满足：

```text
Stage 2 输出间隔约 32 周期
Stage 3 输出间隔约 16 周期
```

建议 Stage 3 高优先级，Stage 2 次优先级，或做静态 TDMA。

---

## 7.2 优先实现 2 DSP 总版本

```text
DSP0：Stage 1 严格半带
DSP1：Stage 2、Stage 3 共享
Stage 4～7：canonical shift-add
```

这是最值得比较的下一组 Pareto 点。

必须记录：

```text
LUT
FF
DSP
BRAM
WNS
功耗
代码复杂度
```

## 7.3 再探索 1 DSP 共享 Stage 1～3

严格半带 Stage 1 约 26 次乘法，Stage 2/3 共 42 次：

\[
26+42=68<128
\]

总吞吐量上可行，但存在级间依赖和更严格截止时间。只有 2 DSP 版本稳定后再做。

---

# 8. 若必须保持 1 DSP：Distributed Arithmetic

Stage 2 输出间隔约 32 周期，24 bit 位串行 DA 有机会完成。

Stage 3 输出间隔约 16 周期，需要 radix-4，即每拍处理 2 bit，约 12 周期。

DA 可能降低 LUT 常数乘法资源，但控制复杂，未必优于增加第 2 个 DSP，因此优先级较低。

---

# 9. Phase 5：Stage 1～3 联合设计

最终只验收完整 128× 链路，因此可以探索：

```text
Stage 1 更短、更弱
+
Stage 2 或 Stage 3 略增强
```

例如：

```text
Stage 1 减少 16～24 tap
Stage 2 增加 2～4 tap
Stage 3 增加 0～2 tap
```

若 Stage 2/3 使用共享 DSP，增加少量 tap 可能只增加空闲 MAC 周期，而不会增加 DSP 数。

候选成本建议包括：

```matlab
stage1_history_len
stage1_mac_pairs
stage23_mac_cycles
max_coeff_w
max_acc_w
total_latency
```

保留前 10～20 个组合，最后跑 Vivado 批量综合。最终仍以实际资源为准。

---

# 10. Stage 3 的 CSD 搜索什么时候做

当前 Stage 3 系数可做 ±1、±2、±4、±8 LSB 整数邻域搜索，并偏向：

```text
2^a
2^a ± 2^b
```

但若 Stage 3 最终改为串行 DSP，CSD 复杂度基本不再重要。

所以顺序应是：

```text
先做 DSP Pareto
若坚持 LUT 版本
再做 CSD / SPT 搜索
```

---

# 11. Stage 4～7 暂不继续优化

四级 canonical halfband 已很简单。若共享一套尾级单元，每个基带周期需要：

```text
S4：8
S5：16
S6：32
S7：64
总计：120 / 128 周期
```

裕量太小且存在级间依赖。

可选实验是 S4～S6 共享、S7 独立，但优先级远低于 Stage 1 和 Stage 2/3 DSP Pareto。

---

# 12. 验证 3.0 必须新增

## 12.1 周期调度表

导出：

```text
job arrival
job start
job finish
deadline
slack
```

保存为：

```text
mac_schedule_trace.csv
```

要求所有任务在 deadline 前结束。

## 12.2 输出数量断言

```text
Stage1 = 输入数 ×2
Stage2 = 输入数 ×4
...
Stage7 = 输入数 ×128
```

## 12.3 流式压力

增加：

```text
随机 valid 空洞
中途复位
复位后立即输入
多个随机种子
完整 24 bit 随机输入
```

## 12.4 满幅判定拆分

```text
functional_match_pass
overflow_pass
saturation_logic_pass
no_clipping_pass
```

---

# 13. 功耗验证

当前并行 LUT 常数乘法网络可能有较大组合切换。

使用 SAIF/VCD 比较：

```text
静音
1 kHz / -1 dBFS
20 kHz / -6 dBFS
随机 PCM
```

分别报告：

```text
Clock
Signals
Logic
DSP
BRAM
MMCM
Static
Total
```

BRAM 循环缓冲和串行 DSP 的价值不只在资源，也可能降低动态功耗。

---

# 14. 推荐实施顺序

```text
Phase 3A
修改 Stage1 MATLAB 搜索：
Profile A/B/C + Q12～Q16 + Pareto

Phase 3B
先做 105 tap Q15 strict-halfband FF 版 RTL
确认相位、舍入、固定延迟和 0 LSB

Phase 3C
改成 BRAM 循环缓冲
比较 FF / BRAM / SRL

Phase 4A
增加第 2 个 DSP，Stage2/3 共用
形成 1 DSP / 2 DSP Pareto

Phase 4B
探索 1 DSP 共享 Stage1～3

Phase 5
Stage1～3 系统级联合搜索
```

建议结果表：

```markdown
| 版本 | LUT | FF | DSP | BRAM | WNS | 通带误差 | 阻带 | 0 LSB |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| Phase2 | 3975 | 3103 | 1 | 0 | 156.988 | 0.00715 | 77.677 | 是 |
| S1 strict HB FF | | | 1 | 0 | | | | |
| S1 strict HB BRAM | | | 1 | 1 | | | | |
| S1 + S23 shared DSP | | | 2 | 0/1 | | | | |
| S123 one DSP | | | 1 | 0/1 | | | | |
| Joint search | | | | | | | | |
```

---

# 15. 现在立即做的五件事

```text
1. 扩展 Stage1 严格半带搜索到 Profile B/C 和 Q12/Q13
2. 保留 105 tap Q15 作为保守参考
3. 选出 2～3 个更短 Pareto 候选
4. 先实现 105 tap strict-halfband true-polyphase FF 版
5. 通过后改 BRAM，并再做 Stage2/3 第 2 DSP 版本
```

---

# 16. 最终判断

你认为仍有较大空间是有依据的，但空间已经从“后级 tap 和 Q 格式”转移到：

```text
Stage1 显式插零
Stage1 历史状态
Stage1 普通 FIR
Stage2/3 组合 LUT 乘法
DSP/LUT/BRAM 的资源重新分配
Stage1～3 联合设计
```

当前最值得做的是：

\[
oxed{
	ext{Stage1 严格半带 true-polyphase}
+
	ext{循环缓冲}
+
	ext{DSP48 预加 MAC}
}
\]

随后：

\[
oxed{
	ext{Stage2/3 共享第 2 个 DSP}
}
\]

最后：

\[
oxed{
	ext{Stage1～3 系统级联合搜索}
}
\]
