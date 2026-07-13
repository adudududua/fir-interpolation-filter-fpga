# 128×音频插值滤波器 Phase 6 下一步优化指导（比赛展示版）

## 0. 当前项目定位重新调整

当前项目已经不是单纯追求 FIR 指标，而是：

1. 完成高保真 128× 音频插值；
2. 证明算法和 FPGA 架构优化有效；
3. 在分赛区决赛现场通过单 DAC + 示波器直观展示。

当前展示方案：

```text
矩阵按键选择输出级

1×  →  4×  →  8×  →  128×

单路 DAC 输出
        |
        ↓
      示波器
```

展示信号：

```text
约15 kHz 正弦
```

这个选择保留，不修改。

原因：

15 kHz 位于音频通带高频区域：

- 低采样率下离散点明显；
- 插值后采样点增加效果明显；
- 示波器上能够直观看到波形重构过程。

因此：

> 现场展示目标不是测量最高音质，而是让评委直观看到“采样率提升 → 波形重构改善”的过程。

---

# 1. Phase 6总体目标

当前已经完成：

- 七级2×插值；
- true polyphase；
- Stage1严格半带；
- BRAM循环缓存；
- DSP MAC复用；
- Stage2/3 DSP sharing；
- Stage4~7 canonical halfband。

下一阶段目标：

## 目标A：进一步降低资源

重点：

- LUT
- FF
- DSP合理利用
- 功耗


## 目标B：增强比赛展示效果

重点：

- 1×/4×/8×/128×切换稳定；
- 示波器波形清晰；
- 展示优化过程。


---

# 2. 第一优先级：确认比赛顶层使用最新优化链

## 当前风险

之前多次出现：

MATLAB优化完成：

```
Phase4/Phase5
```

但是：

Vivado板级top仍调用：

```
旧 interp128_all2x_top_ce
```

导致：

实验资源 ≠ 比赛资源。


---

## 工作

建立最终比赛版本：

```text
board_demo_phase6_top
```

结构：

```
board_demo
    |
    |
matrix_keyboard
    |
    |
debug_select_mux
    |
    |
Phase5/Phase6 interpolation core
    |
    |
DAC
```


---

## 验收

重新生成：

- synthesis
- implementation
- bitstream


记录：

|版本|LUT|FF|DSP|BRAM|
|-|-:|-:|-:|-:|
|旧板级|
|Phase5|
|Phase6|


---

# 3. 第二优先级：DSP资源重新优化（最高收益）

## 当前问题

目前一直追求：

```
DSP数量少
```

但是 XC7A35T：

```
DSP48E1 = 90
```

因此应该优化：

```
总资源
```

而不是单独DSP数量。


---

# 方案1：当前DSP Sharing

结构：

```
DSP0:
Stage1

DSP1:
Stage2 + Stage3共享
```

优点：

- DSP少；
- 架构创新明显。


缺点：

- scheduler；
- pending；
- mux；
- job控制。


---

# 方案2：3 DSP Pareto

改成：

```
DSP0:
Stage1

DSP1:
Stage2

DSP2:
Stage3
```

每一级：

独立：

- history；
- MAC；
- state machine。


删除：

- shared scheduler；
- stage mux；
- pending控制。


---

## 实验

建立：

```
opt/phase6-three-dsp
```


比较：

|方案|DSP|LUT|FF|WNS|
|-|-:|-:|-:|-:|
|2 DSP sharing|
|3 DSP independent|


选择：

实际LUT最低版本。


注意：

比赛创新点不是：

“DSP最少”

而是：

“综合资源最优”。


---

# 4. 第三优先级：Stage2/3统一Q格式

## 当前问题

Stage2：

```
Q15
```

Stage3：

```
Q14
```

导致：

两个round模块。


---

## 优化

Stage3系数全部乘2：

\[
h_{new}=2h_{old}
\]


改为：

```
Stage2 Q15
Stage3 Q15
```


然后：

共享：

```
round_sat_q15
```


---

## 验证

MATLAB：

重新生成：

- coefficient；
- bit-true model。


RTL：

比较：

- Stage2；
- Stage3；
- 最终128×输出。


