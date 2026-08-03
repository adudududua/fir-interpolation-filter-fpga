# P3-K DAC 无波形与测试音 ROM 综合语义修复执行反馈

## 1. 现象与结论

实物板下载 412-LUT / 4-DSP P3-K bitstream 后，DAC 不出波。工具侧使用 GUI 实际生成的 routed DCP 和完整 `board_demo_competition_dac8_top` 做功能仿真，包含真实 20 MHz 输入、两颗 MMCM、65535 拍上电复位、模式控制、测试音 ROM、完整插值链和 DAC ODDR，复现结果为：

```text
BOARD POSTROUTE DAC: edges=11290 data_changes=0 sample_updates=88
BOARD POSTROUTE CTRL: rst_audio=1 mute=0 audio_mode=11 x_valid=1
BOARD POSTROUTE DATA: audio=00 s1=00 s2=00 cic=00
```

`dac_clk` 在 2 ms 测量窗内有 11,290 个边沿，对应约 5.645 MHz；复位已释放、静音未使能、默认 128x 模式和输出 valid 均正常。唯一异常是 ROM 输入及其后所有数据级始终为 0，因此物理现象表现为 8-bit offset-binary DAC 一直输出中点码 128。

## 2. 根因

P3-J 424-LUT Packed-ROM 优化把原 24-bit ROM 扩为 32 bit，先用 `$readmemh` 装入 PCM 低 24 bit，再用同一个 `initial` 中的 `for` 循环写入高 8 bit“下一地址”；运行时直接把该高字节反馈给地址寄存器。这在 RTL XSim 中按 procedural 语义工作，因此原 ROM 测试和完整 RTL 回归均通过。

但 Vivado 2018.3 对推断 block ROM 没有可靠合并第二次 procedural 位域初始化。post-route netlist 中地址 0 对应 RAMB18 INIT 的高字节为 0，首 PCM 样点本身也恰好是 0，结果是：

```text
rd_addr=0 -> pcm=0, next_addr=0 -> rd_addr=0 -> ...
```

这个缺陷从提交 `a6be164` 的 Packed-ROM 优化开始，影响 424-LUT P3-J 及继承该 ROM 的 412-LUT P3-K。旧验证没有发现它有三个原因：RTL 仿真执行了二次初始化；键盘板级测试对音频 common 模块使用 stub；此前 DAC 动态测试没有从综合后的完整 MMCM/POR/ROM 网表启动。

## 3. 修复

修复保持 FIR/CIC 数学路径、系数、字长、舍入、饱和、valid、时钟和板级接口不变，只修改测试音源：

- ROM 恢复为 24-bit signed、单一 `$readmemh`、纯同步读取，继续推断 RAMB18E1；
- 44.1 kHz 与 48 kHz 两个地址区间使用普通时序递增/回绕；
- 不再依赖推断 BRAM 未使用位上的二次 procedural 初始化；
- 保留 family 切换时的同步地址复位和首地址行为。

## 4. 修复版资源、Timing 与功耗

固定配置为 `AreaOptimized_high / flatten full / resource sharing on / Default implementation / 4 DSP / 2 BRAM Tile / 2 MMCM`。

| 指标 | 失效 P3-K | DAC-ROM 修复版 | 变化 |
|---|---:|---:|---:|
| Synth LUT / FF | 449 / 420 | 456 / 422 | +7 / +2 |
| Post-route LUT | 412 | **427** | +15 |
| Post-route FF | 418 | **416** | -2 |
| Slice | 168 | **177** | +9 |
| DSP48E1 | 4 | **4** | 0 |
| RAMB18E1 / Tile | 4 / 2.0 | **4 / 2.0** | 0 |
| MMCM | 2 | **2** | 0 |
| WNS / WHS | +45.083 / +0.056 ns | **+44.983 / +0.105 ns** | 全部满足 |
| TNS / THS | 0 / 0 ns | **0 / 0 ns** | 不变 |
| AD9708 setup / hold | +76.116 / +78.117 ns | **+76.116 / +78.117 ns** | 不变 |
| 总/动态/静态功耗 | 0.271/0.199/0.072 W | **0.271/0.199/0.072 W** | 不变 |

修复 bitstream SHA-256：

