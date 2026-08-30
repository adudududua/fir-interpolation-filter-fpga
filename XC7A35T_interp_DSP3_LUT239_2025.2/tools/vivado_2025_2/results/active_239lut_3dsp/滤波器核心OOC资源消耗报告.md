# 独立滤波器核心 OOC 资源消耗报告

## 1. 报告对象

本报告统计的是高阶插值滤波器数字核心本身，不包含板级顶层中的时钟生成、矩阵按键、DAC 接口、静音控制和其他外围逻辑。

- 工具：AMD Vivado 2025.2，Build 6299465
- 器件：XC7A35T-FGG484-2
- OOC 顶层：`interp128_all2x_v7_folded_fir_cic_top_ce`
- 字长配置：24/20/20 bit
- CIC 积分器实现：`CIC_INTEGRATOR_DSP_MODE=1`
- 目标时钟：6.144 MHz
- 流程：OOC 综合 → 优化 → 布局 → 布线 → post-route 报告
- 生成时间：2026-08-16 20:43

## 2. 布线后核心资源

| 资源 | 使用量 | XC7A35T 可用量 | 占用率 |
|---|---:|---:|---:|
| Slice LUT | **212** | 20,800 | 1.02% |
| Slice Register | **302** | 41,600 | 0.73% |
| DSP48E1 | **3** | 90 | 3.33% |
| RAMB18E1 | **3** | 100 | 3.00% |
| 等效 BRAM Tile | **1.5** | 50 | 3.00% |
| RAMB36E1 | **0** | 50 | 0% |
| MMCM | **0** | 5 | 0% |

因此，本版本可以表述为“独立滤波器核心 OOC：212 LUT、302 FF、3 DSP48E1、3 RAMB18E1（1.5 BRAM Tile）”。工程名称中的“239 LUT”是完整板级实现口径，不能与本表的独立核心 OOC 口径混用。

## 3. 时序与实现状态

核心内部寄存器到寄存器路径的布线后结果为：

| 指标 | 结果 | 判定 |
|---|---:|---|
| 内部 WNS | **+150.852 ns** | 通过 |
| 内部 WHS | **+0.117 ns** | 通过 |
| 未布通网络 | **0** | 通过 |
| DRC Error | **0** | 通过 |

OOC 总体时序报告中可能出现约 `-0.845 ns` 的边界 hold 提示。这来自零输入/输出延迟假设下的 OOC 端口到寄存器边界，不是核心内部寄存器路径失败。用于核心签核的 `timing_internal_setup.rpt` 和 `timing_internal_hold.rpt` 已明确限定为寄存器到寄存器路径，两者均为正裕量。完整板级接口时序应以板级 routed checkpoint 报告为准。

DRC 中的 `CFGBVS-1` 是 OOC 设计没有配置管脚/配置银行电压造成的边界警告；`DPIP-1`、`DPOP-1` 是 DSP 流水级性能建议。它们不改变资源计数，且本次 DRC Error 为 0。

## 4. 与完整板级实现的区别

| 统计口径 | LUT | FF | DSP48E1 | RAMB18E1 | MMCM |
|---|---:|---:|---:|---:|---:|
| 独立滤波器核心 OOC | **212** | **302** | **3** | **3** | **0** |
| 完整板级 routed | **239** | **388** | **3** | **4** | **2** |

两行数据都正确，但回答的问题不同：

- 核心 OOC 用于回答“插值滤波器算法硬件本身消耗多少资源”；
- 完整板级 routed 用于回答“可下载到开发板的整个系统消耗多少资源”。

二者不能相减后把所有差值简单归属到某一个模块，也不能把完整板级 239 LUT 当成独立滤波器核心面积。

## 5. 可复核证据

- `core_ooc_utilization_post_route.rpt`：布线后总资源报告
- `core_ooc_utilization_hierarchical.rpt`：层次资源报告
- `core_ooc_timing_internal_setup.rpt`：核心内部建立时间报告
- `core_ooc_timing_internal_hold.rpt`：核心内部保持时间报告
- `core_ooc_route_status_post_route.rpt`：布通状态报告
- `core_ooc_drc_post_route.rpt`：DRC 报告
- `core_ooc_summary.txt`：机器可读摘要
- `core_ooc_vivado_2025_2.log`：完整 Vivado 执行日志
- `core_ooc_post_route.dcp`：可由 Vivado 2025.2 重新打开核查的布线后 checkpoint

`core_ooc_post_route.dcp` 的 SHA-256：

```text
9FF28CB603DAE3233E1A06764E96651087A48AF6031C514A59A7257896DEBC5C
```

## 6. 演示建议

答辩时不要只展示人工绘制的资源图片。建议同时打开本报告、`core_ooc_utilization_post_route.rpt`，并保留 `core_ooc_post_route.dcp` 作为可现场复核的 Vivado 原始证据。推荐表述为：

> 使用 Vivado 2025.2 对最终 24/20/20 bit、3-DSP 配置的插值滤波器核心进行了独立 OOC 布局布线。布线后核心占用 212 LUT、302 FF、3 个 DSP48E1 和 3 个 RAMB18E1，内部建立与保持裕量均为正，DRC 无 Error。完整板级系统为 239 LUT、388 FF、3 DSP 和 4 RAMB18E1，两者统计边界不同。
