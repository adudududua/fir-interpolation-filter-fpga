# Vivado 2025.2 3-DSP LUT 压缩执行反馈

## 1. 结论

本轮以工具签核的 **239 LUT / 388 FF / 3 DSP48E1 / 4 RAMB18E1 / 2 MMCM**
为唯一公平基线，保持 DSP 和 BRAM 数量不变，同时保持 24/20/20 定点配置、系数、
舍入/饱和、输出样点序列和每 16 个 `ce_out` 接收一帧的吞吐语义不变。

在上述硬约束下，本轮没有找到低于 239 LUT 的可发布候选。239-LUT 版仍是当前最优且
可重复的 3-DSP 点。最接近的工具策略候选为 241 LUT，只差 2 LUT；两种 DSP48E1
TWO24 结构候选分别为 260 LUT 和 262 LUT，均保持 3 DSP、4 RAMB18E1、正时序及
DRC=0，但面积更差。因此它们均按 Stop/Go 门槛判定为 No-Go，不接入正式 RTL，
也不生成板测 bitstream。

## 2. 基线与门禁

基线证据目录：

`XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/structure_experiments/results/cic_dsp_mode1_20260811_232637`

| 项目 | 基线值 |
|---|---:|
| post-route LUT / FF | **239 / 388** |
| DSP48E1 / RAMB18E1 / MMCM | **3 / 4 / 2** |
| WNS / WHS | **+44.703 / +0.079 ns** |
| DRC Error | **0** |
| RTL Smoke | **17/17 PASS** |

有效优化必须同时满足：LUT 小于 239；DSP48E1=3；RAMB18E1=4；MMCM=2；WNS/WHS
为正；DRC Error=0；数值输出严格等价；不降低输入吞吐。

## 3. 候选矩阵

| 候选 | LUT | FF | DSP | RAMB18E1 | WNS/WHS (ns) | 功能结果 | 判定 |
|---|---:|---:|---:|---:|---:|---|---|
| 239-LUT 基线，AreaOptimized_high + ExploreArea | **239** | **388** | **3** | **4** | +44.703/+0.079 | Smoke 17/17 | **保留** |
| 综合 AreaOptimized_medium | 241 | 388 | 3 | 4 | +45.340/+0.070 | RTL 未变 | No-Go，+2 LUT |
| 综合 Default | 263 | 388 | 3 | 4 | +45.238/+0.056 | RTL 未变 | No-Go，+24 LUT |
| 综合 FewerCarryChains | 263 | 388 | 3 | 4 | +45.238/+0.056 | RTL 未变 | No-Go，+24 LUT |
| 实现 ExploreWithRemap + Explore | 269 | 388 | 3 | 4 | +44.624/+0.068 | 同一综合 DCP | No-Go，+30 LUT |
| TWO24：comb + 一级积分器低 24 位 | 260 | 417 | 3 | 4 | +44.386/+0.094 | 16,384 输出 0 LSB | No-Go，+21 LUT/+29 FF |
| TWO24：两级积分器低 24 位 | 262 | 393 | 3 | 4 | +45.052/+0.080 | 95,107 输出 0 LSB | No-Go，+23 LUT/+5 FF |
| comb/一级积分器共享 Fabric CARRY | — | — | 目标 3 | 目标 4 | — | 第二帧触发覆盖保护 | 不可行，吞吐冲突 |

所有完成实现的候选 DRC Error 均为 0。最初一次 TWO24 隔离工程得到 3 RAMB18E1，
原因是 `save_project_as` 没有自动带入工程未列出的
`nf_sine_15k_dual_rate_packed32_256.mem`，使 ROM 资源统计失真。构建脚本已改为显式加入
打包 ROM；表中 260/262 LUT 结果均来自修复后的 4-RAMB18E1 公平复测，早期 3-BRAM
结果不参与结论。

## 4. 结构分析

### 4.1 为什么 239-LUT 基线已经很紧