```text
0FFEC2DC929AE3A16E2CB08B32F5B056F378902416E1E191B9D7D08CC6B0EA7D
```

频响和量化指标不受该修改影响，继续继承已签核六工况最差绝对通带偏差/峰峰纹波/阻带衰减 **0.007730/0.006192/72.371 dB**，严格线性相位。

## 5. 验证结果

### 5.1 定向 ROM 与 RTL

- ROM 定向测试：数据、44.1/48 kHz 回绕及 family 同步复位 PASS；
- Smoke RTL：15/15 PASS；
- Release RTL：15/15 PASS；正式运行目录为 `_work/rtl_regression/20260803_214937`，完整耗时约 10 分 47 秒。此前两次分别在 248 秒和 608 秒被外层命令超时终止，均不是功能失败，也没有被计作 PASS。

### 5.2 修复版 routed DCP 完整板级功能仿真

```text
BOARD POSTROUTE DAC: edges=11290 data_changes=7461 sample_updates=88
BOARD POSTROUTE CTRL: rst_audio=1 mute=0 audio_mode=11 x_valid=1
BOARD POSTROUTE DATA: audio=c2 s1=c1 s2=4c cic=c0 changes=88/176/350/7461
BOARD POSTROUTE DAC ACTIVITY PASS
```

同一测试、同一启动时间和同一测量窗，修复前 `data_changes=0`，修复后为 7,461；因此修复不是只改变 RTL 仿真，而是已进入综合、布局布线后的 RAMB18 INIT 与真实板级输出网表。

新增的公开引脚一键门禁也已对同一修复 DCP 从零复跑，结果为 `edges=11290 / data_changes=7461 / final_data=64 / beep=1`，并输出 `NATIONAL FINALS POSTROUTE BOARD DAC ACTIVITY PASS`。

普通 Vivado 工程的 `impl_1` 也已先 reset 旧实现，再从修复版 `synth_1` 执行 `launch_runs impl_1 -to_step write_bitstream -jobs 4`，精确复现 **427 LUT / 416 FF / 177 Slice / 4 DSP / 2 BRAM Tile / 2 MMCM** 和 **+44.983/+0.105 ns**。GUI 工程 routed DCP 再次通过同一 DAC 活动门禁。GUI 本地 bit 的 SHA-256 为 `B5EB9D07A4807A2117D2792096659CA66634F94A8556E87D2CEE1FE27EF9D726`；它与归档 bit 的哈希不同是因为 Vivado bit header 含构建元数据，不代表逻辑或资源不同。

## 6. 新增发布门槛与复现

以后所有板级候选在 bitstream 发布前必须执行：

```powershell
powershell -ExecutionPolicy Bypass -File `
  matlab_fir/national_finals/sim/run_postroute_board_dac_activity.ps1 `
  -DcpPath <candidate_routed.dcp>
```

脚本会把临时网表和 XSim 文件放入 `matlab_fir/national_finals/_work/postroute_dac_activity/<时间戳>`，不会污染仓库根目录。门禁只依赖公开引脚，要求启动后无 X、2 ms 内超过 10,000 个 DAC 时钟边沿、超过 32 次 DAC 数据变化且蜂鸣器保持无效高电平。

## 7. Git 与回退说明

- 修复分支：`national-finals-p3k-4dsp-dac-rom-fix`；
- 旧 412-LUT 标签与 424-LUT Packed-ROM 标签保留作审计，不移动、不重写，但明确撤销上板资格；
- Packed-ROM 之前的 `nf-p3j-final-430lut-431ff-176slice-4dsp-2bram-reproducible` 不含该缺陷，可作为历史安全回退；
- 最终仍停留在修复分支，分支、提交和标签不使用 `codex` 字样。

## 8. 实板复测结果（2026-08-03）

用户已下载修复版 bitstream 并反馈：**DAC 输出正常、采样率正常**。这项结果关闭了此前唯一未完成的物理板门槛，并与 routed-DCP 中恢复的 DAC 数据活动相互印证，当前版本状态更新为“板级验证通过”。

本次反馈未包含六档逐档实测频率、示波器截图或频谱数值，因此只记录用户实际确认的 DAC 与采样率结论，不补写未测量数据。若赛前需要正式仪器验收报告，仍建议补录各档 DA_CLK、主音频率和 128x 镜像抑制。
