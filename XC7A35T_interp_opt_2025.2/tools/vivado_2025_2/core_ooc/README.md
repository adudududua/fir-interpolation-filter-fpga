# 插值滤波器核心 OOC 现场复现

本目录用于独立实现 `interp128_all2x_v7_folded_fir_cic_top_ce`，向评委展示插值滤波器核心资源，
不会打开或修改正式整板工程的 Top、源文件集和 runs。

## 运行前

1. 使用 Vivado 2025.2；
2. 关闭所有 Vivado GUI 窗口；
3. 确保 Windows 提交内存余量不少于 3 GB，推荐 5 GB 以上；
4. 在仓库根目录打开 PowerShell。

## 一条命令运行

```powershell
powershell -ExecutionPolicy Bypass -File .\XC7A35T_interp_opt_2025.2\tools\vivado_2025_2\core_ooc\run_core_ooc_2025_2.ps1
```

如果 Vivado 不在本项目机器的默认位置：

```powershell
powershell -ExecutionPolicy Bypass -File .\XC7A35T_interp_opt_2025.2\tools\vivado_2025_2\core_ooc\run_core_ooc_2025_2.ps1 -VivadoBat 'D:\Xilinx\Vivado\2025.2\bin\vivado.bat'
```

## 给评委查看

命令结束必须出现 `CORE_OOC_2025_2_DEMO_PASS`。然后打开最新的
`results/<时间戳>/core_ooc_summary.txt` 和 `utilization_post_route.rpt`，应显示：

- 197 LUT、0 LUTRAM、290 FF；
- 4 DSP48E1；
- 3 RAMB18E1，即 1.5 BRAM Tile；
- 0 MMCM、0 DRC Error；
- 核心内部 setup/hold 均通过。

若评委希望在 Vivado GUI 中查看，而不只看文本报告：

1. 启动 Vivado 2025.2，但不要打开正式整板工程；
2. 在 Tcl Console 执行
   `open_checkpoint {<最新结果目录>/core_post_route.dcp}`；
3. 执行 `report_utilization -name core_ooc_utilization`；
4. 在生成的 Utilization 窗口中查看 Slice LUTs、Slice Registers、DSPs 和 Block RAM Tile；
5. 再打开同一目录的 `timing_internal_setup.rpt`、`timing_internal_hold.rpt` 和
   `drc_post_route.rpt`。

2026-08-09 已使用上述正式入口从空结果目录实际复跑，得到
197 LUT / 290 FF / 4 DSP48E1 / 3 RAMB18E1，内部 WNS/WHS=`+151.665/+0.054 ns`，
0 DRC Error，并输出 `CORE_OOC_2025_2_DEMO_PASS`。

OOC 资源实现保留零延迟顶层边界，以复现签核的面积导向放置结果；脚本另外从实现后网表中筛选
“内部寄存器→内部寄存器”路径作为核心内部时序门禁。顶层输入输出边界没有整板中的真实启动/
捕获寄存器，因此其原始 OOC hold 数字不能替代完整系统时序。完整系统接口与跨模块时序应同时
展示整板正式报告，其结果为 239 LUT、377 FF、4 DSP、
4 RAMB18E1（2 BRAM Tile）、2 MMCM，WNS/WHS=`+45.306/+0.082 ns`。

不要用 `239-197` 宣称外围精确消耗 42 LUT：OOC 与整板综合存在跨层级优化和打包差异，两组数据
应分别称为“核心独立实现资源”和“完整系统实现资源”。
