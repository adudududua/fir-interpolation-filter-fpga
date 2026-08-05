# P3-O 361-LUT ExploreWithRemap 优化执行反馈

## 1. 结论与发布口径

本轮从已完成物理板 DAC 与各档采样率验证的 P3-M 正式标签
`nf-p3m-final-368lut-386ff-156slice-4dsp-2bram-boardverified` 出发，逐文件确认
`sources_1/new` 与 `sim_1/new` 均未混入 P3-N 实验 RTL，再建立独立分支
`national-finals-p3o-355to362-target`。

最终不改动滤波 RTL、系数、位宽、舍入、饱和、valid 时序、时钟或板级接口，
只把 `opt_design` 指令从 `Default` 改为 `ExploreWithRemap`。完整板级布局布线结果为：

| 版本 | LUT | FF | Slice | DSP | RAMB18 / Tile | MMCM | WNS/WHS | 功耗（总/动态/静态） |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| P3-M 板测基线，Default | 368 | 386 | 156 | 4 | 4 / 2.0 | 2 | +44.836/+0.117 ns | 0.271/0.199/0.072 W |
| **P3-O，ExploreWithRemap** | **361** | **386** | **158** | **4** | **4 / 2.0** | **2** | **+44.989/+0.103 ns** | **0.271/0.199/0.072 W** |

P3-O 相对 P3-M 减少 **7 LUT**，FF、DSP、BRAM、MMCM和功耗不增加；Slice增加2，
hold余量减少0.014 ns但仍为正，setup余量增加0.153 ns。它达到用户要求的
`355～362 LUT / 4 DSP / 2 BRAM` 目标区间。

当前口径是**工具完整签核候选**。P3-O 的逻辑功能与已板测 P3-M 相同，但新的物理布局
和 bitstream 仍需用户下载实测后，才能把标签从 `toolverified` 升级为 `boardverified`；
在此之前，P3-M 仍是物理板安全回退。

## 2. 为什么只改实现策略也能少 7 LUT

P3-M 综合后为 395 LUT / 388 FF，`Default` 的 `opt_design`、放置和物理映射把它收敛到
368 LUT / 386 FF。`ExploreWithRemap` 在同一综合网表上额外搜索等价的布尔重映射和跨层
LUT 合并，使若干原本分离的组合逻辑可以装入更少的物理 LUT；滤波器状态机和寄存器没有
变化，所以FF仍为386，DSP与RAM原语数量也完全相同。

该收益是实现工具对完整网表的全局映射结果，不对应删除7行RTL，也不能用综合LUT直接预测。
因此正式统计只采用 `utilization_placed.rpt` 的 routed/placed 口径，并用 routed DCP 继续做
DAC 与采样率仿真。策略扫描实测为：

| 同一 395-LUT 综合 DCP | Routed LUT | FF | Slice | WNS/WHS | 判定 |
|---|---:|---:|---:|---:|---|
| Default | 368 | 386 | 156 | +44.836/+0.117 ns | 可复现板测基线 |
| Explore | 368 | 386 | 156 | +44.836/+0.117 ns | 无收益 |
| **ExploreWithRemap** | **361** | **386** | **158** | **+44.989/+0.103 ns** | **Go，首次进入目标区间** |

达到目标后没有继续用高风险 RTL 改写 CIC 舍入/饱和、DAC mux 或 Stage2/3 地址控制，
也没有为追求更低数字重复扫描已知容易增加LUT或只压Slice的策略。原因是这些修改会改变
位真值或板级控制风险，而本轮目标已经用不改RTL的方式达到；继续改写不符合风险收益比。

## 3. 参数与基线真实性核对

从当前源码重新综合得到 **395 LUT / 388 FF / 4 DSP / 2 BRAM Tile**。综合 provenance 和
`synth_1/runme.log` 同时确认以下参数实际绑定，没有复用错误DCP：

