# P3-T Stage1 DSP尾周期饱和与派生指针 341-LUT 执行反馈

## 1. 结论与发布边界

本轮从已完成实板验证的P3-S `343 LUT / 386 FF / 4 DSP / 2 BRAM Tile`标签出发，保持
4 DSP、2 BRAM Tile、2 MMCM、系数、定点语义、接口和六档采样率不变，继续压缩Stage1。
最终工具签核结果为：

| 指标 | P3-S实板基线 | P3-T工具候选 | 变化 |
|---|---:|---:|---:|
| 综合LUT | 374 | **367** | **-7** |
| 综合FF | 388 | **383** | **-5** |
| 布局布线LUT | 343 | **341** | **-2** |
| 布局布线FF | 386 | **381** | **-5** |
| Slice | 151 | **163** | +12 |
| DSP48E1 | 4 | **4** | 0 |
| RAMB18E1 / BRAM Tile | 4 / 2.0 | **4 / 2.0** | 0 |
| MMCM | 2 | **2** | 0 |
| WNS / WHS | +45.025/+0.116 ns | **+45.270/+0.107 ns** | Timing通过 |
| AD9708 setup / hold | +76.116/+78.117 ns | **+76.116/+78.117 ns** | 0 |
| 总/动态/静态功耗 | 0.271/0.199/0.072 W | **0.271/0.199/0.072 W** | 0 |

P3-T降低了LUT和FF，但Slice比P3-S增加12个，因此它是“LUT/FF优先”的新Pareto点，并非
每一项资源都支配P3-S。它已完成RTL、真实UNISIM原语、完整链、复位/CDC、综合实现、
Timing/Power、默认及六模式routed-DCP DAC、GUI重实现和bitstream闭环。**当前只能标记为
tool-verified；物理板六档采样率和DAC波形尚待用户验证。板测前，P3-S仍是正式发布和安全
回退。**

- 分支：`national-finals-p3t-341lut-stage1-dsp-tail`
- 工具签核标签：`nf-p3t-final-341lut-381ff-163slice-4dsp-2bram-toolverified`
- 正式结果：`vivado_results/p3t_341lut_381ff_4dsp_2bram_signedoff`

## 2. 最终优化方法

### 2.1 用稳定写指针派生Stage1历史基址

原Stage1在接受输入时同时保存`wr_ptr`与6-bit `base_ptr`。串行52-tap计算期间`wr_ptr`
保持稳定，因此本轮以`wr_ptr-1`严格派生历史基址，删除独立的6-bit基址寄存器及其相关
控制。行为RAM与真实RAMB18E1原语对拍均为1400个输出、0 LSB，证明环回、启动填充、
复位与调度边界不变。

### 2.2 让Stage1已有DSP48E1接管舍入、溢出检测与饱和钳位

Stage1串行MAC完成后仍有空闲尾周期。本轮复用已有DSP48E1，而不增加DSP：

1. 第一尾周期在DSP PREG中执行原有精确Q15对称舍入；
2. 用`PATTERNDETECT/PATTERNBDETECT`检查舍入结果高位是否为合法符号扩展；
3. 若溢出，下一尾周期通过C端口把按Q15缩放的正/负极限直接装入PREG；
4. 输出端只保留固定切片，删除Fabric中的宽符号扩展比较器与宽饱和mux；
5. 非全国赛参数宽度仍保留原通用Fabric回退，不改变模块的通用语义。

这与此前P3-Q“只把Pattern标志拉出DSP、Fabric仍保留饱和mux”的失败结构不同。P3-T让
DSP真正生成最终钳位值，才能移除Fabric宽选择路径。单独DSP尾周期版本综合为371 LUT；
与派生指针组合后综合进一步降至367 LUT，完整route收敛到341 LUT。

## 3. 本轮候选矩阵与Stop/Go结果

| 候选 | 关键结果 | 结论 |
|---|---|---|
| CIC寄存器拆分 | 综合405 LUT / 409 FF | 明显劣化，撤销 |
| CIC hold预装/首样本mux | 第31个输出起失配 | 功能失败，撤销 |
| Stage2/3紧凑状态 | 综合371/384，实现最好350/382 | 不优于343基线，撤销 |
| Stage2/3锁存预取 | 综合379/389 | 撤销 |
| Stage2/3边界复用 | 综合374/388，实现344/386 | LUT仍高于基线，撤销 |
| 工具策略小矩阵 | ExtraTimingOpt最好353 LUT | 不优于P3-S固定流程 |
| Stage1仅派生基址 | 综合374/382，实现344/380 | FF Pareto但LUT不优，未发布 |
| Stage1调度末更新指针 | 综合380/382 | 撤销 |
| Stage1哨兵指针 | 综合383/382 | 撤销 |
| Stage1双地址游标 | 综合395/394 | 撤销 |
| Stage1仅DSP尾周期饱和 | 综合371/389，实现344/387 | 方向有效但未胜基线 |
| **DSP尾周期饱和 + 派生基址** | **综合367/383，实现341/381** | **最终保留** |

所有失败候选均在独立资源或功能门槛处停止，并已从正式RTL撤销；发布分支只保留最后一行。

## 4. RTL与定点回归

同一份最终源码从零运行Smoke与Release，两轮均为 **17/17 PASS**：

