# 218-LUT/4-DSP 滤波器核心 OOC 复现

本目录用于独立综合、布局布线
`interp128_all2x_v7_folded_fir_cic_top_ce`，不会修改板级工程的 Top、XDC、
源文件集或 runs。脚本显式传入正式 24/20/20 位、4-DSP 参数，避免在 Vivado GUI
中只修改 Top 后误用模块默认参数。

## 为什么手工 Set as Top 会得到 824 LUT / 8 DSP

板级工程 `sources_1` 保存的是 `USE_NATIONAL_FINALS_*` 板级参数。这些参数属于
`board_demo_competition_dac8_top`，不是核心模块的同名参数。把核心直接设为 Top 后，
综合日志会报告 `Unused top level parameter/generic`，核心随即采用自身默认配置，
因此出现约 824 LUT、730 FF、8 DSP 和大量顶层 IO。该结果不是正式签核配置。

## 运行方法

1. 关闭 Vivado GUI；
2. 在本工程根目录打开 PowerShell；
3. 执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\vivado_2025_2\core_ooc\run_core_ooc_218lut_4dsp_2025_2.ps1
```

结果写入 `results/<时间戳>/`。结束时必须出现：

```text
CORE_OOC_218LUT_4DSP_2025_2_PASS
```

正式 Vivado 2025.2 post-route 目标为：

- 190 Slice LUT；
- 279 Slice Register；
- 4 DSP48E1；
- 3 RAMB18E1，即 1.5 BRAM Tile；
- 0 MMCM、0 DRC Error；
- 内部寄存器到寄存器 setup/hold 均通过。

需要在 GUI 查看时，新开 Vivado 2025.2，在 Tcl Console 执行：

```tcl
open_checkpoint {<结果目录>/core_post_route.dcp}
report_utilization -name core_ooc_utilization
```

这里统计的是独立核心 OOC 资源。完整板级 routed checkpoint 为 218 LUT、365 FF、
4 DSP48E1、4 RAMB18E1、2 MMCM。两者综合边界不同，不能通过相减得到外围逻辑的
精确独立面积。

