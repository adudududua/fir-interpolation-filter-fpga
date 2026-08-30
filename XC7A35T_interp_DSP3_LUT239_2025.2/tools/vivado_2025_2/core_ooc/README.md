# 239-LUT/3-DSP 滤波器核心 OOC 复现

本目录用于独立综合、布局布线
`interp128_all2x_v7_folded_fir_cic_top_ce`，不会修改板级工程的 Top、XDC、
源文件集或 runs。脚本显式传入正式 24/20/20 位、3-DSP 参数，避免在 Vivado GUI
中只修改 Top 后误用模块默认参数。

## 运行方法

1. 关闭所有 Vivado GUI；
2. 在本工程根目录打开 PowerShell；
3. 执行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\vivado_2025_2\core_ooc\run_core_ooc_239lut_3dsp_2025_2.ps1
```

结果写入 `results/<时间戳>/`。结束时必须出现：

```text
CORE_OOC_239LUT_3DSP_2025_2_DEMO_PASS
```

正式 Vivado 2025.2 post-route 目标为：

- 212 Slice LUT；
- 302 Slice Register；
- 3 DSP48E1；
- 3 RAMB18E1，即 1.5 BRAM Tile；
- 0 MMCM、0 DRC Error；
- 内部寄存器到寄存器 setup/hold 均通过。

需要在 GUI 查看时，新开 Vivado 2025.2，在 Tcl Console 执行：

```tcl
open_checkpoint {<结果目录>/core_post_route.dcp}
report_utilization -name core_ooc_utilization
```

这里统计的是独立核心 OOC 资源。完整板级 routed checkpoint 为 239 LUT、388 FF、
3 DSP48E1、4 RAMB18E1、2 MMCM。两者综合边界不同，不能通过相减得到外围逻辑的
精确独立面积。

