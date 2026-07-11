# 全 2x MATLAB 后续优化与 RTL 落地指导文件执行反馈

## 1. 反馈对象

本报告用于反馈以下指导文件的实际执行情况：

```text
matlab_fir/all2x_matlab_next_steps_guide.md
```

当前目标为：

```text
输入采样率：44.1 kHz
输出采样率：5.6448 MHz
插值倍数：128 倍
结构：2x × 2x × 2x × 2x × 2x × 2x × 2x
数据格式：24 bit signed
```

## 2. 总体结论

指导文件的总体路线具有较高参考价值，特别是以下主线是正确的：

1. 先修正插值增益和通带判定，再进入 RTL。
2. 建立逐级 bit-true 定点模型。
3. 自动计算系数和累加器位宽。
4. 导出 RTL 参数和 golden 测试向量。
5. Stage 1 使用单 DSP 时分复用，后级使用短 FIR。
6. 用 MATLAB 与 RTL 逐点对拍，而不是只观察波形。
7. 最终使用 Vivado 实际综合结果判断资源优劣。

这些核心建议已经执行，并进一步完成了板级接入、布局布线和 bitstream 生成。

但指导文件并非所有建议都原样采用。其中最重要的例外是“后六级统一使用 `Fs_in_stage - 20 kHz` 作为阻带起点”。实测证明该定义不能保证最终等效滤波器从 24.1 kHz 开始全阻带均达到 70 dB，因此最终采用了更严格的阻带定义。

## 3. 按指导章节逐项反馈

| 指导章节 | 建议内容 | 执行状态 | 说明 |
|---|---|---|---|
| 第 1 章 | 确认当前 MATLAB 结构和结果 | 已采用 | 已重新生成最终频响、逐级参数和总链路结果 |
| 第 2.1 章 | 后级阻带起点改为 `Fs_in_stage - 20 kHz` | 未原样采用 | 试跑后总阻带仅约 66.15 dB，改用更严格定义 |
| 第 2.2 章 | 增加通带最大绝对误差判定 | 已采用 | 最终 `pass_abs_max_db = 0.00729793 dB` |
| 第 2.3 章 | 每级补偿 2 倍插值增益 | 已采用 | 系数设计时乘 2，RTL 正常右移 `FRAC_W` |
| 第 3 章 | 不固定 `COEFF_W = FRAC_W + 2` | 部分采用 | 搜索阶段仍固定，RTL 导出阶段重新计算最小位宽 |
| 第 4 章 | 后级扩展到 Q6~Q10 和更大裁剪阈值 | 暂未采用 | 当前统一搜索 Q12~Q16 已满足指标并完成硬件实现 |
| 第 5 章 | Pareto 候选集与 beam search 联合优化 | 暂未采用 | 当前采用逐级搜索、分级指标分配和总链路复核 |
| 第 6 章 | 使用 CSD/二进制加法成本选方案 | 暂未采用 | 用三版 Vivado 实际综合替代代理成本判断 |
| 第 7 章 | 理论计算累加器位宽 | 已采用 | 输出 `ACC_W_MIN` 和 `ACC_W_RECOMMENDED` |
| 第 8 章 | 建立 2 相 polyphase bit-true 模型 | 已采用 | 已完成逐级 24 bit 舍入、饱和和溢出建模 |
| 第 9 章 | 增加冲激、直流、正弦、小信号、满幅和随机 PCM | 基本采用 | 已覆盖主要测试，未单独增加满幅锯齿和 -20 dBFS |
| 第 10 章 | 输出 MSE、SNR、SINAD、THD 等指标 | 部分采用 | 已输出增益、SNR、饱和、溢出和零输出率，未实现 THD/SINAD |
| 第 11 章 | 导出完整 RTL 配置和测试向量 | 已采用 | 已导出 CSV、Verilog 参数、输入与 golden `.mem` |
| 第 12 章 | Stage 1 单 DSP，后级短 FIR/no-DSP | 已采用并调整 | Stage 1 单 DSP；Stage 2~7 强制使用 LUT |
| 第 13 章 | MATLAB RTL 资源代理函数 | 暂未采用 | 直接用 Vivado 综合三种结构，结果更可靠 |
| 第 14 章 | 将主脚本拆成 01~07 七个脚本 | 部分采用 | 已按 bittrue、rtl_export、compare 分目录，但未按建议名称完全拆分 |
| 第 15 章 P0 | 增益、绝对通带、bit-true、测试 | 已完成 | 除阻带公式按实测修正外，其余核心项目均完成 |
| 第 15 章 P1 | Q6、CSD、Pareto、联合搜索 | 部分完成 | 自动位宽已完成，其余高级搜索未做 |
| 第 15 章 P2 | RTL、向量、对拍、综合 | 已完成 | 还进一步完成布局布线和 bitstream |
| 第 16 章 | 生成最终资源与性能对比表 | 已采用 | 已生成 `all2x_final_comparison.csv` |
| 第 17 章 | 浮点、定点和资源验收 | 已采用 | 当前结果均满足建议的工程余量 |
| 第 18 章 | 按优先级进入 RTL | 基本完成 | 核心确认完成后才进入 RTL；低字长扩展未执行 |

