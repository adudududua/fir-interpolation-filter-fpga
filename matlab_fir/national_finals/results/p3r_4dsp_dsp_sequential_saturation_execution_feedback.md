# P3-R 4-DSP 联合调度优化执行反馈

## 1. 结论与发布状态

P3-R 在不增加乘法器和存储器的条件下，把全国赛完整板级实现优化到：

| 指标 | P3-O 工具候选 | P3-M 实板版 | P3-R 正式实板版 |
|---|---:|---:|---:|
| LUT | 361 | 368 | **348** |
| FF | 386 | 386 | **386** |
| Slice | 158 | 156 | **154** |
| DSP48E1 | 4 | 4 | **4** |
| RAMB18E1 / BRAM Tile | 4 / 2.0 | 4 / 2.0 | **4 / 2.0** |
| MMCM | 2 | 2 | **2** |
| WNS / WHS | +44.989 / +0.103 ns | +44.836 / +0.117 ns | **+45.200 / +0.121 ns** |
| Vectorless 总/动态/静态功耗 | 0.271/0.199/0.072 W | 0.271/0.199/0.072 W | **0.271/0.199/0.072 W** |
| 物理板 | 待测 | 已通过 | **已通过** |

因此 P3-R 相对 P3-O 再减少 **13 LUT、4 Slice**，相对当前已实板通过的
P3-M 减少 **20 LUT、2 Slice**；FF、DSP、BRAM、MMCM和功耗均不增加。P3-R已经完成
RTL、UNISIM原语、完整链、复位/CDC、布局布线、六模式DAC网表仿真和普通GUI工程从零
生成bitstream的工具闭环。**2026-08-06用户完成物理板验证，确认各档输出采样率正确且
DAC输出波形正常，因此P3-R升级为正式实板通过版；P3-M标签保留为前一安全回退。**

- 分支：`national-finals-p3r-4dsp-joint-optimization`
- 360-LUT中间标签：`nf-p3r-checkpoint-360lut-385ff-4dsp-2bram`
- 348-LUT RTL检查点：`nf-p3r-checkpoint-348lut-386ff-4dsp-2bram`
- 正式工具签核标签：`nf-p3r-final-348lut-386ff-154slice-4dsp-2bram-toolverified`
- 正式实板标签：`nf-p3r-final-348lut-386ff-154slice-4dsp-2bram-boardverified`
- 正式结果：`vivado_results/p3r_348lut_386ff_4dsp_2bram_signedoff`

## 2. 为什么这次 Pattern 方法有效

P3-Q 曾只把宽位符号扩展判断换成DSP48E1的`PATTERNDETECT/PATTERNBDETECT`。虽然
Pattern标志能判断溢出，最终的20/21-bit最大值、最小值和正常值选择仍由Fabric宽mux
完成，而且原本可由Vivado联合折叠的“比较器+饱和mux”被拆开，Stage2/3综合从395 LUT
恶化到414 LUT，所以P3-Q正确地判为No-Go。

P3-R没有重复该结构。Stage2/3共享DSP完成最后一次MAC后，下一空闲拍仍在DSP内部完成
`+16383+CARRYIN`的精确Q15舍入；再下一拍由Pattern端口检查舍入结果高位是否严格等于
目标符号扩展。如果溢出，同一DSP通过C端口把目标位宽的最大值或最小值直接装入PREG；
若未溢出则保留正常结果。固定增加的尾拍结束后才拉高输出valid。这样不仅去掉Fabric
比较器，也去掉宽饱和mux，同时完整保留原有舍入和饱和语义。

该调度成立的前提是Stage2/3串行MAC在两次输入任务之间本来就有足够空闲周期。正式
aligned-CE板级路径不会在尾拍结束前覆盖pending任务；回归中仍保留pending-overwrite
断言，防止以后修改输入节拍时静默破坏这一前提。全国赛参数使用signed-22 Stage2和
signed-21 Stage3专用Pattern配置；源码中的其他宽度保留通用比较回退，不影响正式网表。

## 3. 本轮逐项尝试与停止理由

所有资源均采用同一个XC7A35T完整板级顶层、`AreaOptimized_high`、完整flatten和资源共享
口径；进入实现的候选再使用相同DCP做公平策略扫描。

