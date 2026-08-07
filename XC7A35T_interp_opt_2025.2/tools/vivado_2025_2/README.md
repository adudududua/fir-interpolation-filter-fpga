# Vivado 2025.2 迁移、修复与验证记录

## 结论

工程 `XC7A35T_interp_opt_2025.2/XC7A35T_interp.xpr` 已在 Vivado 2025.2 下完成迁移和验证。
2026-08-07 的签核运行成功完成综合、实现、DRC、时序、功耗分析和 bitstream 生成，且直接针对
该复制工程源码执行的全国赛 RTL Smoke 回归为 17/17 PASS。由 2025.2 routed DCP 导出的布线后
功能网表也通过了六档 DAC 活动与采样率检查。

本次只处理工具版本迁移、IP、工程运行状态和验证脚本，没有修改滤波器算法、定点字长、系数或
板级接口。该 2025.2 bitstream 已通过工具和仿真验证；用户随后完成实板复测，确认所有档位的
实际采样率均正确，DAC 输出波形正常。因此本版本已形成 RTL、实现、bitstream 与板级验证闭环。

## 原始失败原因

初始 GUI 综合日志没有 RTL `ERROR`，而是在综合后段突然终止。日志记录的 Windows 提交内存
上限约 46--49 GB，当时剩余提交余量最低只有约 0.45 GB；排查时也只剩约 3.04 GB。
Vivado GUI 和综合子进程合计所需空间超过了余量，因此 Windows 可能直接终止子进程，表现为
综合无明确 RTL 错误、运行突然失败。

此外，命令行复现还发现两个独立的迁移问题：

1. 用户 Tcl Store 目录不完整，缺失 `::tclapp::support::appinit 1.2`，触发
   `[Common 17-539] Failed to load tclapp initializer`。
2. 复制工程仍带有 Vivado 2018.3 生成缓存，Clocking Wizard 6.0 IP 处于旧修订版/锁定状态。

处理方法为：使用 Vivado 自带 `tclapp::reset_tclstore -force` 重建用户 Tcl Store；把
`clk_wiz_audio_44k1` 升级到 Vivado 2025.2 的 Clocking Wizard 6.0 Rev17；重新生成 IP target、
更新编译顺序，并通过 Vivado 的 `reset_run` 重置 `synth_1` 和 `impl_1`。没有删除 RTL 源码。

用户关闭不需要的软件后，实测提交内存余量从约 3.04 GB 上升到约 8.67 GB。这里的“提交内存”
是 Windows 对所有进程承诺的内存总量，受物理 RAM 与页面文件共同限制；它不是 FPGA 的 BRAM，
也不是磁盘剩余空间。

## 2025.2 签核结果

结果目录：`tools/vivado_2025_2/results/20260807_210642`

| 阶段 | LUT | LUTRAM | FF | DSP48E1 | BRAM Tile | RAMB18E1 | IO | MMCM |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| 综合 | 361 | 1 | 384 | 4 | 2 | 4 | 17 | 2 |
| 布局布线后 | **292** | **1** | **376** | **4** | **2** | **4** | **17** | **2** |

注意：Vivado 2018.3 与 2025.2 的综合、逻辑优化和统计结果不能直接混用。292 LUT 是同一 RTL
在 2025.2 本次实际 routed DCP 中的结果，不表示源码又做了一轮算法/RTL 优化。

| 检查项 | 结果 |
|---|---:|
| WNS / TNS | +44.234 ns / 0 ns |
| WHS / THS | +0.112 ns / 0 ns |
| 时序失败端点 | 0 |
| DRC Error | 0 |
| 总片上功耗 | 0.271 W |
| 动态 / 静态功耗 | 0.199 W / 0.072 W |
| 功耗置信度 | Medium（无 SAIF 的 vectorless 估算） |

DRC 中保留 9 条 DPIP-1 和 2 条 DPOP-1 DSP 流水线建议。这些是性能/功耗建议，不是错误；
当前全部时序约束已经满足，不能为了消除建议而随意增加寄存器并改变已签核的周期行为。

