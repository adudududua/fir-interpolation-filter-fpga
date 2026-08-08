# Vivado 2025.2 Stage1 顺序抽头架构 258-LUT 执行反馈

日期：2026-08-08

试验分支：`national-finals-v2025.2-post276-lut-optimization`

工具签核标签：`nf-vivado2025.2-258lut-376ff-4dsp-2bram-toolverified`

板测安全基线提交：`aecc2b3`

板测安全基线标签：`nf-vivado2025.2-276lut-379ff-4dsp-2bram-17io-2mmcm-board-pass`

## 1. 结论

本轮没有继续做个位数控制微调，而是在已经保留 276-LUT 板测基线的前提下，重新设计
Stage1 的系数存储布局和串行 MAC 控制。新候选在 Vivado 2025.2 标准 GUI 工程路径下得到：

**258 LUT / 0 LUTRAM / 376 FF / 4 DSP48E1 / 4 RAMB18E1（2 BRAM Tile）/
17 IO / 2 MMCM**。

相对 276-LUT 板测基线减少 **18 LUT（6.52%）**、减少 3 FF，DSP、BRAM、IO、MMCM 和
0.271 W vectorless 功耗均不变；setup/hold、DRC、bitstream、RTL Release 17/17 和 routed
六档 DAC/采样率仿真全部通过。该结果已达到 **tool-verified**，但尚未使用新 bitstream 做物理
板复测，所以 276-LUT 标签仍是当前正式板测安全回退。

## 2. 为什么选择重构 Stage1

276-LUT 版本的 Stage1 每个对称抽头读取 `Lk/Rk` 两个地址，通过 DSP 预加路径计算
`(Lk + Rk) * Ck`。控制器因此需要同时保存左右抽头种类和有效掩码、计算两套环形地址，并在
MAC 结束后另外预取半带中心延迟样本。实现策略扫描已经证明物理优化无法再消除这些控制开销。

新架构利用统一系数 RAMB18E1 中原本空闲的地址，把 26 个对称系数展开成 52 个顺序系数：

`C0, C1, ..., C25, C25, ..., C1, C0`

展开表放在逻辑地址 128--179，对应物理 Port A 地址映射
`{4'b0010, stage1_addr[5:0], 4'b0000}`。Stage1 从最新到最旧顺序扫描 52 个历史样本，每拍执行
一次直接乘加，并在同一次扫描中捕获中心延迟样本。这样删除了：

1. DSP 对称预加控制；
2. 左/右抽头状态与两套有效掩码；
3. 第二套环形地址公式；
4. MAC 后的独立延迟样本读取状态。

没有新增 RAMB18E1：52 个展开系数占用的仍是原统一系数 BRAM 的空闲空间；Stage1 仍使用
1 个 DSP，整机仍是 4 DSP / 2 BRAM Tile。

## 3. 数值等价性

旧结构每个对称抽头计算：

`(Lk + Rk) * Ck`

新结构在同一 48-bit 累加域中依次计算：

`Lk * Ck + Rk * Ck`

24-bit 输入之和使用 25 bit，不发生预加溢出；24×18 bit 单项乘积和 25×18 bit 对称乘积都能
完整放入 48-bit 累加器，因此这里满足二进制补码分配律，不引入截位位置变化。滤波系数、Q 格式、
舍入、饱和、输出 valid 相位、Stage2/3、均衡器、CIC、ROM、时钟和 DAC 接口全部保持不变。

因此六工况频响严格继承当前正确标度正式路径：44.1/48 kHz 两族的 4x、8x、128x 通带最大
绝对偏差、峰峰纹波和阻带衰减不变；最差通带最大绝对偏差为 0.007730 dB，最差峰峰纹波为
0.006192 dB，最差阻带衰减为 72.371 dB，严格线性相位。

## 4. RTL 验证

### Smoke

- 结果：**17/17 PASS**；
- 目录：`matlab_fir/national_finals/_work/rtl_regression/20260808_151507`；
- 统一系数 RAMB18E1 原语测试改为验证 52 个展开 Stage1 地址和 128 个 Stage2/3 地址；
- Stage1 行为 RAM 与真实 RAMB18E1 两条路径各对拍 1400 个输出，全部 0 LSB；
- 全链、复位、动态切档、CDC、双时钟族、按键、ROM、DAC offset-binary 均通过。

第一次 Smoke 在 full-chain reset elaboration 阶段发现测试台引用内部调试信号 `mac_active`；
这是层次可观测性接口缺失，不是算术失败。最终 RTL 恢复一个不参与功能决策的镜像调试寄存器后，
从头重跑 17/17 通过。

### Release

