# P3-J 后续优化执行指导

> 适用项目：XC7A35T 音频 4×/8×/128× FIR–CIC 插值器  
> 文档日期：2026-08-02  
> 基线标签：`nf-p3j-432lut-431ff-174slice-4dsp-2bram-2mmcm-signedoff`  
> 基线提交：`d441c49958439e1624ff08a73a1c4263de5686ea`  
> 工具基线：MATLAB R2023a、Vivado/XSim 2018.3、`xc7a35tfgg484-2`

## 0. 执行结论

P3-J 已经完成从算法、定点模型到 RTL、布局布线和 bitstream 的闭环，应立即冻结为新的默认工具侧基线：

```text
432 LUT / 431 FF / 174 Slice / 4 DSP48E1
4 RAMB18E1 = 2 BRAM Tile / 2 MMCM
WNS/WHS = +45.624/+0.105 ns
Total/Dynamic/Static = 0.271/0.199/0.072 W（vectorless）
4×/8×/128× RTL = 0 LSB
```

下一阶段不再重复扫描相同 Vivado 策略，也不再继续修改已经签核的 P3-J 标签。推荐顺序为：

```text
P0  P3-J 实物板与强信号证据闭环
 ↓
P1  P3-J × CIC 4/3/2-DSP 正交扫描
 ↓
P2  P3-J × 2/1.5/1-BRAM 正交扫描
 ↓
P3  只按评分需要生成 DSP×BRAM 交叉 Pareto
 ↓
P4  单 MMCM / 未选 MMCM 掉电与 SAIF、板级功耗实测
 ↓
P5  20-bit 边界约束搜索与 9-tap MATLAB 预筛
```

其中最值得立即执行的软件实验是：

```text
保持 P3JointStage3=1，只把 CicIntegratorDspMode 从 2 改为 1、0，
分别生成 P3-J 的 3-DSP 和 2-DSP 完整 post-route 结果。
```

若开发板当前可用，P0 实板验收优先级最高；若暂时无法接触开发板，不必阻塞 P1/P2 工具侧实验，但所有候选都只能标记为“工具侧通过”。

---

## 1. 当前基线与证据边界

### 1.1 P3-J 已证明的内容

P3-J 把原 128× 路径中的独立 11-tap shift-add 均衡器吸收到 Stage3 补偿系数 Bank：

```text
旧 128×：Stage2 → flat Stage3 → 独立均衡器 → N3 Hold CIC16
新 128×：Stage2 → compensated Stage3 → N3 Hold CIC16
```

补偿 Bank 为 11-tap、Q15、signed-18、严格对称系数：

```text
[561, 137, -4232, -1554, 20046, 35584,
 20046, -1554, -4232, 137, 561]
```

4×/8× 继续使用 flat Bank，128× 才使用 compensated Bank。禁止把 compensated Bank 永久用于所有倍率；该错误结构已经导致 8× 绝对通带偏差达到 0.129854/0.112188 dB，明确超过 ±0.05 dB。

P3-J 的 post-route 实测资源为：

| 指标 | P4-D R2 | P3-J | 变化 |
|---|---:|---:|---:|
| LUT | 479 | **432** | −47（−9.81%） |
| FF | 468 | **431** | −37（−7.91%） |
| Slice | 198 | **174** | −24（−12.12%） |
| DSP48E1 | 4 | **4** | 0 |
| BRAM Tile | 2 | **2** | 0 |
| MMCM | 2 | **2** | 0 |
| WNS/WHS | +45.734/+0.121 ns | **+45.624/+0.105 ns** | 通过 |
| vectorless 总功耗 | 0.271 W | **0.271 W** | 无可声明差异 |

### 1.2 六工况算法基线

| 输入 | 输出 | 最大绝对通带偏差 | 峰峰纹波 | 阻带衰减 |
|---:|---:|---:|---:|---:|
| 44.1 kHz | 4× / 176.4 kHz | 0.003022 dB | 0.005709 dB | 78.568 dB |
| 44.1 kHz | 8× / 352.8 kHz | 0.003521 dB | 0.006192 dB | 78.609 dB |
| 44.1 kHz | 128× / 5.6448 MHz | **0.007730 dB** | 0.005848 dB | **72.371 dB** |
| 48 kHz | 4× / 192 kHz | 0.003022 dB | 0.005709 dB | 78.568 dB |
| 48 kHz | 8× / 384 kHz | 0.003007 dB | 0.005678 dB | 78.609 dB |
| 48 kHz | 128× / 6.144 MHz | **0.007606 dB** | 0.005724 dB | **72.371 dB** |

