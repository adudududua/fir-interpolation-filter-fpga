# ILA 24-bit y128 实板逐点验证报告

## 1. 验证结论

2026-07-20 使用 FPGA 实际 ILA 导出的 4096 个连续
`ila_final128_sample_w[23:0]` 样点，与 Phase 7 正式 MATLAB 整数位真
黄金结果完成逐点比较，最终严格通过：

| 项目 | 实板结果 | 判定 |
|---|---:|---|
| 捕获样点数 | 4096 | 有效 |
| 输出数据宽度 | 24-bit signed | 一致 |
| 输出采样率 | 5.6448MHz | 一致 |
| 黄金周期长度 | 56448 点 | 441×128 |
| 自动对齐偏移 | 29799 点 | 固定相位差 |
| 不一致样点数 | **0** | 通过 |
| 最大绝对误差 | **0 LSB** | 通过 |
| RMS 误差 | **0 LSB** | 通过 |
| 最终判定 | **PASS** | 逐点位真一致 |

## 2. 实际输入和数据来源

实板输入为 SW9 演示模式下的相干双音 ROM：

```text
输入采样率：44.1kHz
数据宽度  ：24-bit signed PCM
音调分量  ：4.1kHz + 15kHz
ROM 周期  ：441 点
```

ILA CSV 来源：

```text
D:/FpgaProject/XilinxProject/XC7A35T/fir_interpolation/submit/display/
XC7A35T_interp_opt_df/XC7A35T_interp.runs/impl_1/iladata.csv
```

CSV 共 4097 行，其中 1 行表头、4096 行捕获数据。表头包含完整 y128、
`demo_audio_sync` 和 `ila_measurement_valid_w`；所有捕获行中演示开关均为
1，测量结果有效。y128 以 6 位十六进制补码导出。

提交工程与 MATLAB 验证工程使用的双音 ROM SHA256 均为：

```text
9D9434D4D634DEBB763EB4085A661E020E9108D95FBC8932BEC571F4418252D2
```

因此实板输入数据和黄金模型输入内容完全相同。

## 3. 比较方法

MATLAB 使用正式 Phase 7 参数：

```text
Stage1 2x -> Stage2 2x -> Stage3 2x -> CIC16
CIC: R=16, M=1, N=3
FINAL_PRUNE_LSB=0
输出：24-bit signed y128
```

先运行 12 个输入周期的整数位真模型，舍弃前 8 个周期的启动瞬态，并
验证相邻两个 56448 点输出周期严格相同。随后在一个完整黄金周期内搜索
ILA 捕获序列的固定相位，找到偏移 29799 点后，对全部 4096 点直接进行
整数减法。

自动对齐只消除 ILA 触发位置造成的固定样点偏移，没有进行幅度缩放、
增益拟合、重采样或误差补偿。因此 `0 LSB` 表示 FPGA 与 MATLAB 在每个
24-bit 输出码上完全相同。

## 4. 输出证据

逐点比较数据：

[`results/ila_y128_pointwise_comparison.csv`](results/ila_y128_pointwise_comparison.csv)

文字总结：

[`results/ila_y128_pointwise_summary.txt`](results/ila_y128_pointwise_summary.txt)

完整 MATLAB 数据：

[`results/ila_y128_pointwise_result.mat`](results/ila_y128_pointwise_result.mat)

四联验证图：

![ILA y128 实板逐点验证](figures/ila_y128_pointwise_error_histogram.png)

图中左上角的 ILA 和 MATLAB 时域曲线完全重合；右上角逐点误差始终为
0；左下角 4096 个样点全部集中在 `0 LSB`；右下角 4.1kHz、15kHz 及
旁瓣频谱完全重合。

## 5. 答辩表述

> 我们从 FPGA 实板 ILA 直接导出了完整 128 倍插值后的 24-bit 数据，
> 输入采用 4.1kHz 与 15kHz 的相干双音。MATLAB 使用与 FPGA 相同的定点
> 系数、字长、舍入和 CIC 参数生成黄金结果。消除 ILA 触发造成的固定
> 相位差后，4096 个连续输出样点全部逐点一致，不一致点为 0，最大误差
> 为 0 LSB。由此完成了从 MATLAB 位真模型、RTL 到 FPGA 实际内部数据
> 的板级闭环验证。

## 6. 验证边界

本结果严格证明该双音稳态场景下 4096 个连续 24-bit y128 样点位真一致，
并与已有冲激、daily/nightly 随机 PCM RTL 回归互相补充。它不等同于模拟
输出端的扫频或频谱仪测试；若设备条件允许，后续仍可把模拟扫频和频谱仪
结果作为附加证据，但不影响本次实板数字链 `0 LSB PASS` 结论。
