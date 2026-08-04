# P3-L 395～405 LUT 目标优化执行反馈

## 1. 结论与版本口径

本轮从用户已经确认 **DAC 输出正常、采样率正常** 的 P3-K 安全基线继续优化，目标是在保持 `4 DSP / 2 BRAM Tile / 2 MMCM`、FF 不明显增加的前提下把完整全国赛板级 LUT 降到 395～405。最终候选达到：

| LUT | FF | Slice | DSP | RAMB18 / Tile | MMCM | WNS/WHS | Vectorless 功耗 |
|---:|---:|---:|---:|---:|---:|---:|---:|
| **397** | **409** | **161** | **4** | **4 / 2.0** | **2** | **+44.408/+0.121 ns** | **0.271 W** |

相对 P3-K 实板通过版 `427 LUT / 416 FF / 177 Slice`，减少 **30 LUT、7 FF、16 Slice**，DSP、BRAM、MMCM 不变。当前分支为 `national-finals-p3l-safe-packedrom-395target`。

上述 397-LUT 版本已经完成工具侧完整签核。**2026-08-04 用户进一步完成物理板复测，确认 DAC 输出正常，44.1/48 kHz 两个家族下各倍率档位的实测采样频率均正确。** 因此本版状态由“推荐上板候选”正式提升为 **实板验证通过发布版**，P3-K 427-LUT 版本保留为安全实板回退。用户未提供逐档仪器数值，本文只记录已确认的通过结论，不虚构额外测量数据。

## 2. 优化演进与 Stop/Go 结果

| 阶段 | LUT | FF | Slice | DSP | BRAM Tile | 判断 | 原因 |
|---|---:|---:|---:|---:|---:|---|---|
| P3-K 实板通过基线 | 427 | 416 | 177 | 4 | 2 | 安全回退 | 显式 ROM 地址计数，用户已确认 DAC/采样率正常 |
| 单镜像安全 Packed-ROM | 412 | 418 | 168 | 4 | 2 | Go，继续优化 | 单次 `$readmemh`，默认模式 post-route DAC 有活动；尚未物理板测 |
| DAC 8-bit 选择简化 | 420 | 418 | 172 | 4 | 2 | No-Go | 1029 点等价与 Smoke 通过，但 Vivado 映射反而增加 8 LUT |
| 10-bit cycle + 2-bit phase | 408 | 419 | — | 4 | 2 | Go，但未达目标 | 相对 412 再减 4 LUT；仍存在独立计数器热点 |
| 上述候选 + AddRemap | 408 | 419 | — | 4 | 2 | 无收益 | 与 Default 完全相同 |
| 上述候选 + ExploreArea | 473 | 419 | — | 4 | 2 | No-Go | 面积策略在当前拓扑上明显反向劣化 |
| **复用键盘计数器的 shared guard** | **397** | **409** | **161** | **4** | **2** | **正式实板通过版** | 命中 395～405 目标，FF 同时下降；DAC 与六档采样频率板测正确 |

策略扫描结果说明实现 directive 不能凭名称判断；正式设置继续固定为 `AreaOptimized_high / flatten full / resource sharing on + opt_design Default`。

## 3. 两项正式优化

### 3.1 离线单镜像 Packed-ROM

旧 412/424-LUT 历史版本曾在 RTL 中先用 `$readmemh` 写 24-bit PCM，再在第二个 procedural 初始化中补高位下一地址。RTL 仿真能看到高位，但 Vivado 推断 RAMB18 后第二段高位没有进入器件 INIT，导致下一地址恒零，最终表现为 DAC 无波形。

P3-L 不再依赖第二段初始化。`nf_02_generate_dual_rate_rom.m` 离线生成 `nf_sine_15k_dual_rate_packed32_256.mem`，每个 word 为 `{next_address[7:0], pcm[23:0]}`；RTL 只对一个 32-bit 数组执行一次 `$readmemh`。生成器断言低 24 bit 与原 PCM 完全一致，并验证高 8 bit 地址序列。

该问题采用三层证据关闭：

