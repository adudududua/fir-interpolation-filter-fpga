# 全 2× 级联 128× 插值 MATLAB 后续优化与 RTL 落地指南

> 适用对象：`design_all2x_interp128_compare.m`  
> 当前结构：`2× × 2× × 2× × 2× × 2× × 2× × 2× = 128×`  
> 输入采样率：44.1 kHz  
> 输出采样率：5.6448 MHz

赛题指标：

- 通带：10 Hz～20 kHz
- 通带纹波：不超过 ±0.05 dB
- 阻带衰减：不低于 70 dB
- 相位响应：严格线性相位

---

## 1. 当前 MATLAB 版本已经完成了什么

现有脚本已经完成以下工作：

1. 将 128× 插值拆分成 7 个独立的 2× 插值级；
2. 按各级采样率分别设计 FIR，而不是让所有 2× 级复用同一个滤波器；
3. 对每一级搜索 FIR 阶数、`FRAC_W`、`COEFF_W` 和小系数裁剪阈值；
4. 构造最终等效冲激响应；
5. 检查总通带纹波、总通带平均增益、总阻带衰减、总群延迟和对称性；
6. 导出逐级系数和总链路频响图。

当前结果为：

| 指标 | 当前结果 | 赛题要求 | 结论 |
|---|---:|---:|---|
| 总通带最大偏差 | 约 0.0065 dB | ≤ ±0.05 dB | 通过 |
| 总阻带衰减 | 约 77.67 dB | ≥ 70 dB | 通过 |
| 群延迟波动 | 约 \(10^{-11}\) 样点 | 严格线性相位 | 通过 |
| 总等效冲激响应长度 | 7163 tap | 不作直接限制 | 合理 |

需要注意：

> 7163 tap 是将多级多速率结构折算到最终输出采样率后得到的等效冲激响应长度，不代表 RTL 要实现一个 7163 tap 的单级 FIR。

根据总长度可以反推出当前各级 tap 数大致为：

| Stage | 插值倍率 | tap 数 |
|---:|---:|---:|
| 1 | 1×→2× | 101 |
| 2 | 2×→4× | 17 |
| 3 | 4×→8× | 11 |
| 4 | 8×→16× | 7 |
| 5 | 16×→32× | 7 |
| 6 | 32×→64× | 7 |
| 7 | 64×→128× | 7 |

这说明“越靠后的级越短”的总体设计方向是正确的。

---

# 2. 当前 MATLAB 最需要修正的三个问题

## 2.1 修正 Stage 2～7 的阻带起点

当前脚本使用：

```matlab
if stage_idx == 1
    f_stop_begin = f_stop_base;
else
    f_stop_begin = Fs_in_stage - f_stop_base;
end
```

其中：

```matlab
f_stop_base = FS_IN_BASE - f_pass_high;
```

这会使 Stage 2～7 的阻带起点比实际镜像入口低 4.1 kHz，设计略显保守。

对任意一级 2× 插值器，最靠近基带的镜像起点应为：

\[
f_{\mathrm{stop}} = F_{s,\mathrm{in}} - f_{\mathrm{pass,high}}
\]

建议统一改为：

```matlab
f_stop_begin = Fs_in_stage - f_pass_high;
```

修改后各级阻带起点应为：

| Stage | 本级输入采样率 | 建议阻带起点 |
|---:|---:|---:|
| 1 | 44.1 kHz | 24.1 kHz |
| 2 | 88.2 kHz | 68.2 kHz |
| 3 | 176.4 kHz | 156.4 kHz |
| 4 | 352.8 kHz | 332.8 kHz |
| 5 | 705.6 kHz | 685.6 kHz |
| 6 | 1.4112 MHz | 1.3912 MHz |
| 7 | 2.8224 MHz | 2.8024 MHz |

预期效果：

- Stage 2 可能进一步降阶；
- Stage 3～7 可能降低小数位宽；
- 后级可能容许更强的小系数裁剪；
- 总 LUT 和寄存器有机会继续下降。

---

## 2.2 修改通带判定方式

当前总链路分别判断：

```matlab
pass_gain   = abs(pass_gain_db) <= ripple_target_db;
pass_ripple = ripple_pm_db <= ripple_target_db;
```

