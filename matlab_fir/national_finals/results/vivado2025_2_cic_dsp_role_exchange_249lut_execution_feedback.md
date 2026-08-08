# Vivado 2025.2 CIC DSP 角色交换 249-LUT 执行反馈

日期：2026-08-08

试验分支：`national-finals-v2025.2-245to249-lut-challenge`

工具签核标签：`nf-vivado2025.2-249lut-377ff-4dsp-2bram-toolverified`

实板安全基线标签：`nf-vivado2025.2-258lut-376ff-4dsp-2bram-board-pass`

## 1. 结论与状态边界

本轮在 258-LUT 实板通过基线已经独立保存的前提下完成 245～249 LUT 挑战，Vivado 2025.2
正式布局布线结果为：

**249 LUT / 0 LUTRAM / 377 FF / 4 DSP48E1 / 4 RAMB18E1（2 BRAM Tile）/
17 IO / 2 MMCM**。

相对 258-LUT 实板基线减少 **9 LUT（3.49%）**、增加 1 FF，DSP、BRAM、IO、MMCM 和
0.271 W vectorless 功耗不变。CIC 定向等价、Smoke/Release 17 项 RTL 回归、全链 0-LSB、
Vivado 2025.2 综合/实现、时序、DRC、功耗、bitstream 和 routed-DCP 六档检查全部通过。

当前状态是 **tool-verified，待用户物理板复测**。工具验证能显著降低板测风险，但不能代替
示波器与实际 DAC 板，因此在用户确认前不创建 `board-pass` 标签；258-LUT 标签继续作为正式
实板安全回退。

## 2. 正式优化方法

### 2.1 Stage1 隐式 ready

Stage1 串行核原有 `filter_ready` 只重复表达“当前不忙”，综合路径却为它保留了额外组合与
复位状态。本轮把该信号限制为仿真断言可见，奇相输出直接使用已经在固定拍到达的
`filter_rounded`。周期、输出 valid、算术和 RAM 地址没有改变。该独立检查点从 258 LUT 降至
**256 LUT / 375 FF**，并通过完整 Smoke 17/17。

### 2.2 CIC comb 与积分器进行 DSP 角色交换

258-LUT 版的两个 DSP 用于 CIC 的第一、第三积分器，三级 comb 减法主要落在 Fabric。三级
comb 具有“每拍只执行一次减法、减数宽度固定、结果下一拍使用”的天然串行特征，因此正式版：

1. 用一个显式 `DSP48E1` 的 P 寄存器执行三级 comb 的依次减法；
2. 将第一级 26-bit 积分器从 DSP 换到带 `use_dsp="no"` 的 CARRY4 加法链；
3. 最后一级宽积分器继续留在 DSP；
4. 保持 Stage1 与共享 Stage2/3 各 1 个 DSP。

这样整机仍是 **4 DSP**，但把“DSP 擅长的串行宽减法”换入 DSP，把较窄、容易由 CARRY4
实现的积分器换出。功能上仍执行相同的三级 comb 与三级积分，只改变物理映射，不改变 CIC
阶数、倍率、位宽、截位或输出拍序。

提交前源码审计还发现：如果无条件实例化 comb DSP，虽然正式 `mode=2` 正确，却会破坏历史
`mode=1/0` 的低 DSP 资源语义。最终代码用 generate 把角色交换严格限定在 `mode=2`；
`mode=1/0` 继续使用 Fabric comb，分别保留整机 3-DSP/2-DSP Pareto 映射。最终 Release 的
CIC 定向用例同时实例化三个模式并逐拍比较，确认这一兼容性修复没有改变数值或 valid 时序。

### 2.3 对齐状态复用

显式 DSP PREG 有一拍输出延迟。初版使用独立 `align_pending` 标志，得到 250 LUT / 378 FF。
最终让原 `comb_stage_index` 的空闲编码兼任这一拍对齐状态，删除独立标志及其译码，得到
**249 LUT / 377 FF**。这一步保持总延迟不变，并由 CIC 逐样本等价测试验证。

## 3. 资源演进与策略扫描

