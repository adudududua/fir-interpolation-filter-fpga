# Phase 7 FIR-CIC Hybrid 高创新性优化指导（修正版）

## 0. 修正说明

上一版 CIC 指导中插值 CIC 数据流顺序错误。

正确的：

## CIC 插值器结构

\[
\boxed{
Comb \rightarrow \uparrow R \rightarrow Integrator
}
\]

而不是：

\[
Integrator \rightarrow \uparrow R \rightarrow Comb
\]

后者对应关系错误。

本指导以正确 CIC 插值结构重新规划。

---

# 1. 当前 Phase6 基线

当前稳定比赛版本：

```
44.1kHz PCM

Stage1:
strict halfband
BRAM
DSP

Stage2:
polyphase FIR

Stage3:
polyphase FIR

↓

8× output

352.8kHz

↓

Stage4~7:
canonical halfband

↓

128×

5.6448MHz

↓

DAC
```

资源：

```
LUT ≈1395
FF  ≈1040
DSP =2
BRAM=1
```

Phase7 不替换主线，而建立：

```
codex/all2x-phase7-cic-explore
```

探索分支。

---

# 2. 为什么考虑 CIC

当前 Stage4~7：

主要任务：

- 提升采样率；
- 扩大镜像间隔。


它们不再承担主要音频频谱重构。

因此考虑：

```
8× FIR
    |
    ↓
16× CIC interpolation
    |
    ↓
128×
```


目标：

用无乘法 CIC 替代部分 halfband 级。

---

# 3. 正确 CIC 插值数学原理


CIC 转移函数：

\[
H(z)=
\left(
\frac{1-z^{-RM}}
{1-z^{-1}}
\right)^N
\]


拆分：

\[
H(z)
=
(1-z^{-RM})^N
\cdot
(1-z^{-1})^{-N}
\]


其中：

## Comb

对应：

\[
(1-z^{-RM})^N
\]


## Integrator

对应：

\[
(1-z^{-1})^{-N}
\]


因此插值结构：

\[
\boxed{
Comb
\rightarrow
\uparrow R
\rightarrow
Integrator
}
\]


---

# 4. 为什么插值和抽取顺序不同


## CIC插值

```
低速输入

↓

Comb

↓

插零 ↑R

↓

高速Integrator

↓

输出
```


原因：

Comb处理差分：

\[
y[n]=x[n]-x[n-M]
\]

适合低速。


Integrator：

\[
y[n]=y[n-1]+x[n]
\]

负责恢复插值后的幅度。

---

## CIC抽取

```
高速输入

↓

Integrator

↓

↓R

↓

Comb

↓

输出
```


两者不能混淆。

---

# 5. 在本项目中的目标结构


保持前三阶段：

```
44.1k
 |
Stage1
 |
Stage2
 |
Stage3
 |
8×
 |
352.8kHz
```


替换：

```
Stage4~7
```

为：

```
352.8kHz

↓

16× Comb

↓

插零

↓

16× Integrator

↓

5.6448MHz

↓

补偿FIR

↓

DAC
```


---

# 6. CIC 参数搜索


固定：

插值倍率：

\[
R=16
\]


差分延迟：

\[
M=1
\]


搜索阶数：

\[
N=3,4,5
\]


MATLAB：

建立：

```
matlab_fir/alt_all2x_cic/
```


文件：

```
design_cic16_interpolator.m

analyze_cic_response.m

search_cic_order.m
```

---

# 7. CIC频率响应分析


CIC幅频：

\[
|H(f)|
=
\left|
\frac{
\sin(\pi fRM/F_s)
}
{
R\sin(\pi f/F_s)
}
\right|^N
\]


重点分析：

## 输入频率

352.8kHz


## 输出频率

5.6448MHz


## 音频通带

\[
0\sim20kHz
\]


检查：

- 通带下降；
- 镜像抑制；
- 阻带。


---

# 8. CIC最大问题：通带下垂


CIC不是平坦低通。

高频处：

增益下降：

\[
Droop
\]


因此必须增加：

\[
\boxed{
Compensation\ FIR
}
\]


---

# 9. 补偿 FIR 设计


推荐位置：

放在CIC之前的低速端。


即：

方案A：