```text
USE_NATIONAL_FINALS_STAGE1_DSP48_PREADDER=1
USE_NATIONAL_FINALS_CIC_INTEGRATOR_DSP_MODE=2
USE_NATIONAL_FINALS_P3_JOINT_STAGE3=1
USE_NATIONAL_FINALS_SINGLE_BRAM_STAGE1=1
USE_PHASE7_UNIFIED_BRAM_STAGE23_HISTORY=1
```

最终原语为4个DSP48E1、4个RAMB18E1和2个MMCME2_ADV。路由状态为984/984个可布线网络
全部完成、routing error=0；1407个setup端点和1405个hold端点均无失败。

## 4. Release RTL 回归

最终源码运行目录为：

`matlab_fir/national_finals/_work/rtl_regression/20260805_172537`

结果为 **17/17 PASS**，不是只检查仿真能否结束：

- 行为RAM与真实UNISIM `RAMB18E1` 两套Stage1模型各比较1400个输出，均0 LSB；
- Stage2/3统一历史BRAM、系数BRAM原语、DAC offset-binary、ROM和键盘均通过；
- N3 Hold CIC覆盖连续输入、随机 `ce_out` 停顿、10个随机种子和burst中复位；
- 全链路覆盖冲激、10个固定seed×4096、正/负满量程和997 Hz/−1 dBFS强信号；
- 14组输入的4x/8x/128x均逐样本 **0 LSB**，最长每组比较531584个128x输出；
- 8类内部状态复位场景各比较4096个128x输出；
- 1x/4x/8x/128x共10次不停机动态切档，边沿严格为32/128/256/4096，
  DAC数据持续变化，无X、无runt pulse；
- 模式CDC覆盖1200次原子事务，双MMCM覆盖100次无毛刺切换。

## 5. 布线后 DAC 与采样率门禁

默认44.1 kHz/128x routed-DCP启动仿真运行6 ms，得到：

```text
edges=11290
data_changes=7461
final_data=64
beep_io=1
BOARD POSTROUTE DAC ACTIVITY PASS
```

公开矩阵按键级六模式测试不force内部模式，真实经过扫描、消抖、CDC静音、MMCM/BUFGMUX、
ROM、插值链、DAC寄存器和ODDR。完整140 ms网表仿真结果为：

| 输入族 / 节点 | DAC edges/ms | data changes/ms | 结论 |
|---|---:|---:|---|
| 44.1 kHz / 4x | 177 | 175 | PASS |
| 44.1 kHz / 8x | 353 | 342 | PASS |
| 44.1 kHz / 128x | 5645 | 3709 | PASS |
| 48 kHz / 4x | 192 | 192 | PASS |
| 48 kHz / 8x | 384 | 372 | PASS |
| 48 kHz / 128x | 6144 | 3810 | PASS |

`177 edges/ms` 是176.4 kHz在1 ms整数计数窗中的量化结果，不表示设计频率变成177 kHz。
正式发布DCP运行目录分别为 `_work/postroute_dac_activity/20260805_182536` 与
`_work/postroute_six_mode_dac/20260805_182648`。此前候选DCP的六模式第一次在第4档后被外层15分钟命令
超时终止；复用同一编译快照并放宽超时后完整重跑，六档全部通过，功能本身没有超时错误。

## 6. 频响、Timing、功耗与物理检查

因为P3-O不改RTL和系数，六工况指标逐位继承已签核P3-M：

| 输入 | 节点 | 通带最大绝对偏差 | 峰峰纹波 | 阻带衰减 | 对称误差 |
|---:|---:|---:|---:|---:|---:|
| 44.1 kHz | 4x | 0.003022 dB | 0.005709 dB | 78.568 dB | 0 LSB |
| 44.1 kHz | 8x | 0.003521 dB | 0.006192 dB | 78.609 dB | 0 LSB |
| 44.1 kHz | 128x | 0.007730 dB | 0.005848 dB | 72.371 dB | 0 LSB |
| 48 kHz | 4x | 0.003022 dB | 0.005709 dB | 78.568 dB | 0 LSB |
| 48 kHz | 8x | 0.003007 dB | 0.005678 dB | 78.609 dB | 0 LSB |
| 48 kHz | 128x | 0.007606 dB | 0.005724 dB | 72.371 dB | 0 LSB |

