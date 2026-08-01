# P4-C 深度审计与下一阶段优化指导执行反馈

日期：2026-08-01

指导文件：`matlab_fir/p4c_rtl_deep_audit_and_next_optimization_guide.md`

器件/工具：XC7A35T-FGG484-2 / Vivado、XSim 2018.3

## 1. 总结

指导文件对“先补签核证据，再做结构研究”的优先级判断是正确的；对共享存储、串行前端 ALU、MMCM 掉电和 20 MHz 统一 FIR 的风险分析也有参考价值。执行时没有把其中的资源区间当成保证值，而是按 **RTL 位真、普通 GUI 工程、完整实现、时序/CDC、bitstream** 逐级决定 Go/No-Go。

最终结论如下：

| 项目 | 实际结果 | 决策 |
|---|---|---|
| P0 发布签核闭环 | P4-D：479 LUT / 468 FF / 4 DSP / 2 BRAM；Smoke/Release 15/15 | **完成，继续作为默认版** |
| 补偿器与 CIC C² 共享串行 ALU | 504 LUT / 488 FF / 4 DSP / 2 BRAM；功能通过但面积反升 | **No-Go，独立实验分支保留** |
| PCM ROM + Stage1 历史共享 | 491 LUT / 487 FF / 4 DSP / 1.5 BRAM；16/16 全通过 | **Go，低 BRAM Pareto** |
| Stage2/3 历史改 LUTRAM | 531 LUT / 487 FF / 4 DSP / 1 BRAM；16/16 全通过 | **Go，最低 BRAM Pareto；不替代默认版** |
| 未选 MMCM PWRDWN | 需要新的安全切换 FSM、故障注入、SAIF 与实板电源测量 | **本轮不进入稳定 RTL** |
| 20 MHz 统一三级 FIR | 910 LUT / 692 FF / 3 DSP / 2.5 BRAM 核心；Release 11/11、0 LSB | **已执行；功能 Go、资源 No-Go** |
| CIC PREG | 会改变状态提交、valid/tail 与复位边界 | **后续独立低 FF 研究** |

指导预估的 1 BRAM 目标为约 500～510 LUT、FF≤480；真实 post-route 为 **531 LUT / 487 FF**。它确实少用了一个 BRAM Tile，但没有达到预计的 LUT/FF 区间，因此不能把预估值写成实现结果。

## 2. P0 发布闭环：已全部执行

### 2.1 固定签核配置

- 新增固定参数的 `nf_signedoff_filter_core`，正式全链 testbench 不再依赖十余个散落宏决定算法拓扑。
- Smoke/Release 宏只控制向量规模，不再改变算法配置。
- 板级顶层、命令行构建、普通 Vivado GUI 工程和验证脚本对同一组 Generic 做守卫。

### 2.2 资产和长回归

- `$readmemh` 前增加资产预检；故意移走输入文件时会立即以 `NF_ASSET_MISSING` 失败。
- MATLAB 重新生成冲激及 10 个固定随机种子×4096 输入的发布向量，共 44 个 `.mem`。
- 修正 128x 长随机输出应为 `531584` 点，而不是指导引用旧测试平台得到的 `531552` 点。
- Smoke 与 Release 均为 **15/15 PASS**；Release 的 4x/8x/128x 三节点逐样本 **0 LSB**。
- 普通 GUI 行为仿真、综合、实现和 `write_bitstream` 均实际运行通过。

### 2.3 时序、CDC 与发布绑定

- 为 request/ack bundled-data 的 `mode_shadow[1:0]` 增加 50 ns `set_bus_skew`；P4-D 路由后实际 1.816 ns，裕量 48.184 ns。
- 生成 setup/hold、CDC、bus skew、exception coverage、check_timing、DRC、methodology 和功耗报告。
- `TIMING-18`、`CDC-13/15` 没有简单隐藏，而是在发布清单中记录适用条件和证据。
- 发布清单绑定 Git 分支/提交、配置、资源、时序、功耗、源文件/向量/日志/bitstream SHA-256。

P4-D 最终为 **479 LUT / 468 FF / 198 Slice / 4 DSP / 4 RAMB18（2 BRAM Tile）/ 2 MMCM**，WNS/WHS 为 **+45.734/+0.121 ns**，vectorless 总/动态/静态功耗为 **0.271/0.199/0.072 W**。bitstream SHA-256 为 `44879C48B2A15481A2B7DE598EAA83DE02CD1DABBD9C9BD5D26F0E8399E3E378`。