这种判定存在潜在漏洞。

例如：

- 平均增益为 +0.04 dB；
- 相对平均值最大偏差为 +0.04 dB；

两项分别通过，但最高点可能达到 +0.08 dB，已经超过 ±0.05 dB。

建议增加绝对通带误差：

```matlab
pass_abs_max_db  = max(abs(pass_db));
pass_abs_peak_db = max(pass_db);
pass_abs_min_db  = min(pass_db);

pass_ripple = pass_abs_max_db <= ripple_target_db;
```

建议最终同时输出：

```matlab
res.pass_gain_db      = pass_gain_db;
res.ripple_pp_db      = ripple_pp_db;
res.ripple_pm_db      = ripple_pm_db;
res.pass_abs_max_db   = pass_abs_max_db;
res.pass_abs_peak_db  = pass_abs_peak_db;
res.pass_abs_min_db   = pass_abs_min_db;
```

赛题是否通过，应主要依据：

```matlab
pass_abs_max_db <= 0.05
```

---

## 2.3 修正 2× 插值后的幅度保持问题

当前每一级 FIR 的通带增益约为 1，即：

```matlab
sum(b) ≈ 1
```

但标准 2× 插值过程是：

1. 原序列中间插入一个 0；
2. 再通过低通 FIR。

插零后，直流平均值减半。如果 FIR 直流增益仍为 1，则每级输出幅度约变为输入的 1/2。

七级后：

\[
A_{\mathrm{out}} \approx \frac{A_{\mathrm{in}}}{2^7}
= \frac{A_{\mathrm{in}}}{128}
\]

对应幅度下降：

\[
20\log_{10}(128) \approx 42.14\ \mathrm{dB}
\]

### 推荐做法

每一级 2× FIR 应具有约 2 倍的低频增益：

\[
\sum h[n] \approx 2
\]

可以采用两种实现方法。

### 方法 A：MATLAB 中直接将系数乘 2

```matlab
b_float = firpm(n, fo, ao, w);
b_float = 2 * b_float;
coeff_int = round(b_float * 2^frac_w_try);
```

优点：

- 数学含义清晰；
- MATLAB 模型与 RTL 系数一致；
- 每一级输出幅度自然保持。

缺点：

- 系数整数幅度增大；
- 可能需要增加 `COEFF_W`；
- 累加器位宽也要重新核算。

### 方法 B：系数不变，RTL 输出少右移 1 位

原来：

```verilog
y = acc >>> FRAC_W;
```

改为：

```verilog
y = acc >>> (FRAC_W - 1);
```

等效于整体乘 2。

建议采用方法 A：

> MATLAB 设计阶段明确生成“插值增益已经补偿”的系数，RTL 按正常 `FRAC_W` 右移。

同时在每一级输出以下指标：

```matlab
dc_gain     = sum(b_q);
phase0_gain = sum(b_q(1:2:end));
phase1_gain = sum(b_q(2:2:end));
```

理想情况下：

```text
dc_gain      ≈ 2
phase0_gain  ≈ 1
phase1_gain  ≈ 1
```

这对 polyphase RTL 非常重要。

---

# 3. 不要继续固定 `COEFF_W = FRAC_W + 2`

当前脚本中：

```matlab
coeff_w_try = frac_w_try + 2;
```

这个关系没有必要固定。

- `FRAC_W` 决定小数精度；
- `COEFF_W` 决定整数系数能否被有符号数容纳。

应该在完成量化后，根据实际最大系数自动确定最小总位宽。

建议增加：

```matlab
function coeff_w = required_signed_width(coeff_int)

    max_pos = max(coeff_int);
    min_neg = min(coeff_int);

    coeff_w = 2;

    while max_pos > 2^(coeff_w-1)-1 || ...
          min_neg < -2^(coeff_w-1)
        coeff_w = coeff_w + 1;
    end
end
```

在搜索中改为：

```matlab
coeff_int = round(b_float * 2^frac_w_try);
coeff_w_try = required_signed_width(coeff_int);
```

如需预留 1 位安全裕量，可写成：

```matlab
coeff_w_try = required_signed_width(coeff_int) + 1;
```

