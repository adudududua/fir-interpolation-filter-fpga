# P3：CDC、复位与 AD9708 工程闭环签核

## 结论

P3 不改变 FIR/CIC 系数、字长、舍入或输出样点，只处理板级可靠性。正式 XSim 回归为 `11/11 PASS`，post-route 为 **462 LUT / 447 FF / 180 Slice / 5 DSP / 3 BRAM Tile / 2 MMCM / 17 IO**，全局 WNS/WHS 为 **+46.140/+0.050 ns**，vectorless 功耗为 **0.271 W**。bitstream 已生成；实物板下载和仪器测试仍待现场完成。

相对 P1 的 `446 LUT / 471 FF / 193 Slice`，P3 增加 16 LUT、减少 24 FF 和 13 Slice。增加的逻辑用于原子跨时钟握手、锁定同步和安全静音，不属于滤波算法资源。

## 工程修改

- 两位模式总线改为 request/ack toggle 的 bundled-data 原子握手；源端 shadow 在事务期间保持稳定，音频域等待稳定窗口后一次提交，并在切换期间输出 `8'h80` 静音。
- FIR、CIC、bridge、键盘和模式状态改为同步复位；MMCM `locked`、家族选择和复位释放均经过同步器/释放流水线。
- AD9708 数据寄存器加 `IOB=TRUE`，实现报告确认 8 位数据均进入 OLOGIC；DAC 时钟使用 ODDR 转发，模式 4x/8x/128x 分别保持正确边沿数且无 runt/X。
- 约束采用两个逻辑互斥的 forwarded clock；按 AD9708 `tS=2.0 ns`、`tH=1.5 ns` 加 0.5 ns 板级/封装裕量，设置 `max=2.5 ns`、`min=-2.0 ns`。
- 构建流程新增 `report_methodology`、`report_cdc`、`check_timing` 与 DAC 输出 min/max 路径报告。

## RTL 验证

2026-08-01 从零重跑目录：

```text
matlab_fir/national_finals/_work/rtl_regression/20260801_013825
```

结果为 `NATIONAL FINALS RTL REGRESSION PASS (11/11)`。覆盖内容包括：

- 统一系数 RAMB18E1 全 96 地址；
- 完整链路冲激和固定随机输入，4x/8x/128x 逐点 0 LSB；
- 串行 CIC 连续、停顿和 burst 中复位等价；
- 8 个完整链内部状态中断/恢复场景；
- 动态倍率 10 次切换，边沿数 32/128/256/4096 精确匹配，无 runt pulse 或 X；
- 双 MMCM 家族切换 100 次，高、低脉宽均不小于 65 ns，选择时钟始终保持锁定；
- 模式 CDC 12 个方向各 100 次，共 1200 次事务：一次请求、一次提交、一次应答，提交值只可能为旧值或新值；
- 双家族时钟、测试 ROM、均衡器、键盘和板级集成。

算法数据通路没有变化，P1 六工况指标继续成立：最差通带最大绝对偏差 `0.006117 dB`，最差峰峰纹波 `0.008056 dB`，最差阻带 `72.331 dB`，绝对增益最大误差 `0.003480 dB`。

## post-route 资源、时序与功耗

器件：`xc7a35tfgg484-2`；综合 `AreaOptimized_high + ResourceSharing=on`；实现 `opt_design Default`。

| 指标 | P1 | P3 | 变化 |
|---|---:|---:|---:|
| LUT | 446 | **462** | +16 |
| FF | 471 | **447** | -24 |
| Slice | 193 | **180** | -13 |
| DSP48E1 | 5 | **5** | 0 |
| BRAM Tile / RAMB18E1 | 3 / 6 | **3 / 6** | 0 |
| MMCM | 2 | **2** | 0 |
| IO | 17 | **17** | 0 |
| 全局 WNS | +45.104 ns | **+46.140 ns** | +1.036 ns |
| 全局 WHS | +0.121 ns | **+0.050 ns** | -0.071 ns，仍通过 |
| 总功耗 | 0.271 W | **0.271 W** | 0 |
| 动态/静态功耗 | — | **0.199/0.072 W** | — |

AD9708 最差输出接口时序：

| 时钟族 | setup slack | hold slack |
|---|---:|---:|
| 44.1 kHz | +84.287 ns | +86.288 ns |
| 48 kHz | +76.116 ns | +78.117 ns |

`check_timing` 显示无未约束内部端点、无无时钟寄存器、无多时钟寄存器、无未连接生成时钟，setup/hold 失败端点均为 0。

## CDC/DRC 规则处置

- `CDC-3` 10 条：均为带 `ASYNC_REG` 的两级同步器，符合预期。
- `CDC-13` 2 条：`family_active` 到 `BUFGMUX_CTRL S0/S1`。这是专用无毛刺时钟选择原语的控制入口；功能仿真已覆盖双向切换，作为结构性 waiver 保留，不用 false path 隐藏。
- `CDC-15` 4 条：两位 shadow bus 的 bundled-data 捕获。req/ack 协议保证稳定窗口，1200 次全方向压力测试证明一次原子提交，作为握手结构 waiver 保留。
- `DPIP-1` 4 条、`DPOP-1` 3 条：面积优先、低频设计的流水建议；全局有 46 ns 以上 setup 裕量。
- `DPREG-4` 1 条：当前推断的最后积分器异步反馈建议，P4-A N3 Hold 将作为消除目标；在 P3 不改变算法结构。
- `SYNTH-4` 2 条：Stage 2/3 浅历史 RAM 被有意放入 BRAM；P4-B 专门处理。

Vivado 2018.3 的 `report_methodology` 仍对 8 位 `dac_data` 报 `TIMING-18`。逐时钟族 `report_timing` 已证明两个 forwarded clock 都存在 `max/min` 输出延时，并得到上表正裕量；这是双互斥生成时钟同挂一个端口时的方法学检查误报，原报告保留且不降级/屏蔽。

## 构建产物

结果目录：

```text
matlab_fir/national_finals/vivado_results/board_dual_rate_p3_engineering_closed_v5
```

Bitstream SHA-256：

```text
A38C6D4F4B3C023DBD22897505B85864990CFC7C5D974A84FA38C5F0ADE21033
```

该版本是 P4 结构优化的工程基线，不等同于物理板验收完成。上板必须继续执行 44.1/48 kHz × 4x/8x/128x 六组合、100 次模式/家族切换以及 AD9708 示波器 setup/hold/毛刺检查。
