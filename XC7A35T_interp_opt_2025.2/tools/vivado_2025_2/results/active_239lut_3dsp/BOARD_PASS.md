# ✅ 239-LUT / 3-DSP 24/20/20 物理板验证记录

| 项目 | 记录 |
|---|---|
| 验证日期 | 2026-08-12 |
| Vivado | 2025.2 |
| 配置编号 | `NF-P3-STAGE123-24-20-20-3DSP-PARETO-R1` |
| CIC 积分器 DSP 模式 | `1` |
| 完整系统资源 | 239 LUT / 388 FF / 3 DSP48E1 / 4 RAMB18E1（2 BRAM Tile）/ 2 MMCM |
| 定点规格 | Stage1/Stage2/Stage3 = 24/20/20 bit |
| 物理板验证 | 239-LUT 版本板测通过 |
| RTL Smoke | 17/17 PASS |
| 实现签核 | WNS/WHS=`+44.703/+0.079 ns`，DRC Error=0 |
| bitstream | `board_demo_competition_dac8_top_239lut_3dsp.bit` |
| bitstream SHA-256 | `796844A59E439744082A11CDBD75C4BBAA4538D598B2793310E24E6B2F0401EA` |
| routed DCP | `board_routed_239lut_3dsp.dcp` |
| routed DCP SHA-256 | `89F075A53ADCEC418F9E25531F6C9CE9ED12409436E4599D35666A5EF0E9E188` |
| 正式归档标签 | `nf-vivado2025.2-239lut-388ff-3dsp-2bram-24-20-20-board-pass` |
| LUT 优先实板回退 | 218 LUT / 365 FF / 4 DSP48E1，目录 `XC7A35T_interp_LUTmin_2025.2` |

本记录归档已确认的“239-LUT 版本板测成功”结论；未提供的逐档采样率、
DAC 波形及其他仪器原始读数不作推测。该版本与历史 239 LUT / 377 FF / 4 DSP48E1
实板版本不同，两者通过 FF、DSP 数和配置编号加以区分。
