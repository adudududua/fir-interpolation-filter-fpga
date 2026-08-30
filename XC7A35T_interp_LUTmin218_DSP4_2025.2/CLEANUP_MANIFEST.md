# 218-LUT/4-DSP 正式工程清理说明

## 1. 工程定位

本目录已整理为赛题正式交付使用的 Vivado 2025.2 工程，器件为
`xc7a35tfgg484-2`，正式配置为 **218 LUT / 365 FF / 4 DSP48E1**。

- 工程文件：`XC7A35T_interp.xpr`
- 综合顶层：`board_demo_competition_dac8_top`
- RTL 仿真顶层：`tb_phase7_full_chain_bittrue`
- 滤波器核心顶层：`interp128_all2x_v7_folded_fir_cic_top_ce`
- 正式约束：`XC7A35T_interp.srcs/constrs_1/new/board_demo_competition_dac8_top.xdc`
- 定点字长：Stage1/Stage2/Stage3 = `24/20/20 bit`
- CIC 积分器映射：`CIC_INTEGRATOR_DSP_MODE=2`
- 正式实板标签：`nf-vivado2025.2-218lut-365ff-4dsp-2bram-24-20-20-board-pass`

该目录是纯滤波器板级演示工程，不包含百兆以太网上位机功能；网络测量功能位于
另一个专用工程 `XC7A35T_interp_LUTmin_df`。

## 2. 清理结果

清理前原目录共有 **2716 个文件、434 个目录、121.55 MB**，其中包含大量历史
候选模块、旧报告、Vivado 可再生目录、日志和中间产物。整理后只保留：

1. 正式板级顶层及全部实际 RTL 依赖；
2. 当前正式 XDC 约束；
3. 全链路逐位对拍和仍有价值的专项测试；
4. 8 个项目内本地黄金向量；
5. Vivado 2025.2 构建、工程修复和低内存脚本；
6. 218-LUT/4-DSP 板测位流、DCP、核心 OOC 和完整板级报告；
7. 统一为 Vivado 2025.2 口径的详细中文 Verilog 文件头和代码注释。

补回正式核心 OOC 一键复现入口后，精简基线为 **115 个文件、24 个目录、约
5.25 MB**。后续打开 Vivado 后，工具可能
按需重新生成 cache、runs、`.Xil` 等目录；这些仍属于可再生中间产物。

已签核的板测位流、DCP、实现报告和核心 OOC 证据统一位于
`tools/vivado_2025_2/results/active_218lut_4dsp/`。

## 3. 已移出的历史内容

以下内容已从正式工程目录移出：

- `.Xil`、cache、runs、sim、hw、ip_user_files、xsim.dir 等可再生目录；
- 不再被当前 XPR 引用的候选顶层、历史测试模块和旧版实验文件；
- accumulator、polyphase、word-length 等早期探索报告；
- ILA、频率计、LCD12864 等非本次正式交付功能；
- 旧 Vivado/WebTalk/XSim/JVM 日志、journal、replay 和 crash 文件；
- 历史 Tcl/PowerShell 脚本以及多轮中间构建结果。

正式 v7 数据通路仍依赖的基础模块按 XPR 引用关系保留，不能仅依据目录名或版本号
删除。

## 4. 可恢复备份

本次没有不可逆删除。清理前的 **2716 个原始文件**全部保存在：

`../_cleanup_backup_XC7A35T_interp_LUTmin218_DSP4_2025.2_20260816/`

需要找回历史实验时，请只复制明确需要的单个文件，不要用备份中的旧 `.xpr`、
缓存或 runs 目录覆盖当前 Vivado 2025.2 工程。

## 5. 正式构建身份

板测通过位流：

`tools/vivado_2025_2/results/active_218lut_4dsp/board_demo_competition_dac8_top_218lut_4dsp.bit`

- 文件大小：421341 字节
- SHA-256：`1834675AB971FFA8BD6C03BF1B596D6F5D65C8A36A6B8D0182EEA6C5D408D110`

对应 routed DCP：

`tools/vivado_2025_2/results/active_218lut_4dsp/board_routed_218lut_4dsp.dcp`

- SHA-256：`FC26756258EF14A60872D55CBDDAC928D536727937876788D180E2D3BE35A462`

完整板级 post-route 结果为 218 LUT、365 FF、4 DSP48E1、4 RAMB18E1，
WNS/WHS 为 `+45.279/+0.079 ns`。独立滤波器核心 OOC 结果为 190 LUT、
279 FF、4 DSP48E1、3 RAMB18E1。两组数字的统计边界不同，不应混用。

## 6. 清理后审计与验证

- XPR 登记 58 个文件引用，缺失数为 0，工程外引用数为 0；
- 保留 57 个 Verilog 文件，其中设计源 35 个、仿真源 22 个；
- 57/57 文件具备详细中文文件头，版本均为 `V2025.2`；
- 清理前目标工程与当前保留 RTL 去除注释和空白后，逻辑差异数为 0；
- XPR 与板级顶层均固定 `USE_NATIONAL_FINALS_CIC_INTEGRATOR_DSP_MODE=2`；
- Vivado 2025.2 已完成 35 个设计源和 22 个仿真源的联合编译；
- 板级顶层及全链路测试平台均成功展开；
- 冲激与固定随机向量在 4×、8×、128× 节点逐位对拍均为 0 LSB。

详细结果见 `VERILOG_COMMENT_AUDIT.md`。

## 7. 使用方法

用 Vivado 2025.2 打开 `XC7A35T_interp.xpr`，确认综合顶层为
`board_demo_competition_dac8_top`，即可运行综合、实现和生成位流。

命令行完整构建：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\vivado_2025_2\run_full_build_2025_2.ps1 -Jobs 1
```

若只做现场演示，优先使用第 5 节列出的板测通过位流。只要 RTL、XDC、MEM、
器件或构建参数发生变化，原位流的 SHA-256 和板测结论就不再代表新构建，必须重新
实现、生成位流并完成板级复测。