## 4. 已按照指导文件完成的关键部分

### 4.1 每级 2 倍插值增益补偿

指导文件指出，插零会使平均幅度减半，因此每级 2x FIR 应满足：

```math
\sum_n h[n] \approx 2
```

当前脚本在滤波器设计后执行：

```matlab
b_float = interp_gain * firpm(n, fo, ao, w);
```

其中：

```matlab
interp_gain = 2;
```

每一级还检查：

```text
dc_gain      ≈ 2
phase0_gain  ≈ 1
phase1_gain  ≈ 1
```

最终七级总直流增益为：

```text
128.0185460294
```

目标值为 128，说明每级插值增益已经正确补偿。板级 DAC 显示逻辑也删除了旧链路使用的 128x 左移 4 位补偿，避免新链路被再次放大而削顶。

### 4.2 通带最大绝对误差判定

指导文件建议不能只分别检查平均增益和相对平均值的纹波，还要直接计算：

```matlab
pass_abs_max_db  = max(abs(pass_db));
pass_abs_peak_db = max(pass_db);
pass_abs_min_db  = min(pass_db);
```

该建议已经完整采用。最终结果为：

| 指标 | 结果 |
|---|---:|
| 通带最大绝对误差 | 0.00729793 dB |
| 通带最高点 | +0.00554399 dB |
| 通带最低点 | -0.00729793 dB |
| 赛题限制 | ±0.05 dB |

### 4.3 自动系数位宽和累加器位宽

主设计搜索阶段仍使用 `COEFF_W = FRAC_W + 2` 作为设计容器，但在进入 bit-true 和 RTL 导出前，会根据实际整数系数重新计算：

```text
COEFF_W_MIN
ACC_W_MIN
ACC_W_RECOMMENDED = ACC_W_MIN + 1
```

最终 RTL 使用最小系数位宽和推荐累加器位宽，而不是照搬设计阶段的较宽容器。

| Stage | COEFF_W_MIN | FRAC_W | ACC_W_RECOMMENDED |
|---:|---:|---:|---:|
| 1 | 17 | 16 | 43 |
| 2 | 16 | 15 | 41 |
| 3 | 15 | 14 | 40 |
| 4 | 16 | 15 | 41 |
| 5 | 14 | 13 | 39 |
| 6 | 13 | 12 | 38 |
| 7 | 14 | 12 | 38 |

### 4.4 逐级 bit-true 定点模型

已按指导文件建立以下模块：

```text
alt_all2x/bittrue/round_shift_sat_signed.m
alt_all2x/bittrue/interp2_polyphase_bittrue.m
alt_all2x/bittrue/simulate_all2x_bittrue.m
alt_all2x/bittrue/validate_all2x_bittrue.m
```

模型包含：

1. 2 相 polyphase 计算。
2. 每级整数乘加。
3. 累加器位宽检查。
4. 与 RTL 一致的有符号舍入。
5. 24 bit 输出饱和。
6. 每级输出重新进入下一级。

正常音频测试均无累加器溢出和输出饱和。

### 4.5 定点测试信号

已完成的主要测试包括：