P3-J 仍有较大的通带裕量，但 128× 阻带相对 70 dB 指标只剩：

\[
72.371-70=2.371\ \mathrm{dB}
\]

因此后续缩短 Stage3、降低系数精度或改变 CIC 时，首先应保护阻带，而不是只观察通带图。

### 1.3 尚未证明的内容

以下内容不能由现有 bitstream、XSim 或 vectorless 报告替代：

1. P3-J 尚未完成物理板下载与六档 `DA_CLK` 测量；
2. 尚未完成 P3-J 的 DAC 波形、镜像和动态切换实测；
3. 0.271 W 是无 SAIF 的 vectorless 估计，不能证明真实功耗；
4. 8-bit AD9708 的理论量化噪声底不足以在板上直接证明 72 dB 数字阻带，70 dB 指标应主要由 MATLAB/RTL 证据证明；
5. 早期 −1 dBFS 强信号测试出现过 16 次 CIC 饱和，而正式 13 组 Release 报告饱和计数为 0。两者刺激不同，必须单独闭环，不能互相覆盖。

---

## 2. 全阶段统一执行纪律

### 2.1 Git 与配置纪律

1. 所有实验从 P3-J 签核标签新建独立分支，不移动签核标签；
2. 每个分支只改变一个主变量，禁止同时改变 DSP 映射、BRAM 映射、系数和时钟；
3. 每次构建前要求 `source_worktree_dirty=false`；
4. 每个候选使用唯一 `CONFIG_ID`，并把参数显式传到所有 RTL wrapper、测试 wrapper 和 Tcl 构建脚本；
5. 禁止依赖 `P3JointStage3` 的默认值；签核配置必须显式为 `1`；
6. Smoke 与 Release 使用不同工作目录，禁止复用同名旧向量；
7. 只有通过完整门禁的候选才能打标签；No-Go 分支保留报告，不合入默认分支。

建议分支命名：

| 阶段 | 建议分支 |
|---|---|
| P1 低 DSP | `codex/p3j-cic-dsp-pareto` |
| P2 低 BRAM | `codex/p3j-bram-pareto` |
| P3 交叉 Pareto | `codex/p3j-dsp-bram-cross-pareto` |
| P4 单 MMCM | `codex/p3j-single-mmcm-static-family` |
| P4 动态掉电 | `codex/p3j-mmcm-powerdown-fsm` |
| P5 系数/字长 | `codex/p3j-stage3-fwl-search` |

### 2.2 所有 RTL 候选的共同硬门禁

任一 RTL 候选至少必须满足：

| 类别 | 硬门禁 |
|---|---|
| MATLAB 六工况 | 最大绝对通带偏差 ≤0.05 dB；峰峰纹波 ≤0.05 dB；阻带 ≥70 dB |
| 研究候选内部裕量 | 建议阻带 ≥71 dB，避免只以 0.1 dB 级裕量过门 |
| 线性相位 | 系数严格对称；冲激对称误差 0；相位残差不劣于基线 |
| 位真 | 4×/8×/128× 三正式节点逐样本 0 LSB |
| 回归规模 | 不少于现有 15/15 套件；Release 保留冲激、10 seed×4096、正/负满量程 |
| 复位 | 现有 8 个内部状态恢复场景全部通过 |
| 动态切换 | 现有 10 次无复位倍率切换全部通过，无 X、runt、pending overwrite |
| CDC | 1200 次 request/ack 定向切换通过；bundled bus 约束不退化 |
| 实现 | fully routed；route error=0；WNS>0、WHS>0、TNS=THS=0 |
| DRC | error=0；新增 Critical Warning 必须逐条解释或关闭 |
| 原语审计 | DSP、RAMB18、MMCM 数量必须与目标结构一致，不能只看顶层汇总 |
| 发布 | bitstream、routed DCP、构建日志、源状态和 SHA-256 清单齐全 |

如果候选改变了算法系数或字长，还必须重新生成 MATLAB golden；如果只改变 DSP/BRAM 映射，则必须继续使用 P3-J 原 golden，禁止重新生成一个“顺从新 RTL”的参考答案掩盖错误。

### 2.3 结果等级

文档和 PPT 中统一使用以下措辞：

| 等级 | 允许声明 |
|---|---|
| MATLAB-only | “算法候选通过 MATLAB 门禁” |
| RTL 0 LSB | “定点 RTL 与 MATLAB golden 一致” |
| post-route | “完成 FPGA 工具侧实现与时序签核” |
| bitstream | “已生成可下载位流” |
| physical board | “已完成实板和仪器验证” |