1. RTL ROM 测试用独立 24-bit 文件逐地址对照两个采样率家族的数据、wrap 和同步复位；
2. 路由 DCP 的唯一测试音 RAMB18 审计到 22 个非零 `INIT_xx` 和 2 个非零 `INITP_xx`；
3. 48 kHz 的 4x/8x/128x 布局后网表均产生正确边沿数且 DAC 数据持续变化。若高位下一地址仍为零，这三档不会通过。

### 3.2 复用持续运行的键盘/上电计数器

首次优化把 12-bit family guard 改成四个 1024-cycle phase，综合从 449 LUT 降至 436 LUT，实现降至 408 LUT，但实例报告仍显示 family-switch 约 19 个 LUT。正式全国赛参数 `USE_SHARED_KEYPAD_SCAN_TICK=1` 下，16-bit `pwr_rst_cnt` 在上电复位完成后仍持续运行，并已供键盘扫描复用。

最终版本直接用 `&pwr_rst_cnt[9:0]` 产生 1024-cycle tick，只保留 3-bit family 状态：状态1在下一 tick 提交新家族，状态2～4继续保持音频复位。请求到提交的等待随共享计数器相位为1～1024拍，提交后的保护时间固定为3072拍；从检测请求起立即 busy/静音。非共享参数分支仍保留独立12-bit计数器，避免破坏历史配置。

该变化使综合从 `436 LUT / 421 FF` 降到 `425 LUT / 411 FF`，实现从 `408 LUT / 419 FF` 降到 `397 LUT / 409 FF`。

## 4. RTL 完整回归

### 4.1 Smoke

- 结果：**16/16 PASS**
- 运行目录：`matlab_fir/national_finals/_work/rtl_regression/20260803_231835`

### 4.2 Release

- 结果：**16/16 PASS**
- 运行目录：`matlab_fir/national_finals/_work/rtl_regression/20260803_232831`
- Release 总耗时约 669 s，没有用 Smoke 结果替代发布回归。

16 个隔离用例为：

1. `rom`
2. `dac_offset_binary_equivalence`（1029 点）
3. `unified_coeff_ramb18_primitive`
4. `history_ramb18_primitive`
5. `stage1_single_bram_equivalence`
6. `equalizer`
7. `stage23_unified_history`
8. `cic_serial_equivalence`
9. `cic_n3_hold_equivalence`（DSP mode 2/1/0）
10. `clock`（双家族频率与100次无毛刺切换）
11. `mode_cdc_handshake`
12. `keypad`
13. `board`
14. `full_chain_bittrue`
15. `full_chain_reset_recovery`（8类内部状态）
16. `dynamic_mode_switch`（10次无复位切换）

滤波数据通路与 P3-K 的正式系数、字长和 Q15 舍入未改变，因此六工况频响继续为：

| 输入 | 节点 | 通带最大绝对偏差 | 峰峰纹波 | 阻带衰减 | 对称误差 |
|---:|---:|---:|---:|---:|---:|
| 44.1 kHz | 4x | 0.003022 dB | 0.005709 dB | 78.568 dB | 0 LSB |
| 44.1 kHz | 8x | 0.003521 dB | 0.006192 dB | 78.609 dB | 0 LSB |
| 44.1 kHz | 128x | 0.007730 dB | 0.005848 dB | 72.371 dB | 0 LSB |
| 48 kHz | 4x | 0.003022 dB | 0.005709 dB | 78.568 dB | 0 LSB |
| 48 kHz | 8x | 0.003007 dB | 0.005678 dB | 78.609 dB | 0 LSB |
| 48 kHz | 128x | 0.007606 dB | 0.005724 dB | 72.371 dB | 0 LSB |

## 5. 布局后全板 DAC 验证

### 5.1 默认 44.1 kHz / 128x

- DCP：`vivado_results/p3l_safe_packedrom_sharedguard/national_finals_board_routed.dcp`
- 运行目录：`_work/postroute_dac_activity/20260803_233958`
- 2 ms：11290 个 DAC 上升沿、7461 次数据变化，`beep_io=1`
- 结果：PASS

### 5.2 六种正式模式、公开引脚驱动

