# Vivado 2025.2 Stage1/2/3 = 24/20/20 字长优化执行反馈

## 1. 结论

用户提出的 `Stage1/Stage2/Stage3 = 24/20/20 bit` 有明确参考价值，并已完成从 MATLAB、RTL、
OOC、整板实现到 routed 六模式回归的完整工具闭环。最终正式整板 post-route 为：

**218 LUT / 365 FF / 4 DSP48E1 / 4 RAMB18E1（2 BRAM Tile）/ 2 MMCM / 17 IO**。

相对已板测 221-LUT 基线净减 **3 LUT（1.36%）和 2 FF（0.54%）**，DSP、BRAM、MMCM、IO
均不变；WNS/WHS 从 `+44.556/+0.079 ns` 变为 `+45.279/+0.079 ns`，没有以时序换面积。
该版本当前定义为 **tool-verified 候选**；物理板尚待用户下载验证，所以不能提前标成 board-pass，
221-LUT 标签仍是安全回退。

## 2. 方法与实现

221-LUT 基线的三级 FIR 数据宽度是 `24/22/20`：Stage1 的 24-bit 输出右移 2 bit并饱和到
22 bit送入 Stage2，Stage2 的 22-bit 输出再右移 2 bit并饱和到20 bit送入 Stage3。

本轮改为：

1. Stage1 输出仍保持24 bit，第一次级间量化改为右移4 bit并饱和到20 bit；
2. Stage2 的输入、历史 RAM 读口、共享 DSP 数据口及输出统一收窄到20 bit；
3. Stage2 到 Stage3 的第二个 bridge 变为 `SHIFT_N=0` 的同宽传输，只保留原 valid/phase
   握手，不再生成第二套数值舍入器；
4. 4x 调试/公开节点改为左移4 bit恢复24-bit PCM 标度，外部接口标度不变；
5. Stage2 的 DSP48E1 `PATTERNDETECT` 符号扩展掩码按20-bit结果重新推导；Stage3 平坦通路
   保持20 bit，补偿通路仍保持有符号21 bit，CIC 位宽和结构不变。

因此这不是简单把寄存器声明从22改成20，而是同步修改量化点、DSP溢出判据、公开节点标度、
MATLAB金标准以及所有验证入口。第二个 bridge 的控制时序仍保留，避免破坏 Stage3 输入相位。

## 3. MATLAB 有限字长结果

配置标识为 `NF-P3-STAGE123-24-20-20-CANDIDATE-R1`。六工况频响 6/6 通过，严格线性
相位；下表取 44.1/48 kHz 两族中的最差值：

| 输出节点 | 最大绝对通带偏差 | 峰峰纹波 | 阻带衰减 | 结论 |
|---|---:|---:|---:|---|
| 4x | 0.003022 dB | 0.005714 dB | 78.277 dB | PASS |
| 8x | 0.003447 dB | 0.006162 dB | 78.359 dB | PASS |
| 128x | 0.007605 dB | 0.005733 dB | 72.355 dB | PASS |

全幅正/负、固定随机种子及 −1/−60/−90 dBFS 双采样率音频共9类定向测试全部通过，累加器
溢出为0，候选没有比221-LUT基线增加饱和次数。随机输入相对24/22/20基线的 4x/8x/128x
SNR约为 `99.07/96.74/96.28 dB`。这说明24/20/20不是与旧版本逐样本相同，而是在满足
±0.05 dB、≥70 dB、严格线性相位约束下形成新的、经过量化分析的位真规格。

## 4. 资源分层比较

全部数字均来自同一 Vivado 2025.2 策略与 post-route 报告：

| 统计口径 | 24/22/20 基线 | 24/20/20 候选 | 变化 |
|---|---:|---:|---:|
| FIR 前端 OOC LUT / FF | 187 / 160 | 181 / 158 | −6 / −2 |
| 完整插值核心 OOC LUT / FF | 193 / 281 | 190 / 279 | −3 / −2 |
| 完整整板 LUT / FF | 221 / 367 | 218 / 365 | −3 / −2 |
| DSP48E1 | 4 | 4 | 0 |
| 整板 RAMB18E1 / BRAM Tile | 4 / 2 | 4 / 2 | 0 |
| 核心 RAMB18E1 / BRAM Tile | 3 / 1.5 | 3 / 1.5 | 0 |
| MMCM / IO | 2 / 17 | 2 / 17 | 0 |