| 候选 | 综合 LUT/FF | 最佳实现 LUT/FF | 结论 |
|---|---:|---:|---|
| P3-O基线 | 395/388 | 361/386 | 本轮比较基准 |
| 二进制调度器+由当前相位反推pending相位 | 393/385 | 364/约385 | 实现不优，撤销 |
| 仅删除pending相位寄存器 | 389/386 | 362/384 | FF略低但LUT仍高于P3-O，撤销 |
| `{stage,phase,index}` micro-PC | 396/386 | 未实现 | 综合已劣化，停止 |
| 反推pending相位+one-hot家族保护窗 | 388/387 | 360/385 | 首个有效中间回退点 |
| **DSP空闲拍完成舍入、Pattern检查和PREG钳位** | **374/388** | **348/386** | **正式保留** |
| 9-tap补偿Stage3 | 375/388 | 未实现 | MATLAB频响通过但比11-tap正式结构多1综合LUT |
| signed-20 Stage3搜索 | — | — | 80,001个候选均不能同时通过频响与强信号峰值门禁 |
| 3-bit one-hot尾状态改2-bit二进制 | 384/389 | 未实现 | 多10综合LUT、多1 FF，撤销 |
| DSP钳位但Fabric比较高位 | 380/388 | 未实现 | 比Pattern检查多6综合LUT，撤销 |
| P3-Q Pattern-only历史路线 | 414/388 | 未实现 | 保留Fabric饱和mux，破坏联合折叠，No-Go |

失败候选均已恢复；正式两个RTL文件与348-LUT检查点逐字节一致。9-tap候选的六工况最差
绝对通带偏差为0.0198073 dB、阻带72.390 dB，数学上合格但资源没有收益，因此不能仅因
抽头更少就发布。signed-20路线的失败说明当前21-bit Stage3不是未经证明的保守位宽。

## 4. 最终实现策略扫描

以下结果全部来自同一份374-LUT/388-FF综合网表：

| `opt_design`策略 | LUT | FF | Slice | WNS / WHS | 结论 |
|---|---:|---:|---:|---:|---|
| Default | 353 | 386 | 161 | +45.025/+0.077 ns | 可用 |
| AddRemap | 353 | 386 | 161 | +45.025/+0.077 ns | 无额外收益 |
| Explore | 353 | 386 | 161 | +45.025/+0.077 ns | 无额外收益 |
| **ExploreWithRemap** | **348** | **386** | **154** | **+45.200/+0.121 ns** | **正式选择** |
| ExploreArea | 402 | 386 | 159 | +44.812/+0.112 ns | 明显劣化 |

选择ExploreWithRemap不是只看LUT：它同时是最低Slice，并保持正setup/hold裕量。普通GUI
工程及脚本均固定该策略，发布门槛为`LUT<=349 / FF<=400 / DSP=4 / RAMB18E1=4 /
MMCM=2`，可防止手动工程静默采用错误参数或旧资源结果。

## 5. RTL与定点完整回归

最终源码先后完成Smoke和Release两次独立回归，均为 **17/17 PASS**：

- Smoke证据：`_work/rtl_regression/20260805_224819`；
- Release证据：`_work/rtl_regression/20260805_231040`；
- 全链14组输入：冲激、10个固定随机seed、正满量程、负满量程、997 Hz/−1 dBFS；
- 每组4x、8x、128x三个节点逐样本比较均为 **0 LSB**；长用例有效输出数分别为
  `y4=16605 / y8=33219 / y128=531584`；
- Stage1行为RAM与真实RAMB18E1原语各比较1400个输出，均0 LSB；
- Stage2比较336个、Stage3比较671个输出，均0 LSB；
- 统一系数ROM全地址、CIC定向/模边界/随机停顿、DAC offset-binary均通过；
- 8类内部状态复位场景各恢复4096个128x输出；
- 1200次CDC原子采样、100次时钟家族切换、10次动态倍率切换均无X、无runt、无
  pending覆盖。

“综合/实现能跑完”没有被当作功能通过条件。上述测试覆盖了本轮新增尾拍的输出valid
相位、正常值、正/负饱和边界，以及切换和复位发生在运算中间时的恢复行为。

## 6. 六工况频响

本轮没有改系数、有效位宽或量化定义，频响逐点继承已签核Golden；严格线性相位不变。