但不建议一开始就加裕量。先用最小位宽综合，再根据 Vivado 结果决定。

---

# 4. 扩展后级字长搜索范围

当前：

```matlab
FRAC_W_LIST = [16 15 14 13 12];
```

对于 Stage 4～7 明显过于保守。

以当前 Stage 7 为例：

```text
7 tap
Q12
通带纹波约 2×10^-7 dB
阻带衰减约 140 dB
```

这说明后级仍有很大字长冗余。

建议改成按级搜索：

```matlab
FRAC_W_LIST_CELL = {
    [16 15 14 13 12], ...          % Stage 1
    [15 14 13 12 11 10], ...       % Stage 2
    [14 13 12 11 10 9], ...        % Stage 3
    [12 11 10 9 8 7 6], ...        % Stage 4
    [12 11 10 9 8 7 6], ...        % Stage 5
    [12 11 10 9 8 7 6], ...        % Stage 6
    [12 11 10 9 8 7 6]             % Stage 7
};
```

调用时：

```matlab
frac_w_list = FRAC_W_LIST_CELL{stage_idx};
```

同时扩大裁剪阈值：

```matlab
PRUNE_THR_LIST_CELL = {
    [0 1 2 4 8 16], ...
    [0 1 2 4 8 16], ...
    [0 1 2 4 8 16 32], ...
    [0 1 2 4 8 16 32 64], ...
    [0 1 2 4 8 16 32 64], ...
    [0 1 2 4 8 16 32 64], ...
    [0 1 2 4 8 16 32 64]
};
```

注意：

> 裁剪阈值是整数系数域中的阈值。不同 `FRAC_W` 下同一个整数阈值对应不同的实际幅度，因此最好同时输出实际裁剪幅度。

```matlab
prune_real = prune_thr / 2^frac_w_try;
```

---

# 5. 将“单级独立通过”改成“总链路联合优化”

当前每一级都先独立满足较严格的通带和阻带指标，再选最优方案。

问题是：

- 某一级单独略差，不代表总链路不合格；
- 每一级都达到 80～84 dB，可能造成明显过度设计；
- 赛题只要求最终 128× 总链路达到 70 dB。

## 推荐改成两阶段搜索

### 阶段 1：每一级生成候选集

每一级不要只保存一个最佳结果，而是保存若干个 Pareto 候选。

每个候选至少记录：

```matlab
candidate.stage_idx
candidate.order_n
candidate.taps
candidate.frac_w
candidate.coeff_w
candidate.prune_thr
candidate.coeff_int
candidate.b
candidate.nonzero_half
candidate.csd_cost
candidate.acc_width_est
candidate.delay_bits_est
candidate.pass_gain_db
candidate.ripple_pm_db
candidate.stop_attn_db
```

候选只需满足较宽松的单级门槛，例如：

```text
通带偏差 < 0.03 dB
阻带衰减 > 55 dB
线性相位通过
```

### 阶段 2：组合候选并检查总链路

不建议直接穷举所有组合。可以采用逐级保留前 K 个解的 beam search。

伪代码：

```matlab
beam = initial_empty_chain;

for stage_idx = 1:7

    new_beam = [];

    for chain_idx = 1:length(beam)
        for cand_idx = 1:length(stage_candidates{stage_idx})

            new_chain = append_stage(beam(chain_idx), ...
                                     stage_candidates{stage_idx}(cand_idx));

            total_metric = fast_check_partial_chain(new_chain);

            if total_metric.has_potential
                new_chain.cost = estimate_hw_cost(new_chain);
                new_beam = [new_beam, new_chain];
            end
        end
    end

    new_beam = sort_by_cost_and_margin(new_beam);
    beam = new_beam(1:min(K, length(new_beam)));
end
```

建议：

```matlab
K = 20;
```

最后只对保留下来的组合做高精度 `freqz` 检查。

---

# 6. 当前最优目标不能只看非零半系数数目

目前的选择逻辑主要依据：

1. 非零半系数更少；
2. 系数位宽更小；
3. 阶数更小；
4. 裁剪阈值更小。

但对于 FPGA，非零系数数量并不能完整代表 LUT 成本。