| 测试 | 结果 |
|---|---|
| 冲激输入 | 通过 |
| 直流常数 | 通过 |
| 1 kHz，-1 dBFS | 增益误差 -0.003740 dB，SNR 83.409 dB |
| 19 kHz，-6 dBFS | 增益误差 -0.000487 dB，SNR 80.699 dB |
| 20 kHz，-6 dBFS | 增益误差 -0.007778 dB，SNR 77.059 dB |
| 1 kHz，-60 dBFS | 通过 |
| 1 kHz，-90 dBFS | 通过 |
| 1 kHz，-110 dBFS | 输出未异常归零 |
| 随机 21 bit PCM | 通过 |
| 正满幅、负满幅、满幅交替 | 边界饱和逻辑工作正常 |

满幅测试允许出现 24 bit 输出饱和，其目的不是证明满幅信号完全无削顶，而是验证饱和边界和正负数处理正确。

### 4.6 RTL 参数和 golden 向量导出

已生成：

```text
alt_all2x/rtl_export/all2x_rtl_stage_config.csv
alt_all2x/rtl_export/all2x_rtl_stage_params.vh
alt_all2x/rtl_export/all2x_random_input_24bit.mem
alt_all2x/rtl_export/all2x_random_golden_24bit.mem
alt_all2x/rtl_export/all2x_random_vector_summary.txt
```

随机向量包含 128 个输入样点和 22907 个 golden 输出样点，生成过程无累加器溢出、无输出饱和。

### 4.7 MATLAB 与 RTL 逐点对拍

| 对拍项目 | 样点数 | 最大误差 | 不一致点数 |
|---|---:|---:|---:|
| 冲激响应 | 6651 | 0 LSB | 0 |
| 随机 PCM | 22907 | 0 LSB | 0 |

这比仅观察 RTL 波形更严格，说明系数顺序、偶奇相、舍入、饱和和流水延迟均与 MATLAB 模型一致。

### 4.8 RTL 资源映射建议

指导文件建议 Stage 1 使用单 DSP 时分复用，后级使用短 FIR。该方向已经采用，但时钟周期判断根据本工程实际结构进行了调整。

当前 RTL 工作时钟不是指导文件示例中的 100 MHz，而是最终 DAC 时钟 5.6448 MHz。Stage 1 的 2x 输出 CE 每 64 个时钟周期到来一次，对称结构需要 47 次乘加，因此一个 DSP 仍然足够：

```text
可用周期：64
所需乘加：47
结论：单 DSP 可以在下一个 ce2_out 前完成
```

最终映射为：

```text
Stage 1：单 DSP 时分复用 MAC
Stage 2~7：LUT 常系数乘法
```

### 4.9 实际综合对比

指导文件强调最终应以 Vivado 实测资源为准。已经综合三种结构：

| 方案 | LUT | FF | DSP | WNS |
|---|---:|---:|---:|---:|
| 原 4x + 5 级 2x | 9002 | 4497 | 2 | +165.584 ns |
| 全 2x 直接并行 | 9376 | 4118 | 38 | +134.988 ns |
| 全 2x 单 DSP + LUT 后级 | 5912 | 4218 | 1 | +165.930 ns |

最终全 2x 独立插值链相对原结构减少：

```text
LUT：34.3%
FF ：6.2%
DSP：50.0%
```

## 5. 调整后采用的部分

### 5.1 阻带起点没有照抄指导公式

指导文件建议所有级统一使用：

```matlab
f_stop_begin = Fs_in_stage - f_pass_high;
```

其中 `f_pass_high = 20 kHz`。

该公式只考虑当前级理想 0~20 kHz 基带对应的最近镜像入口，但最终赛题验收要求是：从 24.1 kHz 开始直到最终 Nyquist 频率，所有阻带频点都必须低于 -70 dB。

实测试跑统一公式后，总链路在约 66 kHz 处出现约 -66.15 dB 的峰值，最终阻带不合格。原因是前级 20~24.1 kHz 过渡带中的残留能量在后续上采样时也会形成镜像，后级不能只按照 20 kHz 理想通带边界设计。

最终采用：