禁止把后一级证据提前写入前一级结果。

---

## 3. P0：P3-J 实物板与强信号证据闭环

### 3.1 物理板下载基线

只下载已签核 bitstream，并首先核对 SHA-256：

```text
8E2C2DB3329BBE519CB8F87249961A35E120A79EE49A2CC706C62D9D037FA85C
```

六档时钟应为：

| 家族 | 4× | 8× | 128× |
|---|---:|---:|---:|
| 44.1 kHz | 176.4 kHz | 352.8 kHz | 5.6448 MHz |
| 48 kHz | 192 kHz | 384 kHz | 6.144 MHz |

建议验收：

1. 每档 `DA_CLK` 相对理论值误差不超过 ±0.5%；
2. 记录频率、占空比、峰峰值、上升/下降时间和探头设置；
3. 15 kHz、0.50FS 演示信号在六档均稳定输出；
4. 家族和倍率各方向至少切换 100 次，记录最长静音窗口、恢复时间和最短高/低脉宽；
5. 不出现持续 DC、随机突跳、缺脉冲、器件失锁或必须重新上电才能恢复的状态；
6. 保存示波器截图、频谱截图、板卡供电、环境温度和 bitstream 哈希。

实板频谱主要证明“主音保留、插值镜像明显受抑、模式切换可工作”。不要用 8-bit DAC 的模拟噪声底替代 70 dB 数字阻带证明。

### 3.2 解决“0 次与 16 次饱和”差异

建立固定测试 `p3_strong_44k1_minus1dbfs`：

1. 从 `p3_01_search_joint_stage3_equalizer.m` 中定位曾触发 16 次饱和的精确频率、幅度、长度、相位和随机种子；
2. 把刺激导出为固定 `.mem`，并记录 SHA-256；
3. 同一刺激分别运行 P4-D MATLAB bit-true、P3-J MATLAB bit-true 和 P3-J RTL；
4. 分开统计 Stage3 输入、Stage3 输出、CIC 内部模运算和最终饱和器，不把不同位置的计数混在一起；
5. 输出首次事件样点、事件总数、峰值和对应模式；
6. 将该向量永久加入 Release，避免后续候选只通过较弱的满量程模式。

判定规则：

- 正确性门禁：P3-J RTL 必须与 P3-J bit-true 0 LSB；
- 相对门禁：同一刺激下 P3-J 饱和次数不得多于 P4-D；
- 音质优选：若 −1 dBFS 单音仍发生最终输出削顶，应单独评估输入 headroom，而不是暗中缩放滤波器增益；
- 所有报告必须同时写出“正式 Release 向量”和“−1 dBFS 专项向量”的计数。

P0 完成后建议生成：

```text
p3j_physical_board_signoff.md
p3j_board_measurements.csv
p3j_strong_signal_saturation_summary.csv
```

---

## 4. P1：P3-J 的 4/3/2-DSP 正交扫描

### 4.1 原理与一阶预估

P3-J 删除的是独立均衡器；`CicIntegratorDspMode` 改变的是 N3 Hold CIC 两级高速积分器映射，两者基本正交：

| `CicIntegratorDspMode` | 第一积分器 | 第二积分器 | 全机 DSP |
|---:|---|---|---:|
| 2 | DSP48E1 | DSP48E1 | 4 |
| 1 | CARRY4/FF | DSP48E1 | 3 |
| 0 | CARRY4/FF | CARRY4/FF | 2 |

旧 P4-C 相对 4-DSP 基线的实测代价为：

\[
\Delta_{3DSP}=+25\ \mathrm{LUT}+26\ \mathrm{FF}
\]

\[
\Delta_{2DSP}=+44\ \mathrm{LUT}+55\ \mathrm{FF}
\]

由此对 P3-J 作一阶外推：

| 候选 | 一阶估算 | 推荐保留门槛 |
|---|---:|---:|
| P3-J / 4 DSP | **432 LUT / 431 FF**（实测） | 已签核 |
| P3-J / 3 DSP | 约 **457 LUT / 457 FF** | LUT≤465，FF≤470 |
| P3-J / 2 DSP | 约 **476 LUT / 486 FF** | LUT≤485，FF≤500 |

这些只是差分外推，不是 Vivado 结果。综合优化可能跨层级重写逻辑，最终只能引用 post-route 数字。

### 4.2 执行步骤

