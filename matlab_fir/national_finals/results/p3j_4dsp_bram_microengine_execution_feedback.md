# P3-J 4-DSP BRAM/微引擎下一轮优化执行反馈

## 1. 结论

本轮没有把完整全国赛板级设计降到 280～299 LUT，也没有发现“单纯增加 BRAM 就能进入 200 多 LUT”的可行证据。实际保留的改进是在原 P3-J 正确性签核版上压缩板级 ROM 地址控制和矩阵键盘扫描控制，最终从干净提交 `785eb61c67e3d1005b7f2e59f65f7097b026109a` 重建为：

| 指标 | 前一 P3-J 基线 | 本轮最终版 | 变化 |
|---|---:|---:|---:|
| LUT | 430 | **424** | **-6** |
| FF | 431 | **431** | 0 |
| Slice | 176 | **169** | **-7** |
| DSP48E1 | 4 | **4** | 0 |
| RAMB18E1 / BRAM Tile | 4 / 2.0 | **4 / 2.0** | 0 |
| MMCM | 2 | **2** | 0 |
| WNS/WHS | +45.636/+0.119 ns | **+45.042/+0.080 ns** | 均为正，0 failing endpoint |
| 总/动态/静态功耗 | 0.271/0.199/0.072 W | **0.271/0.199/0.072 W** | vectorless 估计不变 |

正式结果目录为 `vivado_results/p3j_final_424lut_431ff_169slice_4dsp_2bram_packedrom`，bitstream SHA-256 为 `2BA97CCE337638D57268EE04CCE0D09D2FDF6637B1A4A25D35E57BCB49C3ED4B`。当前环境没有实物开发板，物理下载、示波器和音频仪器验证仍待执行，不能把工具侧 bitstream PASS 写成实板 PASS。

## 2. 为什么“多用 BRAM 换到 280～299 LUT”没有实现

重新做保层次综合后，完整设计为 471 LUT/437 FF，主要层次为：公共音频/滤波层约 400 LUT，其中滤波核心约 355 LUT；Stage1 约 150 LUT，Stage2/3 约 131 LUT，CIC 约 70 LUT。板级按键、测试音源、顶层和 CDC 还要消耗其余逻辑。若完整板级要低于 300 LUT，滤波核心需再减少约 130～170 LUT，远大于地址译码或少量状态机可以提供的收益。

当前 4 个 RAMB18E1 已分别承担测试音 ROM、Stage1 历史、Stage2/3 历史和统一 FIR 系数。把 Stage1 历史拆成双 RAMB18，或把 Stage2/3 历史拆开，都会增加到 5 个 RAMB18E1（2.5 Tile），但实测 LUT 反而增加。因此不能再用“多 1 个或若干 BRAM 就自然下降到 200 多 LUT”作为资源预算。

另外，系统中的滤波/CIC 时钟实际就是 44.1 kHz 家族的 5.6448 MHz 或 48 kHz 家族的 6.144 MHz，而不是此前一度假设的 98.304 MHz。两个高率 CIC integrator 在 128x 输出时钟上每拍都必须更新，现有时钟域内没有 16 个空闲拍可以把它们无代价地合并为一个 DSP。

## 3. 候选逐项执行结果

| 候选 | 综合/OOC 结果 | 功能结果 | Stop/Go |
|---|---|---|---|
| P3-J 原配置重建 | 471 LUT / 437 FF / 4 DSP / 4 RAMB18 | 作为层次审计参考；full flatten 正式基线为 467/437 | 参考 |
| Stage2/3 历史拆分 | 478 LUT / 437 FF / 4 DSP / 5 RAMB18 | 结构可综合 | **No-Go：+11 LUT** |
| Stage1 双 BRAM | 477 LUT / 413 FF / 4 DSP / 5 RAMB18 | 结构可综合 | **No-Go：-24 FF 但 +10 LUT** |
| 高时钟两相共享 CIC | 82 LUT / 108 FF / 2 DSP；原 CIC 为 71/119/2 | 240 输入、3840 输出逐样本 0 LSB | **No-Go：省 11 FF 但多 11 LUT** |
| ROM 高位打包下一地址 | 完整板级 455 LUT / 435 FF | 44.1/48 kHz 全循环、复位和数据测试 PASS | **Go：相对 467/437 为 -12/-2** |
| 再叠加 ultra keypad | 完整板级 453 LUT / 433 FF | SW1～SW8、行优先、抖动、板级控制 PASS | **Go：累计 -14/-4** |
| 综合 AreaOptimized_medium | 453 LUT / 433 FF | 与 high 同网表资源 | 同分 |
| 综合 Default | 465 LUT / 433 FF | 可综合 | **No-Go：多 12 LUT** |
| 实现 Default | **424 LUT / 431 FF / 169 Slice** | timing/DRC/CDC/bitstream PASS | **最终保留** |
| 实现 AddRemap | 424 LUT / 431 FF / 169 Slice | timing/DRC/CDC/bitstream PASS | 同分，保留更简单的 Default |

历史 20 MHz 跨时钟域统一三级 FIR 也被复核：它虽然以 1 个 FIR DSP 完成 Release 0 LSB，但核心达到 910 LUT/692 FF/3 DSP/2.5 BRAM，CDC/FIFO/ping-pong bank 开销远大于现有两 FIR DSP 结构，不能作为 200 多 LUT 路线。

## 4. 最终保留优化方法

### 4.1 测试音 ROM 打包下一地址

原 ROM 每个地址只保存 24-bit PCM，而 RAMB18 的有效物理字宽还有空闲位。本轮把每个逻辑字扩展为 32 bit：低 24 bit 保存 PCM，高 8 bit保存下一 ROM 地址。44.1 kHz 的 0～146 地址和 48 kHz 的 147～162 地址各自在 ROM 内形成循环链。