要求：

```
max error = 0 LSB
```


---

# 5. 第四优先级：DSP48深度利用

## 当前问题

DSP可能只负责：

```
乘法
```

但是：

- 对称预加；
- accumulator；
- round bias

仍可能消耗LUT。


---

## 优化目标

希望：

```
sample_a + sample_b

↓

DSP48 pre-adder

↓

multiply

↓

DSP accumulator

↓

round
```


---

## 检查

Vivado：

```
report_dsp_utilization

Open Synthesized Design

Schematic
```


确认：

- pre-adder进入DSP；
- multiplier进入DSP；
- accumulator进入DSP。


---

# 6. 第五优先级：数据字长优化

## 当前

所有级：

```
24bit
```


但是：

后级已经经过滤波和插值。


---

## 建议搜索

保持：

```
Stage1:
24bit
```

尝试：

```
Stage2:
22/24bit

Stage3:
20/22/24bit

Stage4~7:
18/20/22bit
```


---

## MATLAB验证

每个候选检查：

### 频域

- 通带纹波；
- 阻带衰减。


### 音频

- SNR；
- THD；
- SINAD。


目标：

```
通带误差 < 0.01dB
阻带 >70dB
SNR >90dB
```


---

# 7. 第六优先级：Stage4~7共享canonical halfband

## 当前

四级：

```
Stage4
Stage5
Stage6
Stage7
```

均使用：

\[
[-1,0,9,16,9,0,-1]/16
\]


---

## 优化

设计：

```
shared_halfband_engine
```


输入：

```
stage_id
phase
sample
```


输出：

对应级结果。


---

## 风险

需要重新设计：

- CE；
- 延迟；
- phase同步。


建议：

先MATLAB建立schedule。


---

# 8. 第七优先级：展示系统优化

注意：

展示方案保持：

```
15kHz正弦
1×/4×/8×/128×
矩阵按键切换
单DAC
示波器
```


---

# 展示1：采样重构过程

示波器显示：

## 1×

最低采样密度：

波形离散明显。


## 4×

采样点增加：

波形改善。


## 8×

更平滑。


## 128×

接近连续模拟波形。


这是最直观展示。


---

# 展示2：增加屏幕/串口资源信息

建议增加：

OLED或者串口：

显示：

```
Interpolation:
128×

Fs_out:
5.6448MHz

LUT:
xxxx

DSP:
x

BRAM:
x
```


让评委同时看到：

性能 + 资源。


---

# 展示3：增加资源优化演进页

PPT：

```
Traditional FIR

↓

Polyphase

↓

Halfband

↓

BRAM

↓

DSP sharing
```


展示：

算法优化如何转换成FPGA资源下降。


---

# 9. 不建议当前优先做

## CIC替换尾部

原因：

- 风险高；
- 位宽复杂；
- 补偿滤波器需要重新设计。


作为后续研究，不作为决赛主线。


---

## 1 DSP全链共享

理论：

Stage1+2+3：

约68 MAC/输入周期。

但是：

- 调度复杂；
- RTL风险；
- 展示价值低。


不推荐比赛前做。


---

# 10. 最推荐执行顺序

## Phase6-A

完成：

```
Phase5链路接入最终板级top
```

---

## Phase6-B

完成：

```
2 DSP vs 3 DSP Pareto
```

---

## Phase6-C

完成：

```
Stage3 Q14→Q15

共享round
```

---

## Phase6-D

完成：

```
DSP48深度映射
```

---

## Phase6-E

完成：

```
数据字长优化
```

---

## Phase6-F

完成：

```
比赛展示模式稳定
```

---

# 最终推荐比赛版本

```
输入:
44.1kHz 24bit PCM

展示:
15kHz正弦

模式:
1×
4×
8×
128×

硬件:
Stage1:
strict halfband + BRAM + DSP

Stage2:
DSP MAC

Stage3:
DSP MAC

Stage4~7:
canonical halfband

输出:
单DAC
示波器观察
```

最终目标：

不是单纯追求最低DSP，而是：

```
资源合理
结构清晰
指标满足
现场可展示
```