- 结果：**17/17 PASS**；
- 目录：`matlab_fir/national_finals/_work/rtl_regression/20260808_153111`；
- 逐项审计 17 份 `xsim.log`，每份均有 PASS，`ERROR/FATAL/FAIL` 命中数均为 0；
- 全链冲激、10 个随机 seed、正/负满量程和强 −1 dBFS 共 14 组输入，在 4x/8x/128x 三节点
  全部逐样本 **0 LSB**；
- 8 类内部状态复位恢复、10 次不停机动态切档和 1200 次 CDC 定向转换全部通过。

## 5. 综合、实现、时序与功耗

两次结果均使用 `AreaOptimized_high / flatten_hierarchy=full / resource_sharing=on /
SHREG_MIN_SIZE=5`，实现采用 `ExploreArea + Explore`。

| 阶段/版本 | LUT | LUTRAM | FF | DSP | RAMB18E1 | BRAM Tile | 相对基线 |
|---|---:|---:|---:|---:|---:|---:|---|
| 276-LUT 板测基线综合 | 341 | 0 | 387 | 4 | 4 | 2 | — |
| 258-LUT 候选综合 | **319** | **0** | **384** | **4** | **4** | **2** | −22 LUT，−3 FF |
| 276-LUT 板测基线 routed | 276 | 0 | 379 | 4 | 4 | 2 | — |
| 258-LUT 候选 routed | **258** | **0** | **376** | **4** | **4** | **2** | **−18 LUT，−3 FF** |

标准 GUI 工程从 `reset_run synth_1` 开始完整重建，最终输出：

- WNS/TNS：`+45.222/0 ns`；
- WHS/THS：`+0.077/0 ns`；
- setup/hold 失败端点：0/0；
- DRC Error：0；
- 总/动态/静态功耗：`0.271/0.199/0.072 W`，Medium confidence；
- 完整构建标志：`VIVADO_2025_2_FULL_BUILD_PASS`；
- 结果目录：
  `XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/results/20260808_161249`。

## 6. 布线后六档验证

从 258-LUT routed DCP 导出包含 Xilinx 原语的功能网表，六个公开档位全部通过：

| 模式 | 1 ms 内 DA_CLK 边沿 | DAC 数据变化次数 | 结果 |
|---|---:|---:|---|
| 44.1 kHz / 4x | 177 | 175 | PASS |
| 44.1 kHz / 8x | 353 | 342 | PASS |
| 44.1 kHz / 128x | 5645 | 3710 | PASS |
| 48 kHz / 4x | 192 | 192 | PASS |
| 48 kHz / 8x | 384 | 372 | PASS |
| 48 kHz / 128x | 6144 | 3810 | PASS |

六档 DAC 数据均持续变化、没有 X。177/353/5645 是 1 ms 有限窗口内的整数边沿计数，分别
对应理论 176.4/352.8/5644.8 kHz。结果目录：
`matlab_fir/national_finals/_work/postroute_six_mode_dac/20260808_154424`。

## 7. bitstream 与可复现性

标准 GUI 工程生成的 bitstream：

`XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/results/20260808_161249/board_demo_competition_dac8_top_2025_2.bit`

SHA-256：`A9BD34D4770434330B199E1AADC23B71C2DF76B3B4EFEB8DAC4F15498526B491`

脚本从同一 routed DCP 生成的压缩 bitstream SHA-256 为
`DE447F7F93CEACD0433A989DF46FDC48FEC0AF12ACC23751E9C60CF74BCBD3BB`。两者压缩设置不同，
所以文件哈希和大小不同；设计资源、时序与 DRC 结论一致。推荐板测使用标准 GUI 工程结果。

本轮还遇到一次 Vivado 2025.2 Tcl Store 报错。受限进程无法访问 `%APPDATA%/Xilinx` 时，
Vivado 会把权限错误误报为用户 Tcl Store 损坏或缺失 appinit/xsim/modelsim。允许 Vivado 正常
访问自身用户配置目录后，DCP 打开和 bitstream 立即成功；设计本身没有报错，也没有删除用户配置。

## 8. 发布与回退策略

- 258-LUT 候选保存为独立工具签核提交和标签，状态写作 `tool-verified`；
- 在物理板确认 44.1/48 kHz 六档采样率和 DAC 波形前，不把它写成 board-verified；
- 任何板级异常均可直接切回 `aecc2b3` 或
  `nf-vivado2025.2-276lut-379ff-4dsp-2bram-17io-2mmcm-board-pass`；
- 所有 DCP、仿真目录和 Vivado 临时文件均放在 Git 忽略的 `_work` 或时间戳 `results` 下，仓库
  主目录没有新增 `.Xil`、`xsim.dir`、`vivado*.log/.jou` 等杂项。
