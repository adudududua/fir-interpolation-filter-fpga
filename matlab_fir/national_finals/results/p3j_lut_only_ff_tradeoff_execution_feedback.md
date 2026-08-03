# P3-J 4-DSP LUT-only / FF 换 LUT 优化执行反馈

## 1. 目标与验收门槛

本轮从已签核的 `424 LUT / 431 FF / 169 Slice / 4 DSP / 2 BRAM Tile / 2 MMCM` P3-J Packed-ROM 版本出发，只允许用少量 FF 换取 LUT，不改变滤波系数、字长、舍入、饱和、输出序列或板级接口。

Go 条件固定为：

- post-route LUT 必须小于 424；
- DSP=4、BRAM Tile=2、MMCM=2；
- FF 目标不超过 440，绝对上限 448；
- WNS/WHS 均为正，DRC/CDC 门禁不变；
- RTL 位真、复位、动态切档和真实 RAMB18 原语测试全部通过。

综合 LUT 只用于快速筛选，最终结论一律以 `utilization_placed.rpt` 为准。

## 2. 已执行候选

### 2.1 系数 BRAM parity 携带终止标志

统一系数 RAMB18E1 中所有系数都能用 signed-17 表示，因此尝试把 parity bit 17 改作 Stage1/Stage2/Stage3 的末次 MAC 标志，parity bit 16 保留真实符号。Stage1 和 Stage2/3 调度器由 BRAM 标志结束 MAC，并删除 Stage1 的冗余 `active_fill_count` 快照。

该候选通过完整 Smoke RTL 回归 15/15；真实 RAMB18E1 原语同时验证了系数值和终止标志，Stage1、Stage2/3、全链路、8 个复位场景和 10 次动态切档均通过。但实现结果为 430 LUT，未达到门槛。

### 2.2 键盘去抖移位历史与列号推导

尝试用 5-bit 稳定历史替换 3-bit 饱和计数，并由 one-hot `kr_drive_low` 推导扫描列号，删除独立 `scan_idx`。键盘定向仿真通过；保留层级综合中键盘模块少 1 LUT，但顶层多 1 LUT，全局仍为 453 LUT，净收益为 0，未进入实现。

### 2.3 CIC 尾突发移位状态

尝试以 15-bit 连续 1 移位状态替换 4-bit `burst_remaining` 递减计数器，删除减法器、非零比较和末项比较。该结构增加约 11 FF，符合本轮 FF 预算；CIC 三种 DSP 模式、连续/停顿、10×256 随机、4096 输出和半途复位等价仿真全部通过。

Vivado 2018.3 对带复位/使能的 15-bit 移位状态仍生成额外选择逻辑，综合反而由 453/428 增至 457 LUT/439 FF，因此按 Stop/Go 在实现前回退。

### 2.4 共享启动延时与键盘扫描计数

原板级顶层同时使用 16-bit 上电计数终止译码和低 14-bit 键盘扫描节拍。候选改为累计四个既有 16384-cycle 扫描周期，保持复位仍在第 65535 个 20 MHz 周期释放，扫描周期仍为 16384；板级集成仿真中的 SW2/SW6、音频域复位和采样率切换均通过。

组合在系数标志候选上时，综合降到 451 LUT，但默认实现为 429 LUT；单独作用于原始 424-LUT 基线时，综合为 452 LUT，默认实现为 427 LUT。两者均未低于基线。

## 3. 实测资源、时序和功耗

| 候选 | Synth LUT/FF | Placed LUT/FF/Slice | DSP | BRAM Tile | WNS/WHS | 功耗（总/动态/静态） | 结论 |
|---|---:|---:|---:|---:|---:|---:|---|
| 原始 P3-J Packed-ROM | 453/433 | **424/431/169** | 4 | 2 | **+45.042/+0.080 ns** | 0.271/0.199/0.072 W | 当前最优 |
| 系数 BRAM 终止标志 | 453/428 | 430/426/177 | 4 | 2 | +45.674/+0.096 ns | 0.271/0.199/0.072 W | No-Go：少 5 FF，多 6 LUT |
| 键盘移位去抖 | 453/428 | 未实现 | 4 | 2 | — | — | No-Go：综合净 0 LUT |
| CIC 15-bit 移位尾状态 | 457/439 | 未实现 | 4 | 2 | — | — | No-Go：综合多 4 LUT |
| 系数标志 + 共享启动计数 | 451/428 | 429/426/182 | 4 | 2 | +45.156/+0.056 ns | 0.271/0.199/0.072 W | No-Go：综合少 2 LUT，placed 多 5 LUT |
| 仅共享启动计数 | 452/433 | 427/431/173 | 4 | 2 | +44.926/+0.096 ns | 0.271/0.199/0.072 W | No-Go：placed 多 3 LUT |
| 原始 RTL 同环境重新实现 | 453/433 | **424/431/169** | 4 | 2 | **+45.042/+0.080 ns** | 0.271/0.199/0.072 W | 精确复现基线 |

