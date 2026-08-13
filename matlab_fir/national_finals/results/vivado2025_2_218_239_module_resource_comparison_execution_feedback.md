# Vivado 2025.2 218-LUT与239-LUT板测版本的同口径资源复核

## 1. 目的与版本边界

本项工作用于对比下列两个已完成物理板功能验证的资源Pareto端点：

- `nf-vivado2025.2-218lut-365ff-4dsp-2bram-24-20-20-board-pass`（`c1301157`）；
- `nf-vivado2025.2-239lut-388ff-3dsp-2bram-24-20-20-board-pass`（`bb6a2af`）。

完整系统资源直接取自各标签对应的板级routed checkpoint。滤波器核心资源不采用整板网表的
反向归属值，而是从两个不可变标签分别导出RTL快照，执行参数匹配的独立OOC post-route。
历史239-LUT/377-FF/4-DSP版本的197 LUT/290 FF核心结果以及更早版本的193 LUT/281 FF结果，
均不用于当前239-LUT/388-FF/3-DSP与218-LUT/365-FF/4-DSP的对比。

## 2. 同口径OOC方法

两版采用相同的Vivado 2025.2、器件`xc7a35tfgg484-2`、顶层
`interp128_all2x_v7_folded_fir_cic_top_ce`、33项源清单、24/20/20 bit数值参数、
6.144 MHz边界时钟以及综合、优化、布局和布线指令。唯一受控变量是与板测版本一致的
`CIC_INTEGRATOR_DSP_MODE=2/1`。源清单中的核心RTL、CIC、FIR、桥接及RAM封装文件字节一致；
两个标签中只有不参与OOC顶层展开的板级wrapper默认模式不同，实际OOC差异由Tcl generic明确注入。

每个版本均在两个空结果目录中重新实现，结果为2/2精确一致。正式计数直接读取Vivado
post-route `report_utilization`，不通过模块分项求和反推总量。

## 3. 正式资源结果

| 统计边界 | 218-LUT/4-DSP版 | 239-LUT/3-DSP版 | 差分（239−218） |
|---|---:|---:|---:|
| **独立滤波器核心OOC** | **190 LUT / 279 FF / 4 DSP / 3 RAMB18E1** | **212 LUT / 302 FF / 3 DSP / 3 RAMB18E1** | **+22 LUT / +23 FF / −1 DSP / 0 RAMB18E1** |
| **完整板级post-route** | **218 LUT / 365 FF / 4 DSP / 4 RAMB18E1** | **239 LUT / 388 FF / 3 DSP / 4 RAMB18E1** | **+21 LUT / +23 FF / −1 DSP / 0 RAMB18E1** |

OOC核心包括三级2倍FIR、级间桥接与量化、16倍CIC、核心内部控制及3个RAMB18E1；不包括
测试音频ROM、按键与模式控制、时钟管理、DAC/IO及板级包装。完整系统与OOC为两个独立统计
边界，不能以二者相减推导所谓“精确外围面积”。

## 4. 时序与实现限定

218版和239版的内部寄存器路径WNS/WHS分别为`+150.943/+0.069 ns`和
`+151.611/+0.099 ns`，四次实现均为0 DRC Error。零I/O延迟的独立边界模型在每版中均产生
同一条`stage3_compensated_mode`端口到寄存器hold违例（−0.845 ns），且若干CE输入未建立
完整接口延迟约束。因此，这些OOC结果作为严格可比的资源A/B实现和内部路径观察，不表述为
整体时序收敛的OOC签核。完整接口时序采用对应板级post-route结果：

| 版本 | 板级WNS/WHS | DRC Error | 板级状态 |
|---|---:|---:|---|
| 218 LUT / 4 DSP | +45.279/+0.079 ns | 0 | board-verified |
| 239 LUT / 3 DSP | +44.703/+0.079 ns | 0 | board-verified |

## 5. 模块差异的辅助物理归属

为解释22-LUT核心差分，对OOC扁平化DCP按RTL源位置、端点连接与物理BEL进行辅助归属：

| 解释性类别 | 218版 LUT/FF | 239版 LUT/FF | DSP 218/239 | RAMB18E1 218/239 |
|---|---:|---:|---:|---:|
| FIR1级 | 37/83 | 36/83 | 1/1 | 1/1 |
| FIR2/3级 | 40/73 | 38/73 | 1/1 | 1/1 |
| FIR共享系数存储 | 0/0 | 0/0 | 0/0 | 1/1 |
| 2→4倍桥接与量化 | 41/2 | 41/2 | 0/0 | 0/0 |
| **16倍CIC相关逻辑** | **38/121** | **62/144** | **2/1** | **0/0** |
| 跨级共享逻辑 | 34/0 | 35/0 | 0/0 | 0/0 |
| **OOC总计** | **190/279** | **212/302** | **4/3** | **3/3** |

该归属可闭合到正式OOC总量，并说明净差分主要与16倍CIC的DSP角色映射有关。不过，分类脚本
需要对扁平化后的跨级LUT作连接关系判断，结果依赖综合与物理实现，故仅作为结构定位证据，
不称为Vivado原生层次面积或RTL模块独立面积。正式资源结论始终以第3节的OOC总量为准。

## 6. 证据与复现入口

- 参数匹配OOC入口：
  `submit/finally/images/work/resource_compare_218_239/run_matched_core_ooc_2025_2.tcl`；
- 重复运行CSV：
  `submit/finally/images/work/resource_compare_218_239/matched_ooc/evidence/matched_ooc_repeated_runs.csv`；
- 包含报告SHA-256与边界时序限定的JSON：
  `submit/finally/images/work/resource_compare_218_239/matched_ooc/evidence/matched_ooc_evidence.json`；
- 两标签完整源码哈希：
  `matched_ooc/lut218_source_sha256.txt`与`matched_ooc/lut239_source_sha256.txt`；
- OOC物理归属明细：
  `matched_ooc/analysis/module_resource_distribution.csv`；
- 报告插图：
  `submit/finally/images/generated/resource_compare_218_239/figure_218_239_matched_ooc_board_comparison.png`。

本次工作仅新增隔离的OOC复核证据并更新文档，没有修改两个板测标签，也没有改变当前
268-LUT/2-DSP生产RTL。
