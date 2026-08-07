# P3-U 333-LUT 控制路径深度优化执行反馈

## 1. 结论与版本状态

本轮在已实板通过的 P3-T 基线上继续优化，最终得到完整板级
**333 LUT / 382 FF / 152 Slice / 4 DSP / 4 RAMB18E1（2 BRAM Tile）/ 2 MMCM**。
相对 P3-T 的 `341 LUT / 381 FF / 163 Slice`，减少 **8 LUT 和 11 Slice**，增加
**1 FF**，DSP、BRAM、MMCM、IO、滤波器系数、定点位宽和功耗报告值均不变。

当前分支为 `national-finals-p3u-4dsp-deep-optimization`。P3-U 已完成两轮 RTL
17/17、正式布局布线、时序/DRC/CDC、默认及六档 routed-DCP DAC、普通 GUI 工程从零
综合/实现/bitstream 重建，状态为 **tool-verified**。P3-U 尚未由用户下载到物理板，
因此不能标为 boardverified；最新实板安全回退仍是
`nf-p3t-final-341lut-381ff-163slice-4dsp-2bram-boardverified`。

## 2. 本轮实际采用的两项 RTL 优化

### 2.1 精确 Johnson 键盘消抖

正式参数 `DEBOUNCE_SCANS=5` 原来使用 3-bit 二进制加一器、终值比较器和饱和保持。
P3-U 使用六状态 Johnson 序列：

```text
000 -> 001 -> 011 -> 111 -> 110 -> 100 -> commit
```

它保留原有“候选键连续稳定后才提交”的精确扫描周期、SW1～SW8 映射、行优先级、
按下/释放和抖动行为，但把加一器改为移位与反相反馈。非正式参数值仍保留通用二进制
计数器分支，不破坏模块可复用性。

### 2.2 CDC bundled-data 等待 token

控制域到音频域的原子模式握手原来使用 `transfer_pending` 加二进制倒计数器。
正式 `SETTLE_CYCLES=3` 下，P3-U 改为 one-hot token：

```text
0001 -> 0010 -> 0100 -> 1000 -> capture -> 0000
```

该序列与旧 `3 -> 2 -> 1 -> 0 -> capture` 周期完全一致，保留静音窗口、模式总线稳定期、
请求/应答 toggle、复位后首次捕获和 busy 期间合并最新值的语义，同时删除 pending flag、
二进制减法器和零比较路径。测试仍以 `SETTLE_CYCLES=7` 覆盖参数化长序列。

## 3. 实验路线、资源结果与停止线

本轮不是只运行一个实现策略。所有结构候选均先做定向 RTL，再综合；只有达到资源停止线的
候选才进入完整实现。

| 路线 | 综合 LUT/FF | 最佳实现 LUT/FF/Slice | 结论 |
|---|---:|---:|---|
| P3-T 实板基线 | 367/383 | 341/381/163 | 安全起点 |
| 同一 P3-T 网表策略扫描 | — | 337/381/146 | 仅策略收益，不是最终结构 |
| CIC 最终量化器 29→20 bit | 373/— | — | 比基线多 LUT，No-Go |
| DSP Pattern 量化助手 | — | — | 需要复制 29-bit next-state 加法或改变延迟，No-Go |
| Stage1 tail-pipe | 363/381 | 335/379/151 | LUT 不优且 Slice 增加，No-Go |
| 键盘 one-hot-only 扫描 | 368/— | — | 比 Johnson 路线差，No-Go |
| Johnson 精确消抖 | 366/383 | 335/381/143 | 有效，保留 |
| CDC ring counter | 364/383 | 337/—（Default）/347（EWR） | 实现打包变差，撤销 |
| **Johnson + CDC shift token** | **365/384** | **333/382/152** | **当前最优，保留** |
| 顶层共享 tick 边沿检测 | 367/386 | 334/384/146 | 多 1 LUT/2 FF，No-Go |
| CDC rotated phase | 363/383 | 334/381/152（Default）/344（EWR） | 综合好但实现差，撤销 |
| ResourceSharing auto | 365/384 | — | 与 on 完全相同 |
| AreaOptimized_medium | 369/384 | — | 综合多 4 LUT，停止 |
| EWR + ExtraTimingOpt | — | 340/382/154 | GUI 默认曾误用，劣于 Explore |
| Default + Explore | — | 337/382/151 | 劣于 EWR + Explore |
| EWR + ExtraPostPlacementOpt | — | 333/382/152 | 与 Explore 无差异 |
| **EWR + Explore** | **365/384** | **333/382/152** | **正式实现策略** |