常数乘法资源还取决于：

- 系数二进制中 `1` 的数量；
- CSD 表示中的非零数字数量；
- 正负移位加减法数量；
- 乘法器输入位宽；
- 累加器位宽；
- 是否使用 DSP；
- 是否进行时分复用；
- Vivado 是否识别公共子表达式。

## 建议增加 CSD 或二进制代价估计

可以先使用一个简单的二进制代价：

```matlab
function cost = binary_nonzero_cost(coeff_int)

    cost = 0;

    for k = 1:length(coeff_int)
        v = abs(coeff_int(k));

        if v == 0
            continue;
        end

        cost = cost + max(sum(dec2bin(v) == '1') - 1, 0);
    end
end
```

更好的做法是实现 CSD 转换，统计：

```text
CSD 非零数字数 - 1
```

每个候选的硬件代价可以先写成：

```matlab
cost = ...
    5.0 * nonzero_half + ...
    2.0 * csd_add_count + ...
    0.05 * delay_bits_est + ...
    0.5 * acc_width_est;
```

权重不需要一开始就非常准确。后续用 Vivado 综合数据拟合。

---

# 7. 为各级计算理论累加器位宽

设：

- 输入数据位宽为 `DATA_W`；
- 系数为有符号整数 `coeff_int`；
- 最坏输入幅度为 \(2^{DATA_W-1}-1\)。

可以采用保守上界：

\[
A_{\max}
=
(2^{DATA_W-1}-1)
\sum_k |c_k|
\]

需要的有符号累加器位宽：

\[
W_{\mathrm{acc}}
=
1+\left\lceil \log_2(A_{\max}+1)\right\rceil
\]

MATLAB 函数：

```matlab
function acc_w = estimate_acc_width(coeff_int, data_w)

    x_max = 2^(data_w-1) - 1;
    acc_max = double(x_max) * sum(abs(double(coeff_int)));

    acc_w = ceil(log2(acc_max + 1)) + 1;
end
```

建议额外留 1 位：

```matlab
acc_w_safe = estimate_acc_width(coeff_int, DATA_W) + 1;
```

每一级都导出：

```text
ACC_W_MIN
ACC_W_RECOMMENDED
```

后续 RTL 可以分别综合：

```text
ACC_W_RECOMMENDED
ACC_W_RECOMMENDED + 1
ACC_W_RECOMMENDED + 2
```

观察 LUT、CARRY4、DSP 映射和时序变化。

---

# 8. 建立逐级 bit-true 定点模型

这是 RTL 前最重要的一步。

当前总链路使用 double 系数卷积，不能反映：

- 每一级整数乘加；
- 每一级舍入；
- 每一级饱和；
- 级间固定 24 bit；
- 累加器溢出；
- 低幅度信号被逐级舍入；
- 每级 2 倍增益补偿；
- RTL 与 MATLAB 是否逐点一致。

建议建立目录：

```text
matlab_fir/
└── alt_all2x/
    ├── design_all2x_interp128_compare.m
    ├── bittrue/
    │   ├── round_shift_sat_signed.m
    │   ├── interp2_polyphase_bittrue.m
    │   ├── simulate_all2x_bittrue.m
    │   ├── analyze_fixed_signal.m
    │   └── compare_matlab_rtl_output.m
    └── rtl_export/
        ├── export_stage_config.m
        └── export_test_vectors.m
```

## 8.1 舍入、右移和饱和函数

建议采用与 RTL 完全一致的舍入规则。

```matlab
function y = round_shift_sat_signed(acc, shift_n, out_w)

    acc = int64(acc);

    if shift_n > 0
        round_bias = bitshift(int64(1), shift_n - 1);

        if acc >= 0
            temp = acc + round_bias;
        else
            temp = acc - round_bias;
        end

        temp = bitsra(temp, shift_n);
    else
        temp = bitshift(acc, -shift_n);
    end

    y_max = int64(2^(out_w-1) - 1);
    y_min = int64(-2^(out_w-1));

    if temp > y_max
        y = y_max;
    elseif temp < y_min
        y = y_min;
    else
        y = temp;
    end
end
```

必须根据最终 RTL 的实际规则决定：

