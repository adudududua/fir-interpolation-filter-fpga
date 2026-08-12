# Vivado 2025.2 218-LUT与239-LUT板测检查点的模块级资源对比

## 1. 目的与版本边界

本项工作用于解释下列两个已完成物理板功能验证的资源Pareto端点，而不是重新综合得到新的发布版本：

- `nf-vivado2025.2-218lut-365ff-4dsp-2bram-24-20-20-board-pass`；
- `nf-vivado2025.2-239lut-388ff-3dsp-2bram-24-20-20-board-pass`。

分析在隔离Git工作树中依次检出两个标签并只读打开对应routed DCP；主工程始终保持
`national-finals-2dsp-lut-optimization`分支及268-LUT/2-DSP配置。两个检查点均采用Vivado
2025.2、XC7A35T-FGG484-2、24/20/20 bit、4个RAMB18E1和2个MMCM；差异变量为
`CIC_INTEGRATOR_DSP_MODE=2/1`。

## 2. 统计方法

正式工程使用`flatten_hierarchy=full`，路由后常规`report_utilization -hierarchical`仅保留顶层
总计。为避免将综合前层次数字误作实现后模块资源，本项审计采用以下口径：

1. LUT按物理`SLICE_X*/A|B|C|D LUT`计数，同一物理LUT的O5/O6原语合并为1；
2. FF仅统计Slice Register，与`report_utilization`一致；8个OLOGIC DAC输出寄存器不计入FF；
3. DSP48E1和RAMB18E1按路由后原语计数；
4. 优先依据原语的RTL源文件归属模块；对无源位置的扁平化LUT追踪寄存器、DSP和BRAM起止点；
5. 同时跨越多个模块的物理LUT单列为共享逻辑，不作任意拆分。

该口径下的资源汇总分别严格回归218/365/4/4与239/388/3/4。原始原语、LUT端点、物理BEL及
归属结果位于`submit/finally/images/work/resource_compare_218_239`。

## 3. 模块级资源结果

| 模块/统计类别 | 218版 LUT/FF | 239版 LUT/FF | DSP 218/239 | RAMB18E1 218/239 | 差分（239−218） |
|---|---:|---:|---:|---:|---:|
| FIR1级 | 11/83 | 10/83 | 1/1 | 1/1 | −1 LUT |
| FIR2/3级 | 20/73 | 20/73 | 1/1 | 1/1 | 0 |
| FIR共享系数存储 | 0/0 | 0/0 | 0/0 | 1/1 | 0 |
| 2→4倍桥接量化 | 51/2 | 52/2 | 0/0 | 0/0 | +1 LUT |
| **16倍CIC插值** | **34/109** | **57/132** | **2/1** | **0/0** | **+23 LUT/+23 FF/−1 DSP** |
| 滤波器核心跨级/共享逻辑 | 7/0 | 7/0 | 0/0 | 0/0 | 0 |
| 核心—外围接口共享逻辑 | 59/0 | 57/0 | 0/0 | 0/0 | −2 LUT |
| 测试音频ROM | 0/15 | 0/15 | 0/0 | 1/1 | 0 |
| 外围及外围共享逻辑 | 36/83 | 36/83 | 0/0 | 0/0 | 0 |
| **完整板级总计** | **218/365** | **239/388** | **4/3** | **4/4** | **+21 LUT/+23 FF/−1 DSP** |

其中，FIR1级、FIR2/3级和共享系数存储合计使用2个DSP48E1与3个RAMB18E1；测试音频ROM
使用第4个RAMB18E1。两版上述结构与寄存器数量均保持不变。

## 4. 差分解释

239-LUT版本的CIC保留1个末级积分DSP；218-LUT版本新增
`gen_comb_dsp_role_exchange.u_cic_comb_dsp48e1`，由DSP48E1执行串行comb角色交换并保存宽位
状态。检查点源位置与原语清单显示，模式2相对模式1减少23个`comb_operand_fabric`相关
Slice Register；与之相连的物理LUT也减少23。因此，CIC由57 LUT/132 FF/1 DSP变为
34 LUT/109 FF/2 DSP，形成**+1 DSP、−23 LUT、−23 FF**的直接资源交换。

整板LUT仅减少21而非23，是因为由239版切换至218版时，FIR1级、2→4倍桥接量化和
核心—外围接口共享逻辑的物理LUT分别变化+1、−1和+2，合计产生+2 LUT偏移，
抵消了CIC局部减少23 LUT中的2 LUT。两版时序和实现完整性保持通过：

| 版本 | WNS/WHS | DRC Error | 板级状态 |
|---|---:|---:|---|
| 218 LUT / 4 DSP | +45.279/+0.079 ns | 0 | board-verified |
| 239 LUT / 3 DSP | +44.703/+0.079 ns | 0 | board-verified |

因此，可在本工程与这两个检查点的范围内陈述：增加1个CIC DSP后，核心减少23 LUT和23 FF，
完整板级净减少21 LUT和23 FF；BRAM和FIR数据通路不变，且两版均满足时序约束。跨层次共享LUT依赖当前综合、
布局与布线结果，不能外推为独立RTL模块的通用面积常数。

## 5. 报告与归档

- 技术报告已新增第9.4.3节、表9-16和图9-7；
- 主README已增加本次审计摘要；
- 机器可读汇总：
  `submit/finally/images/work/resource_compare_218_239/analysis/module_resource_comparison.csv`；
- 物理LUT证据：
  `submit/finally/images/work/resource_compare_218_239/analysis/physical_lut_attribution.csv`；
- 图形文件：
  `submit/finally/images/generated/resource_compare_218_239/figure_218_239_module_resource_distribution.png`。

本次仅执行检查点只读审计与文档更新，没有修改两个板测标签，也没有改变当前268-LUT生产RTL。
