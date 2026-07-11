# 全 2x V3 Phase 3 Stage 1 严格半带执行反馈

## 1. 结论

`all2x_optimization_guide_v3.md` 对当前瓶颈的判断成立。Stage 1 从
93-tap 显式插零 FIR 改为 105-tap 严格半带 true-polyphase 后，虽然
数学 tap 数增加，但真实历史状态和 MAC 次数明显下降。

当前 Phase 3 推荐实验点为 BRAM 版本：

```text
Stage 1：105 tap Q15 strict-halfband
         纯延迟相 + 52-tap 对称滤波相
         26 次单 DSP MAC
         64x24bit BRAM 循环缓冲
Stage 2/3：V2 共享数据通路 true-polyphase
Stage 4～7：canonical Q4 shift-add
级间桥：valid-only
```

该版本已完成 MATLAB 频响、bit-true、Stage 1 单元 RTL、完整七级 RTL
和 Vivado 独立综合闭环。

## 2. Phase 3A：系统级搜索

`v2_07_design_stage1_strict_halfband.m` 已扩展为：

```text
Profile A：总通带 <= 0.01 dB，总阻带 >= 75 dB，Stage 1 >= 76 dB
Profile B：总通带 <= 0.01 dB，总阻带 >= 75 dB
Profile C：总通带 <= 0.02 dB，总阻带 >= 73 dB
FRAC_W  ：Q12～Q16
```

新增真实架构成本：

```text
FILTER_PHASE_LEN
MAC_PAIR_COUNT
REAL_HISTORY_LEN
COEFF_W
ACC_W
```

搜索得到：

| 候选 | Profile | MAC 对数 | 历史长度 | 总通带误差 / dB | 总阻带 / dB |
|---|---|---:|---:|---:|---:|
| 105 tap Q15 | A | 26 | 52 | 0.00523 | 78.620 |
| 101 tap Q15 | B | 25 | 50 | 0.00582 | 75.381 |
| 97 tap Q15 | C | 24 | 48 | 0.00619 | 74.305 |
| 101 tap Q13 | C | 25 | 50 | 0.00461 | 73.031 |

101/97 tap 只减少 1～2 次 MAC，却明显压缩阻带余量，因此首版 RTL
选择 105-tap Q15。短候选保留在 Pareto 文件中，不用于当前板级版本。

## 3. 系数单一数据源

执行顺序：

```text
v3_01_select_stage1_pareto.m
v3_02_export_stage1_rtl.m
```

自动导出：

```text
stage1_strict_halfband_selected.csv
stage1_strict_halfband_selected.mat
coeff_v3/stage1_*_coeff_int.txt
stage1_strict_rtl_manifest.csv
stage1_strict_rtl_summary.txt
all2x_v3/all2x_v3_stage1_coeff_pkg.vh
```

105-tap Q15 系数满足：

```text
纯延迟相整数和 = 32768
滤波相整数和   = 32768
滤波相长度     = 52
对称系数对     = 26
```

## 4. Phase 3B：FF 版本

新增模块：

```text
interp2_stage1_strict_halfband_mac_ce.v
interp128_all2x_v3_strict_s1_top_ce.v
```

模块在 phase0 接收真实输入，同时输出 26 个输入样点前的纯延迟相；
随后使用 26 个周期完成滤波相 MAC，在 phase1 输出结果。

验证结果：

| 测试 | Golden 点数 | 最大误差 | 不一致点 |
|---|---:|---:|---:|
| Stage 1 冲激 | 615 | 0 LSB | 0 |
| Stage 1 随机 | 359 | 0 LSB | 0 |
| 七级冲激 | 40059 | 0 LSB | 0 |
| 七级随机 | 23675 | 0 LSB | 0 |

完整七级 RTL 相对 MATLAB golden 的固定延迟为 127 个最终输出样点。

## 5. Phase 3C：BRAM 版本

新增模块：

```text
interp2_stage1_strict_halfband_bram_ce.v
interp128_all2x_v3_strict_s1_bram_top_ce.v
```

实现要点：

1. 64 深度循环地址，保存 52 个有效真实输入样点。
2. phase0 使用 Port A 写入当前输入。
3. MAC 周期使用两个端口同步读取对称样点。
4. phase1 预读下一次纯延迟相数据。
5. BRAM 内容不复位，`fill_count` 屏蔽复位后的陈旧数据。

BRAM 单元和完整七级对拍结果均为 0 LSB，固定延迟仍为 127 个最终
输出样点，所有 MAC 截止时间断言均通过。

## 6. 资源对比

| 版本 | LUT | FF | DSP | BRAM Tile | WNS / ns | 0 LSB |
|---|---:|---:|---:|---:|---:|---:|
| Phase 2 | 3975 | 3103 | 1 | 0 | +156.988 | 是 |
| Strict-HB FF | 3537 | 2105 | 1 | 0 | +159.856 | 是 |
| Strict-HB BRAM | 3222 | 925 | 1 | 1 | +159.809 | 是 |

BRAM 版相对 Phase 2：

```text
LUT：3975 -> 3222，减少 753，下降 18.94%
FF ：3103 ->  925，减少 2178，下降 70.19%
DSP：1 -> 1
BRAM Tile：0 -> 1（实际为 2 个 RAMB18）
```

BRAM 版 Stage 1 层次资源约为：

```text
265 LUT / 143 FF / 1 DSP / 2 RAMB18
```

因此 FF 和 BRAM 两个 Stop/Go 门槛均通过，BRAM 版形成新的最佳
独立链路 Pareto 点。

## 7. 对 V3 指导的变通

1. 没有直接采用更短 Profile B/C 候选，因为只节省 1～2 次 MAC，
   阻带余量损失更明显。
2. FF 和 BRAM 都使用独立实验顶层；当前板级 V2 默认参数保持不变。
3. BRAM 映射为两个 RAMB18，但合计只占一个 Block RAM Tile，符合
   `BRAM <= 1` 的停止线。
4. 暂未强制增加 DSP 流水，因为当前 WNS 超过 +159 ns，增加流水会
   改变调度和固定延迟，而不会解决实际时序问题。

## 8. 尚未完成的 V3 验证项

在把 BRAM 版切到板级前，还应补充：

```text
随机 valid 空洞
中途复位与复位后立即输入
多随机种子完整 24bit 输入
MAC job arrival/start/finish/deadline/slack CSV
板级综合、实现和功耗报告
```

Phase 4 的下一实验点是增加第 2 个 DSP，由 Stage 2/3 共享。该实验
应继续使用独立顶层，并与当前 `3222 LUT / 925 FF / 1 DSP / 1 BRAM`
比较；只有 LUT 明显下降且调度断言通过，才考虑作为新的推荐版本。