- Smoke：`_work/rtl_regression/20260806_153535`；
- Release：`_work/rtl_regression/20260806_154315`；
- Stage1行为RAM和真实RAMB18E1各1400输出，均为 **0 LSB**；
- 全链14组覆盖冲激、10个固定seed、正/负满量程和强−1 dBFS信号；
- 4x/8x/128x逐样本最大误差均为 **0 LSB**；
- 长用例输出数为`16605 / 33219 / 531584`；
- 8类内部状态复位各比较4096个128x输出并全部通过；
- CIC连续、随机停顿和突发中复位，1200次原子CDC、100次时钟族切换、10次动态倍率切换
  全部通过，无X、runt pulse或pending覆盖；
- 真实历史RAMB18E1、统一系数RAMB18E1、DAC offset-binary和板级键盘路径均通过。

正式结果目录保存Smoke/Release各17份XSim日志，不以“仿真运行结束”代替逐样本对拍。

## 5. 六工况频响

P3-T不修改系数、字长和定点传递函数，严格继承已签核频响：

| 输入家族 | 输出 | 最大绝对通带偏差 | 通带峰峰纹波 | 阻带衰减 |
|---|---:|---:|---:|---:|
| 44.1 kHz | 4x | 0.003022 dB | 0.005709 dB | 78.568 dB |
| 44.1 kHz | 8x | 0.003521 dB | 0.006192 dB | 78.609 dB |
| 44.1 kHz | 128x | 0.007730 dB | 0.005848 dB | 72.371 dB |
| 48 kHz | 4x | 0.003022 dB | 0.005709 dB | 78.568 dB |
| 48 kHz | 8x | 0.003007 dB | 0.005678 dB | 78.609 dB |
| 48 kHz | 128x | 0.007606 dB | 0.005724 dB | 72.371 dB |

六工况均满足通带纹波不超过0.05 dB、阻带衰减至少70 dB，并保持严格线性相位。

## 6. 实现、DAC与GUI闭环

- 综合：367 LUT / 383 FF / 4 DSP48E1 / 4 RAMB18E1；
- 正式route：341 LUT（340 Logic + 1 SRL）/ 381 FF / 163 Slice / 4 DSP / 2 BRAM Tile；
- WNS/WHS=`+45.270/+0.107 ns`，TNS/THS=0；
- AD9708最差setup/hold=`+76.116/+78.117 ns`；
- route为0个布线错误；DRC无Error，仅有9项DPIP、2项DPOP流水建议和1项AVAL Advisory，
  均为低资源串行DSP结构的已知性能建议，不影响当前正时序裕量；
- vectorless总/动态/静态功耗=`0.271/0.199/0.072 W`（Medium confidence）；
- 默认routed-DCP 6 ms：11290个DAC边沿、7462次数据变化、终值64、beep无效；
- 六档routed-DCP：44.1 kHz为`177/353/5645 edges/ms`，48 kHz为
  `192/384/6144 edges/ms`，六档均有持续数据变化；
- GUI `reimplement -> write_bitstream`再次得到341/381/4-DSP/4-RAMB18/2-MMCM。

首次GUI检查遇到Vivado 2018.3的`wait_on_run`竞态：外部实现子进程仍在route/write_bitstream
时，Tcl已返回并把中间状态误判为失败；后台实际随后成功写出bit。验证脚本现循环检查持久化
`PROGRESS/STATUS`直到100%、真实失败或超时，随后重跑`reimplement`通过。GUI发布门槛同步
收紧为`LUT<=342 / FF<=390 / DSP=4 / RAMB18E1=4 / MMCM=2`，可防止手动工程静默使用旧
P3-S/P3-R结果。

bitstream SHA-256：
`5AC1C621941FC5207B85CAE225037E2A99A8676852A30E93C0DCACFE8B47C098`

routed DCP SHA-256：
`6426D844217E58F7BA1CABA125737FF82CA1FA14D84DCD113AE7064CF77F400B`

## 7. 手动复现与板测

```powershell
powershell -ExecutionPolicy Bypass -File .\matlab_fir\national_finals\vivado\open_national_finals_gui_clean.ps1
powershell -ExecutionPolicy Bypass -File .\matlab_fir\national_finals\vivado\run_national_finals_vivado_build.ps1 -Step all -ResultTag p3t_manual_rebuild
powershell -ExecutionPolicy Bypass -File .\matlab_fir\national_finals\sim\run_national_finals_rtl_regression.ps1 -RegressionScale Release
powershell -ExecutionPolicy Bypass -File .\matlab_fir\national_finals\sim\run_postroute_board_dac_activity.ps1 -DcpPath .\matlab_fir\national_finals\vivado_results\p3t_341lut_381ff_4dsp_2bram_signedoff\national_finals_board_routed.dcp
powershell -ExecutionPolicy Bypass -File .\matlab_fir\national_finals\sim\run_postroute_six_mode_dac.ps1 -DcpPath .\matlab_fir\national_finals\vivado_results\p3t_341lut_381ff_4dsp_2bram_signedoff\national_finals_board_routed.dcp
```

板测必须使用签核目录内bit，依次检查44.1/48 kHz下4x/8x/128x六档实际采样率与DAC波形。
在用户确认六档全部正常前，P3-T不能打`boardverified`标签；遇到任何异常应直接切回已板测的
P3-S标签。
