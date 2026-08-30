# XC7A35T 218-LUT / 4-DSP 插值滤波器正式工程

本目录是 Vivado 2025.2 下的纯滤波器板级演示工程，正式配置为 24/20/20 位、
`CIC_INTEGRATOR_DSP_MODE=2`。它用于展示 44.1/48 kHz 双采样率家族、
1×/4×/8×/128× 输出模式、RTL 逐位验证以及板级 DAC 输出。

本工程不包含百兆网络上位机；需要网络抓取和任意输入上传时，请使用同级目录中的
`XC7A35T_interp_LUTmin_df`。

## 快速使用

1. 用 Vivado 2025.2 打开 `XC7A35T_interp.xpr`；
2. 综合顶层应为 `board_demo_competition_dac8_top`；
3. 仿真顶层应为 `tb_phase7_full_chain_bittrue`；
4. 重新构建时依次运行综合、实现和 Generate Bitstream；
5. 现场演示优先下载已完成板测的正式位流：
   `tools/vivado_2025_2/results/active_218lut_4dsp/board_demo_competition_dac8_top_218lut_4dsp.bit`。

单独复现滤波器核心资源时，不要只在 GUI 中把核心文件设为 Top；板级参数名不会
自动映射为核心参数名。应关闭 Vivado GUI 后运行：

```powershell
powershell -ExecutionPolicy Bypass -File .\tools\vivado_2025_2\core_ooc\run_core_ooc_218lut_4dsp_2025_2.ps1
```

## 正式结果边界

- 完整板级 post-route：218 LUT、365 FF、4 DSP48E1、4 RAMB18E1；
- 独立滤波器核心 OOC：190 LUT、279 FF、4 DSP48E1、3 RAMB18E1；
- 板级 WNS/WHS：`+45.279/+0.079 ns`；
- 全链路黄金向量：4×、8×、128× 节点均为 0 LSB。

“218 LUT”是完整板级 routed checkpoint 的统计，“190 LUT”是独立滤波器核心 OOC
的统计，两者边界不同，不能相减推导外围模块资源。

## 关键文件

- `XC7A35T_interp.xpr`：Vivado 2025.2 工程；
- `XC7A35T_interp.srcs/sources_1/new/board_demo_competition_dac8_top.v`：板级顶层；
- `XC7A35T_interp.srcs/sources_1/new/all2x_v7/interp128_all2x_v7_folded_fir_cic_top_ce.v`：滤波器核心展示顶层；
- `XC7A35T_interp.srcs/sim_1/new/tb_phase7_full_chain_bittrue.v`：全链路逐位测试；
- `tools/vivado_2025_2/results/active_218lut_4dsp/`：板测位流、DCP、报告和身份说明；
- `tools/vivado_2025_2/core_ooc/`：正式核心 OOC 一键复现脚本；
- `CLEANUP_MANIFEST.md`：清理范围、备份路径和构建身份；
- `VERILOG_COMMENT_AUDIT.md`：中文注释及 Vivado 验证记录。

## 修改提醒

已签核位流的 SHA-256 为：

`1834675AB971FFA8BD6C03BF1B596D6F5D65C8A36A6B8D0182EEA6C5D408D110`

修改任何 RTL、XDC、MEM、器件或构建参数后，必须重新综合、实现、生成位流并完成
板级验证；旧位流和旧资源报告不能继续代表修改后的工程。
