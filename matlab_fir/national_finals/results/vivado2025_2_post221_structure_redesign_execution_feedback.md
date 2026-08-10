# Vivado 2025.2 221-LUT 板测版后结构重构试验执行反馈

## 1. 结论

本轮以用户已经完成六档采样率和 DAC 波形物理板验证的 221-LUT 版本为唯一正式基线，标签为
`nf-vivado2025.2-221lut-367ff-4dsp-2bram-board-pass`。实验分支为
`national-finals-v2025.2-global-fir-scheduler`，分支名、提交名均不包含 `codex` 字样。

本轮没有找到可以替代 221-LUT 板测版的整板候选。所有重构均在独立 OOC 包装器和实验目录中
验证；正式 bridge、Stage1、Stage2/3、CIC 和板级 `.xpr` 均保持在 221-LUT 板测基线状态。
因此本轮不生成候选 bitstream，不把“功能跑通但资源更差”的方案误报为优化。

## 2. 比较口径

整板正式基线为 **221 LUT / 367 FF / 4 DSP48E1 / 4 RAMB18E1（2 BRAM Tile）/ 2 MMCM**。
结构候选主要修改 Stage1、两个级间量化 bridge 与共享 Stage2/3 FIR，所以面积 A/B 使用同一个
FIR 前三节点 OOC 边界；该边界不含下游 CIC、PCM ROM、按键、CDC、DAC、IO 和 MMCM：

**187 LUT / 159 FF / 2 DSP48E1 / 3 RAMB18E1**。

该 187-LUT 数字不能与整板 221 LUT 直接相减来声称外围资源，因为两种综合边界的跨层合并和
打包不同。它只用于本轮候选之间的严格同口径比较。

## 3. 256× 双采样率族时钟可行性

为了给统一调度器提供足够空闲拍，本轮先验证 44.1 kHz 族 `11.2896 MHz` 与 48 kHz 族
`12.288 MHz` 的 256× 计算时钟。两个 MMCM 输出经 `BUFGMUX_CTRL` 选择计算时钟，再经
`BUFR /2` 产生原 128× 音频时钟。独立时钟候选已完成综合、布局布线和 DRC：

| 项目 | 结果 |
|---|---:|
| post-route LUT / FF | 5 / 8（仅测试活动逻辑） |
| MMCM / BUFGCTRL / BUFR | 2 / 1 / 1 |
| WNS / WHS | +79.928 / +0.248 ns |
| DRC Error | 0 |

结论是时钟拓扑在 XC7A35T 上可布线，但 `BUFR` 是新增全局时钟资源，不能因为时钟可行就假定
计算结构一定省 LUT。

## 4. 候选矩阵

以下 FIR 前端数字均为 Vivado 2025.2、器件 `xc7a35tfgg484-2`、
`AreaOptimized_high + flatten_hierarchy=full + resource_sharing=on + shreg_min_size=5` 的
post-synth 同口径结果：

| 候选 | LUT | FF | DSP | RAMB18 | 相对 187-LUT 基线 | RTL 结果 | 结论 |
|---|---:|---:|---:|---:|---:|---|---|
| 正式 FIR 前端参考 | 187 | 159 | 2 | 3 | 0 | 221-LUT 正式核心来源 | 基线 |
| 旧 256× 全局共享 FIR 种子 | 620 | 358 | 1 | 5 | +433 LUT | 仅结构综合 | No-Go |
| 全局单 DSP FIR 调度器 | 316 | 276 | 1 | 3 | +129 LUT、−1 DSP | 64k 周期逐拍等价 | No-Go |
| 固定时隙 Stage2/3，Stage1 独立 | **186** | 165 | 2 | 3 | **−1 LUT、+6 FF** | 64k 周期逐拍等价 | 收益不足，No-Go |
| Stage2/3 DSP 吸收两级量化 | 197 | 159 | 2 | 3 | +10 LUT | 26k 周期逐拍等价 | No-Go |
| 固定时隙 DSP 同时吸收两级量化 | 254 | 211 | 2 | 3 | +67 LUT、+52 FF | 64k 周期逐拍等价 | No-Go |

固定时隙方案还扫描了 `AreaOptimized_high/medium`、`FewerCarryChains` 和 `Default`：结果分别为
`186/165`、`186/165`、`188/165`、`188/165`（LUT/FF）。曾删除 6 个返回流水 FF，虽然 FF
恢复到 159，但 LUT 反升到 194，因此回退。−1 LUT 不能覆盖新增 256× 时钟选择/分频、跨时钟
集成和板级验证风险，故没有进入正式整板实现。