```matlab
Stage 1:
    f_stop_begin = 24.1 kHz

Stage 2~7:
    f_stop_begin = Fs_in_stage - 24.1 kHz
```

当前结果：

```text
总阻带衰减 = 77.67936345 dB
阻带余量   = 7.67936345 dB
```

因此，这一项不是遗漏指导，而是经过试跑后根据最终等效滤波器指标主动修正。

### 5.2 系数位宽优化分成两个阶段

指导文件建议搜索阶段直接使用最小 `COEFF_W`。当前实现采用两阶段方式：

1. MATLAB 搜索时使用 `FRAC_W + 2`，保证候选系数不会因容器太窄被误删。
2. 候选确定后，根据真实整数系数计算 `COEFF_W_MIN`。
3. RTL 使用 `COEFF_W_MIN`，不是使用搜索容器位宽。

这种实现没有完全照抄指导文件，但最终硬件位宽已经达到指导目标。后续若要扩大候选空间，可再把最小位宽计算移入主搜索循环。

### 5.3 脚本结构没有完全按 01~07 命名拆分

当前仍保留一个主设计脚本：

```text
design_all2x_interp128_compare.m
```

但 bit-true、RTL 导出和 RTL 对拍已经拆分为独立模块：

```text
alt_all2x/bittrue/
alt_all2x/rtl_export/
compare_all2x_rtl_impulse_tb.m
compare_all2x_rtl_random_tb.m
```

没有继续拆分候选生成和联合搜索，是因为当前尚未实现 Pareto/beam search，强行拆成七个入口会增加调用复杂度而没有实际收益。

## 6. 暂未采用的部分及原因

### 6.1 后级 Q6~Q10 搜索

当前主脚本仍统一搜索：

```matlab
FRAC_W_LIST = [16 15 14 13 12];
```

没有扩展到 Q6~Q10，原因如下：

1. 当前总通带最大误差仅 0.0073 dB，阻带有 7.68 dB 余量。
2. 最终 RTL 只使用 1 个 DSP，LUT 也已经低于原方案。
3. 继续压缩后级字长会增加重新量化、bit-true、RTL 系数更新和对拍工作。
4. 比赛交付阶段优先保持已经通过 0 LSB 对拍和布局布线的稳定版本。

该项属于可继续探索的资源优化，不是当前正确性所必需。

### 6.2 Pareto 候选集和 beam search

当前没有保存每级多个 Pareto 候选，也没有执行跨七级 beam search。

当前方式是：

1. 为不同级分配不同的单级纹波和阻带目标。
2. 每级搜索最少非零半系数方案。
3. 级联后重新检查最终总链路。
4. 不合格时调整单级目标并重新搜索。

没有实现 beam search 的主要原因是组合搜索代码量和运行时间较大，而当前方案已经达到频响、资源和时序目标。若后续目标变成“证明全局最优”，则应补做该项。

### 6.3 CSD 成本模型

当前没有实现 CSD 编码和 `csd_add_count`。

原因是 Vivado 对常系数乘法会进行自身优化，理论 CSD 加法数不一定等于最终 LUT。当前已经直接综合：

```text
并行 DSP 版本
Stage 1 单 DSP + 后级 DSP 版本
Stage 1 单 DSP + 后级 LUT 版本
```

实际综合结果已经给出了更可靠的资源选择依据。CSD 仍可用于 MATLAB 早期筛选，但不影响当前最终结论。

### 6.4 MATLAB RTL 资源代理函数

指导文件建议实现 `estimate_rtl_cost`。当前未实现该代理函数，而是直接使用 Vivado 层级综合报告。

原因是本工程规模可控，实际综合耗时可以接受，而且最终资源会受到：

1. 常系数值。
2. 位宽。
3. Vivado 共享与化简。
4. 输出端口是否保留。
5. DSP 推断属性。
6. 层级优化。

这些因素影响，简单代理函数容易误判。

### 6.5 THD、SINAD 和活动文件功耗

当前 bit-true 报告实现了增益误差、拟合 SNR、饱和和溢出统计，但没有实现 THD、SINAD 和完整频谱失真分析。

板级功耗已经生成，结果为：

```text
0.168 W
```