| 输入家族 | 输出 | 最大绝对通带偏差 | 通带峰峰纹波 | 阻带衰减 |
|---|---:|---:|---:|---:|
| 44.1 kHz | 4x | 0.003022 dB | 0.005709 dB | 78.568 dB |
| 44.1 kHz | 8x | 0.003521 dB | 0.006192 dB | 78.609 dB |
| 44.1 kHz | 128x | 0.007730 dB | 0.005848 dB | 72.371 dB |
| 48 kHz | 4x | 0.003022 dB | 0.005709 dB | 78.568 dB |
| 48 kHz | 8x | 0.003007 dB | 0.005678 dB | 78.609 dB |
| 48 kHz | 128x | 0.007606 dB | 0.005724 dB | 72.371 dB |

六工况均满足通带纹波不超过0.05 dB、阻带至少70 dB的比赛门槛。

## 7. 布局布线、CDC、DAC与GUI闭环

正式结果目录保存bit、routed DCP和全部报告。关键结果如下：

- 综合网表：374 LUT / 388 FF / 4 DSP / 4 RAMB18E1；
- 布局布线：348 LUT / 386 FF / 154 Slice / 4 DSP / 4 RAMB18E1 / 2 MMCM；
- WNS/WHS：+45.200/+0.121 ns；AD9708 setup/hold：+76.116/+78.117 ns；
- route error为0；内部端点无no-clock、constant-clock或unconstrained；
- vectorless总/动态/静态功耗：0.271/0.199/0.072 W（Medium confidence）；
- CDC报告保留已审计的BUFGMUX控制`CDC-13`与bundled-data`CDC-15`警告；对应信号已有
  精确false path、50 ns absolute max-delay与bus-skew约束，不能错误宣称“零CDC警告”；
- 默认档routed-DCP仿真6 ms：11290个DAC边沿、7462次数据变化、终值64、beep关闭；
- 六模式routed-DCP仿真140 ms全部通过：44.1 kHz为`177/353/5645 edges/ms`，
  48 kHz为`192/384/6144 edges/ms`，六档DAC数据持续变化且无X；这里177是1 ms整数
  计数窗对176.4的量化结果，不代表频率被设计成177 kHz；
- 普通Vivado GUI工程从零运行`synth_1 -> impl_1 -> write_bitstream`，再次得到
  348 LUT / 386 FF / 4 DSP / 4 RAMB18E1 / 2 MMCM并成功生成bitstream；
- GUI生成的routed DCP再次通过默认DAC活动测试：11290边沿、7462次变化。

正式bitstream SHA-256：
`FC3B091B493A785E3814D05108E6A39BFF11709BA4DF469399C6D5F52F8D8FE5`

正式routed DCP SHA-256：
`95F0919BC5C107F0F69C3BCFFBEE9E9055A827E5E2E2D307A404F32D5C80403E`

GUI普通工程生成的bit因构建元数据不同，SHA-256为
`A49356DFF16B652CAA42CAE429A51CB92863AEE755747954940AAC17A60D184E`；资源、时序和
功能门禁一致。构建包装器对工程XPR执行字节级备份/恢复，没有覆盖用户已有GUI改动。

## 8. 手动复现与板测建议

从正式标签切出后，可在Vivado 2018.3普通工程中运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\matlab_fir\national_finals\vivado\run_national_finals_vivado_build.ps1
```

完整RTL回归及布局后板级门禁分别为：

```powershell
powershell -ExecutionPolicy Bypass -File .\matlab_fir\national_finals\sim\run_national_finals_rtl_regression.ps1 -Profile Release
powershell -ExecutionPolicy Bypass -File .\matlab_fir\national_finals\sim\run_postroute_board_dac_activity.ps1 -DcpPath .\matlab_fir\national_finals\vivado_results\p3r_348lut_386ff_4dsp_2bram_signedoff\national_finals_board_routed.dcp
powershell -ExecutionPolicy Bypass -File .\matlab_fir\national_finals\sim\run_postroute_six_mode_dac.ps1 -DcpPath .\matlab_fir\national_finals\vivado_results\p3r_348lut_386ff_4dsp_2bram_signedoff\national_finals_board_routed.dcp
```

2026-08-06用户已确认44.1/48 kHz两个家族的4x/8x/128x各档输出采样率均正确、DAC输出
波形正常，P3-R据此升级为正式实板通过版。用户没有提供逐档仪器数值，本文只记录明确
确认的结论，不虚构额外测量数据；后续优化仍必须保留P3-R板测标签和bitstream作为回退。
