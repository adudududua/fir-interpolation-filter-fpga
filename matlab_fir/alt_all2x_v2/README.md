# 全 2x 优化 2.0 实验目录

本目录按照 `all2x_optimization_guide_v2.md` 执行结构优化实验，不修改 `alt_all2x` 稳定版本。

## 稳定基线

```text
Git commit：8418c7f
Git tag   ：regional-final-all2x-baseline
结构      ：7 级显式插零 2x FIR
独立链路  ：5912 LUT / 4218 FF / 1 DSP
板级      ：6426 LUT / 4416 FF / 1 DSP
频响      ：通带最大误差 0.00729793 dB，阻带 77.67936345 dB
RTL 对拍  ：冲激与随机 PCM 均为 0 LSB
```

## Phase 1 目标

按以下顺序把 Stage 4～7 替换为精确 canonical halfband7：

```text
Stage 7
Stage 6～7
Stage 5～7
Stage 4～7
```

精确核为：

```text
[-1, 0, 9, 16, 9, 0, -1] / 16
```

每一步必须检查：

1. 总通带最大绝对误差不大于 0.01 dB。
2. 总阻带衰减不低于 75 dB。
3. 常规 bit-true 无累加器溢出、无输出饱和。
4. MATLAB 与 RTL 随机 PCM、冲激响应均为 0 LSB。
5. Vivado LUT、FF、DSP 和 WNS 均有独立记录。

只有 Phase 1 的实际资源确有改善，才继续全链 true-polyphase。

## MATLAB 执行顺序

1. `v2_01_extract_current_baseline.m`
2. `v2_02_test_canonical_halfband7.m`
3. `v2_03_validate_canonical_bittrue.m`
4. `v2_04_compare_canonical_rtl.m`
5. `v2_05_export_stage23_polyphase.m`
6. `v2_06_compare_stage23_rtl.m`
7. `v2_07_design_stage1_strict_halfband.m`
8. `v2_08_validate_stage1_strict_bittrue.m`
9. `v3_01_select_stage1_pareto.m`
10. `v3_02_export_stage1_rtl.m`
11. `v3_03_generate_stage1_rtl_golden.m`
12. `v3_04_compare_stage1_rtl.m`
13. `v3_05_compare_stage1_bram_rtl.m`

## Phase 1 结果

推荐候选为 Stage 4～7 全部使用 canonical halfband7：

```text
频响：通带最大绝对误差 0.00715181 dB
      阻带衰减 77.67735619 dB
对拍：随机 PCM 与冲激响应均为 0 LSB
资源：4302 LUT / 3678 FF / 1 DSP
时序：WNS +165.930 ns
```

相对稳定基线减少 1610 LUT 和 540 FF。详细过程见：

```text
../all2x_optimization_guide_v2_feedback.md
```

## Phase 2 结果

Stage 2/3 改为共享数据通路 true-polyphase，六个级间桥改为
valid-only 轻量结构：

```text
频响：通带最大绝对误差 0.00715181 dB
      阻带衰减 77.67735619 dB
对拍：随机 PCM 与冲激响应均为 0 LSB
资源：3975 LUT / 3103 FF / 1 DSP
时序：WNS +156.988 ns
```

详细过程见：

```text
../all2x_phase2_polyphase_feedback.md
```

## Phase 3 结果

Stage 1 改为 105-tap Q15 strict-halfband true-polyphase，分别验证
FF 历史和 BRAM 循环缓冲两个版本：

| 版本 | LUT | FF | DSP | BRAM Tile | WNS / ns |
|---|---:|---:|---:|---:|---:|
| Phase 2 | 3975 | 3103 | 1 | 0 | +156.988 |
| Strict-HB FF | 3537 | 2105 | 1 | 0 | +159.856 |
| Strict-HB BRAM | 3222 | 925 | 1 | 1 | +159.809 |

FF 和 BRAM 版本的 Stage 1 单元及完整七级冲激、随机 PCM 对拍均为
0 LSB。当前推荐实验点是 BRAM 版本，板级稳定实例仍保持 Phase 2。

详细过程见：

```text
../all2x_phase3_stage1_strict_feedback.md
```