1. 从 P3-J 签核标签新建分支；
2. 固定 `P3JointStage3=1`、所有 FIR/BRAM/时钟参数和 `AreaOptimized_high/full/on + Default`；
3. 只把 `CicIntegratorDspMode` 依次设为 1、0；
4. 先运行 CIC 独立等价测试，覆盖连续输入、随机停顿、burst 内复位和正负满量程；
5. 再运行 P3-J Smoke、Release、复位恢复和动态模式切换；
6. 完成综合、布局布线、DRC、CDC、时序、功耗报告和 bitstream；
7. 审计 primitive：3-DSP 档必须恰为 3 个 DSP48E1，2-DSP 档必须恰为 2 个；
8. 与旧 504/494/3-DSP 和 523/523/2-DSP 点作直接 Pareto 比较。

现有脚本的目标调用形式为：

```powershell
# P3-J 3-DSP
...run_national_finals_vivado_build.ps1 `
  -Step all -P3JointStage3 1 -CicIntegratorDspMode 1

# P3-J 2-DSP
...run_national_finals_vivado_build.ps1 `
  -Step all -P3JointStage3 1 -CicIntegratorDspMode 0
```

若当前脚本尚未暴露 `-P3JointStage3`，应先把该参数显式贯穿 PowerShell→Tcl→top generic→TB wrapper；不能删掉参数后依赖默认值。

### 4.3 Go/No-Go

3-DSP 候选只有同时满足以下条件才保留：

- 4×/8×/128× 0 LSB；
- 饱和计数与 P3-J 同刺激一致；
- LUT≤465、FF≤470；
- 实际 DSP=3；
- 完整 route/timing/CDC/DRC 通过；
- 资源上不再被旧 504/494/3-DSP 点支配。

2-DSP 候选对应门槛为 LUT≤485、FF≤500、实际 DSP=2，其余相同。

即使两者通过，也不自动替代 4-DSP 默认版。XC7A35T 有 90 个 DSP，当前 4 个 DSP 只占 4.44%；低 DSP 版本应作为评分或系统集成明确重罚 DSP 时的 Pareto 选项。

P1-TWO24 只作为备选。它在旧基线上为 518/498/3-DSP，预计与 P3 组合仍可能高于普通 CARRY 3-DSP 路线；只有 P3-J+CARRY 出现异常回归或资源未达门槛时，才值得重新组合验证。

---

## 5. P2：P3-J 的 2/1.5/1-BRAM 正交扫描

### 5.1 1.5 BRAM：优先执行

P4-E 的“PCM ROM 与 Stage1 历史共享”相对旧 P4-D 的实测变化为：

\[
491-479=+12\ \mathrm{LUT},\qquad 487-468=+19\ \mathrm{FF}
\]

与 P3-J 一阶组合约为：

\[
\boxed{444\ \mathrm{LUT}/450\ \mathrm{FF}/4\ \mathrm{DSP}/1.5\ \mathrm{BRAM\ Tile}}
\]

执行时只合入 P4-E 的存储共享，不合入 P2 distributed ROM，不改变两组 Stage3 系数、DSP 映射和时钟。

建议门槛：

```text
优选：LUT≤455，FF≤465
最大继续观察线：LUT≤465，FF≤475
必须：3 RAMB18E1 = 1.5 BRAM Tile
```

同时复测 44.1/48 kHz 首 ROM 地址、Stage1 读延迟、PCM/历史仲裁和动态切换；这些是该路线的真实风险，不是滤波系数。

### 5.2 1 BRAM：再执行

P2-A distributed coefficient ROM 相对 P4-D 的旧实测变化为：

\[
513-479=+34\ \mathrm{LUT},\qquad 496-468=+28\ \mathrm{FF}
\]

乐观组合估算为：

\[
\boxed{466\ \mathrm{LUT}/459\ \mathrm{FF}/4\ \mathrm{DSP}/1\ \mathrm{BRAM\ Tile}}
\]

但该估算可能偏低。P3-J 在 RAMB18E1 中利用空闲地址保存第二组 Stage3 系数，几乎不增加资源；改用 distributed ROM 后，compensated Bank 会真实消耗 LUT，而且综合器可能复制 ROM。因此 1-BRAM 路线必须重新做完整 A/B，不能直接沿用 P2-A 数字。

建议门槛：

```text
LUT≤490，FF≤480，DSP=4
2 RAMB18E1 = 1 BRAM Tile
```

专用 ROM 测试至少覆盖：