CDC rotated-phase 的首次 generate 写法还导致 XDC 层级目标名改变；改为扁平寄存器后约束恢复，
但资源仍不优。该问题没有通过删约束规避，而是修复层级后重新综合/实现再判 No-Go。

## 4. 六工况频响与相位

P3-U 只改变键盘消抖、模式 CDC 的等待编码和实现布局策略；滤波数据通路逐位未变，Release
又证明 14 组输入在 4x/8x/128x 所有节点均为 0 LSB。因此继承已签核的六工况频响：

| 输入家族 | 输出 | 最大绝对通带偏差 | 通带峰峰纹波 | 阻带衰减 |
|---|---:|---:|---:|---:|
| 44.1 kHz | 4x | 0.003022 dB | 0.005709 dB | 78.568 dB |
| 44.1 kHz | 8x | 0.003521 dB | 0.006192 dB | 78.609 dB |
| 44.1 kHz | 128x | 0.007730 dB | 0.005848 dB | 72.371 dB |
| 48 kHz | 4x | 0.003022 dB | 0.005709 dB | 78.568 dB |
| 48 kHz | 8x | 0.003007 dB | 0.005678 dB | 78.609 dB |
| 48 kHz | 128x | 0.007606 dB | 0.005724 dB | 72.371 dB |

六工况均满足通带纹波不超过 0.05 dB、阻带至少 70 dB和严格线性相位；冲激对称误差为
0 LSB。44.1 kHz 的 1 ms 门级计数显示 177/353/5645 是整数窗口计数，设计标称频率仍为
176.4/352.8/5644.8 kHz。

## 5. RTL 完整签核

Smoke 和 Release 均为 **17/17 PASS**。Release 覆盖：

- 完整链：冲激、10 个固定随机种子、正/负满量程、强 −1 dBFS，共 14 组；
- 4x/8x/128x 每个内部签核节点均逐样本 0 LSB；
- Stage1 行为 RAM 与真实 RAMB18E1 各 1400 输出 0 LSB；
- 历史 RAMB18E1 全地址扫描与 5000 个随机地址；
- 统一 FIR 系数 RAMB18E1 的 32 个 Stage1 和 128 个 Stage2/3 地址；
- N3 Hold CIC 的连续、停顿、10×256 随机和 burst 中复位；
- 8 类全链内部状态复位恢复，每类比较 4096 个 128x 输出；
- 1200 次 CDC 定向事务：原子提交、bundled data 稳定、每请求一次 ACK；
- 100 次双 MMCM 家族切换脉宽压力；
- 10 次不复位动态倍率切换，无 runt pulse、无 X；
- SW1～SW8 按键、抖动、行优先级和完整板级控制集成。

正式日志位于结果目录中的 `rtl_smoke_*_xsim.log` 与 `rtl_release_*_xsim.log`，不以单纯
“仿真进程退出 0”代替逐样本 PASS 标记。

## 6. 综合、实现、Timing、DRC/CDC 与功耗

| 项目 | P3-T 实板版 | P3-U 工具签核版 | 变化 |
|---|---:|---:|---:|
| LUT | 341 | **333** | **−8** |
| FF | 381 | **382** | +1 |
| Slice | 163 | **152** | **−11** |
| DSP48E1 | 4 | **4** | 0 |
| RAMB18E1 / BRAM Tile | 4 / 2 | **4 / 2** | 0 |
| MMCM | 2 | **2** | 0 |
| WNS/WHS | +45.270/+0.107 ns | **+45.704/+0.079 ns** | 均通过 |
| 总/动态/静态功耗 | 0.271/0.199/0.072 W | **0.271/0.199/0.072 W** | 报告精度下不变 |