3-DSP 模式把两级 23-bit 低速 comb 串行复用一条 Fabric 减法通路，把 26-bit 一级积分器
放在 Fabric CARRY，把 29-bit 末级积分器放入 DSP48E1；另外两颗 DSP 用于前三级 FIR。
相对 4-DSP 218-LUT 板测版，多出的主要代价正是一级 26-bit CARRY 累加器及其 26-bit 状态。

布局后网表中，CIC 可直接识别的控制 LUT 只剩 6 个：4 个 burst 计数 LUT，以及
`comb_active`、`comb_stage_index` 各 1 个。comb 减法和一级积分器主体已经映射为 CARRY4，
因此继续只改控制状态的理论收益很小；历史 one-hot/移位 burst 实验也已证明会增加 LUT/FF。

### 4.2 TWO24 为什么没有收益

TWO24 能在一颗 DSP48E1 中同时处理两个 24-bit 低半部，但 26-bit/29-bit CIC 状态仍需要
Fabric 保存并修正高 2/5 位、分段进位和时序对齐。节省的 CARRY 链被高位修正、跨宽度加法、
DSP 输入选择及额外寄存器抵消，最终分别为 260/417 和 262/393，均劣于 239/388。

### 4.3 为什么 comb 与一级积分器不能共享同一 CARRY 链

若要求每 16 个 `ce_out` 接收一帧，同时必须输出该帧的 16 个高采样率点，那么一级积分器
在连续 `ce_out` 下每拍都要使用 CARRY。下一帧的两级 comb 也必须在帧边界附近完成，二者
没有可用于无损时分复用的空拍。候选仿真在第二帧到达时触发输入覆盖保护，证明共享方案会
降低吞吐或丢帧，因此即使潜在 LUT 更低也不满足赛题接口语义。

## 5. 工具策略结论

同一 239-LUT 综合 DCP 上，`ExploreArea/Explore` 明显优于 Default 或
ExploreWithRemap；改变综合指令后，`AreaOptimized_medium` 最接近但仍为 241 LUT，
Default/FewerCarryChains 均为 263 LUT。由此可知 239 不是一次偶然的默认策略结果，而是
当前 RTL 在已扫描策略中的稳定最优点。

## 6. 可复现入口

候选源、等价 testbench 和构建/扫描脚本位于：

`XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/structure_experiments`

- `build_3dsp_two24_candidate.ps1`：comb + 一级积分器 TWO24 候选；
- `build_3dsp_integrator_pair_candidate.ps1`：TWO24 双积分器候选；
- `scan_3dsp_implementation_strategies.ps1`：从 239-LUT 综合 DCP 扫描实现策略；
- `scan_3dsp_synthesis_directive.ps1`：从正式 RTL 扫描综合面积指令；
- `tb_cic_two24_mode1_equiv.v`、`tb_cic_integrator_pair_mode1_equiv.v`：逐样点等价验证；
- `analyze_3dsp_lut_hotspots.tcl`：导出 routed LUT cell 清单。

长路径下 Vivado 2025.2 的增量综合临时文件可能触发 `Synth 8-787`，综合策略扫描应把
结果目录放在仓库根部的短临时目录。该失败不产生资源结论，短目录复跑后的 241/263 数字
才是表中正式结果。

## 7. 建议

当前建议继续把 **239 LUT / 388 FF / 3 DSP / 4 RAMB18E1** 作为 3-DSP 下一板测候选。
若还要显著压缩 LUT，优先级应为：

1. 等评分公式明确后，判断 3-DSP 相对已板测 218-LUT/4-DSP 是否真的占优；
2. 若必须低于 239，需放宽至少一项约束，例如允许第 4 颗 DSP、调整吞吐协议，或接受经过
   MATLAB/RTL 重新量化验证的近似位宽；
3. 在 DSP=3、BRAM=4、严格 0-LSB 和现有吞吐全部固定时，继续微调的合理预期仅为 0～2 LUT，
   不宜把它当作确定收益。

本轮不修改正式 3-DSP RTL 和 `.xpr` 泛型，不生成新 bitstream，不宣称板测通过。