- WNS/TNS：`+44.989 ns / 0 ns`；WHS/THS：`+0.103 ns / 0 ns`；
- AD9708 output setup/hold：`+76.116/+78.117 ns`；
- `check_timing`：无no-clock、constant-clock或unconstrained internal endpoint；
- DRC：0 Error，保留7条DSP输入pipeline Warning、2条PREG Warning和1条Advisory；
- CDC：计数与P3-M一致，保留BUFGMUX专用选择与握手结构的既有审计项；
- vectorless功耗：总/动态/静态 `0.271/0.199/0.072 W`，Medium confidence。

Bitstream SHA-256：
`A64D5817BB08841BF1ADB10E291F3533C3E2BEB7B898133AD334E61B3A153E6C`

Routed DCP SHA-256：
`1754F3395FA5293BB564B0F3D33EE59DC1804054570E19A30D00E24EEC77B0D6`

## 7. 普通 GUI 与脚本复现

以下入口均已把正式实现默认值改为 `ExploreWithRemap`：

- `vivado/run_national_finals_vivado_build.ps1`；
- `vivado/build_national_finals_board.tcl`；
- `vivado/implement_national_finals_single_process.tcl`；
- `vivado/configure_national_finals_gui_project.tcl`；
- `vivado/verify_national_finals_gui_project.tcl`。

GUI签核门槛收紧为 `LUT<=362 / FF<=400 / DSP=4 / RAMB18E1=4 / MMCM=2`，防止普通
实现静默回到368-LUT Default或错误的8-DSP参数。命令行从零复现可用：

```powershell
powershell -ExecutionPolicy Bypass -File `
  .\matlab_fir\national_finals\vivado\run_national_finals_vivado_build.ps1 `
  -Step all -ResultTag p3o_final_361lut_386ff_4dsp_2bram
```

GUI从零签核可在Vivado Tcl Console中执行：

```tcl
source matlab_fir/national_finals/vivado/configure_national_finals_gui_project.tcl
source matlab_fir/national_finals/vivado/verify_national_finals_gui_project.tcl rebuild
```

2026-08-05 已实际执行上述 `rebuild`，不是只做配置检查。普通工程从零完成
`synth_1 -> impl_1 -> write_bitstream`，约127秒结束，0 Error，并再次报告
`GUI_LUT=361 / GUI_FF=386 / GUI_DSP=4 / GUI_BRAM18=4 / GUI_MMCM=2`，最终输出
`NATIONAL_FINALS_GUI_IMPLEMENTATION_PASS`。完整日志已归档到正式结果目录的
`gui_rebuild.log`。因此用户在GUI中手动运行时无需额外修改generic或实现指令；建议并行
jobs保持为4。

所有Vivado/XSim临时日志继续写入 `matlab_fir/national_finals/_work`，不会写到仓库根目录。

## 8. Git回退与板测待办

- 当前分支：`national-finals-p3o-355to362-target`；
- 工具签核标签：`nf-p3o-toolverified-361lut-386ff-158slice-4dsp-2bram`；
- 物理板回退：`nf-p3m-final-368lut-386ff-156slice-4dsp-2bram-boardverified`。

正式证据目录为
`matlab_fir/national_finals/vivado_results/p3o_final_361lut_386ff_4dsp_2bram`，其中包含
bitstream、routed DCP、资源/Timing/功耗/DRC/CDC报告、17项RTL回归的关键XSim日志、
两项routed-DCP DAC日志及普通GUI从零重建日志。

用户板测只需确认：下载P3-O bitstream后DAC有正常波形，44.1/48 kHz下1x/4x/8x/128x
边沿均正确，切换不锁死且无持续128直流码。通过后再增加`boardverified`标签；工具侧不会虚构
物理仪器结论。
