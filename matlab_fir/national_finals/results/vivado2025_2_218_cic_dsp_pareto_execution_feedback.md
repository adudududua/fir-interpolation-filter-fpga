# Vivado 2025.2 218 基线 CIC DSP 4/3/2 档 Pareto 执行反馈

## 1. 目标与不变量

在已板测 218 LUT / 365 FF / 4 DSP / 4 RAMB18E1 / 2 MMCM 的 24/20/20 基线上，
仅切换已有 `USE_NATIONAL_FINALS_CIC_INTEGRATOR_DSP_MODE=2/1/0`，重新获得当前架构在
Vivado 2025.2 下的真实 post-route Pareto。滤波系数、24/20/20 字长、bridge 量化、
Stage3 联合补偿、CIC 模运算、采样率、RAM 和板级接口保持不变。

实验脚本用 `open_project -read_only` 打开正式工程，把完整泛型列表传给
`synth_design -generic`，并在每次运行前后比较 `.xpr` SHA-256。两个候选都通过
`XPR_UNCHANGED_PASS`，没有污染正式工程配置。

## 2. Post-route 结果

| CIC 积分器 DSP 模式 | 综合 LUT | 综合 FF | Routed LUT | Routed FF | DSP | RAMB18E1 | MMCM | WNS/WHS | DRC Error |
|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 2（正式基线） | 280 | 373 | **218** | **365** | **4** | 4 | 2 | +45.279/+0.079 ns | 0 |
| 1 | 301 | 396 | **239** | **388** | **3** | 4 | 2 | +44.703/+0.079 ns | 0 |
| 0 | 329 | 425 | **268** | **417** | **2** | 4 | 2 | +44.389/+0.078 ns | 0 |

3-DSP 点以 `+21 LUT / +23 FF` 换取 `-1 DSP`。2-DSP 点相对 3-DSP 再以
`+29 LUT / +29 FF` 换取 `-1 DSP`。三者均无路由失败网络，满足正时序，并保持
4 RAMB18E1 和 2 MMCM。

实现目录：

- 4-DSP 基线：`tools/vivado_2025_2/results/20260811_231722`；
- 3-DSP：`tools/vivado_2025_2/structure_experiments/results/cic_dsp_mode1_20260811_232637`；
- 2-DSP：`tools/vivado_2025_2/structure_experiments/results/cic_dsp_mode0_20260811_232845`。

## 3. 功能回归

三个 DSP 模式均通过 Vivado 2025.2 默认 24/20/20 Smoke **17/17**，覆盖 ROM、
DAC 映射、RAMB18 原语、Stage1、Stage2/3、CIC 连续/停顿/边界、双时钟族、CDC、
键盘、板级顶层、端到端 4x/8x/128x 0 LSB、8 类复位恢复和 10 次不停机动态切档。

- 4-DSP：`_work/rtl_regression/20260811_231341`；
- 3-DSP：`_work/rtl_regression/20260811_233111`；
- 2-DSP：`_work/rtl_regression/20260811_233447`。

因为三个模式仅改变完全等价的 DSP48E1/CARRY4 物理映射，数值结果与 218 金标准
逐样本一致，频响继承已签核的 4x/8x/128x 六模式结果。

## 4. 功耗与评分解读

三点的无 SAIF、Medium 置信度 Vivado 估算都是总/动态/静态
`0.271/0.199/0.072 W`，其中两颗 MMCM 估算为 0.197 W。这只能说明 DSP 映射差异
被当前时钟估算掩盖，不能作为三者实测功耗相等的结论。

若评分是线性加权，3-DSP 优于 4-DSP 的条件为：

`DSP权重 > 21×LUT权重 + 23×FF权重`。

2-DSP 优于 3-DSP 的条件为：

`DSP权重 > 29×LUT权重 + 29×FF权重`。

若评分按各类器件占总资源百分比等权相加，DSP 只有 90 个，减少 DSP 的影响会
大于增加几十个 LUT/FF；若评分主要看 LUT 绝对数，218/4-DSP 明显更优。

## 5. Stop/Go 结论

- **218/4-DSP：Go，继续作为正式 board-pass 与 LUT-first 版本。**
- **239/3-DSP：Go as Pareto，是当前更平衡的低 DSP 候选，待评分公式确认和物理板测。**
- **268/2-DSP：Keep as Pareto，只在 DSP 权重足够高时推进 bitstream/板测。**

两个实验候选只输出 routed DCP 和报告，没有生成会被误当作正式发布的
bitstream，正式 `.xpr` 仍固定 DSP 模式 2。

## 6. 执行故障记录

第一次 3-DSP 脚本在打开工程前失败，原因是从 `structure_experiments` 向上回溯目录少了
一层，指向不存在的 `tools/XC7A35T_interp.xpr`。该次运行未打开工程、未执行综合且未修改
任何 RTL/XPR。路径修正为回溯三层后，3-DSP 和 2-DSP 完整流程均通过。
