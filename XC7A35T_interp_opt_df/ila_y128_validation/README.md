# ILA 24-bit y128 与 MATLAB 黄金结果逐点验证

## 1. 验证目的

这项验证补充在现有 RTL 仿真和 ILA 波形展示之后，直接使用 FPGA 实板中
ILA 捕获的 `ila_final128_sample_w[23:0]`，与 Phase 7 正式整数位真 MATLAB
模型逐点比较，并生成误差直方图。

它回答的是：**实板中运行的完整 128× 插值数据，是否与 MATLAB 黄金模型
在每一个 24-bit 输出样点上完全一致。**

正式判定门槛为：

```text
mismatch count = 0
maximum error  = 0 LSB
```

本验证使用已有 SW9 演示 ROM，无需修改 RTL，也无需重新生成 bitstream。
该 ROM 是 44.1kHz、441 点相干多音信号，包含 4.1kHz 与 15kHz 两个分量；
因此这项逐点测试本身也属于可重复的多音板级验证。

## 2. 当前验证链路

```text
SW9 多音 ROM（4.1kHz + 15kHz，24bit，44.1kHz）
                    |
                    v
Stage1 2x -> Stage2 2x -> Stage3 2x -> CIC16
                    |
                    v
ila_final128_sample_w（24bit，5.6448MHz）
                    |
                    v
Vivado ILA CSV -> MATLAB 自动对齐 -> 逐点误差/直方图/频谱重合
```

MATLAB 使用的正式参数为 `2×2×2×16=128×`、CIC `R=16, M=1, N=3`，
并与板级实例一样使用 `FINAL_PRUNE_LSB=0`。

## 3. Vivado ILA 抓取步骤

1. 使用互相配套的 `.bit` 和 `.ltx` 编程 FPGA。
2. 打开 SW9，使 `demo_audio_sync=1`。
3. 等待至少 **0.5 秒**，让旧 NCO 数据完全离开滤波器状态。
4. 在 ILA 波形窗口找到 `ila_final128_sample_w[23:0]`。
5. 右键该信号，把 `Radix` 设置为 **Hex**。
6. 建议在 Trigger Setup 中加入 `demo_audio_sync == 1`。
7. 点击一次 Run Trigger，抓取一帧 4096 点数据。
8. 选择 `File -> Export -> Export ILA Data`，格式选择 CSV。
9. 把 CSV 保存为：

```text
ila_y128_validation/captures/ila_y128_capture.csv
```

可以导出全部探针，也可以只导出 y128。若 CSV 中包含
`demo_audio_sync`，脚本会额外检查它是否始终为 1。

## 4. MATLAB 操作

打开 MATLAB R2023a，执行：

```matlab
cd('D:/FpgaProject/XilinxProject/XC7A35T/fir_interpolation/XC7A35T_interp_opt_df/ila_y128_validation');
result = ila_y128_compare('captures/ila_y128_capture.csv');
```

第一次运行会调用 Phase 7 位真模型生成 56448 点稳态黄金周期，之后自动
缓存。由于 ILA 触发位置和上电相位不固定，脚本会在整个黄金周期内搜索
最佳固定延迟，然后对全部捕获点进行严格逐点比较。

先验证工具链本身时，可以运行：

```matlab
run('ila_y128_selftest.m');
```

自检会生成一份 Vivado 风格的 4096 点 Hex CSV，预期结果为严格 0 LSB。
它只检查 CSV 解析和比较流程，最终证据仍应使用 FPGA 实际导出的 CSV。

## 5. 自动生成的证据

| 文件 | 内容 |
|---|---|
| `results/ila_y128_pointwise_comparison.csv` | 每个样点的 ILA、MATLAB 和误差值 |
| `results/ila_y128_pointwise_summary.txt` | 样点数、对齐量、最大误差和 PASS/FAIL |
| `results/ila_y128_pointwise_result.mat` | 可继续分析的完整 MATLAB 数据 |
| `figures/ila_y128_pointwise_error_histogram.png` | 波形、误差、直方图和频谱重合四联图 |

PASS 时，误差曲线应为一条零线，误差直方图的全部计数都集中在 `0 LSB`，
ILA 与 MATLAB 的时域波形及频谱曲线应完全重合。

## 6. FAIL 时优先检查

按以下顺序排查：

1. `demo_audio_sync` 是否为 1，即 SW9 是否真的打开；
2. 打开 SW9 后是否等待了至少 0.5 秒；
3. 导出的是否为 `ila_final128_sample_w[23:0]`，而不是 DAC 8-bit 数据；
4. y128 的 Radix 是否为 Hex；
5. 当前 `.bit` 与 `.ltx` 是否来自同一次实现；
6. 当前工程是否仍是 Phase 7 正式 N=3、`FINAL_PRUNE_LSB=0` 版本；
7. CSV 是否包含连续的一整帧数据，且中途没有重新切换 SW9 或复位。

## 7. 答辩时的表述

可以这样介绍：

> 除 RTL 仿真逐点对拍外，我们还从实板 ILA 直接捕获完整 128 倍插值后的
> 24-bit 数据。输入采用 4.1kHz 与 15kHz 的相干多音 ROM，MATLAB 使用与
> FPGA 相同的定点系数、字长、舍入和 CIC 参数生成黄金结果。脚本自动消除
> ILA 触发造成的固定相位差，然后对全部 4096 个样点逐点比较。验收标准是
> mismatch 为 0、最大误差为 0 LSB，并用误差直方图和频谱重合图形成板级
> 闭环证据。

## 8. 可选扩展测试

- 扫频：使用原有 AUTO 功能逐步改变单音频率，记录通带内幅度变化；
- 多音：本验证已经使用 4.1kHz + 15kHz 相干双音，可继续增加三音 ROM；
- 频谱仪：若有条件，可在 DAC 模拟输出端复核镜像抑制和杂散；
- 更长抓取：若后续把 ILA 深度提高，可比较 8192 或 16384 个连续样点。

这些项目是附加证据；当前最优先、成本最低且判定最明确的是 4096 点
24-bit y128 与 MATLAB 位真黄金结果的严格 0 LSB 对拍。
