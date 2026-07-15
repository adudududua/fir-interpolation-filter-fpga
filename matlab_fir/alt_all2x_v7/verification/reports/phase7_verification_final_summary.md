# Phase 7 FIR-CIC 最终验证汇总

## 1. 验证结论

正式候选 `interp128_all2x_v7_folded_fir_cic_top_ce` 的 MATLAB 位真、RTL 逐点对拍、CIC 定向测试、补码边界、复位恢复、动态切档、RTL 冲激频谱以及 Vivado 实现均已通过。

当前自动化发布判定为 **PASS**。板级已有上一版 Phase 7 静态验证结果；由于本轮修复了动态切档时钟毛刺，新的 bitstream 仍需人工下载并补做一次动态切档复测，完成后才能把“本次 bitstream 板级闭环”标为 PASS。

## 2. 正式配置

```text
44.1 kHz / 24 bit signed PCM
  -> Stage1 2x strict halfband，105 tap
  -> 24 bit 输出
  -> Stage2 2x true polyphase，17 tap
  -> 22 bit 输出
  -> Stage3 2x folded compensation FIR，11 tap
  -> 20 bit 输出
  -> CIC16，R=16，M=1，N=3，FULL_W=32，PRUNE=0
  -> 5.6448 MHz / 24 bit signed PCM
```

| 节点 | 等效冲激长度 | 固定 valid 对齐 | 说明 |
|---|---:|---:|---|
| 4x | 225 | 3 | 独立 FIR 插值节点 |
| 8x | 459 | 7 | CIC 预加重内部展示节点 |
| 128x | 7374 | 112 | 最终赛题验收节点 |

128x 冲激响应为偶长度对称序列，群延迟为 `(7374-1)/2 = 3686.5` 个最终输出样点。

## 3. RTL 位真与定向回归

| 类别 | 测试规模 | 最大误差 / 异常 | 结果 |
|---|---:|---:|---|
| 正式顶层冲激 | 256 个输入样点 | 4x/8x/128x 均 0 LSB | PASS |
| daily 随机 PCM | 4 seed × 1024 | 三节点均 0 LSB | PASS |
| nightly 随机 PCM | 10 seed × 4096 | 三节点均 0 LSB | PASS |
| nightly 128x 比较量 | 5,315,520 个随机输出点 | 0 mismatch | PASS |
| CIC 定向流 | 656 个实际输入、10496 个输出 | 0 LSB、0 valid 空洞 | PASS |
| CIC comb 冲激 | `[1,-3,3,-1]` | 完全一致 | PASS |
| CIC burst | 每个输入 16 个连续输出 | 0 计数误差 | PASS |
| 输入速率负向测试 | 连续输入违反 16 拍约束 | 65 ns 命中 pending overwrite `$fatal` | EXPECTED PASS |
| CIC 正常动态范围 | 定向、正负直流 | 0 wrap、0 saturation | PASS |
| 32 bit 模回绕边界 | 三级积分器 6 组正负边界 | 精确模 `2^32` | PASS |
| 正负直流 16 相 | `±32768` | 相位差 0 LSB | PASS |
| Stage3 中心拆分 | 4107 组边界/随机值 | 精确相等 | PASS |

nightly 每个随机种子的输出比较点为：

```text
4x   : 16,605
8x   : 33,219
128x : 531,552
```

## 4. 复位与动态接口

### 4.1 复位恢复

| 层级 | 场景 | 比较方式 | 结果 |
|---|---|---|---|
| CIC 核 | pending、burst remaining=15/8/1 | 状态清零并与冷启动参考比较 | PASS |
| 完整顶层 | Stage1 MAC、Stage2 pending/job、Stage3 job、CIC pending/15/8/1 | 每场景比较 4096 个 128x 输出，并同步检查 4x/8x | PASS |

全部 12 个定向复位场景均未发现旧状态泄漏。

### 4.2 动态切档

首轮相位压力测试在组合时钟选择器上捕获到 4 个 `0 ns` 的 `DA_CLK` 脉冲。RTL 随后改为分离 `mode_request` 和 `mode_state`，仅在 1x、4x、8x 候选时钟同时处于低电平的 128x 下降沿提交新模式。

修复后完成 10 次无复位切换，包括压力相位和：

```text
1x -> 4x -> 8x -> 128x -> 8x -> 1x -> 128x
```