1. flat/comp 两组全部有效地址；
2. signed-18 符号扩展；
3. Bank 选择在 pending/job 边界快照；
4. 每地址逐 bit 故障注入，证明测试参考不与 DUT 同错；
5. 综合后无 ROM 复制、无重新推回 BRAM；
6. 动态切档时一个 MAC job 内不得混用两组系数。

P2-B 的“数据输出寄存”旧版比 P2-A 多 20 FF，不作为首选；除非 P3-J 上地址寄存方案出现时序问题，否则不重复实现。

### 5.3 P2 的判定原则

- 1.5-BRAM 候选若达到门槛，应保留为优先低 BRAM 版；
- 1-BRAM 候选即使 LUT 达到 480～490，也仍是有效硬资源 Pareto，但不替代最低 LUT/FF 默认版；
- 如果 1-BRAM 因双 Bank 超过 490 LUT 或 480 FF，应停止，不再通过大范围策略扫描“碰运气”；
- 所有存储候选的输出必须继续与 P3-J 原 golden 0 LSB。

---

## 6. P3：DSP × BRAM 交叉 Pareto

只有 P1、P2 各自独立通过后，才允许做交叉组合。不要一开始就生成全部 3×3 组合。

一阶估算矩阵如下：

| 候选 | LUT/FF 估算 | DSP | BRAM Tile | 是否建议立即做 |
|---|---:|---:|---:|---|
| 当前默认 | **432/431 实测** | 4 | 2.0 | 已完成 |
| 3-DSP | 457/457 | 3 | 2.0 | **是** |
| 2-DSP | 476/486 | 2 | 2.0 | **是** |
| 1.5-BRAM | 444/450 | 4 | 1.5 | **是** |
| 1-BRAM | 466/459 | 4 | 1.0 | **是** |
| 3-DSP + 1.5-BRAM | 469/476 | 3 | 1.5 | 评分同时重罚 DSP/BRAM 时 |
| 3-DSP + 1-BRAM | 491/485 | 3 | 1.0 | 明确需要 1 Tile 时 |
| 2-DSP + 1-BRAM | 510/514 | 2 | 1.0 | 仅作极限研究点 |

交叉估算没有包含综合非线性和第二系数 Bank 的额外 LUT，不能作为最终报告值。

建议只优先构建两个点：

1. `3-DSP + 1.5-BRAM`：较均衡，预计仍低于 500 LUT/FF；
2. `3-DSP + 1-BRAM`：在 BRAM 和 DSP 都紧张时使用。

`2-DSP + 1-BRAM` 只有在评分公式对 DSP/BRAM 的权重远高于 LUT/FF 时才值得实现。它并不是“最优版”，只是硬宏资源最小版。

### 6.1 Pareto 判定

比较维度至少包括：

```text
LUT、FF、Slice、DSP、BRAM Tile、MMCM、WNS、WHS、SAIF dynamic power、证据等级
```

如果候选 A 在所有受关注资源上都不优于 B，且至少一项更差，则 A 被 B 支配，应标记 No-Go。不要通过人为加权总分掩盖这种支配关系。

---

## 7. P4：MMCM 与真实功耗优化

### 7.1 为什么功耗优先级高

P3-J 的逻辑资源占用已经很低：

| 资源 | 数量 | XC7A35T 占用率约值 |
|---|---:|---:|
| LUT | 432 | 2.08% |
| FF | 431 | 1.04% |
| DSP | 4 | 4.44% |
| BRAM Tile | 2 | 4.00% |
| MMCM | 2 | 40.00% |

vectorless 报告中总动态功耗约 0.199 W，两颗 MMCM 合计也约 0.197 W。这只能说明“值得实测”，不能据此直接声称 MMCM 占真实动态功耗的 99%。

### 7.2 路线 A：两个单家族、单 MMCM bitstream

这是最低风险的第一步：

- 44.1 kHz 家族 bitstream：只保留产生 5.6448 MHz 的 MMCM；
- 48 kHz 家族 bitstream：只保留产生 6.144 MHz 的 MMCM；
- 两个版本均继续支持本家族的 4×/8×/128×；
- `family_sel` 在该版本中固定或只作状态显示，不能伪装成仍支持实时跨家族切换。

门禁：

1. post-route 原语审计为 1 MMCM；
2. 本家族三个倍率仍为 0 LSB；
3. WNS/WHS、DRC、CDC、bitstream 通过；
4. 三档 `DA_CLK` 和 DAC 波形实测通过；
5. 与双 MMCM P3-J 使用完全相同的刺激、时长、电压、温度和 SAIF 窗口比较功耗。

该路线牺牲实时家族切换功能，因此是独立低功耗交付物，不应覆盖双家族默认版。

