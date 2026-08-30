# Vivado 2025.2 正式构建工具

本目录只保留 DSP3/LUT239 正式工程仍需要的构建和维护脚本。

| 文件 | 作用 |
|---|---|
| `run_full_build_2025_2.ps1` | 一键执行正式工程完整构建，建议使用 `-Jobs 1` |
| `build_project_2025_2.tcl` | 执行综合、实现、报告和位流生成 |
| `prepare_project_2025_2.tcl` | 整理工程设置、源文件和运行配置 |
| `activate_239lut_3dsp_2025_2.tcl` | 激活 239-LUT/3-DSP 正式配置 |
| `core_ooc/` | 独立实现正式 24/20/20 位、3-DSP 滤波器核心并生成可复核报告 |
| `synth_low_memory_pre.tcl` | 综合前低内存设置 |
| `repair_gui_synth_2025_2.tcl` | 修复 GUI 综合运行配置 |
| `verify_gui_impl_after_synth_2025_2.tcl` | 综合后核验 GUI 实现配置 |
| `query_tclstore.tcl` | 检查 Tcl Store 状态 |
| `reset_tclstore.tcl` | 重置异常 Tcl Store 配置 |
| `run_tclstore_maintenance_clean.ps1` | 在干净环境中执行 Tcl Store 维护 |

正式综合顶层是 `board_demo_competition_dac8_top`，CIC 配置为
`CIC_INTEGRATOR_DSP_MODE=1`。`core_ooc/` 中只保留与本工程对应的正式 3-DSP
核心复现脚本；旧 4-DSP OOC 脚本及历史候选配置不在本工程中。

已签核位流和报告位于：

`results/active_239lut_3dsp/`

推荐命令：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\vivado_2025_2\run_full_build_2025_2.ps1 -Jobs 1
```

只统计独立滤波器核心时，关闭全部 Vivado 窗口后运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\vivado_2025_2\core_ooc\run_core_ooc_239lut_3dsp_2025_2.ps1
```

该流程不修改板级 XPR，post-route 目标为
`212 LUT / 302 FF / 3 DSP48E1 / 3 RAMB18E1`。

若 Vivado 报 Tcl Store catalog 异常，先运行维护脚本；若报内存不足，请重启电脑、
关闭其他大型程序并仅保留一个 Vivado 实例。
