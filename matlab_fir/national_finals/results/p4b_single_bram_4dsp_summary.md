# P4-B 单 BRAM 历史调度 4-DSP / 2-BRAM-Tile 签核

## 结论

P4-B 在 P4-A 的严格等价 N3 Hold 4-DSP 数据通路上，只改变历史样本的存储与读取调度，不改变 FIR/CIC 系数、Q 格式、舍入、饱和、输出样点或 valid 节拍。最终全国赛板级 post-route 结果为：

**504 LUT / 493 FF / 202 Slice / 4 DSP48E1 / 2 BRAM Tile（4 RAMB18E1）/ 2 MMCM / 17 IO**。

相对 P4-A 的 `491 LUT / 444 FF / 197 Slice / 4 DSP / 3 BRAM Tile`，P4-B 用 `+13 LUT / +49 FF / +5 Slice` 换掉一个完整 BRAM Tile，DSP 和功耗不变。因此：

- P4-A 是 LUT/FF 更低的 4-DSP Pareto 点；
- P4-B 是 BRAM 最低的 4-DSP Pareto 点；
- 两版都保留独立分支、提交和标签，不能用单一“最优”覆盖另一版。

## 结构改写

### Stage 1：2 个 RAMB18E1 降为 1 个

旧 Stage 1 用双同步读端口同拍取出一对对称历史样本。新核使用一个 64×24-bit SDP RAMB18E1：

1. phase-zero 刚到达的当前输入直接旁路为第 0 对左样本，同时写入循环历史；
2. 单读口按 `R0,L1,R1,...,L25,R25` 连续发出 51 次读请求；
3. RAM 返回左样本时锁存，返回右样本时与锁存左样本送入原 Stage 1 DSP48E1；
4. 26 次 MAC 在约 53 拍内完成，早于相邻 `ce2_out` 的 64 拍截止期；
5. 纯延迟相在下一相位单独预读，输出相位与旧核一致。

### Stage 2/3：2 个 RAMB18E1 降为 1 个

Stage 2 和 Stage 3 的浅循环历史合并到一个 32×22-bit SDP RAMB18E1，最高地址位选择 stage bank。共享 MAC 每拍只需要一次历史读；同时写入时 Stage 2 优先，罕见的 Stage 3 同拍写入进入一项队列，并在其下一次读任务前提交。显式 RAMB18E1 避免 Vivado 将共享数组回退映射成 LUTRAM。

最终 4 个 RAMB18E1 的原语清单严格为：

1. 双采样率测试音 ROM；
2. Stage 1 历史；
3. Stage 2/3 统一历史；
4. Stage 1/2/3 统一 FIR 系数。

## RTL 验证

Vivado XSim 2018.3 从空目录运行 **14/14 PASS**，目录：

`matlab_fir/national_finals/_work/rtl_regression/20260801_022831`

新增和关键门禁包括：

- Stage 1 新旧核比较 1400 个输出，valid 与数据逐拍一致，0 LSB；
- Stage 2/3 统一历史分别比较 336/671 个输出，0 LSB；
- N3 Hold 与旧 N3 CIC 比较 7680 个输出，覆盖连续、随机停顿和中途复位，0 LSB；
- 全链 impulse + 固定随机 PCM 的 Stage 1/2/3/128x 节点全部 0 LSB；
- 8 个内部状态中途复位场景，每场比较 4096 个 128x 输出；
- 1200 次原子 CDC 事务、100 次时钟家族切换、10 次不停机倍率切换全部通过。

由于 P4-B 与 P1/P3/P4-A 全链逐点位真一致，六工况频响也保持 P1 修复后的结果：通带最大绝对偏差 `0.004610～0.006116 dB`，峰峰纹波 `0.005703～0.008056 dB`，阻带衰减 `72.331～78.669 dB`，绝对增益误差 `-0.001599～-0.003480 dB`。

## 综合与 post-route 结果

| 指标 | P4-A | P4-B | 变化 |
|---|---:|---:|---:|
| 综合 LUT / FF | 501 / 450 | 525 / 499 | +24 / +49 |
| post-route LUT | 491 | **504** | +13 |
| post-route FF | 444 | **493** | +49 |
| Slice | 197 | **202** | +5 |
| DSP48E1 | 4 | **4** | 0 |
| BRAM Tile / RAMB18E1 | 3 / 6 | **2 / 4** | **-1 / -2** |
| MMCM | 2 | **2** | 0 |
| WNS / WHS | +45.738 / +0.052 ns | **+45.637 / +0.119 ns** | 全部满足 |
| TNS / THS | 0 / 0 ns | **0 / 0 ns** | 0 |
| 功耗 | 0.271 W | **0.271 W** | 报告精度下不变 |

P4-B 的 setup/hold 失败端点均为 0；AD9708 最差 48-kHz setup/hold 仍为 `+76.116/+78.117 ns`。DRC 为 7 条 Warning 和 1 条 Advisory、0 Error，均为面积优先 DSP 未增加流水的性能建议。CDC 报告保留 P3 已书面说明的 BUFGMUX 专用选择入口和原子 bundled-data 总线提示，没有用 false path 隐藏。

bitstream：

`matlab_fir/national_finals/vivado_results/board_dual_rate_p4b2_bram2_v1/national_finals_dual_rate_4x8x128x_areaopt.bit`

SHA-256：`DA0665E43A8DA5230AB93FC786AB0EED47BD83FE393C9B1416BA3360B8DE5E85`

软件、RTL、综合、布局布线、时序、DRC、功耗和 bitstream 均已签核；实物开发板下载、六档 DA_CLK、频谱和切换压力测试仍是现场门禁。