新增 `tb_board_postroute_six_mode_dac.v` 和 `run_postroute_six_mode_dac.ps1`。测试只根据 DUT 输出的 `key_kr` 驱动 `key_kc`，实际等待矩阵按键消抖；不 force 内部 mode、family、reset 或 ROM 地址。完整仿真硬件时间 140 ms，运行目录 `_work/postroute_six_mode_dac/20260803_234102`。

| 模式 | DAC edges / 1 ms | data changes / 1 ms | 结果 |
|---|---:|---:|---|
| 44.1 kHz / 4x | 177 | 175 | PASS |
| 44.1 kHz / 8x | 353 | 342 | PASS |
| 44.1 kHz / 128x | 5645 | 3709 | PASS |
| 48 kHz / 4x | 192 | 192 | PASS |
| 48 kHz / 8x | 384 | 372 | PASS |
| 48 kHz / 128x | 6144 | 3810 | PASS |

六档均无 X、数据非恒定、beep inactive-high。该门禁覆盖真实 POR、键盘、CDC、MMCM/BUFGMUX、family guard、ROM、FIR/CIC、DAC 数据寄存器和 ODDR。

## 6. 实现、时序、DRC/CDC 与 bitstream

- 目标器件：`XC7A35T-FGG484-2`
- 综合：425 LUT / 411 FF / 4 DSP / 4 RAMB18E1
- 布局布线：397 LUT / 409 FF / 161 Slice / 4 DSP / 4 RAMB18E1（2 Tile）/ 2 MMCM
- WNS/WHS：`+44.408/+0.121 ns`
- AD9708 data output setup/hold slack：`+76.116/+78.117 ns`
- 路由：1028/1028 routable nets，0 routing error
- mode bus skew：1.875 ns，requirement 50 ns，slack 48.125 ns
- mode absolute datapath：0.838～0.895 ns，requirement 50 ns
- 功耗：0.271 W，Medium confidence；该数值没有 SAIF，只适合结构间估计
- bitstream：`national_finals_dual_rate_4x8x128x_areaopt.bit`
- SHA-256：`AC8735BAD24450FA038C79B104072DA70CEFA6FEF7B599C52CE16ECA5F091440`

DRC 没有阻断 bitstream 的 Error/Critical Warning；存在 DSP 输入/输出流水建议。Methodology 的8个 `TIMING-18` 来自 DAC 外部接口未设置传统 output delay，但工程另外导出了 AD9708 data setup/hold 路径。CDC 的 `CDC-13 ×2` 是 BUFGMUX_CTRL 的专用选择输入，`CDC-15 ×4` 是带 max-delay/bus-skew 的两位原子模式握手；构建脚本锁定其数量，不能笼统写成“零告警”。

## 7. Git 回退与物理板验证结论

- 分支：`national-finals-p3l-safe-packedrom-395target`
- 单镜像 Packed-ROM 提交：`9770915`
- DAC 8-bit No-Go 提交/回退：`d87545d` / `f971fd3`
- phase guard 中间提交：`70ad6e7`
- shared guard 提交：`49e7e5d`
- P3-K 实板通过标签：`nf-p3k-final-427lut-416ff-177slice-4dsp-2bram-dacromfix`
- P3-L 工具签核标签：`nf-p3l-toolverified-397lut-409ff-161slice-4dsp-2bram`
- P3-L 正式板级发布标签：`nf-p3l-final-397lut-409ff-161slice-4dsp-2bram-boardverified`

物理板最终门禁及结果：

1. [x] 下载 P3-L bitstream，DAC 输出正常；
2. [x] 逐档测试 44.1/48 kHz 两个家族及 4x/8x/128x 倍率，实际采样频率均正确；
3. [x] 用户确认各档板级输出无问题，本版可作为正式版本上传 Git；
4. [ ] 未提供逐档仪器数值、频谱截图及切换次数，本文不作未获数据支持的量化声明；
5. [x] P3-K 427-LUT 标签继续保留为安全回退，不覆盖历史 bitstream。

最终结论：P3-L 已完成 MATLAB、RTL 0-LSB、复位与动态切换、综合、布局布线、Timing、DRC/CDC、post-route 六模式 DAC、bitstream 和物理板 DAC/采样频率闭环，可以作为全国总决赛正式版本。