P3-U 综合为 365 LUT / 384 FF / 4 DSP / 4 RAMB18E1；正式实现使用
`AreaOptimized_high / full / resource sharing on + ExploreWithRemap + Explore`。
TNS/THS 均为 0，失败端点为 0，987/987 个可布线网络完成，route error 为 0；AD9708
最差 setup/hold 为 `+76.116/+78.117 ns`。

DRC 无 Error，保留 9 项 DPIP、2 项 DPOP 和 1 项 AVAL Advisory，均为低面积串行 DSP
故意不增加输入/输出流水级的性能建议；当前时序裕量充分。CDC 的 `CDC-13 ×2` 对应
BUFGMUX 非 FD 选钟端，`CDC-15 ×4` 对应有 max-delay/bus-skew 约束的原子模式总线；
1200 次握手和六档门级切族提供功能证据。方法学 `TIMING-18 ×8` 是 DAC 数据相对两路
可选 DAC 时钟的通用提示，专用 AD9708 setup/hold 报告已对两个时钟族分别签核。

功耗为无 SAIF 的 vectorless 估计，不能把 0.001 W 量级差异解释为实板功耗改善。

## 7. 布局布线后 DAC 与六档测试

同一个正式 routed DCP 的默认上电测试在 6 ms 内得到：

```text
DAC edges        = 11290
DAC data changes = 7462
final data       = 64
```

六档公开按键级门级测试为：

| 家族/档位 | edges/ms | DAC 数据变化次数 |
|---|---:|---:|
| 44.1 kHz / 4x | 177 | 175 |
| 44.1 kHz / 8x | 353 | 342 |
| 44.1 kHz / 128x | 5645 | 3710 |
| 48 kHz / 4x | 192 | 192 |
| 48 kHz / 8x | 384 | 372 |
| 48 kHz / 128x | 6144 | 3810 |

六档均有正确的 DAC 时钟边沿数和持续数据变化，排除了综合/实现后 ROM 地址锁死、DAC
静态输出、切族丢请求和模式未提交等已知风险。

## 8. GUI 手动构建可复现性

最初把 GUI 的 place directive 保持在 P3-T 的 `ExtraTimingOpt` 时，干净实现得到 340 LUT，
不是 333 LUT。这是“脚本报告与手动 GUI 不一致”的直接原因。本轮已同步修正 XPR、配置、
构建、打开和验证脚本为 `ExploreWithRemap + Explore`。

随后对普通工程执行 `reset_run synth_1`，再从零运行 `synth_1` 和
`impl_1 -to_step write_bitstream`，得到：

```text
GUI_LUT=333
GUI_FF=382
GUI_DSP=4
GUI_BRAM18=4
GUI_MMCM=2
GUI_PLACE_DIRECTIVE=Explore
NATIONAL_FINALS_GUI_IMPLEMENTATION_PASS
```

GUI 生成的 bitstream 成功，正式 timing report 同样为 WNS/WHS `+45.704/+0.079 ns`。
用户手动运行前应关闭所有旧 Vivado 窗口，再运行
`matlab_fir/national_finals/vivado/open_national_finals_gui_clean.ps1`，防止旧内存工程保存时
覆盖 XPR 策略。

## 9. 正式文件、哈希与下一步

正式目录：
`matlab_fir/national_finals/vivado_results/p3u_333lut_382ff_4dsp_2bram_signedoff`

```text
signed-off bit SHA-256 = F9B670CEF444B4C60D66AF1898FC57F3BAB9C66BFDAF14E7D2E2BA8CD526C688
routed DCP SHA-256     = 75D2D8C9865A8952051102DC35BD188A9D7AE175F20B25FB256B8B108CEBB57C
GUI rebuild bit SHA-256= 7436FF2A7954CC1CDFDBE82CC06625BA9E450F1484873979FFF81689D750217C
```

两个 bitstream 的哈希不同是 bit 文件构建时间/运行路径元数据造成的正常现象；两条路径的
资源、原语计数、实现策略和 Timing 一致。

下一步应由用户下载 P3-U bitstream，逐一确认 44.1/48 kHz 的 4x/8x/128x 采样率及 DAC
波形。只有板测通过后，才把标签从 `toolverified` 升级为 `boardverified`；板测前任何异常
均可直接回退到 P3-T 板测标签。