### 7.3 路线 B：双 MMCM、未选 MMCM 动态掉电

如果必须保留 44.1/48 kHz 实时切换，控制 FSM 必须运行在不会被切换的 50 MHz 系统时钟域：

```text
IDLE
→ MUTE
→ WAKE_TARGET
→ WAIT_LOCK
→ LOCK_STABLE
→ SWITCH_CLOCK
→ VERIFY_HEARTBEAT
→ POWER_DOWN_OLD
→ WARMUP
→ UNMUTE
→ IDLE
```

另设 `FAULT` 与回退路径。最低安全要求：

- 任意时刻不得同时关闭两个 MMCM；
- 目标 `LOCKED` 经同步并连续稳定若干个 50 MHz 周期后才能切换；
- 切换前必须静音，切换完成且 heartbeat 正常后才能关闭旧 MMCM；
- `WAIT_LOCK`、`VERIFY_HEARTBEAT` 都有超时；
- 超时后回到原时钟并保持静音或进入可诊断故障态；
- `PWRDWN`、BUFGMUX 选择、模式 ACK 和数据通路复位的先后关系写成断言；
- 不能把 FSM 放在将被关停的音频时钟域。

验证至少包括：

1. UNISIM 正常往返切换 1000 次；
2. 目标 MMCM 永不锁定、延迟锁定、短暂掉锁三类故障注入；
3. 检查 runt pulse、双时钟同时失效和 FSM 死锁；
4. 进入 4×/8×/128× 后的首个有效样点和静音恢复；
5. 实板记录最短高/低脉宽、最长静音时间和 100 次往返成功率；
6. 使用同一 post-route SAIF 和实板电流重复 A/B。

功耗 Go/No-Go 建议：

```text
功能门禁必须全部通过；
同刺激 SAIF 动态功耗下降 ≥20%：Go；
下降 10%～20%：结合是否必须实时切换再决定；
下降 <10%：不值得用复杂时钟 FSM 交换风险；
实板电流下降必须大于仪器重复测量不确定度。
```

### 7.4 路线 C：单 MMCM + DRP

只有在路线 B 已经完成安全切换、故障注入和实板功耗闭环后才研究。DRP 会在重配置期间中断输出时钟，还要维护 divider、fractional、lock/filter 配置表；当前不作为下一步首选。

### 7.5 mode-gated CE

先用 post-route SAIF 查看不同倍率下 Stage3、CIC 和相关 ROM 的层级动态功耗。如果它们合计不足系统动态功耗的 5%，停止该路线。

若占比足够，再考虑：

```text
4×：停止不需要的 Stage3/CIC 更新
8×：停止 CIC 更新
128×：全链运行
```

只门控 CE，不自行生成门控时钟。由于当前动态切换是无复位通过的，门控后会改变隐藏状态；必须定义“后台维持状态”或“切换时复位+暖机+静音”中的一种，不能直接停止状态后仍沿用旧切换协议。

---

## 8. P5：算法与有限字长微优化

该阶段预期收益只有个位数或十位数 LUT/FF，优先级低于 DSP、BRAM 和 MMCM。

### 8.1 signed-20 Stage3 边界约束搜索

当前 compensated Stage3 满量程峰值为 527320，而 signed-20 上限为 524287：

\[
\frac{527320-524287}{524287}=0.579\%
\]

直接整体缩放所需增益为：

\[
20\log_{10}\left(\frac{524287}{527320}\right)=-0.05010\ \mathrm{dB}
\]

这会基本耗尽 ±0.05 dB 绝对通带指标，因此禁止简单 trim。正确做法是搜索 6 个独立对称整数系数：

\[
h=[a,b,c,d,e,f,e,d,c,b,a]
\]

建议目标函数：

\[
J(h)=w_p\delta_{p,abs}+w_r\delta_{p,pp}
+w_s\max(0,71-A_s)^2
+w_o\max(0,P_{max}-524287)^2
+w_g\left|\sum h-65536\right|
\]

其中：

- `h` 保持 Q15、signed-18、整数、严格对称；
- `Pmax` 来自完整 bit-true 链和固定强信号集合，不能只用浮点频响；
- 44.1/48 kHz 六工况联合优化；
- 4×/8× flat Bank 不变；
- 阻带内部门槛建议 ≥71 dB；
- 进入 RTL 前，128× 最大绝对通带偏差建议 ≤0.02 dB。