这样删除了外部 `+1`、两组范围比较器和采样族相关的回绕 mux；仍只使用原来的一个 RAMB18E1。复位或采样族变化时仍由首地址装载保证确定性，读数据和下一地址来自同一个同步 ROM 字。

### 4.2 Ultra-compact 矩阵键盘控制

扫描过程中不再分别保存 row0/row1 的 found/mode 上下文，而是用 `{valid,family,mode[1:0]}` 一个 4-bit 候选编码表达扫描结果；row0 命中可以覆盖已有 row1 命中，保持 SW1～SW4 的优先级。行驱动改成一热循环移位，最终行为与旧 compact keypad 对拍一致。

该优化单独只再减少约 2 个综合 LUT，但代码已进入 XPR、批处理构建、CLI RTL 回归和 GUI 校验，避免手动 Vivado 工程漏源或 generic 漂移。

## 5. MATLAB 与 RTL 验证

MATLAB `p3_01_search_joint_stage3_equalizer.m` 退出码为 0，并输出 `P3_JOINT_STAGE3_EQUALIZER_MATLAB_GATE_PASS`。偏好文件和绘图缓存权限警告不影响 CSV、数值门禁或最终 PASS。

| 输入族 | 节点 | 绝对通带最大偏差 | 峰峰纹波 | 阻带衰减 |
|---|---:|---:|---:|---:|
| 44.1 kHz | 4x | 0.003022 dB | 0.005709 dB | 78.568 dB |
| 44.1 kHz | 8x | 0.003521 dB | 0.006192 dB | 78.609 dB |
| 44.1 kHz | 128x | 0.007730 dB | 0.005848 dB | 72.371 dB |
| 48 kHz | 4x | 0.003022 dB | 0.005709 dB | 78.568 dB |
| 48 kHz | 8x | 0.003007 dB | 0.005678 dB | 78.609 dB |
| 48 kHz | 128x | 0.007606 dB | 0.005724 dB | 72.371 dB |

全部六工况保持严格线性相位。Release XSim 正式运行目录为 `_work/rtl_regression/20260803_171058`，结果为 **15/15 PASS**：冲激、10 个固定 seed×4096、正/负满量程和 997 Hz/-1 dBFS 强信号共 14 组全链输入，4x/8x/128x 全部逐样本 0 LSB；另有内部复位恢复 8/8、无停机倍率切换 10/10、1200 次原子 CDC 事务，以及 RAMB18/CIC/时钟/键盘单元测试。

第一次 Release 的外层执行上限被错误设为 900 秒，在全链 case 10 已 PASS 后被执行器终止。设计没有报错；将外层上限提高到 2400 秒并从零重跑后，约 904.6 秒正常完成 15/15。手工运行时不应再给完整 Release 设置 15 分钟以内的外层超时。

## 6. 实现、时序、功耗和 GUI 复现

最终从 clean source 运行 `AreaOptimized_high / flatten full / resource sharing on / opt_design Default`。综合为 453 LUT/433 FF，post-route 为 424 LUT/431 FF/169 Slice。WNS/WHS 为 +45.042/+0.080 ns，TNS/THS 均为 0；AD9708 setup/hold 为 +76.116/+78.117 ns。mode bus-skew 约束 50 ns，实测 2.000 ns；最大绝对数据延迟 1.053 ns。route error=0，既有 CDC-13/CDC-15 专用 BUFGMUX 与 bundled-data waiver 计数没有漂移。

普通 Vivado 工程另从 `reset_run synth_1` 开始，以 `-jobs 4` 执行 `synth_1/impl_1 -> write_bitstream`，约 152 秒完成并输出：

```text
GUI_LUT=424
GUI_FF=431
GUI_DSP=4
GUI_BRAM18=4
GUI_MMCM=2
NATIONAL_FINALS_GUI_IMPLEMENTATION_PASS
```

因此用户手动打开 `XC7A35T_interp.xpr` 后使用 4 jobs，可复现同一结构；不要把 jobs 调回 19，否则本机可能因内存压力出现 opt/route 长时间无进展。

## 7. 复现命令

Release RTL：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  .\matlab_fir\national_finals\sim\run_national_finals_rtl_regression.ps1 `
  -RegressionScale Release -CicIntegratorDspMode 2
```

批处理综合、实现和 bitstream：

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File `
  .\matlab_fir\national_finals\vivado\run_national_finals_vivado_build.ps1 `
  -Step all -SynthesisDirective AreaOptimized_high `
  -FlattenHierarchy full -ResourceSharing on `
  -ImplementationOptDirective Default `
  -Stage1Dsp48Preadder 1 -CicIntegratorDspMode 2 `
  -P3JointStage3 1 -Stage1SingleBram 1 -Stage23UnifiedBram 1 `
  -ResultTag p3j_final_424lut_431ff_169slice_4dsp_2bram_packedrom
```

GUI 工程配置与重建：

```powershell
vivado -mode batch -source .\matlab_fir\national_finals\vivado\configure_national_finals_gui_project.tcl
vivado -mode batch -source .\matlab_fir\national_finals\vivado\verify_national_finals_gui_project.tcl -tclargs rebuild
```

## 8. Git 回退路线

- 分支：`national-finals-p3j-4dsp-bram-microengine`
- 前一稳定标签：`nf-p3j-final-430lut-431ff-176slice-4dsp-2bram-reproducible`
- 本轮源码提交：`a6be164`；发布证据脚本提交：`785eb61`
- 本轮最终标签：`nf-p3j-final-424lut-431ff-169slice-4dsp-2bram-packedrom`

本轮没有使用含 `codex` 的分支名、提交名或标签名。