FIR前端单独减少6 LUT，但加入后级CIC并允许跨层打包后，完整核心和整板的净收益均为3 LUT；
两种独立口径得到相同整板净变化，说明结果不是旧 run 或策略偶然波动。

## 5. RTL 与系统验证

- MATLAB 六模式频响：6/6 PASS；定向数值：9/9 PASS；
- 清理后 Smoke：17/17 PASS，目录
  `matlab_fir/national_finals/_work/rtl_regression/20260811_190516`；
- Release：17/17 PASS，目录
  `matlab_fir/national_finals/_work/rtl_regression/20260811_182157`；
- Release 共14组输入：冲激、10个固定 seed×4096、正/负满幅、997 Hz/−1 dBFS强音频；
- 4x/8x/128x 全节点对24/20/20 MATLAB金标准逐样本0 LSB；
- 8类内部状态复位恢复通过；10次无复位动态切档无窄脉冲、无X；
- ROM、DAC offset-binary、统一系数RAMB18、历史RAMB18、时钟族、CDC、按键与板级顶层测试通过。

正式 XPR 结果目录：
`XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/results/20260811_190839`。
综合为280 LUT / 373 FF；post-route为218 LUT / 365 FF。WNS/WHS=`+45.279/+0.079 ns`，
TNS/THS=0，DRC Error=0，vectorless总/动态/静态功耗=`0.271/0.199/0.072 W`，Medium
confidence；bitstream成功生成。

最终 routed DCP 六模式回归目录为
`matlab_fir/national_finals/_work/postroute_six_mode_dac/20260811_191105`，结果如下：

| 采样率族/倍率 | edges/ms | DAC data changes |
|---|---:|---:|
| 44.1 kHz / 4x | 177 | 175 |
| 44.1 kHz / 8x | 353 | 342 |
| 44.1 kHz / 128x | 5645 | 3710 |
| 48 kHz / 4x | 192 | 192 |
| 48 kHz / 8x | 384 | 372 |
| 48 kHz / 128x | 6144 | 3810 |

日志以 `BOARD POSTROUTE SIX-MODE DAC PASS` 结束。177/353/5645 是1 ms窗口的整数边沿
计数，分别对应176.4/352.8/5644.8 kHz。

## 6. 同轮结构候选与取舍

本轮还验证了把两路低24位积分器装入一个 DSP48E1 `TWO24` SIMD 的候选。连续输入和随机
CE/中途复位均实现0-LSB等价，但同口径 OOC 从基线 `77 LUT / 121 FF / 2 DSP` 变为
`83 LUT / 144 FF / 2 DSP`，增加6 LUT和23 FF，因此按Stop/Go门槛判为No-Go，未进入正式XPR。
正式工程、板级参数链和发布回归已移除该实验入口，只在 `tools/structure_experiments` 保留审计材料。

## 7. 复现与板测边界

关闭 Vivado GUI 后，在仓库根目录运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\XC7A35T_interp_opt_2025.2\tools\vivado_2025_2\run_full_build_2025_2.ps1 -Jobs 1
```

工具必须输出 `VIVADO_2025_2_FULL_BUILD_PASS`，并满足218/365/4-DSP/4-RAMB18/2-MMCM、
正WNS/WHS和0 DRC Error。建议上板文件为
`XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/results/20260811_190839/board_demo_competition_dac8_top_2025_2.bit`，
SHA-256=`1834675AB971FFA8BD6C03BF1B596D6F5D65C8A36A6B8D0182EEA6C5D408D110`。

自动验证不能代替物理 DAC、模拟波形和实测采样率；只有用户确认六档采样率和 DAC 波形正常后，
才能创建 board-pass 标签。若板测异常，立即回退到
`nf-vivado2025.2-221lut-367ff-4dsp-2bram-board-pass`。