但没有使用仿真活动文件，Vivado 标记为 Low confidence。因此该功耗只能作为初步估计，不能作为最终高精度功耗结论。

## 7. 超出指导文件完成的工作

在完成指导文件核心路线后，还进一步完成了：

1. 将全 2x 链路接入正式板级顶层。
2. 当前版本固定使用 44.1 kHz / 5.6448 MHz，不再实例化 48 kHz MMCM。
3. 增加 20 MHz 按键域到音频域的两级 `mode_sel` 同步器。
4. 修正异步时钟组 XDC，消除跨时钟时序违例。
5. 上电默认选择 128x，理论 `DA_CLK = 5.6448 MHz`。
6. 删除旧链路的 128x 左移 4 位 DAC 显示补偿。
7. 完成板级综合、布局布线、DRC 和 bitstream 生成。

板级 post-route 结果：

| 项目 | 结果 |
|---|---:|
| LUT | 6426 / 20800 |
| FF | 4416 / 41600 |
| DSP | 1 / 90 |
| WNS | +44.635 ns |
| TNS | 0 ns |
| WHS | +0.093 ns |
| THS | 0 ns |

## 8. 当前仍可继续的优化

如果后续还要继续追求极限资源或更完整的答辩数据，建议按以下顺序进行：

1. 增加 THD、SINAD 和频谱失真测试。
2. 使用 RTL 仿真活动文件重新评估功耗，提高功耗报告置信度。
3. 将 Stage 4~7 的 `FRAC_W` 搜索扩展到 Q6~Q11。
4. 为每级保留 Pareto 候选并实现 beam search。
5. 增加 CSD 成本统计，与 Vivado LUT 结果拟合。
6. 上板测量 4x、8x、128x 的 DA_CLK 和 DAC 输出频谱。

这些项目属于进一步优化或完善材料，不影响当前版本满足赛题核心指标。

## 9. 证据文件

| 内容 | 文件 |
|---|---|
| MATLAB 主设计 | `alt_all2x/design_all2x_interp128_compare.m` |
| 最终浮点/量化结果 | `alt_all2x/all2x_interp128_summary.txt` |
| 总链路频响图 | `alt_all2x/all2x_interp128_response.png` |
| bit-true 验证 | `alt_all2x/bittrue/all2x_bittrue_summary.txt` |
| RTL 参数配置 | `alt_all2x/rtl_export/all2x_rtl_stage_config.csv` |
| 随机 golden 摘要 | `alt_all2x/rtl_export/all2x_random_vector_summary.txt` |
| 冲激 RTL 对拍 | `alt_all2x/all2x_rtl_impulse_compare_summary.txt` |
| 随机 RTL 对拍 | `alt_all2x/all2x_rtl_random_compare_summary.txt` |
| 最终结构对比 | `alt_all2x/all2x_final_comparison.csv` |
| 分析总报告 | `interp128_scheme_analysis_report.md` |
| 板级结果说明 | `../XC7A35T_interp_audio_pcm_wordlen_opt/reports_all2x_board/README.md` |
| 板级时序报告 | `../XC7A35T_interp_audio_pcm_wordlen_opt/reports_all2x_board/timing_board_all2x_post_route.txt` |
| 板级 bitstream | `../XC7A35T_interp_audio_pcm_wordlen_opt/reports_all2x_board/board_demo_competition_dac8_top_all2x.bit` |

## 10. 最终反馈结论

本工程没有机械地照搬指导文件，而是采用了其中对正确性和 RTL 落地最关键的部分，并对不适合最终全阻带验收的阻带公式进行了实测修正。

当前已经完成：

```text
MATLAB 设计与频响验证
每级 2 倍插值增益补偿
绝对通带误差检查
自动最小位宽与累加器位宽
逐级 bit-true 验证
冲激与随机 PCM 0 LSB 对拍
实际 Vivado 资源对比
板级接入、布局布线与 bitstream
```

暂未完成的内容主要是 Pareto/beam search、CSD 代理成本、Q6~Q10 极限字长搜索和 THD/SINAD。这些属于进一步追求全局最优或完善评测维度的工作，不影响当前版本达到赛题要求并具备上板条件。