生成文件：

- `tools/vivado_2025_2/results/20260807_210642/board_demo_competition_dac8_top_2025_2.bit`
- `tools/vivado_2025_2/results/20260807_210642/board_routed_2025_2.dcp`
- 同目录下保存综合/实现利用率、时序、DRC、功耗、布线状态和完整日志。

bitstream SHA-256：
`040D70619A0693FA9E450350801E79BE934B6E2AA8B2C4A20159249B1A1ECBEC`

## 实板验证

2026-08-07 用户使用上述 2025.2 bitstream 完成板级验证：44.1 kHz/48 kHz 两个输入采样率族、
全部公开插值档位的 DA_CLK 实测均正确，AD9708 DAC 输出波形均正常。该结果与 RTL 回归及
布线后六档功能网表计数一致，本版本状态由 `tool-verified` 更新为 `board-verified`。

## 功能验证结果

直接指定 `XC7A35T_interp_opt_2025.2` 工程源码，使用 Vivado 2025.2 xvlog/xelab/xsim：

- 全国赛 RTL Smoke 回归：17/17 PASS；
- 全链路冲激 + 1 个随机种子在 4x/8x/128x 各节点均为 0 LSB；
- Stage1 行为模型与 RAMB18E1 原语各 1400 个输出均为 0 LSB；
- 8 类内部状态复位恢复全部通过；
- 10 次无复位动态切档无 runt pulse、无 X；
- ROM、DAC offset-binary、系数/历史 BRAM、双时钟族和模式 CDC 均通过。

RTL 回归目录：
`matlab_fir/national_finals/_work/rtl_regression/20260807_213020`

2025.2 routed DCP 六档布线后功能网表结果：

| 档位 | 1 ms 内 DA_CLK 边沿 | DAC 数据变化次数 |
|---|---:|---:|
| 44.1 kHz / 4x | 177 | 175 |
| 44.1 kHz / 8x | 353 | 342 |
| 44.1 kHz / 128x | 5645 | 3710 |
| 48 kHz / 4x | 192 | 192 |
| 48 kHz / 8x | 384 | 372 |
| 48 kHz / 128x | 6144 | 3810 |

177/353/5645 是 1 ms 有限观察窗内的整数边沿计数，分别对应理论 176.4/352.8/5644.8 kHz，
并不表示 44.1 kHz 族的 4x 频率被改成了 177 kHz。

布线后回归目录：
`matlab_fir/national_finals/_work/postroute_six_mode_dac/20260807_211646`

## 推荐的手动使用方法

### GUI

1. 确认没有其它 Vivado 实例仍在后台运行。
2. 打开 `XC7A35T_interp_opt_2025.2/XC7A35T_interp.xpr`。
3. 依次运行 `Run Synthesis`、`Run Implementation`、`Generate Bitstream`。
4. 如果可用提交内存不足 4 GB，先关闭浏览器、办公软件等大内存程序，再重试。
5. 比较资源时必须打开本次最新 `impl_1` 的 Utilization Report，不能拿旧 run 或综合报告比较。

### 一键低内存完整构建

在 PowerShell 中执行：

```powershell
powershell.exe -NoProfile -ExecutionPolicy Bypass -File `
  ".\tools\vivado_2025_2\run_full_build_2025_2.ps1" -Jobs 1
```

脚本会先检查 Vivado GUI 是否关闭和提交内存余量，然后把所有 `.log/.jou/.rpt/.dcp/.bit`
集中放入带时间戳的 `tools/vivado_2025_2/results` 子目录，不污染工程主目录。

若 Tcl Store 错误再次出现，请先关闭 Vivado，再执行：

```powershell
& 'E:\app\Xilinx20252\2025.2\Vivado\bin\vivado.bat' -mode batch -notrace `
  -source '.\tools\vivado_2025_2\reset_tclstore.tcl'
```

然后用 `query_tclstore.tcl` 检查输出是否包含 `APPINIT_REQUIRE_PASS=1.2`。