## 3. 串行前端 ALU：已执行并判定 No-Go

指导建议把无乘法补偿器与 CIC 的两级低速 comb 共享一条 23-bit 串行加减单元。实验保留既有 FIR DSP、CIC 高速积分器和定点边界，只重排低速加减时序。

第一次 XSim 暴露历史轮转次序错误；修正为在事务边界更新历史后，Smoke **15/15 PASS**。但 post-route 为 **504 LUT / 488 FF / 204 Slice / 4 DSP / 2 BRAM / 2 MMCM**，相对 P4-D 增加 25 LUT、20 FF、6 Slice，没有达到指导的 LUT≤459、FF最多增加8的门槛。增加的调度状态、操作数选择和提交控制抵消了共享算术单元的收益，因此按 Go/No-Go 回退。

- 分支：`codex/national-finals-p4e-serial-front-alu`
- 提交：`47bd54b`

## 4. 1.5 BRAM：已执行并验证通过

### 4.1 实现方法

使用一个 512×36 的 SDP RAMB18E1 同时保存：

- PCM ROM：地址 0～162；
- Stage1 历史：地址 256～319。

Stage1 读具有优先级；被阻塞的 PCM 请求保持到已证明的空闲窗口。RAM 输出寄存器兼作 PCM 预取缓冲，不再额外复制 24-bit 数据寄存器；增加 deadline-miss 断言，防止“仿真偶尔正确、板级偶尔丢样”的隐患。

### 4.2 遇到的问题与修复

- 原语仿真初期受 `glbl` GSR 影响，测试平台增加上电释放等待后再开始比较。
- 初版预取路径重复保留了一组数据寄存器；改为复用 RAM 输出寄存器，避免无谓 FF。
- 44.1 kHz 最坏周期中 128 拍有 116 拍被 Stage1 使用，仅剩 12 拍空闲；测试覆盖全部 64 个历史地址、44.1 kHz 150 个样本回卷和 48 kHz 20 个样本回卷。

### 4.3 结果

post-route 为 **491 LUT / 487 FF / 202 Slice / 4 DSP / 3 RAMB18（1.5 BRAM Tile）/ 2 MMCM**，WNS/WHS **+46.132/+0.105 ns**；50 ns bus-skew 实测 2.023 ns。Smoke 与 Release 均 **16/16 PASS**，普通 GUI 行为仿真与实现也通过。bitstream SHA-256 为 `8B873CBE619E3179A426C5A971C0D1F03329D18B2A58298BE6E5F1D172DD53DD`。

- 分支：`codex/national-finals-p4e-bram15`
- 提交：`bb8d599`
- 标签：`national-finals-p4e-491LUT-487FF-4DSP-1p5BRAM`

## 5. 1 BRAM：已执行并验证通过

### 5.1 实现方法

在 1.5 BRAM 方案上继续把 Stage2/3 历史从一个 RAMB18E1 改为 **8 个 RAM32M**。最终只保留：

- 1 个 PCM/Stage1 共享 RAMB18E1；
- 1 个统一 FIR 系数 RAMB18E1。

即总计 2 个 RAMB18E1，折合 **1 BRAM Tile**。系数、DSP MAC、舍入、饱和、valid 和插值倍率均不变。

### 5.2 遇到的问题与修复

第一次 Smoke 只有动态模式用例失败。原因不是数据通路，而是测试平台错误地用 Stage2/3 BRAM 宏同时控制 Stage1 单 BRAM 开关，导致测试配置与板级配置不同。把 Stage1 共享 RAM 独立固定使能后：

- Smoke：**16/16 PASS**；
- Release：**16/16 PASS**，冲激 + 10 seed×4096，三节点全为 0 LSB；
- 复位：8/8 PASS；动态倍率切换：10/10 PASS；
- 普通 GUI 行为仿真和 GUI 综合/实现：PASS。

### 5.3 结果与取舍

post-route 为 **531 LUT / 487 FF / 204 Slice / 4 DSP / 2 RAMB18（1 BRAM Tile）/ 8 RAM32M / 2 MMCM**，WNS/WHS **+45.898/+0.105 ns**，bus-skew 1.859 ns；vectorless 总/动态/静态功耗 **0.270/0.198/0.072 W**。bitstream SHA-256 为 `32CBB432B53B84D6DE71E7751DFAD0A6F9B3668BBBEB6B8C39A3BE78A8AE3A22`。

