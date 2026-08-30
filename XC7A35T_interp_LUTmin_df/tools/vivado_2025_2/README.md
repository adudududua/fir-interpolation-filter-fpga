# Vivado 2025.2 工程辅助脚本

本目录只保留当前百兆网络板级验证工程仍会使用的工程构建、修复、低内存和 Tcl Store 维护脚本。历史策略扫描结果、时间戳运行目录和旧资源对比归档已经移出正式工程。

## 脚本说明

- `synth_low_memory_pre.tcl`：综合前低内存设置；当前 XPR 的 `synth_design` 步骤会调用它，必须保留。
- `build_project_2025_2.tcl`：Vivado 2025.2 批处理构建入口。
- `prepare_project_2025_2.tcl`：工程路径、顶层、源文件和约束准备。
- `repair_gui_synth_2025_2.tcl`：修复 GUI 综合运行配置。
- `verify_gui_impl_after_synth_2025_2.tcl`：综合后检查实现流程状态。
- `run_full_build_2025_2.ps1`：PowerShell 完整构建封装。
- `query_tclstore.tcl`、`reset_tclstore.tcl`、`run_tclstore_maintenance_clean.ps1`：定位和修复本机 Vivado Tcl Store catalog 异常。

## 资源口径

本工程是“插值器 + 百兆网络上传/回传/测量”的完整板级系统。正式网络位流的签核资源为：

- 3091 LUT；
- 3962 FF；
- 39.5 BRAM Tile；
- 4 DSP48E1。

滤波器核心本身的 218-LUT/4-DSP OOC 结果属于另一种统计边界，不能用来代替本网络演示工程的完整资源。正式位流身份、SHA-256、时序和 DRC 以
`../../network_capture/results/implementation/BUILD_INFO.md` 为准。

## 推荐流程

现场展示无需重新构建，优先下载已签核的：

`../../network_capture/results/implementation/board_network.bit`

只有修改 RTL、XDC 或 MEM 后才需要重新综合、实现并生成位流；重新构建后必须重新记录 bitstream 的大小、生成时间、SHA-256、时序、资源和 DRC。
