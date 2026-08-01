# P2 双分布式系数 ROM 验证总结

## 结论

P2 将 P4-E 的单块系数 `RAMB18E1` 拆成 Stage 1 和 Stage 2/3 两个分布式 ROM，并对“地址寄存”和“数据寄存”两种一拍读取契约做了同条件综合、布线和 RTL 回归。地址寄存方案 P2-A 达到 **513 LUT / 496 FF / 4 DSP / 1 BRAM Tile / 2 MMCM**，并通过 **17/17 Release**。

P2-A 相比 P4-E 再节省 **0.5 BRAM Tile**，代价是 **+22 LUT / +9 FF**；相比默认 P4-D 节省 **1 BRAM Tile**，代价是 **+34 LUT / +28 FF**。因此它是有效的“BRAM 最小化” Pareto 分支，但不取代 P4-D `479 LUT / 468 FF / 4 DSP / 2 BRAM Tile`的综合最优默认版。

## 结构与判断逻辑

- 保持 Stage 1/2/3 系数、Q15 定点、舍入、饱和、CIC 和外部接口不变，因此频率响应与 P4-D/P4-E 一致。
- `nf_dual_distributed_fir_coeff_rom.v` 保留两个独立 ROM 数组，避免手工大 `case` 和多层译码器。
- P2-A 寄存地址，组合 ROM 输出；P2-B 寄存 ROM 数据。两者对外都是一拍延迟，可以在不改调度器的情况下 A/B 对比。
- 专用单元测试穷举 96 个有效地址，同时通过 96 次单位故障注入证明比较器对每个系数敏感，防止“A/B 同错仍 PASS”。

## 同条件 Vivado 2018.3 实现

| 方案 | LUT | FF | DSP48E1 | RAMB18 | BRAM Tile | MMCM | WNS / WHS | 矢量缺省功耗 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|
| P4-D 默认 | 479 | 468 | 4 | 4 | 2.0 | 2 | +45.734 / +0.121 ns | 0.271 W |
| P4-E 系数 BRAM | 491 | 487 | 4 | 3 | 1.5 | 2 | +46.132 / +0.105 ns | 0.271 W |
| **P2-A 地址寄存** | **513** | **496** | **4** | **2** | **1.0** | **2** | **+45.949 / +0.117 ns** | **0.270 W** |
| P2-B 数据寄存 | 516 | 516 | 4 | 2 | 1.0 | 2 | +45.764 / +0.103 ns | 0.270 W |

P2-A/P2-B 均完全布线，路由错误为 0；时序没有 failing endpoint。P2-A bundled-data 总线布线后实测 skew 为 **1.780 ns**，相对 50 ns 约束余量 **48.220 ns**。P2-B 对应为 1.913/48.087 ns。

功耗是 Vivado vectorless 估计，Confidence Level 为 Medium，只用于 A/B 方向性对比，不冒充 SAIF 或实板测量。

## 功能与 RTL 证据

- P2-A Smoke：17/17 PASS。
- P2-B Smoke：17/17 PASS。
- P2-A Release：**17/17 PASS**。
- Release 全链：冲激 + 10 个固定 seed×4096，4x/8x/128x 全部逐样本 **0 LSB**。
- 每个随机 seed 比较数：4x=16605，8x=33219，128x=531584。
- 正/负满幅、冲激、复位后零输出、8 个内部状态复位场景、10 次动态模式切换全部通过。
- 系数 ROM：96/96 地址 A/B 一致，96/96 故障敏感性检查通过。

Release 运行目录（已忽略的临时工作区）：`matlab_fir/national_finals/_work/rtl_regression/20260802_032217`。

## bitstream 与可复现性

| 方案 | 源码提交 | 构建起始状态 | bit SHA-256 |
|---|---|---|---|
| P2-A | `9950b869c041eeec353a4616fe1a5008ef541a45` | clean | `A730052ECED485F0BF1A903FBE1525DE4CC1704500BC65654893AA2C3BF021C1` |
| P2-B | `9950b869c041eeec353a4616fe1a5008ef541a45` | clean（P2-A 产物未跟踪） | `0959DC34D0D0CEE0A797A36A056F9FC80DDED91B0CBDD9257FADB51F2C63BFBD` |

P2-A 是本分支保留的实现候选；P2-B 只作为完整 A/B 反例保留。板级下载与仪器测量仍需在实物开发板上执行，不将 bitstream 生成等同于实板完成。