相对 P4-D，它用 **+52 LUT / +19 FF / +6 Slice** 换取 **-1 BRAM Tile**。这是有效的最低 BRAM Pareto，但不比 P4-D 综合更优。

- 分支：`codex/national-finals-p4f-bram1`
- 提交：`2bcdb48`
- 标签：`national-finals-p4f-531LUT-487FF-4DSP-1BRAM`

## 6. 三个版本的频响继承关系

P4-E/P4-F 只改变存储映射，Release 全链对拍又证明 4x/8x/128x 与 P4-D golden 逐样本 0 LSB，因此六工况频响、绝对增益和严格线性相位保持不变：

| 输入 | 输出 | 通带最大绝对偏差 | 峰峰纹波 | 阻带衰减 |
|---:|---:|---:|---:|---:|
| 44.1 kHz | 4x | 0.004610 dB | 0.005703 dB | 78.669 dB |
| 44.1 kHz | 8x | 0.005395 dB | 0.006174 dB | 78.562 dB |
| 44.1 kHz | 128x | 0.006116 dB | 0.008056 dB | 72.331 dB |
| 48 kHz | 4x | 0.004610 dB | 0.005703 dB | 78.669 dB |
| 48 kHz | 8x | 0.005395 dB | 0.005719 dB | 78.562 dB |
| 48 kHz | 128x | 0.006116 dB | 0.006116 dB | 72.331 dB |

## 7. 未执行项目及原因

### 7.1 未选 MMCM PWRDWN

这可能是功耗收益最大的方向，但不能把 `PWRDWN` 直接接到 `family_sel`。正确实现需要 `MUTE → 唤醒目标 MMCM → LOCKED 稳定 → 切 BUFGMUX → 新时钟 heartbeat → 关闭旧 MMCM → 预热 → 解除静音` 的容错 FSM，还要验证锁定超时、runt pulse、首样点和 DAC 静音。当前没有实板电源轨与示波器接入，也没有代表真实播放活动的 post-route SAIF；仅凭 vectorless 报告无法证明 30% 动态功耗下降。因此本轮不把它写入稳定 RTL。

### 7.2 单 MMCM + DRP

它比 PWRDWN 更激进，重配置期间音频时钟必然中断，还涉及 divider、fractional、lock/filter 寄存器表。应在双 MMCM 安全掉电 FSM 经实板验证后再研究。

### 7.3 Stage2/3 DSP 再共享补偿器

现有局部截止期已很紧，直接插入补偿 job 会产生调度气泡。串行前端 ALU 的实测又证明控制和操作数复用成本会抵消算术共享收益，因此没有继续把更复杂的 job 塞入当前 DSP 调度器。

### 7.4 20 MHz 统一三级 FIR（后续已在独立分支执行）

初版反馈将它列为后续研究，随后按指导建立 `codex/national-finals-x3-20m-unified-fir` 独立分支并完成实现。它使用 4-deep Gray 输入 FIFO、160-clock 统一调度器和 y2/y4/y8 ping-pong 输出 bank，把 Stage1/2/3 从两颗 FIR DSP 合并为一颗；功能与资源的最终结论见第 9 节。该实验没有混入已签核 P4-D。

### 7.5 CIC PREG

指导估计可减少约 55 个 Slice FF，但 DSP 内部状态提交会改变复位、尾部样本和 valid 的相对周期。当前 P4-D 时序余量充足，P4-E/F 又以存储为目标，因此本轮没有用协议风险交换较少 FF。

### 7.6 Hogenauer pruning、N4、IFIR/FRM 与继续全局减位

这些方向都会改变系数、位真 golden 或噪声/频响边界，不属于“存储映射严格等价”实验。现有六工况已满足指标，若执行必须新建数学候选、重新生成 golden、重跑六工况和完整 RTL，不在本轮冒充等价优化。

## 8. 最终推荐与切换方法

默认继续使用 P4-D，因为它在 4 DSP 条件下仍是 LUT/FF 最低且发布证据最完整的版本。只有评分或系统集成明确重罚 BRAM 时，才选择 P4-E 或 P4-F。

