# DSP3/LUT239 正式工程清理说明

## 1. 工程定位

本目录是赛题最终交付使用的 Vivado 2025.2 工程，目标器件为
`xc7a35tfgg484-2`，正式配置为 `239 LUT / 3 DSP` 板测版本。

- 工程文件：`XC7A35T_interp.xpr`
- 综合顶层：`board_demo_competition_dac8_top`
- RTL 仿真顶层：`tb_phase7_full_chain_bittrue`
- 正式约束：`XC7A35T_interp.srcs/constrs_1/new/board_demo_competition_dac8_top.xdc`
- CIC 配置：`CIC_INTEGRATOR_DSP_MODE=1`
- 正式配置编号：`NF-P3-STAGE123-24-20-20-3DSP-PARETO-R1`

## 2. 保留内容

清理后只保留以下几类内容：

1. 正式板级顶层及其全部 RTL 依赖；
2. 当前正式约束文件；
3. 当前全链路逐位对拍测试及仍有价值的专项测试；
4. 8 个项目内本地黄金向量，不再依赖原工程外部绝对路径；
5. Vivado 2025.2 正式构建与维护脚本；
6. 已签核的 239-LUT/3-DSP 位流、DCP 和实现报告。
7. 与正式参数一致的独立滤波器核心 OOC 复现脚本，位于
   `tools/vivado_2025_2/core_ooc/`，用于生成 212-LUT/3-DSP 核心证据。

已签核的板测位流、DCP、实现报告和核心 OOC 证据统一位于
`tools/vivado_2025_2/results/active_239lut_3dsp/`。其中位流为：

`board_demo_competition_dac8_top_239lut_3dsp.bit`

SHA-256：

`796844A59E439744082A11CDBD75C4BBAA4538D598B2793310E24E6B2F0401EA`

## 3. 已清理内容

以下内容已从正式工程目录移出：

- v2～v6 旧版本、候选架构和实验顶层；
- 已废弃的旧板级顶层、旧时钟 IP 和旧仿真顶层；
- `national_finals/experiments` 等探索性源码；
- 早期资源、字长、polyphase、accumulator 等实验报告；
- 历史 Vivado/XSim 日志、journal、crash 文件；
- `.Xil`、cache、runs、sim、gen、hw、ip_user_files 等可再生目录；
- 大量旧版 Tcl、PowerShell 和中间构建结果。

清理前约为 2736 个文件、121 MB；完成源码整理后约为 100 个文件、
3.7 MB。最终数字会因 Vivado 再次打开工程而临时生成 cache、runs 等目录。

## 4. 可恢复备份

本次没有不可逆删除历史内容。所有移出的文件均保存在：

`../_cleanup_backup_XC7A35T_interp_DSP3_LUT239_2025.2_20260816/`

如需找回某个历史实验，请只复制明确需要的单个文件；不建议把整个备份目录
重新合并到正式工程，也不要覆盖当前 `.xpr`。

## 5. 清理后验证

- XPR 中登记的 58 个文件引用全部存在，缺失数为 0；
- 35 个保留的 Verilog 源文件通过 Vivado 2025.2 `xvlog` 分析；
- 正式综合顶层通过 XSim 静态展开；
- `tb_phase7_full_chain_bittrue` 仿真顶层通过 XSim 静态展开；
- 仿真展开仅提示 DSP48E1 的未使用级联输出 `ACOUT` 未连接，这是正常的未使用输出；
- 尝试执行 Vivado RTL 综合级验证时，当前 Windows 系统提交内存接近上限，
  Vivado 在装载器件阶段退出；这不是缺少源文件或语法错误。建议重启电脑后只开
  一个 Vivado，再进行完整重构建。

本次清理没有重新生成正式位流；原有签核位流、综合/布局布线 DCP、利用率、
时序、DRC、功耗、CDC 和 bus-skew 报告均已原样保存。

## 6. 使用方法

GUI 使用：用 Vivado 2025.2 打开 `XC7A35T_interp.xpr`，确认顶层为
`board_demo_competition_dac8_top` 后运行综合、实现和生成位流。

命令行完整构建：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\vivado_2025_2\run_full_build_2025_2.ps1 -Jobs 1
```

该工程曾遇到系统提交内存不足，因此建议完整构建时关闭其他 Vivado、MATLAB、
浏览器等大型程序，并保持 Windows 页面文件为“系统管理”或足够大。