如果证明 20-bit 安全，再重新推导 CIC 状态宽度；不能直接把 26/29 机械改成 25/28。即使数学上可减 1 bit，在 DSP 映射版上也可能不减少任何资源，因此应先做综合 OOC 预算。

Go 条件：

```text
signed-20 全覆盖不溢出
六工况通过且阻带≥71 dB
RTL 0 LSB
完整 post-route 至少减少 8 LUT 或 8 FF，或明显改善低 DSP CARRY 版
```

否则保留 signed-21。

### 8.2 9-tap compensated Stage3 预筛

先只在 MATLAB 搜索 9-tap 对称候选，不立即改 RTL。进入 RTL 的门槛：

- 最大绝对通带偏差 ≤0.02 dB；
- 阻带 ≥71 dB；
- 严格线性相位；
- signed-20 或 signed-21 强信号均无新增饱和；
- 两相任务拍数确实减少，且不增加 Bank/调度控制；
- OOC 综合预估至少节省 10 LUT 或 10 FF。

11→9 tap 不会减少现有两颗 FIR DSP或 BRAM Tile，当前 72.371 dB 阻带裕量又较小，因此失败概率较高。若 MATLAB 无法同时满足 0.02/71 dB，立即停止，不做 RTL。

### 8.3 暂不采用的算法路线

- 全局 CSD/MCM/CSE：当前 FIR 已使用共享 DSP，系数移位加法可能增加 LUT 和路由；
- DA 分布式算法：会把充足的 DSP 资源换成 LUT/ROM，目标不匹配；
- Hogenauer pruning：会改变 golden，且 DSP 内状态减位未必减少 Slice；
- CIC sharpening、IFIR/FRM：增加新级和控制，当前资源瓶颈不在 FIR 乘法器；
- HLS 自动生成：难以保持现有 cycle-exact、0 LSB、动态切换和原语级证据；
- 所有模式共用 compensated Bank：已有频响 No-Go 证据。

---

## 9. 实验矩阵与停止线

| ID | 唯一变量 | 目标资源 | 先验估算 | 硬停止线 |
|---|---|---:|---:|---|
| E0 | P3-J 基线 | 4 DSP / 2 BRAM / 2 MMCM | 432/431 实测 | 冻结 |
| D1 | CIC mode=1 | 3 DSP | 457/457 | >465 LUT 或 >470 FF |
| D2 | CIC mode=0 | 2 DSP | 476/486 | >485 LUT 或 >500 FF |
| B1 | PCM+Stage1 共享 | 1.5 BRAM | 444/450 | >465 LUT 或 >475 FF |
| B2 | distributed 双 Bank | 1 BRAM | 466/459 乐观值 | >490 LUT 或 >480 FF |
| X1 | D1+B1 | 3 DSP / 1.5 BRAM | 469/476 | >500 LUT 或 >510 FF |
| X2 | D1+B2 | 3 DSP / 1 BRAM | 491/485 | >520 LUT 或 >520 FF |
| M44 | 44.1 单家族 | 1 MMCM | 不预填功耗 | 功能退化或实测收益不明确 |
| M48 | 48 单家族 | 1 MMCM | 不预填功耗 | 功能退化或实测收益不明确 |
| MPD | inactive MMCM 掉电 | 2 实例/1 活动 | 不预填功耗 | SAIF 降幅<10%或切换不安全 |
| A20 | Stage3 signed-20 | 可能少量 LUT/FF | 不预填 | 不满足 0.02 dB/71 dB/峰值门禁 |
| A9 | 9-tap Stage3 | 调度与少量逻辑 | 不预填 | MATLAB 先失败即停止 |

任何候选一旦在较早层级越过停止线，就不再浪费时间生成 bitstream。例如 B2 综合已明显超过 490/480，可在确认不是配置错误后直接 No-Go。

---

## 10. 每个候选必须保存的产物

建议每个候选使用独立结果目录，至少包含：

```text
config.json
source_state_at_build_start.json
synthesis_sources.txt
matlab_frequency_metrics.csv
saturation_summary.csv
rtl_smoke_full_chain_xsim.log
rtl_release_full_chain_xsim.log
reset_recovery_xsim.log
dynamic_mode_switch_xsim.log
utilization_synthesized.rpt
utilization_placed.rpt
utilization_hierarchical.rpt
dsp_utilization_routed.rpt
bram_utilization_routed.rpt
mmcm_utilization_routed.rpt
timing_summary_routed.rpt
cdc_routed.rpt
drc_routed.rpt
power_vectorless_routed.rpt
power_saif_routed.rpt              # 功耗阶段必需
national_finals_board_routed.dcp
candidate.bit
release_manifest.json
SHA256SUMS
decision.md
```

