# P3-P 近期论文驱动的下一轮优化执行反馈

## 1. 结论

本轮从 P3-O `361 LUT / 386 FF / 158 Slice / 4 DSP / 2 BRAM Tile / 2 MMCM`
工具签核候选出发，检索了 2022～2026 年与 FPGA FIR、MCM、有限字长和时分复用
常数乘相关的工作，并按“先做层次化热点审计，再做可证明等价的小步试验”的方式执行。

共完成五类 RTL/映射候选和一次四策略实现扫描。所有候选都至少到达综合；四个候选
完成布局布线和 bitstream，所有实现均通过 Timing、DRC、CDC 审计和功耗报告，但最终
LUT 分别为 367、最低 369、370 和 368，均未优于 P3-O 的 361 LUT。因此本轮结论为
**No-Go：不修改正式滤波 RTL，继续保留 P3-O 为最低 LUT 工具签核候选**。

实验分支为 `national-finals-p3p-paper-driven-optimization`，分支名、提交名和标签名均不含
`codex`。P3-O 的正式回退标签保持为
`nf-p3o-toolverified-361lut-386ff-158slice-4dsp-2bram`。

## 2. 论文检索与适用性判断

| 年份 | 工作 | 可借鉴点 | 对当前工程的判断 |
|---|---|---|---|
| 2024 | [Efficient FIR filtering with Bit Layer Multiply Accumulator](https://arxiv.org/abs/2403.01351) | BLMAC 利用系数 bit-layer 稀疏性，以多周期移位/累加替代普通乘法器 | 适合“以 LUT 换 DSP”；当前只有 4 个 DSP，且主要目标是继续降 LUT，不作为正式候选 |
| 2023 | [Toward the Multiple Constant Multiplication at Minimal Hardware Cost](https://hal.science/hal-03784625v3) | 用 ILP 最小化 one-bit adder 成本，并允许带严格误差界的中间截断 | 对常数乘网络很有价值；当前 FIR 乘法已集中在两个时分复用 DSP 中，直接改成 MCM 会引入选择器，不盲目替换 |
| 2023 | [An algorithm for the design of optimal finite wordlength FIR filters](https://doi.org/10.1016/j.dsp.2023.104275) | 直接搜索有限字长最优系数，而不是把浮点系数简单舍入 | 可用于未来“允许重设计系数”的独立路线；本轮要求保持已签核频响和 0-LSB 回归，且系数存于 BRAM、乘法在 DSP 中，预期 LUT 收益有限 |
| 2022 | [Multiplication and Accumulation Co-Optimization for Low Complexity FIR Filter Implementation](https://www.mdpi.com/2079-9292/11/11/1721) | 联合考虑常数乘、分组和局部累加的结构成本 | 直接启发了本轮 Stage2/3 饱和锥与输出保持寄存器的联合审计 |
| 2023 | [Optimal Adder-Multiplexer Co-Optimization for Time-Multiplexed Multiplierless Architectures](https://doi.org/10.1109/TCSI.2023.3289229) | 时分复用结构不能只数加法器，还必须联合最小化 mux | 与当前 Stage2/3、CIC 的时分复用调度最相关；本轮优先试验共享/级联结果逻辑，而不是单独减少算术节点 |
| 2025 | [Resource Optimization in Polyphase-Filter STFT Based on Time-Multiplexed Constant Multiplication](https://doi.org/10.1109/TVLSI.2025.3608756) | 用 DAG 组织时分复用 SCM/MCM，联合减少加法器和 mux | 说明继续压缩需要同时改变调度和选择网络；但当前 1-DSP Stage1 与 1-DSP Stage2/3 已高度串行化，剩余瓶颈主要是控制/饱和/板级外围 |
| 2025 | [Resource-Optimized Time-Multiplexed Constant Multiplication via Adjacency Matrix Modeling](https://doi.org/10.1109/TCAD.2025.3632193) | 以邻接矩阵统一描述并优化时分复用加法器/选择器 | 可作为未来自动搜索微架构的方向；Vivado 2018.3 当前 RTL 不具备论文求解器，不能把论文百分比直接套到本工程 |
| 2026 | [Decompose, Optimize, and Reconstruct: Very Large Constant Multiplication at Scale](https://arxiv.org/abs/2605.23998) | 对超大位宽 MCM 做分解、最优重构和 CP/SAT 搜索 | 面向几十到上千位常数乘；本工程系数为 16/18 bit，相关性低，仅作为后续自动 MCM 工具参考 |

筛选后的优先级是：

1. 先用 `flatten_hierarchy=rebuilt` 定位实际热点；
2. 优先做不改系数、不改字长、不改采样节拍的结果/复位/ROM 映射联合优化；
3. 每个候选先做 RTL 等价或原语比对，再综合；只有综合有潜力才实现；
4. 以 post-route LUT 为主判据，同时要求 DSP=4、BRAM Tile=2、MMCM=2、Timing 和 DAC 接口约束通过。

## 3. P3-O 层次化热点审计

为了避免在 `flatten_hierarchy=full` 的单一顶层数字上猜测，本轮额外运行 rebuilt 层次综合。
该口径总量为 397 LUT / 388 FF / 4 DSP / 2 BRAM Tile，层次热点如下：

| 层次 | LUT | FF | DSP | RAMB18E1 | 观察 |
|---|---:|---:|---:|---:|---|
| Stage2/3 共享 FIR | 127 | 77 | 1 | 1 | 最大热点；包括串行调度、两种输出饱和和历史 BRAM 外围 |
| Stage1 FIR | 113 | 98 | 1 | 1 | 已使用 DSP48 预加器、AREG 和单 BRAM，继续压缩空间很小 |
| N3 Hold CIC | 70 | 107 | 2 | 0 | 两个高率积分器已在 DSP，组合级和量化为主要 LUT |
| 双采样率测试音 ROM | 30 | 15 | 0 | 1 | 值得审计推断 BRAM 的输出保持、复位和地址外围 |
| 矩阵键盘 | 28 | 24 | 0 | 0 | 已是超紧凑共享扫描版本；改动会增加板级交互风险 |

层次报告只能用于定位，不能作为最终资源结论；最终仍统一采用 full flatten 的 post-route
`utilization_placed.rpt`。

## 4. 候选执行结果

### 4.1 候选 A：BRAM 同步输出直连

思路是删除测试音 ROM 的 24-bit 二次保持寄存器，直接使用同步 BRAM 输出。RTL 中同时实例化
新旧路径逐样本比较，两采样率、回绕和同步复位均通过。

结果为综合 `395 LUT / 382 FF`，实现 `367 LUT / 380 FF / 157 Slice`，WNS/WHS
`+45.062/+0.060 ns`，功耗 `0.271 W`。虽然少 6 FF，但比 P3-O 多 6 LUT。
Vivado 日志还提示显式直连后 BRAM 可选输出寄存器不能合并，说明旧 RTL 已获得更好的 BRAM
寄存器吸收。判定 No-Go。

### 4.2 候选 B：Stage2/3 级联饱和与实现策略扫描

利用严格恒等式 `sat21(sat22(x)) = sat21(x)`，让 Stage3 的 21-bit 饱和从已经计算的
Stage2 22-bit 饱和结果继续收窄，希望共享比较/mux 锥。综合确实由 395 LUT 降到
`391 LUT / 388 FF`，但实现打包反向增长：

| opt_design 策略 | LUT | FF | Slice | WNS/WHS |
|---|---:|---:|---:|---|
| ExploreWithRemap | 370 | 386 | 157 | +45.322/+0.074 ns |
| Default | 369 | 386 | 159 | +45.138/+0.121 ns |
| AddRemap | 369 | 386 | 159 | +45.138/+0.121 ns |
| ExploreArea | 425 | 386 | 173 | Timing 通过 |

四种策略都不低于 361 LUT，因此不能用“综合少 4 LUT”代替实现结论。判定 No-Go。

### 4.3 候选 C：直接使用 Stage2/3 DSP PREG 保持结果

Stage2/3 DSP 的 `PREG` 在 MAC/舍入结束后保持到下一任务接收边沿，因此尝试删除两级共
43-bit 输出寄存器，保留原 valid 脉冲。Stage2/3 对照仿真比较 336 个 Stage2 输出和
671 个 Stage3 输出，达到 0 LSB。

综合为 `416 LUT / 345 FF / 4 DSP / 2 BRAM Tile`：FF 减少 43，但组合边界消失导致 LUT
增加 21，未进入实现。该结果验证了论文强调的“不能只减少寄存器/算术节点而忽略 mux 与
组合锥”。判定 No-Go。

### 4.4 候选 D：窄 valid 屏蔽宽 ROM 复位

思路是取消 24-bit `sample_out` 的运行时清零，改用现有 1-bit `x_in_valid` 在首个样本前
把输入屏蔽为零；首个 `x_in_update_ce` 到来时再使能数据。ROM 单元测试通过。

综合为 `394 LUT / 388 FF`，实现为 `370 LUT / 386 FF / 155 Slice`，WNS/WHS
`+44.781/+0.064 ns`，功耗 `0.271 W`。Vivado 原先已消除大部分宽复位成本，最终 LUT
反而增加。判定 No-Go。

### 4.5 候选 E：显式 256×32 RAMB18E1 测试音 ROM

该候选不依赖 ROM 推断，手工生成 `INIT_00...INIT_1F`，用 RAMB18E1 SDP 36-bit 读口把
`{DOBDO,DOADO}` 组合成 32-bit `{next_addr,PCM}`。执行中发现并解决：

- RAMB18E1 在 TDP 模式不允许 36-bit 口，改为 SDP；
- UNISIM 全局 GSR 持续 100 ns，原语 testbench 必须等 GSR 结束后发首个 sample request；
- 修正后 44.1/48 kHz 两族、回绕和同步复位的原语仿真逐样本通过。

综合为 `390 LUT / 406 FF`，实现为 `368 LUT / 402 FF / 162 Slice`，WNS/WHS
`+44.939/+0.072 ns`，功耗 `0.271 W`。相对 P3-O 多 7 LUT、16 FF、4 Slice；手工原语
没有超过推断器的寄存器吸收和打包。判定 No-Go，显式原语代码已从正式 RTL 回退。

## 5. 统一汇总

| 版本/候选 | Synth LUT/FF | Routed LUT/FF/Slice | DSP | BRAM Tile | WNS/WHS | Power | 结论 |
|---|---:|---:|---:|---:|---:|---:|---|
| **P3-O 基线** | **395/388** | **361/386/158** | **4** | **2** | **+44.989/+0.103 ns** | **0.271 W** | **继续保留** |
| A BRAM 输出直连 | 395/382 | 367/380/157 | 4 | 2 | +45.062/+0.060 ns | 0.271 W | No-Go |
| B 级联饱和，最佳策略 | 391/388 | 369/386/159 | 4 | 2 | +45.138/+0.121 ns | 0.271 W | No-Go |
| C DSP PREG 直出 | 416/345 | 未实现 | 4 | 2 | — | — | 综合停止 |
| D valid 屏蔽宽复位 | 394/388 | 370/386/155 | 4 | 2 | +44.781/+0.064 ns | 0.271 W | No-Go |
| E 显式测试音 RAMB18 | 390/406 | 368/402/162 | 4 | 2 | +44.939/+0.072 ns | 0.271 W | No-Go |

## 6. 为什么没有采用“论文中的大幅百分比”

论文中的大幅下降通常相对通用乘法器、多常数并行网络或尚未联合优化的时分复用基线。
当前工程已经是 1-DSP Stage1、1-DSP Stage2/3、2-DSP CIC，两块 FIR 系数和历史状态又已
合并进两块 BRAM Tile；剩余 361 LUT 包含键盘、CDC、双 MMCM 控制、DAC、饱和和调度。
因此论文方法仍有方向价值，但不能把其百分比直接乘到 361 LUT 上。

BLMAC/MCM 路线若替代 DSP，最可能得到“DSP 更少、LUT 更多”的另一个 Pareto 点；有限
字长最优系数路线会改变系数和 golden，必须另开算法分支重新完成六工况频响、MATLAB
定点、RTL 0-LSB 和板测，不适合作为本轮保持 4 DSP/2 BRAM 的低风险正式升级。

## 7. 最终状态与下一步

- 正式 RTL 已逐文件恢复到 P3-O，滤波系数、字长、舍入、饱和、valid、时钟和 DAC 接口均未改变；
- 当前最低 LUT 工具签核候选仍为 P3-O 361/386/158/4-DSP/2-BRAM；
- 当前物理板安全回退仍为 P3-M 368/386/156/4-DSP/2-BRAM；
- 本轮没有把任何 No-Go bitstream 宣称为板级通过版本；
- 若继续追求明显下降，建议建立独立的自动搜索路线：把 Stage2/3 调度、饱和、输出寄存器和 mux 一起建模，而不是继续手工删除单个寄存器；或明确接受更多 DSP/BRAM 后重新定义 Pareto 目标。
