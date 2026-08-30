# Vivado 2025.2 工程辅助脚本

本目录只保留 218-LUT/4-DSP 正式板测工程仍会使用的工程准备、构建、低内存和 Tcl Store 修复脚本。历史资源扫描、中间运行目录与旧候选构建已经移出正式工程。

## 当前正式配置

- 顶层：`board_demo_competition_dac8_top`
- 核心：`interp128_all2x_v7_folded_fir_cic_top_ce`
- 器件：`xc7a35tfgg484-2`
- 字长：Stage1/Stage2/Stage3 = `24/20/20 bit`
- CIC 积分器映射：`CIC_INTEGRATOR_DSP_MODE=2`
- 完整板级资源：218 LUT / 365 FF / 4 DSP48E1 / 4 RAMB18E1 / 2 MMCM
- 独立核心 OOC：190 LUT / 279 FF / 4 DSP48E1 / 3 RAMB18E1

正式位流、DCP、时序、资源、DRC、功耗与板测记录均位于：

`results/active_218lut_4dsp/`

## 脚本说明

- `synth_low_memory_pre.tcl`：综合前低内存设置；XPR 的综合步骤会调用，必须保留。
- `prepare_project_2025_2.tcl`：检查并准备工程路径、源文件、顶层和约束。
- `build_project_2025_2.tcl`：Vivado 2025.2 批处理构建入口。
- `run_full_build_2025_2.ps1`：PowerShell 完整构建封装。
- `core_ooc/`：使用正式 24/20/20 位、4-DSP 参数独立实现滤波器核心，
  不修改板级 XPR；用于复现 190 LUT / 279 FF / 4 DSP48E1 结果。
- `repair_gui_synth_2025_2.tcl`：修复 GUI 综合运行配置。
- `verify_gui_impl_after_synth_2025_2.tcl`：综合后检查实现流程。
- `query_tclstore.tcl`、`reset_tclstore.tcl`、`run_tclstore_maintenance_clean.ps1`：定位和修复本机 Tcl Store catalog 异常。

## 使用建议

现场展示优先下载已经完成板测的：

`results/active_218lut_4dsp/board_demo_competition_dac8_top_218lut_4dsp.bit`

只有 RTL、XDC 或 MEM 发生变化后才需要重新构建。重新生成位流后，不得继续沿用旧的板测身份；必须重新记录 SHA-256、资源、时序、DRC，并完成物理板复测。