- 负数是否采用对称舍入；
- 是否使用 round-to-nearest；
- 是否截断；
- 饱和发生在右移前还是右移后。

MATLAB 与 Verilog 必须逐位一致。

## 8.2 2相 polyphase 定点模型

不要在 bit-true 模型中真的插 0 再做完整 FIR。

对于 2× 插值：

\[
y[2n]=\sum_k h[2k]x[n-k]
\]

\[
y[2n+1]=\sum_k h[2k+1]x[n-k]
\]

建议函数接口：

```matlab
function [y, stat] = interp2_polyphase_bittrue( ...
    x, coeff_int, frac_w, data_w, acc_w)
```

输出统计信息：

```matlab
stat.acc_overflow_count
stat.output_sat_count
stat.max_abs_acc
stat.max_abs_output
stat.zero_output_count
stat.phase0_gain
stat.phase1_gain
```

实现要点：

```matlab
h0 = coeff_int(1:2:end);
h1 = coeff_int(2:2:end);
```

分别计算偶相和奇相输出。

如果系数已经包含插值增益 2，则右移：

```matlab
shift_n = frac_w;
```

如果系数没有乘 2，但想在输出补偿增益，则右移：

```matlab
shift_n = frac_w - 1;
```

两种方法不要混用。

## 8.3 完整 7 级定点链路

建议：

```matlab
function [y, stage_stat] = simulate_all2x_bittrue( ...
    x, stage_result, data_w, acc_w_list)

    y = int64(x);

    for stage_idx = 1:length(stage_result)

        [y, stage_stat(stage_idx)] = ...
            interp2_polyphase_bittrue( ...
                y, ...
                stage_result(stage_idx).coeff_int, ...
                stage_result(stage_idx).frac_w, ...
                data_w, ...
                acc_w_list(stage_idx));
    end
end
```

每一级输出仍保持 24 bit。

---

# 9. 必须增加的定点测试信号

## 9.1 冲激

用途：

- 检查滤波器系数顺序；
- 检查偶相和奇相是否交换；
- 检查总群延迟；
- 检查 MATLAB 与 RTL 是否一致。

```matlab
x = zeros(1, 256, 'int64');
x(1) = 2^22;
```

## 9.2 直流常数

用途：

- 检查每级插值增益；
- 检查输出是否逐级减半；
- 检查 polyphase 两相直流增益是否一致。

```matlab
x = int64(ones(1, 1024) * 2^20);
```

通过条件：

```text
最终稳态输出 ≈ 输入幅值
偶相和奇相幅度基本相同
```

## 9.3 正弦

至少测试：

```text
1 kHz：-1 dBFS、-6 dBFS、-20 dBFS
19 kHz：-6 dBFS
20 kHz：-6 dBFS
```

检查：

- 幅度保持；
- SNR；
- THD；
- 通带边缘误差；
- 总延迟。

## 9.4 小信号

建议：

```text
-60 dBFS
-90 dBFS
-110 dBFS
```

检查多级舍入后是否异常归零。

## 9.5 满幅极限

包括：

```text
正满量程
负满量程
正负交替
满幅方波
接近满幅 20 kHz 正弦
```

检查：

- 累加器溢出；
- 输出饱和；
- 增益补偿后是否削顶。

## 9.6 随机 PCM

```matlab
x = randi([-2^23, 2^23-1], 1, 4096, 'int32');
```

用途：

- 对照 RTL 仿真输出；
- 检查逐点完全一致；
- 检查正负数舍入边界。

---

# 10. 定点性能评价指标

建议增加：

```matlab
function metric = analyze_fixed_signal(y_fixed, y_ref)
```

至少输出：

```text
峰值误差
均方误差 MSE
最大绝对误差
SNR
SINAD
THD
饱和次数
累加器溢出次数
零输出比例
直流增益误差
通带边缘幅度误差
```

MATLAB 与 RTL 逐点比较：

```matlab
diff = int64(y_matlab) - int64(y_rtl);

max_abs_diff = max(abs(diff));
num_mismatch = nnz(diff);
```

最终要求：

```text
max_abs_diff = 0
num_mismatch = 0
```

---