`decision.md` 只回答四个问题：

1. 改了什么唯一变量；
2. 功能、频响和饱和是否保持；
3. post-route 资源和时序相对 P3-J 如何变化；
4. Go、No-Go 还是仅保留为 Pareto，理由是什么。

---

## 11. 最终推荐交付形态

下一轮结束后不应强行只保留一个版本，而应形成最多四个清晰交付点：

| 用途 | 推荐版本 |
|---|---|
| 默认最低 LUT/FF、完整双家族 | P3-J 4-DSP / 2-BRAM / 2-MMCM |
| DSP 受限 | 通过门禁后的 P3-J 3-DSP 或 2-DSP |
| BRAM 受限 | 通过门禁后的 P3-J 1.5-BRAM 或 1-BRAM |
| 功耗优先 | 单家族单 MMCM，或完成安全 FSM 的动态掉电版 |

默认版只有在新候选同时满足以下条件时才替换：

1. 所有功能和证据等级不下降；
2. 至少减少一种明确稀缺资源；
3. LUT/FF、时序、功耗和切换风险代价符合对应门槛；
4. 已完成与基线相同等级的 clean build、bitstream 和实物板验证。

---

## 12. 明确停止的路线

本阶段不要重复投入：

1. 大范围 Vivado 策略扫描：Default、AddRemap、Explore 已同分，其他策略更差；
2. 单纯 CREG→PREG 面积优化：routed DCP 已证明不存在可直接删除的 Slice 状态 FF；
3. X3 20 MHz 统一三级 FIR：功能虽 0 LSB，但核心增加 533 LUT、331 FF 和 1 BRAM Tile；
4. TWO24 作为默认 3-DSP 路线：旧实测 518/498，先完成更简单的 CARRY 正交组合；
5. 直接整体降低 compensated Stage3 增益：需要 −0.05010 dB，触碰绝对通带指标；
6. 未做 MATLAB 门禁就直接把 11 tap 改成 9 tap；
7. 在未完成 PWRDWN 安全 FSM 前直接做单 MMCM DRP；
8. 用 vectorless 0.001 W 差异宣称节能；
9. 用 8-bit DAC 板测噪声底宣称 72 dB 数字阻带；
10. 把 bitstream 生成成功写成实板通过。

---

## 13. 建议立即开始的最小任务单

```text
[ ] 冻结并备份 P3-J 签核标签、manifest、bit/DCP SHA-256
[ ] 固化曾出现 16 次饱和的 −1 dBFS 精确向量
[ ] 在 P3-J 分支显式设置 P3JointStage3=1
[ ] 运行 CicIntegratorDspMode=1 的全链回归与 post-route
[ ] 运行 CicIntegratorDspMode=0 的全链回归与 post-route
[ ] 输出 4/3/2-DSP P3-J 实测对比表
[ ] 从纯 P3-J 重新合入 1.5-BRAM 路线并验证
[ ] 再独立实现 1-BRAM 双 distributed Bank
[ ] 根据实际评分权重决定是否构建交叉 Pareto
[ ] 物理板可用时完成六档 DA_CLK、波形、切换和功耗记录
[ ] 面积 Pareto 冻结后再建立 MMCM 功耗分支
[ ] 最后才运行 signed-20/9-tap MATLAB 预筛
```

本轮最可能得到的有效结果不是“一个版本同时把所有资源都降到最低”，而是：

\[
\boxed{
\text{P3-J 默认最低 LUT/FF}
+\text{新 3/2-DSP Pareto}
+\text{新 1.5/1-BRAM Pareto}
+\text{独立低功耗时钟版本}
}
\]

这比继续追逐个位数 LUT 更有工程价值，也更容易形成论文中完整的“算法—RTL—资源—时序—功耗—实板”证据链。

---

## 14. 本指导依据

- `p3_joint_stage3_rtl_signoff.md`
- `p4d_export_audit_and_next_optimization_guide_v2_execution_feedback(2).md`
- `release_manifest_p3_joint_stage3.json`
- `p4b_rtl_next_optimization_guide_execution.md`
- `p4c_rtl_deep_audit_and_next_optimization_guide_execution.md`
- `x3_20m_unified_fir_nogo.md`

文中的 432/431、六工况、时序、bit/DCP 哈希为已签核结果；457/457、476/486、444/450、466/459 及交叉矩阵均为基于既有版本增量的一阶估算，必须由新一轮 Vivado post-route 替换后才能作为实现结论。
