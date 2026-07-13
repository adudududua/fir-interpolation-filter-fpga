# FIR 128×音频插值器 Phase 7 高创新性优化指导

## 0. 当前状态

当前 Phase6 已达到：

- 44.1 kHz → 5.6448 MHz
- 七级 2× 插值
- Stage1 strict-halfband + BRAM + DSP
- Stage2/3 polyphase + DSP sharing
- Stage4~7 canonical halfband
- mixed word length：
  - Stage1: 24 bit
  - Stage2: 22 bit
  - Stage3: 20 bit
  - Stage4~7: 18 bit

当前板级：

- LUT: 1395
- FF: 1040
- DSP: 2
- BRAM: 1

已经满足：

- 通带指标
- 阻带指标
- 严格线性相位
- 0 LSB bit-true
- 1×/4×/8×/128×单DAC展示

因此 Phase7 不再以“小修小补”为目标，而探索：

\[
\boxed{
\text{混合 FIR + CIC 多速率架构}
}
\]

目标：

在保持音频指标的同时：

- 降低资源；
- 提升创新性；
- 形成答辩亮点。

---

# 1. 核心创新方向：CIC替代Stage4~7

## 当前结构

```
44.1k
 |
Stage1
 |
Stage2
 |
Stage3
 |
8× (352.8k)
 |
Stage4
 |
Stage5
 |
Stage6
 |
Stage7
 |
128× (5.6448MHz)
```

其中：

Stage4~7主要作用：

- 提高采样率；
- 扩大镜像间隔；
- 提供最终重构。

它们不再承担主要音频滤波任务。

因此适合替换。


---

# 2. 新结构方案

提出：

## Hybrid FIR-CIC Architecture


```
44.1k
 |
Stage1 strict halfband
 |
Stage2 polyphase FIR
 |
Stage3 polyphase FIR
 |
8× 352.8kHz
 |
16× CIC interpolator
 |
128× 5.6448MHz
 |
Compensation FIR
 |
DAC
```


核心思想：

- FIR负责音频保真；
- CIC负责高倍率升采样。


---

# 3. 为什么CIC适合这里

CIC特点：

无需乘法器。

结构：

## Integrator

\[
y[n]=y[n-1]+x[n]
\]


## Comb

\[
y[n]=x[n]-x[n-R]
\]


因此：

硬件只需要：

- 加法器；
- 减法器；
- 延迟。


适合：

大倍率插值。


---

# 4. MATLAB第一阶段：CIC可行性验证


建立：

```
matlab_fir/alt_all2x_cic/
```


新增：

```
design_cic_tail.m
check_cic_response.m
design_compensation_fir.m
```


---

# 5. CIC参数搜索


固定：

插值倍率：

\[
R=16
\]


搜索：

阶数：

\[
N=3,4,5
\]


差分延迟：

\[
M=1
\]


比较：

- 通带下降；
- 阻带衰减；
- 补偿难度。


---

# 6. CIC频响分析


CIC响应：

\[
H(f)=
\left|
\frac{\sin(\pi fRM/F_s)}
{R\sin(\pi f/F_s)}
\right|^N
\]


重点观察：

## 通带

10Hz~20kHz

要求：

补偿后：

\[
|E(f)|<0.01dB
\]


## 阻带

要求：

\[
A_s>70dB
\]


---

# 7. 补偿FIR设计


CIC缺陷：

高频下降。


因此设计：

Compensation FIR。


位置：

建议：

放在低速端：

```
8×输出
352.8kHz
 |
Compensation FIR
 |
CIC
```


原因：

低速：

- tap少；
- 运算量低。


搜索：

```
tap:
15
21
31
41

word length:
Q12~Q16
```


---

# 8. 位宽设计


CIC最大问题：

积分增长。


增长：

\[
B=N\log_2(RM)
\]


例如：

R=16

N=4


增长：

\[
4\times4=16bit
\]


输入：

24bit


积分器可能需要：

\[
40bit
\]


---

# 9. Hogenauer剪枝


不要直接保留40bit。


实现：

```
full precision
        |
        ↓
stage pruning
        |
        ↓
optimized width
```


搜索：

每级：

- 保留bit数；
- 舍入位置。


目标：

减少：

- FF；
- LUT；
- BRAM。


---

# 10. CIC RTL架构


新增：

```
interp_cic16_stage.v
```


结构：

```
Input
 |
Integrator1
 |
Integrator2
 |
Integrator3
 |
Integrator4
 |
 ↑
rate change
 |
Comb1
 |
Comb2
 |
Comb3
 |
Comb4
 |
Output
```


---

# 11. 插值CIC特殊实现


注意：

插值CIC不是普通CIC。


流程：

```
低速输入
 |
积分器
 |
插零/保持
 |
高采样率comb
```


需要验证：

- valid时序；
- CE；
- 延迟。


---

# 12. 与当前Phase6比较


必须建立Pareto表：


|方案|LUT|FF|DSP|BRAM|
|-|-:|-:|-:|-:|
|Phase6 FIR halfband|
|CIC N=3|
|CIC N=4|
|CIC N=5|


同时比较：

|指标|
|-|
|通带纹波|
|阻带|
|群延迟|
|SNR|
|THD|


---

# 13. Stop/Go标准


CIC版本只有满足：

## 资源

至少：

LUT下降：

\[
>15\%
\]


或：

DSP下降：

\[
\ge1
\]


## 性能

满足：

- 通带误差 <0.01dB
- 阻带 >70dB
- 线性相位


## 定点

满足：

- MATLAB/RTL 0 LSB


才替换主线。


---

# 14. 如果CIC失败怎么办


不要删除。


它仍然可以作为创新探索。


最终答辩可以展示：

```
方案A:
全FIR

方案B:
FIR+CIC混合

比较:
资源/性能
```


这本身就是创新。


---

# 15. 推荐实施路线


## Phase7-A

MATLAB CIC频响探索

目标：

找到：

N=4/5

最优补偿FIR。


---

## Phase7-B

bit-true模型

建立：

```
FIR+CIC golden model
```


验证：

- 冲激；
- 正弦；
- PCM。


---

## Phase7-C

RTL CIC模块


先：

独立仿真。


---

## Phase7-D

接入8×后级


替换：

Stage4~7。


---

## Phase7-E

板级展示


保持：

```
15kHz

1×
4×
8×

128×
```

不改变。


---

# 16. 最终创新叙事


不要说：

“换了CIC”。


应该说：

> 针对高倍率音频过采样中后级采样率提升需求远高于有效信息带宽的问题，提出FIR-CIC混合多速率架构。前级采用严格半带与polyphase FIR保证音频频谱重构，后级采用无乘法CIC实现高倍率采样扩展，并通过补偿滤波和定点剪枝恢复通带平坦性，在保证线性相位和音频性能的同时降低FPGA资源消耗。


---

# 17. 当前建议

主线：

```
Phase6 mixed-width FIR
```

保留。

探索：

```
Phase7 FIR-CIC hybrid
```

作为创新分支。


不要直接覆盖比赛版本。
