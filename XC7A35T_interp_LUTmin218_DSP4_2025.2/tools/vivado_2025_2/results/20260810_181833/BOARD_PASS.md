# 221-LUT 物理板验证记录

- 验证日期：2026-08-10；
- Vivado：2025.2；
- 完整系统资源：221 LUT / 367 FF / 4 DSP48E1 / 4 RAMB18E1（2 BRAM Tile）/ 2 MMCM；
- 用户物理板反馈：44.1 kHz 与 48 kHz 两个输入采样率族下，各倍率档位输出采样率均正确；
- 用户物理板反馈：各倍率档位 DAC 输出波形均正常；
- bitstream SHA-256：`08B2DE6DB8DF1FBC9E59EA78808C57BD007E414243B5F6FF9C7FF1B2797D91A7`；
- routed DCP SHA-256：`BFE4A9A25958C232E24091A08EE7A2F0E564AB3DF8C45EEFEB9CCA3CF1DC943F`；
- 工具签核标签：`nf-vivado2025.2-221lut-367ff-4dsp-2bram-toolverified`；
- 正式实板标签：`nf-vivado2025.2-221lut-367ff-4dsp-2bram-board-pass`；
- 前一实板安全回退：`nf-vivado2025.2-234lut-369ff-4dsp-2bram-board-pass`。

本记录仅归档用户明确确认的采样率和 DAC 波形结论；未提供的逐档仪器原始读数不作推测。