```powershell
# 默认稳定版
git switch codex/national-finals-p4d-release-closure

# 1.5 BRAM 完整工程与 bitstream
git switch codex/national-finals-p4e-bram15

# 1 BRAM 完整工程与 bitstream
git switch codex/national-finals-p4f-bram1

# 串行前端 ALU No-Go 研究记录
git switch codex/national-finals-p4e-serial-front-alu

# X3 20 MHz 统一 FIR：功能通过、资源 No-Go 的完整研究分支
git switch codex/national-finals-x3-20m-unified-fir
```

三个可用档位均只完成了工具侧签核。最终“板级验证通过”仍需在目标板上下载相应 bitstream，完成六个采样率/倍率组合、家族切换、DA_CLK、DAC 波形、镜像抑制和供电测量后才能声明。

## 9. X3 20 MHz 统一三级 FIR：已执行，功能 Go / 资源 No-Go

### 9.1 实际执行内容

- 音频域输入通过 4-deep Gray 异步 FIFO 送到 20 MHz 系统域；
- Stage1/2/3 使用同一共享 MAC/DSP48E1，160 个系统时钟完成一个输入帧，小于 48 kHz 最坏约 416.67 个系统时钟的帧间隔；
- y2/y4/y8 使用 ping-pong bank，完整写入后才翻转 commit，音频域按原固定节拍读出；
- 保留 P4-D 真 Q15 系数、舍入、饱和、补偿器和 N3 Hold CIC，不改变 golden；
- 新增前端冲激对拍和完整 X3 全链 testbench，执行 Smoke 与 10-seed Release；
- 对 `nf_x3_20m_filter_core` 从头执行 OOC 综合、布局布线、时序、功耗、CDC 和 DRC。

### 9.2 遇到的问题与修复

实际实现暴露并修复了 Stage1 启动历史掩码、6-bit 环形地址回绕、历史 Stage3 Q14 系数、Gray FIFO `wr_full` 组合自环、复位阻止 LUTRAM 推断和 BRAM 异步复位控制六类问题。最终 DRC 不再有 LUTLP 或 `REQP-1840`。剩余 `NSTD-1/UCIO-1` 来自 OOC 顶层未绑定引脚；CDC-15 对应 Gray 指针控制下的 FIFO payload 和 commit/select 控制下的稳定 bank payload，若将来重启板级路线仍需补物理 bus-skew/max-delay 约束。

### 9.3 功能与频响

前端冲激在 Stage1 物理历史地址回绕后仍为 0 LSB；完整 Release 为 **11/11 PASS**：冲激 y4/y8/y128 输出 `1245/2499/40064` 点，十组随机用例每组输出 `16605/33219/531584` 点，三节点全部逐样本 0 LSB，且没有 FIFO overflow、bank overrun 或 X 输出。因此 X3 与 P4-D 的六工况通带最大绝对偏差、峰峰纹波和阻带衰减完全相同，沿用第 6 节表格。

### 9.4 实现结果与停止理由

| 滤波核心口径 | LUT | FF | DSP | RAMB18 / BRAM Tile |
|---|---:|---:|---:|---:|
| P4-D 已布线滤波层级 | 377 | 361 | 4 | 3 / 1.5 |
| X3 OOC post-route | 910 | 692 | 3 | 5 / 2.5 |
| X3 相对 P4-D 核心 | **+533** | **+331** | **-1** | **+2 / +1.0** |

X3 的 20 MHz 与 6.144 MHz WNS/WHS 分别为 `+34.839/+0.072 ns`、`+149.833/+0.081 ns`，时序通过；OOC vectorless 总/动态/静态功耗为 `0.076/0.005/0.070 W`，但因不含双 MMCM 和板级包装，不能与 P4-D 完整板级 0.271 W 直接比较。

这个结果证明创新调度在功能上可行，但为了节省 1 DSP 引入的双时钟状态机、异步 FIFO、三组帧 bank 和提交控制造成了显著 LUT/FF/BRAM增长。核心级数据已经越过停止线，所以没有继续改 P4-D 板级工程，也没有生成不能代表发布候选的 X3 bitstream。当前推荐和最终停留分支仍为 P4-D。更完整的调度、修复、CDC/DRC 与复现路径见 [X3 独立执行报告](x3_20m_unified_fir_nogo.md)。