4096 个 128x 基准周期内的边沿数为 `32 / 128 / 256 / 4096`，没有毛刺、零宽脉冲、X 或数据失效，结果 PASS。

## 5. 正式 RTL 冲激频率与相位

以下数据直接来自 XSim 输出 CSV，不是仅由 MATLAB 设计系数计算。

| 指标 | 4x | 8x 预加重 | 128x 最终 |
|---|---:|---:|---:|
| 通带最大绝对偏差 | 0.00301125 dB | 不按最终门槛验收 | 0.00303062 dB |
| 15 kHz 增益 | - | +0.07573159 dB | 最终响应已补平 |
| 20 kHz 增益 | - | +0.13429277 dB | 最终响应已补平 |
| 阻带衰减 | 78.67042 dB | 内部节点 | 72.34929 dB |
| 冲激对称误差 | - | - | 0 output LSB |
| 群延迟均值 | - | - | 3686.5 sample |
| 分块拟合群延迟峰峰值 | - | - | `6.457e-11` sample |
| 线性相位拟合残差 | - | - | `2.842e-14 rad` |

最终 128x 同时通过赛题门槛 `±0.05 dB / 70 dB` 和内部发布门槛 `±0.01 dB / 72 dB`。

![正式 RTL 冲激频响](../figures/phase7_rtl_impulse_response.png)

![正式 RTL 线性相位](../figures/phase7_rtl_linear_phase.png)

## 6. Vivado 实现

| 项目 | 本轮安全切档修正版 |
|---|---:|
| LUT | 1128 / 20800，5.42% |
| FF | 964 / 41600，2.32% |
| BRAM Tile | 1 / 50，2.00% |
| DSP | 2 / 90，2.22% |
| WNS / TNS | +45.113 ns / 0 ns |
| WHS / THS | +0.142 ns / 0 ns |
| Setup / Hold 失败端点 | 0 / 0 |
| DRC | 0 Error，31 Warning |
| Vectorless 总功耗 | 0.168 W，Low confidence |

时钟交互报告显示 `clk_20M` 和 `clk_audio_128x_44k1` 两个域内路径均为 `Clean / Timed`；5 条控制域跨音频域路径由 XDC 明确归入 `Asynchronous Groups`。实现网表枚举到 2 个 `DSP48E1`：Stage1 位于 `DSP48_X1Y0`，共享 Stage2/3 位于 `DSP48_X1Y1`。

层次报告确认综合的是：

```text
gen_phase7_folded
u_interp128_all2x_v7_folded_fir_cic_top_ce
u_interp2_stage1_strict_halfband_bram_ce
u_interp2_stage23_folded_cic_dsp_ce
u_cic_interp16_core_ce
```

DRC Warning 为 DSP 流水建议和 BRAM 异步控制检查，不是实现错误。功耗没有加载 SAIF/VCD，不能当作精确实测功耗。

bitstream：

```text
matlab_fir/alt_all2x_v7/vivado_results/board_folded_n3/
board_demo_competition_dac8_top_phase7_folded_n3.bit

SHA256:
91C3108B7EDB8CD35F5E31C3881FC045CB70FB3A4B88AE6B2187808584962CD5
```

## 7. 板级证据与剩余动作

上一版 Phase 7 bitstream 已完成静态板级演示，用户记录为：

| 档位 | 理论 DA_CLK | 实测 DA_CLK | 结果 |
|---|---:|---:|---|
| 1x | 44.1 kHz | 未单独记录 | DA 波形可用于阶梯对比 |
| 4x | 176.4 kHz | 176.37 kHz | 正常 |
| 8x | 352.8 kHz | 352.86 kHz | 正常 |
| 128x | 5.6448 MHz | 5.64 MHz | 正常 |

DA 波形能够明显观察到从 1x 到 128x 逐级变光滑。

本轮只改变板级模式提交时机，滤波数据通路和三档分频值没有变化。为严谨对应当前 SHA256，仍需把上述新 bitstream 下载到板上，连续切换四档并检查：

1. 4x、8x、128x 频率保持原实测范围；
2. 运行中切档无窄脉冲、异常跳变或停顿；
3. 复位后 128x 连续稳定；
4. 条件允许时补记 1x 的实测频率。

完成这一步后，Phase 7 即形成 MATLAB、RTL、实现和当前 bitstream 板级验证的完整闭环。