# 11. 为 RTL 导出完整配置，而不只是系数

每一级建议导出：

```text
STAGE_INDEX
FS_IN
FS_OUT
ORDER
TAPS
PHASE0_TAPS
PHASE1_TAPS
COEFF_W
FRAC_W
DATA_W
ACC_W
GAIN_MODE
NONZERO_HALF
CSD_COST
EXPECTED_GROUP_DELAY
```

建议导出：

```text
all2x_rtl_stage_config.csv
```

例如：

```csv
STAGE,FS_IN,FS_OUT,TAPS,COEFF_W,FRAC_W,ACC_W,GAIN_MODE
1,44100,88200,101,16,14,43,COEFF_X2
2,88200,176400,17,12,10,38,COEFF_X2
```

还可以自动生成 Verilog 参数文件：

```verilog
localparam integer STAGE1_TAPS    = 101;
localparam integer STAGE1_COEFF_W = 16;
localparam integer STAGE1_FRAC_W  = 14;
localparam integer STAGE1_ACC_W   = 43;
```

---

# 12. RTL 资源导向的推荐映射

不要把 7 个滤波器全部做成并行 LUT 乘法器。

## Stage 1：101 tap

推荐：

```text
2相 polyphase
线性相位对称结构
单 DSP 时分复用 MAC
```

原因：

- 偶相约 51 tap；
- 奇相约 50 tap；
- 利用对称性后，每相约 25～26 次乘法；
- Stage 1 输出速率只有 88.2 kHz；
- 在 100 MHz 系统时钟下，每个输出样点约有 1134 个时钟周期；
- 一个 DSP 完全足够。

## Stage 2：17 tap

比较两种候选：

```text
A：短 FIR，并行常数乘法，no-DSP
B：单 DSP 时分复用
```

由 Vivado 综合决定。

## Stage 3：11 tap

优先：

```text
2相 polyphase
对称短 FIR
no-DSP
```

## Stage 4～7：7 tap

优先：

```text
2相 polyphase
常数移位加法
no-DSP
```

后级系数位宽可能很低，适合 LUT 实现。

---

# 13. 建议增加一个 RTL 资源代理函数

MATLAB 中增加：

```matlab
function cost = estimate_rtl_cost(stage, data_w, sys_clk)
```

输出：

```matlab
cost.delay_register_bits
cost.nonzero_half
cost.csd_adders
cost.acc_width
cost.mac_cycles_per_output
cost.available_cycles_per_output
cost.can_use_single_dsp
cost.estimated_dsp
cost.estimated_lut_score
```

单 DSP 是否可用：

```matlab
available_cycles = floor(sys_clk / stage.Fs_out);
required_cycles  = stage.nonzero_half;

can_use_single_dsp = required_cycles <= available_cycles;
```

对于对称 polyphase，应按每个相位实际非零乘法数计算。

---

# 14. 建议修改后的主脚本结构

建议将一个大脚本拆成：

```text
01_design_stage_candidates.m
02_joint_select_all2x_chain.m
03_check_all2x_float_response.m
04_check_all2x_bittrue_response.m
05_export_all2x_rtl_files.m
06_generate_all2x_test_vectors.m
07_compare_all2x_rtl_results.m
```

对应功能：

## `01_design_stage_candidates.m`

生成每一级多个候选，不只保存一个最优结果。

## `02_joint_select_all2x_chain.m`

联合搜索最终资源最优组合。

## `03_check_all2x_float_response.m`

检查理想量化系数频响。

## `04_check_all2x_bittrue_response.m`

检查逐级 24 bit 定点数据通路。

## `05_export_all2x_rtl_files.m`

导出系数、参数、累加器位宽、gain 模式和 group delay。

## `06_generate_all2x_test_vectors.m`

生成 RTL testbench 输入和 MATLAB golden 输出。

## `07_compare_all2x_rtl_results.m`

读取 Vivado 仿真输出并逐点比较。

---

# 15. 推荐实施顺序

## P0：必须先完成

1. 修正 Stage 2～7 阻带起点；
2. 改成绝对 ±0.05 dB 通带判定；
3. 明确每级 2× 插值增益；
4. 增加每相直流增益检查；
5. 建立逐级 bit-true 模型；
6. 验证冲激、直流、正弦和随机 PCM。

