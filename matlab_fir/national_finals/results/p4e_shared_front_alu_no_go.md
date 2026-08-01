# P4-E 串行前端共享 ALU：No-Go 结论

## 实验目标

把三抽头 CIC 补偿器与 N=3 Hold16 CIC 的两级低速 comb 合并为一条
23-bit 串行 add/sub 数据通路，保持补偿器原 21-bit 接口截取点，尝试减少
并行宽加法链。

实验分支：`codex/national-finals-p4e-serial-front-alu`

稳定基线：`8afa03f` / `national-finals-p4d-479LUT-468FF-4DSP-2BRAM-release-closed`

## 实现与修正

- 五个运算状态严格执行 `2*x1-x0`、`-x2`、`x1+(t>>>3)`、
  `q-q_z1`、`d0-d0_z1`。
- `q` 在进入 comb 前保持原来的无损 21-bit 窄化，未改变算法量化点。
- 第一次 Smoke 暴露历史轮换过早问题：补偿加法错误读取了当前输入；历史
  轮换移动到 `q` 形成后，重新回归达到逐节点 0 LSB。
- 复位回归原来直接引用旧实例层次；测试宏改为明确引用共享 ALU 实例后，
  8 种内部状态复位恢复全部通过。

## 验证结果

- RTL Smoke：`15/15 PASS`。
- 全链 impulse + random seed01：4x、8x、128x 全部逐有效样点 `0 LSB`。
- 8 种内部状态复位恢复：PASS。
- 动态模式切换、CDC、双时钟族、RAMB18 primitive 和板级集成：PASS。
- post-route：时序通过，`WNS=+46.125 ns`、`WHS=+0.121 ns`。
- bundled-data bus skew：实际 `1.787 ns`，相对 50 ns 约束余量 `48.213 ns`。

## 资源对比

| 阶段 | 版本 | LUT | FF | Slice | DSP | BRAM Tile | MMCM |
|---|---|---:|---:|---:|---:|---:|---:|
| 综合 | P4-D 基线 | 503 | 474 | - | 4 | 2 | 2 |
| 综合 | P4-E 共享 ALU | 526 | 494 | - | 4 | 2 | 2 |
| 综合变化 | P4-E - P4-D | **+23** | **+20** | - | 0 | 0 | 0 |
| post-route | P4-D 基线 | 479 | 468 | 198 | 4 | 2 | 2 |
| post-route | P4-E 共享 ALU | 504 | 488 | 204 | 4 | 2 | 2 |
| post-route 变化 | P4-E - P4-D | **+25** | **+20** | **+6** | 0 | 0 | 0 |

vectorless 功耗仍为 `0.271 W total / 0.199 W dynamic / 0.072 W static`，没有收益。

## No-Go 原因

共享 23-bit CARRY 链本身成立，但五路操作数选择器、状态译码和保存当前输入
所需的 20-bit 寄存器，超过了被移除并行加法器的代价。Vivado 对原并行表达式
已经能利用常量移位和独立低扇出结构；强制时间复用反而引入更昂贵的宽 mux。

该方案同时违反指导中的三个 Go 条件：

- 目标 `LUT<=459`，实测为 `504`；
- 目标相对基线至少减少 20 LUT，实测增加 25 LUT；
- 目标 FF 增量不超过 8，实测增加 20 FF。

因此不进入 Release 10x4096 和板级发布候选；保留实验分支作为可复核的
No-Go 证据，默认发布版本继续使用 P4-D 479 LUT / 468 FF / 4 DSP。