| 检查点 | Synth LUT | Synth FF | Routed LUT | Routed FF | DSP | RAMB18 | 结论 |
|---|---:|---:|---:|---:|---:|---:|---|
| 258-LUT 实板基线 | 319 | 384 | 258 | 376 | 4 | 4 | 安全回退 |
| Stage1 隐式 ready | 318 | 383 | 256 | 375 | 4 | 4 | 保留 |
| CIC DSP 角色交换初版 | 326 | 386 | 250 | 378 | 4 | 4 | 已达近目标 |
| **角色交换 + 对齐状态复用** | **325** | **385** | **249** | **377** | **4** | **4** | **正式候选** |

正式架构的实现策略比较如下；不能把不同架构的最低数字混为同一候选：

| `opt_design` / `place_design` | Routed LUT | FF | WNS/WHS | 结论 |
|---|---:|---:|---:|---|
| `ExploreArea / Explore` | **249** | **377** | +43.997/+0.085 ns | 正式采用 |
| `ExploreWithRemap / Explore` | 278 | 378 | +44.666/+0.096 ns | LUT 明显变差 |
| `ExploreSequentialArea / Explore` | 280 | 378 | +45.185/+0.109 ns | LUT 明显变差 |

## 4. 已试但未采用的候选

| 候选 | 结果 | 为什么未采用 |
|---|---|---|
| Stage1 单 metadata pipeline | 260 LUT / 367 FF | FF 更少，但 LUT 高于 258 基线 |
| 键盘 one-hot 编码 | 259 LUT / 375 FF | 综合看似较好，布局布线反而增加 1 LUT |
| Stage2/3 派生 metadata | 254 LUT / 368 FF | 正确 2025.2 全链回归出现 8x 未知值、128x 饱和不一致与 pending 覆盖，功能 No-Go，已回退 |
| Stage2/3 直接使用 DSP PREG 输出 | 综合 317 LUT / 333 FF | 改变流水边界，存在时序语义风险，未进入正式实现 |
| CIC burst 状态统一 | 综合 317 LUT / 376 FF | 没有形成可靠 routed 优势 |
| CIC 两位 comb FSM | 综合 319 LUT / 375 FF | LUT 无改善 |

这里最重要的审计结论是：**254 LUT 的实现数字没有成为候选**，因为它没有通过正确源码的
全链 RTL 回归。最终 249-LUT 版不是从失败候选继续打补丁，而是完整恢复可信架构后采用独立的
CIC 映射优化。

## 5. 验证完整性

### 5.1 回归源路径修复

回归脚本原默认指向旧的 2018.3 工程副本，可能出现“测试通过但没有测到当前 2025.2 RTL”的
假阳性。本轮把默认 `SourceProject` 改为 `XC7A35T_interp_opt_2025.2`，并为显式 DSP 原语的
CIC 用例加入 `glbl` 与 `unisims_ver`。此后所有正式回归都针对当前工程源码。

### 5.2 CIC 定向 bit-true

- 连续输入：320 个输出；
- 随机停顿输入：480 个输出；
- 10 个随机 seed：每个 256 个输出；
- 中途复位恢复：PASS；
- 合计逐样本等价比较：**4096 个输出，全部 PASS**；
- 日志：
  `matlab_fir/national_finals/_work/lut245_challenge/cic_comb_dsp_role_exchange/rtl_cic_targeted/xsim.log`。

### 5.3 完整 RTL 回归

| 套件 | 工具 | 结果 | 目录 |
|---|---|---|---|
| Smoke | Vivado/XSim 2025.2 | **17/17 PASS** | `matlab_fir/national_finals/_work/rtl_regression/20260808_233138` |
| Release | Vivado/XSim 2025.2 | **17/17 PASS** | `matlab_fir/national_finals/_work/rtl_regression/20260808_231807` |

Release 包含冲激、10 个随机 seed、正/负满量程和强 −1 dBFS 共 14 组全链输入；4x、8x、
128x 三个正式节点逐样本 **0 LSB**。同时覆盖 Stage1 行为 RAM/RAMB18E1、CIC 三映射、
8 类内部状态复位恢复、10 次不停机动态切档、ROM、DAC offset-binary、系数/历史 BRAM、CDC、
按键和 44.1/48 kHz 双时钟族。

### 5.4 频响指标

本轮没有改变系数或定点算术，以下值由正式 RTL 冲激响应继承并由 Release 0-LSB 证明没有漂移：