完成标准：

```text
浮点总链路通过
bit-true 总链路无累加器溢出
正常幅度下无输出饱和
直流与正弦幅度保持
随机 PCM 可生成 golden 输出
```

## P1：资源优化

1. `COEFF_W` 改为自动最小位宽；
2. 后级搜索到 Q6～Q10；
3. 增加 CSD 代价；
4. 增加累加器理论位宽；
5. 每一级保留 Pareto 候选；
6. 进行总链路联合搜索。

完成标准：

```text
总通带绝对误差 ≤ 0.05 dB
总阻带衰减 ≥ 72 dB
至少保留 2 dB 工程裕量
bit-true 无异常
估算 LUT 成本低于当前方案
```

建议不要只卡在 70.00 dB，定点和 RTL 实现最好保留至少 2～4 dB 裕量。

## P2：RTL 对接

1. Stage 1 实现单 DSP polyphase MAC；
2. Stage 2 比较 DSP MAC 和 no-DSP；
3. Stage 3～7 使用短 FIR；
4. 导出 RTL test vector；
5. Vivado 仿真与 MATLAB 逐点比对；
6. 综合资源和时序；
7. 根据综合结果反向修正 MATLAB 资源代价模型。

---

# 16. 最终应形成的结果表

建议生成：

```text
all2x_final_comparison.csv
```

至少包含：

| 方案 | LUT | FF | DSP | BRAM | WNS | 通带最大误差 | 阻带衰减 | SNR | 饱和次数 |
|---|---:|---:|---:|---:|---:|---:|---:|---:|---:|
| 旧版 4×+5×2× | 实测 | 实测 | 2 | 实测 | 实测 | 实测 | 实测 | 实测 | 实测 |
| 全2×直接并行 | 实测 | 实测 | 0 | 实测 | 实测 | 实测 | 实测 | 实测 | 实测 |
| 全2×优化 polyphase | 实测 | 实测 | 1 | 实测 | 实测 | 实测 | 实测 | 实测 | 实测 |

只有完成这个表，才能可靠判断新结构是否真的优于旧结构。

---

# 17. 推荐的最终 MATLAB 验收条件

## 浮点频响

```text
10 Hz～20 kHz 最大绝对幅度误差 ≤ 0.045 dB
24.1 kHz～2.8224 MHz 阻带衰减 ≥ 72 dB
严格对称
严格线性相位
```

这里将指标设得略严于赛题，用于保留工程裕量。

## 定点数据通路

```text
24 bit 输入、24 bit 级间输出
无累加器溢出
-1 dBFS 正弦不饱和
直流稳态增益误差可接受
1 kHz、19 kHz、20 kHz 幅度满足要求
低幅度信号不会异常归零
MATLAB 与 RTL 逐点完全一致
```

## 资源

目标建议：

```text
DSP ≤ 1
LUT 明显低于旧版 10197
FF 不高于旧版或仅小幅增加
WNS > 0
```

---

# 18. 当前最推荐的下一步

按照优先级，下一步直接执行：

```text
第一步：修正 f_stop_begin
第二步：加入每级 2 倍插值增益
第三步：改用绝对通带误差判定
第四步：建立 7 级 polyphase bit-true 模型
第五步：将后四级 FRAC_W 搜索扩展到 6～12 bit
第六步：导出第一版 RTL 参数和 golden test vector
```

不要马上开始写 7 个 RTL 模块。

在 MATLAB 中先回答以下问题：

1. 每一级最终应该使用多少 tap？
2. 每一级最低可以使用多少 `FRAC_W`？
3. 每一级实际需要多少 `COEFF_W`？
4. 每一级理论最小 `ACC_W` 是多少？
5. 每一级是否已经正确补偿 2 倍插值增益？
6. 满幅输入时是否会饱和？
7. 小信号经过七级后是否仍然保留？
8. Stage 1 是否能用一个 DSP 完成？
9. 总链路是否保留至少 2 dB 阻带裕量？
10. MATLAB 与未来 RTL 是否能做到逐点完全一致？

全部确认后，再进入 RTL，返工风险最低。
