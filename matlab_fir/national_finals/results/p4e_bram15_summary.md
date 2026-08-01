# P4-E：PCM ROM 与 Stage 1 历史共享 RAMB18（1.5 BRAM 候选）

## 结论

该结构通过 RTL、普通 Vivado GUI 工程和 post-route 验证，是一个有效的 BRAM 优先 Pareto 候选，但不替代 LUT/FF 更低的 P4-D 默认版。

| 版本 | LUT | FF | Slice | DSP | RAMB18 | BRAM Tile | MMCM | WNS | WHS | Vectorless 功耗 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| P4-D 默认版 | 479 | 468 | 198 | 4 | 4 | 2.0 | 2 | +45.734 ns | +0.121 ns | 0.271 W |
| P4-E 共享 RAM | 491 | 487 | 202 | 4 | 3 | 1.5 | 2 | +46.132 ns | +0.105 ns | 0.271 W |
| 变化 | +12 | +19 | +4 | 0 | -1 | -0.5 | 0 | +0.398 ns | -0.016 ns | 0.000 W |

因此：需要最低 LUT/FF 时使用 P4-D；评分更重视 BRAM 时可选 P4-E。

## 结构与实现方法

- 新增一个 512×36 SDP RAMB18E1，把板载测试 PCM ROM 放在地址 0～162，把 64×24-bit Stage 1 历史放在地址 256～319。
- 写端口只写 Stage 1 历史；读端口由 Stage 1 和 PCM 共享。
- Stage 1 读请求优先；PCM 采样请求在忙时保持，等待每个 128-clock 调度周期的空闲窗口完成。
- 直接复用 PCM 输出寄存器作为预取缓冲，避免再增加一组 24-bit PCM 保持寄存器。
- 增加 `pcm_deadline_miss_dbg`，仿真中若 PCM 请求跨越截止期会立即失败。
- 保持 P4-D 的 1-DSP Stage 1、1-DSP Stage 2/3、2-DSP CIC、统一系数 RAM、N=3 Hold 等数据通路不变，因此滤波频响和定点传递函数不变。

## 验证证据

| 检查 | 结果 |
|---|---|
| 共享 RAM 行为模型与 RAMB18E1 原语模型 | PASS；64 个历史地址、44.1 kHz 150 点、48 kHz 20 点 |
| 最紧仲裁窗口 | PASS；先占用 116/128 clocks，仅留 12-clock PCM 空闲窗口 |
| Smoke RTL 回归 | 16/16 PASS |
| Release RTL 回归 | 16/16 PASS |
| 全链逐位比对 | 脉冲 + 10 seeds × 4096；4×/8×/128×全部 0 LSB |
| 复位恢复 | 8/8 内部状态场景 PASS |
| 动态模式 | 10 次无复位切换 PASS，无 runt pulse/X |
| GUI Behavioral Simulation | PASS；脉冲 + seed01，全部 0 LSB |
| GUI synth/impl/bitstream | PASS；491 LUT / 487 FF / 4 DSP / 3 RAMB18 / 2 MMCM |
| 布局布线 | PASS；TNS/THS=0，实际 mode bus skew 2.023 ns ≤ 50 ns |

Smoke 运行目录：`matlab_fir/national_finals/_work/rtl_regression/20260801_191138`

Release 运行目录：`matlab_fir/national_finals/_work/rtl_regression/20260801_191557`

bitstream：`matlab_fir/national_finals/vivado_results/p4e_pcm_stage1_shared_3ramb18/national_finals_dual_rate_4x8x128x_areaopt.bit`

bitstream SHA-256：`8B873CBE619E3179A426C5A971C0D1F03329D18B2A58298BE6E5F1D172DD53DD`

## 实施中发现并解决的问题

1. RAMB18E1 原语仿真最初在上电阶段读到未知值。原因是 UNISIM `glbl` 的全局复位仍在生效；测试平台等待 120 ns 后再开始访问，行为模型与原语模型随后完全一致。
2. 初版共享结构综合为 515 LUT / 517 FF。主要增量来自重复的 24-bit PCM 预取寄存器；改为复用输出寄存器后降为 post-route 491 LUT / 487 FF。
3. 原动态模式测试仍实例化独立 PCM ROM，不能证明板级共享路径。现已强制启用共享 RAM，并在 44.1/48 kHz 和 4×/8×/128×切换回归中通过。
4. 新增端口在两个旧测试平台中未显式连接，虽不影响功能但产生警告；已补齐固定输入与占位输出，Release 日志不再包含该警告。

## 版本定位

- 分支：`codex/national-finals-p4e-bram15`
- 本分支保存完整 Vivado 工程、RTL、测试、bitstream、构建清单和 release manifest。
- 推荐默认发布仍为 P4-D：`codex/national-finals-p4d-release-closure`。
