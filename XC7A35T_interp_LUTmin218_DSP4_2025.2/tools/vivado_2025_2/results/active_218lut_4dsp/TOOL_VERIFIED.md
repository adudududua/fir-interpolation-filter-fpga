# Vivado 2025.2 24/20/20 字长候选工具签核

状态：**tool-verified + board-pass**。2026-08-11 用户已确认本 218-LUT/4-DSP
版本完成物理板验证；`BOARD_PASS.md` 记录该结论，221-LUT 版本保留为前一安全回退。

## 正式整板结果

| 项目 | 结果 |
|---|---:|
| Slice LUT | 218 |
| LUTRAM | 0 |
| FF | 365 |
| DSP48E1 | 4 |
| RAMB18E1 / BRAM Tile | 4 / 2 |
| IO / MMCM | 17 / 2 |
| WNS / WHS | +45.279 / +0.079 ns |
| DRC Error | 0 |
| Vectorless 总/动态/静态功耗 | 0.271 / 0.199 / 0.072 W |

综合前报告值为 280 LUT / 373 FF；上表为正式 post-route 值。

## 插值滤波器核心 OOC

核心顶层 `interp128_all2x_v7_folded_fir_cic_top_ce` 的独立 post-route 结果为
190 LUT / 279 FF / 4 DSP48E1 / 3 RAMB18E1（1.5 BRAM Tile），内部寄存器路径
WNS/WHS 为 +150.943/+0.069 ns，DRC Error 为 0。对应报告和 DCP 使用
`core_ooc_*` 文件名保存在本目录。

## 自动验证

- MATLAB 六模式频响 6/6、定向数值测试 9/9；
- 24/20/20 Smoke RTL：17/17；
- Release RTL：17/17，冲激、10 个固定随机种子、正负满幅及 −1 dBFS 强音频共 14 组，
  4x/8x/128x 对 24/20/20 MATLAB 金标准逐样本 0 LSB；
- 8 类复位恢复、10 次不停机动态切档、100 次时钟族切换和 1200 次模式 CDC 检查通过；
- 本目录 routed DCP 的六模式门级回归以 `BOARD POSTROUTE SIX-MODE DAC PASS` 结束。

六模式门级计数为：44.1 kHz 族 4x/8x/128x=`177/353/5645 edges/ms`，48 kHz 族
4x/8x/128x=`192/384/6144 edges/ms`；六档 DAC 数据均持续变化且无 X。

## 哈希

- bitstream SHA-256：`1834675AB971FFA8BD6C03BF1B596D6F5D65C8A36A6B8D0182EEA6C5D408D110`
- routed DCP SHA-256：`FC26756258EF14A60872D55CBDDAC928D536727937876788D180E2D3BE35A462`

正式板测文件：`board_demo_competition_dac8_top_218lut_4dsp.bit`。