另外还把正式 Stage2/3 的 4 个互斥布尔状态尝试合并为 3-bit 枚举。Smoke 17/17 通过，完整
核心 OOC 只从 `193 LUT / 281 FF` 变为 `193 LUT / 280 FF`，LUT 不变；该改动没有达到本轮
LUT 优先门槛，已经从正式 RTL 恢复，不作为候选保留。

## 5. 结构方法与失败原因

### 5.1 全局单 DSP 调度

一颗 DSP48E1 执行 Stage1 的 52 次顺序 MAC，并允许 Stage2/3 短任务抢占；抢占前保存 Stage1
累加上下文，短任务完成后同拍恢复。仿真中的 pending 覆盖、历史写冲突和 Stage1 截止期断言均
未触发，说明调度在周期上可行。但共享一颗 DSP 需要保存两类累加上下文、所有权状态、宽数据
多路选择、抢占/恢复状态和不同字长的舍入饱和选择，Fabric 开销远大于省下的一颗 DSP。

首版 RTL 曾在短任务启动同拍漏交付一个 `y8`，逐拍对照立即报错；修复为启动同拍完成当前
结果提交后，64k 周期和所有 deadline 断言通过。该问题说明统一调度不能只用“仿真有输出”作为
通过标准，必须比较 valid 相位和每个节点的全部样本。

### 5.2 固定时隙 Stage2/3

Stage1 保持独立 DSP，Stage2/3 在 256× 时钟下使用简单 issue/return 流水和固定状态，取消
128× 时钟下的紧凑调度压力。功能和断言均通过，但仅得到 1 LUT 净收益，并增加 6 FF；任何
整板时钟接入和边界逻辑都很可能抵消这 1 LUT，因此不值得替换已板测结构。

### 5.3 DSP48 预加器吸收量化

两级 bridge 的 Q 格式右移、最近舍入和饱和被搬到 Stage2/3 DSP48 的空闲状态，正满量程边界
使用“截断值已经为最大值时禁止进位”保证逐位等价。该方法成功通过了随机数据和补偿模式切换
对拍，但动态 `A/D/INMODE` 选择、宽结果暂存和量化任务控制增加的 LUT 超过删除的两个 bridge。

第一版正满量程曾出现 1 个原始 LSB 差异，根因正是最大正数再执行舍入进位会越界；加入上述
边界抑制后重新完成 26k/64k 周期逐拍对照。最终淘汰原因是资源，而不是遗留功能错误。

## 6. RTL 验证证据

- 固定时隙 Stage2/3：64,000 周期，`y2/y4/y8=500/1000/2000`，逐样本等价；
- 全局单 DSP 调度：64,000 周期，`y2/y4/y8=500/1000/2000`，逐样本等价；
- 固定时隙加量化折叠：64,000 周期，`y2/y4/y8=500/1000/2000`，逐样本等价；
- 独立量化折叠：26,000 周期，`y2/y4/y8=407/813/1624`，逐样本等价；
- 参数关闭路径在实验接口扩展后再次完成 64,000 周期复验；
- 所有候选均包含 pending overwrite、history collision 和 deadline 断言，未出现 ERROR/FATAL。

一键复现入口：

```powershell
powershell -ExecutionPolicy Bypass -File `
  .\XC7A35T_interp_opt_2025.2\tools\vivado_2025_2\structure_experiments\run_rtl_equivalence.ps1
```

生成文件只写入
`XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/_work/structure_redesign`，不写仓库主目录。

## 7. 停止线与正式版本状态

本轮遵守“只有资源真实优于当前正式版才进入 Release 17/17、正式工程实现、bitstream 和 routed
六档回归”的门槛。最好的固定时隙候选只有 FIR 前端 −1 LUT，无法形成可信的整板净收益；其余
候选均明显恶化。因此没有消耗时间对 No-Go 结构生成板级 bitstream。

正式推荐和板测状态不变：

- 当前版本：`221 LUT / 367 FF / 4 DSP / 2 BRAM Tile`，用户六档采样率和 DAC 波形板测通过；
- 当前标签：`nf-vivado2025.2-221lut-367ff-4dsp-2bram-board-pass`；
- 前一回退：`nf-vivado2025.2-234lut-369ff-4dsp-2bram-board-pass`。

本轮证明 221 LUT 不只是“小改动扫描”的局部最优：统一单 DSP、256× 固定时隙和 DSP 内折叠
量化三条不同结构路线都没有形成整板 LUT 优势。在仍固定 4 DSP、2 BRAM Tile 和完全相同定点
语义的条件下，下一次若要显著下降，需要改变数据存储编码或把 FIR/CIC 的状态边界进一步合并，
而不是继续增加通用调度层。
