# Vivado 2025.2 234-LUT 实板通过归档

2026-08-10，用户使用本目录 bitstream 完成物理板验证，确认：

- 44.1 kHz 与 48 kHz 两个输入采样率族下，各个公开插值档位的实际输出采样率均正确；
- AD9708 DAC 输出波形正常；
- 234-LUT 版本板测通过。

正式实现资源为 **234 LUT / 0 LUTRAM / 369 FF / 4 DSP48E1 / 4 RAMB18E1
（2 BRAM Tile）/ 17 IO / 2 MMCM**。WNS/WHS=`+44.925/+0.060 ns`，TNS/THS=0，
路由失败网络为 0，DRC Error=0。

归档文件：

- `board_demo_competition_dac8_top_2025_2_board_pass.bit`
  - 大小：2,192,155 bytes
  - SHA-256：`F9DB8E33C3959C448FDE316A51BA9A13ABC83D5AE1F69655CD5D0B698A871E85`
- `board_routed_2025_2_board_pass.dcp`
  - 大小：513,552 bytes
  - SHA-256：`47CDCA8E43C2DA817D028828564862EC56C64F0E791C6F845DE05A3E03DA3162`

本目录保存的是用户实际下载验证的精确 bitstream。前一份
`results/20260810_160858` 继续作为独立生产脚本的完整工具签核归档，两者使用相同正式 RTL、
约束和 Vivado 2025.2 版本。