```
352.8kHz

↓

Compensation FIR

↓

CIC
```

原因：

补偿 FIR 工作在：

352.8kHz

而不是：

5.6448MHz。


优点：

- tap更少；
- MAC更少。


---

# 10. 补偿FIR搜索


搜索：

tap：

```
15
21
31
41
```


字长：

```
Q12
Q14
Q16
```


指标：

```
通带误差 <0.01dB

阻带 >70dB

线性相位
```


---

# 11. 位宽设计（重点）


CIC积分器会产生位增长。


增长：

\[
B=N\log_2(RM)
\]


例如：

R=16

N=4

M=1


增长：

\[
4\times4=16bit
\]


24bit输入：

理论：

\[
24+16=40bit
\]


因此不能直接全部保留。


---

# 12. Hogenauer剪枝


采用：

```
Full precision CIC

↓

误差分析

↓

逐级削减bit

↓

optimized CIC
```


目标：

降低：

- FF；
- LUT；
- 功耗。


验证：

必须比较：

- full precision；
- pruning版本。


---

# 13. MATLAB bit-true流程


建立：

```
FIR Stage1~3

↓

Comb

↓

Upsample16

↓

Integrator

↓

Compensation FIR
```


逐级量化：

```
round

saturation

wordlength
```


验证：

- impulse；
- random PCM；
- 15kHz sine；
- 20kHz sine。


---

# 14. RTL结构设计


新增：

```
cic_interp16_top.v
```


内部：

```
comb_chain_lowrate

↓

rate_change_x16

↓

integrator_chain_highrate

↓

compensation_fir
```


---

# 15. Comb RTL


低速：

352.8kHz


一级：

\[
y[n]=x[n]-x[n-M]
\]


只需要：

- delay register；
- subtractor。


---

# 16. 插零模块


输入：

352.8kHz


输出：

5.6448MHz


结构：

```
x

↓

x 0 0 ... 0 x 0 0 ...0

```

倍率：

16。


---

# 17. Integrator RTL


高速：

5.6448MHz


一级：

\[
y[n]=y[n-1]+x[n]
\]


N级级联。


注意：

这里位宽最大。

---

# 18. 与Phase6比较


建立：

|版本|LUT|FF|DSP|BRAM|
|-|-:|-:|-:|-:|
|Phase6 FIR|
|CIC N=3|
|CIC N=4|
|CIC N=5|


同时比较：

|指标|
|-|
|通带纹波|
|阻带衰减|
|群延迟|
|SNR|
|THD|
|功耗|


---

# 19. Stop/Go条件


CIC版本只有满足：

## 资源

至少：

```
LUT下降15%
```

或者：

```
DSP下降1个
```


## 性能

满足：

```
passband error <0.01dB

stopband >70dB

linear phase
```


## 定点

满足：

```
MATLAB/RTL 0 LSB
```


才考虑替换Phase6。

---

# 20. 推荐实施顺序


## Phase7-A

MATLAB CIC频响搜索

输出：

```
cic_order_search.csv
```


---

## Phase7-B

补偿FIR设计


输出：

```
cic_compensation_candidates.csv
```


---

## Phase7-C

bit-true模型


完成：

```
FIR+CIC golden model
```


---

## Phase7-D

RTL CIC模块


先独立仿真。


---

## Phase7-E

替换Stage4~7


比较：

资源和性能。


---

# 21. 比赛展示保持不变


不要改变：

```
15kHz正弦

1×
4×
8×
128×


单DAC

矩阵按键

示波器
```


CIC只是内部架构优化。


---

# 22. 最终创新叙事


建议表述：

> 针对高倍音频过采样中后级采样率提升需求远高于有效信息带宽的问题，提出FIR-CIC混合多速率插值架构。前级采用严格半带与polyphase FIR完成音频频谱重构，后级采用无乘法CIC插值器完成高倍率采样扩展，并通过补偿FIR与Hogenauer位宽优化恢复通带平坦性，在保持线性相位和音频性能的同时进一步降低FPGA资源消耗。

---

# 23. 最终建议

主线保持：

```
Phase6 mixed-width FIR
```

探索：

```
Phase7 FIR-CIC Hybrid
```

不要直接覆盖。

先MATLAB验证，再决定是否进入RTL。
