# P4-D 发布闭环签核（479 LUT / 468 FF / 4 DSP）

## 结论

P4-D 不改变 P4-C 的滤波传递函数、系数、字长、舍入、饱和、吞吐或板级资源结构，而是补齐可复现发布所缺少的仿真资产、固定配置、Release 长回归、CDC 物理约束和清单。最终重新综合、布局布线和生成 bitstream 后仍为 **479 LUT / 468 FF / 198 Slice / 4 DSP48E1 / 2 BRAM Tile（4 RAMB18E1）/ 2 MMCM**，因此 P4-C 资源基线没有回退。

当前环境已完成全部软件和 FPGA 工具侧验证；实物板下载、示波器测量 DA_CLK 和音频频谱仍需在现场执行，不能把 bitstream 成功表述为实板已通过。

## 本轮修正

1. 新增 `nf_signedoff_filter_core.v`，把 P4-C/P4-D 的全部算法和存储参数固定在唯一包装层中；Smoke/Release 回归规模不再通过算法宏间接改变硬件拓扑。
2. 全链 testbench 新增 `.mem` 预检，缺少任一资产会立即报 `NF_ASSET_MISSING`；已通过故意移走 `impulse_input_24bit.mem` 的负向测试。
3. GUI `sim_1` 显式登记 8 个日常 `.mem`，固定顶层为 `tb_phase7_full_chain_bittrue`，不再依赖十个易漂移的 topology 宏。
4. 新增 `nf_04_generate_release_vectors.m`，确定性生成冲激和 10 个固定 seed × 4096 输入的 4x/8x/128x golden；41,293,728 字节的大向量只存放在已忽略的 `_work/release_vectors`。
5. 修正旧 Release TB 的 128x 样本数：正确值是 `531584`，不是指导和旧 TB 沿用的 `531552`。解析校验为 `138368 + (4096-1024)×128 = 531584`，十个 MATLAB seed 的实际行数也全部一致。
6. 板级顶层默认 generic 对齐签核值；XPR、批处理构建和 GUI 检查继续进行第二层配置验证。
7. request/ack bundled-data CDC 总线增加 `50.000 ns` bus-skew 约束；post-route 实测 `1.816 ns`，裕量 `48.184 ns`。
8. 实现脚本新增 `report_exceptions -coverage` 和 `report_bus_skew`；发布清单脚本记录配置、Git、资源、时序、功耗、回归和关键文件 SHA-256。

## RTL 与 GUI 验证

| 门槛 | 结果 |
|---|---:|
| Smoke 回归 | 15/15 PASS；冲激 + seed01×1024，4x/8x/128x 全部 0 LSB |
| Release 回归 | 15/15 PASS；冲激 + 10 seed×4096，三个节点逐样本 0 LSB |
| 每个 Release seed 输出数 | 4x=16605，8x=33219，128x=531584 |
| 内部状态复位恢复 | 8/8 场景 PASS，每场比较 4096 个 128x 输出 |
| 模式 CDC | 1200 次定向事务 PASS，原子提交且每次一个 ACK |
| 动态倍率切换 | 10 次 PASS，无 runt pulse、无 X |
| GUI behavioral simulation | PASS，Vivado 工程自动导出 8 个 `.mem` |
| 缺资产负向测试 | PASS，观察到 `NF_ASSET_MISSING` |
| GUI `impl_1 -> write_bitstream` | PASS，资源断言全部通过 |

## 实现、时序和功耗

| 项目 | P4-D 实测 |
|---|---:|
| Slice LUT / FF / Slice | **479 / 468 / 198** |
| DSP48E1 | **4** |
| BRAM Tile / RAMB18E1 | **2 / 4** |
| MMCM / IO | **2 / 17** |
| WNS / TNS | **+45.734 ns / 0 ns** |
| WHS / THS | **+0.121 ns / 0 ns** |
| AD9708 setup / hold slack | **+76.116 / +78.117 ns** |
| mode bus-skew requirement / actual | **50.000 / 1.816 ns（MET）** |
| Vectorless total / dynamic / static | **0.271 / 0.199 / 0.072 W** |
| Routing errors | **0** |
| Bitstream | **PASS** |

Vectorless 功耗没有 SAIF 激励，适合版本间同口径比较，不等于实物功耗。

## TIMING-18 与 CDC 审核结论

### TIMING-18

Vivado 2018.3 `report_methodology` 仍对 `dac_data[7:0]` 给出 8 条 TIMING-18，称相对两个互斥的 forwarded generated clock 缺 output delay。该警告未被隐藏，按以下证据审核后保留书面豁免：

- XDC 对 `dac_clk_44k1_128x` 和 `dac_clk_48k_128x` 均设置 max `2.500 ns`、min `-2.000 ns`，第二组使用 `-add_delay`；
- `check_timing -verbose` 报告 `0 ports with no output delay specified`；
- `0` 个无时钟寄存器、`0` 个未约束内部端点、`0` 个 partial output delay；
- 实际 DAC 输出 setup/hold 路径均已计入外部延迟并分别有 `+76.116/+78.117 ns` 裕量。

因此这是 Vivado 2018.3 对一个输出端口关联两个逻辑互斥 generated clock 的 methodology 报告局限，不是未约束 DAC 数据口。若更换 Vivado 版本或修改 forwarded-clock 结构，必须重新审核，不能沿用豁免。

### CDC-13 / CDC-15

- 两条 CDC-13 是 `BUFGMUX_CTRL` 的 S0/S1 专用选择端，不是普通数据寄存器采样；双家族切换已有 100 次无毛刺时钟压力测试。
- 四条 CDC-15 是两位 `mode_shadow` 被两个互斥音频时钟域捕获。源端从 req 发起直到同步 ack 返回始终保持数据稳定，目标端检测 req 后再等待三拍并原子捕获；1200 次事务验证通过。
- P4-D 进一步增加 50 ns bus-skew 物理约束，布线后实际 1.816 ns、裕量 48.184 ns。

## 发布物

- 结果目录：`matlab_fir/national_finals/vivado_results/p4d_release_closure_4dsp`
- bitstream SHA-256：`44879C48B2A15481A2B7DE598EAA83DE02CD1DABBD9C9BD5D26F0E8399E3E378`
- 机器可读清单：`release_manifest_p4d.json`
- 普通 Vivado 工程 bitstream：`XC7A35T_interp_audio_pcm_wordlen_opt/XC7A35T_interp.runs/impl_1/board_demo_competition_dac8_top.bit`