## 4. 实现策略扫描

固定“系数标志 + 共享启动计数”的同一份 451-LUT 综合 DCP，单进程扫描全部受支持的小范围 `opt_design` 策略：

| `opt_design` 策略 | Placed LUT | FF | Slice | WNS/WHS | 结果 |
|---|---:|---:|---:|---:|---|
| Default | 429 | 426 | 182 | +45.156/+0.056 ns | 最小但未过门槛 |
| Explore | 429 | 426 | 182 | +45.156/+0.056 ns | 与 Default 相同 |
| AddRemap | 429 | 426 | 182 | +45.156/+0.056 ns | 与 Default 相同 |
| ExploreWithRemap | 429 | 426 | 182 | +45.156/+0.056 ns | 与 Default 相同 |
| ExploreArea | 495 | 426 | 189 | +45.624/+0.075 ns | 明显更差 |

这证明“综合 LUT 更低”不等于“实现 LUT 更低”。原始结构在 `opt_design` 中能从 453 LUT 合并到 424 LUT；候选增加的标志网络或改变的计数结构破坏了部分跨层合并，最终面积反而增加。

## 5. 验证证据

- 完整 Smoke RTL：15/15 PASS；运行目录 `matlab_fir/national_finals/_work/rtl_regression/20260803_185922`；
- 系数 RAMB18E1：系数与 Stage1/Stage2/3 终止标志全部 PASS；
- CIC 移位状态：DSP 模式 2/1/0、连续 320、停顿 480、10×256 随机、半途复位、4096 输出全部等价；
- 板级共享启动计数：reset=65535、scan=16384，SW2/SW6 和采样率切换 PASS；
- 所有完成实现的候选均通过时序、DRC、CDC 和 bitstream 生成；
- 原始 RTL clean rebuild 精确复现 424 LUT、431 FF、169 Slice 和 +45.042/+0.080 ns，排除工具口径或随机波动造成的假比较。

本轮没有可用物理板，因此上述结论是 MATLAB/RTL/实现/bitstream 工具侧验证，不宣称新候选完成实板验证。最终推荐继续使用此前已签核、待本轮实物复测的 424-LUT bitstream。

## 6. Git 回退路线

| 用途 | 分支/标签 | 提交 | 状态 |
|---|---|---|---|
| 当前推荐 424-LUT 版本 | `national-finals-p3j-4dsp-bram-microengine` / `nf-p3j-final-424lut-431ff-169slice-4dsp-2bram-packedrom` | `d07da37` | 保留 |
| 系数标志实验 | `national-finals-p3j-4dsp-lut-only` / `nf-p3j-experiment-430lut-426ff-4dsp-2bram-coeffflags` | `50e033f` | No-Go 备份 |
| 组合实验 | `national-finals-p3j-4dsp-lut-only` / `nf-p3j-experiment-429lut-426ff-4dsp-2bram-combined` | `e316d9c` | No-Go 备份 |
| 顶层单变量实验 | `national-finals-p3j-4dsp-lut-toponly` / `nf-p3j-experiment-427lut-431ff-4dsp-2bram-toponly` | `bbbf001` | No-Go 备份 |

本轮所有新分支和提交均未使用 `codex/` 前缀。

## 7. 最终结论

在 `DSP=4、BRAM Tile=2、MMCM=2、滤波响应与位真序列不变、FF<=448` 的约束下，本轮没有找到低于 424 LUT 的可行版本。424 LUT / 431 FF / 169 Slice 仍是当前综合最优且可重复的发布候选。若后续还要求显著下降到 300 或 200 多 LUT，需要放宽至少一个结构约束，例如增加 BRAM、增加 DSP、降低板级功能，或重新定义可接受的算法/字长误差；仅靠小幅增加 FF 已没有实测收益。