| 节点 | 最差通带最大绝对偏差 | 最差峰峰纹波 | 阻带衰减 | 相位 |
|---|---:|---:|---:|---|
| 4x | 0.003022 dB | 0.005709 dB | 78.568 dB | 严格线性 |
| 8x | 0.003521 dB | 0.006192 dB | 78.609 dB | 严格线性 |
| 128x | 0.007730 dB | 0.005848 dB | 72.371 dB | 严格线性 |

48 kHz 族的对应最大绝对偏差为 0.003022/0.003007/0.007606 dB，峰峰纹波为
0.005709/0.005678/0.005724 dB；阻带衰减相同。六个工况均满足 ±0.05 dB、≥70 dB。

## 6. 正式实现、时序、DRC 与功耗

结果目录：
`XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/results/20260808_233550`

| 阶段 | LUT | LUTRAM | FF | DSP | RAMB18E1 | BRAM Tile | IO | MMCM |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 综合 | 325 | 0 | 385 | 4 | 4 | 2 | 17 | 2 |
| 布局布线 | **249** | **0** | **377** | **4** | **4** | **2** | **17** | **2** |

| 检查项 | 结果 |
|---|---:|
| WNS / TNS | +43.997 ns / 0 ns |
| WHS / THS | +0.085 ns / 0 ns |
| setup / hold 失败端点 | 0 / 0 |
| 无时钟寄存器 / 内部未约束端点 | 0 / 0 |
| 组合环 / 锁存环 | 0 / 0 |
| DRC Error | 0 |
| 总 / 动态 / 静态功耗 | 0.271 / 0.199 / 0.072 W |

按键矩阵端口采用 false-path，`dac_clk` 是设计输出时钟，因此 `check_timing` 中相应 I/O delay
提示不是内部时序遗漏；内部端点全部受约束。

## 7. 布线后六档 DAC 与采样率门禁

正式 routed DCP 六档结果目录：
`matlab_fir/national_finals/_work/postroute_six_mode_dac/20260808_234015`

| 模式 | 1 ms 内 DA_CLK 边沿 | DAC 数据变化次数 | 结果 |
|---|---:|---:|---|
| 44.1 kHz / 4x | 177 | 175 | PASS |
| 44.1 kHz / 8x | 353 | 342 | PASS |
| 44.1 kHz / 128x | 5645 | 3710 | PASS |
| 48 kHz / 4x | 192 | 192 | PASS |
| 48 kHz / 8x | 384 | 372 | PASS |
| 48 kHz / 128x | 6144 | 3810 | PASS |

六档 DAC 数据都持续变化且没有 X。`177/353/5645` 是 1 ms 窗口的整数边沿计数，对应理论
176.4/352.8/5644.8 kHz，并非把采样率改成整数 kHz。

## 8. bitstream、手动复现与回退

推荐板测 bitstream：

`XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/results/20260808_233550/board_demo_competition_dac8_top_2025_2.bit`

SHA-256：`353308536B12E16CE896236D3754430B372ED1F957CB52B744EA2A8F57B6D1AB`

routed DCP SHA-256：
`A14C4AC012B57EF24ADEEFECC46EBDCEA22713781AC97F6BAFD0265369B5C4D3`

手动复现时打开 `XC7A35T_interp_opt_2025.2/XC7A35T_interp.xpr`，执行 Reset Runs 后再运行
Generate Bitstream；机器提交内存有限时将 jobs 设为 1～4。也可在 PowerShell 中执行：

```powershell
XC7A35T_interp_opt_2025.2\tools\vivado_2025_2\run_full_build_2025_2.ps1 -Jobs 1
```

构建脚本已设置硬门禁：LUT ≤249、FF ≤390、DSP=4、RAMB18E1=4、MMCM=2、WNS/WHS≥0、
DRC Error=0，任一条件不满足就返回失败，不会用旧结果冒充通过。

若物理板出现任何采样率或 DAC 异常，直接回退：

```powershell
git switch --detach nf-vivado2025.2-258lut-376ff-4dsp-2bram-board-pass
```

所有试验与仿真临时文件均位于 Git 忽略的 `_work` 或正式工程的时间戳 `results` 目录，没有在
仓库主目录新增 `.Xil`、`xsim.dir`、`vivado*.log/.jou` 等杂项。
