`ifndef ALL2X_V2_COEFF_PKG_VH
`define ALL2X_V2_COEFF_PKG_VH

//=============================================================
// 文件名       : all2x_v2_coeff_pkg.vh
// 功能简述     : Stage 2/3 true-polyphase RTL 自动导出系数。
//                本文件由 v2_05_export_stage23_polyphase.m 生成。
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-11
// 版本         : V2025.2
// 开发工具     : MATLAB / Vivado 2025.2
// 修订记录     :
//                2026-07-11：新增 Stage 2/3 两相系数。
//                2026-08-16：统一正式交付版本与中文文件头口径；
//                            系数常量及位宽定义保持不变。
//=============================================================

`define V2_S2_P0_C0      (-16'sd115)
`define V2_S2_P0_C1      (16'sd534)
`define V2_S2_P0_C2      (-16'sd1302)
`define V2_S2_P0_C3      (16'sd2116)
`define V2_S2_P0_C4      (16'sd30298)
`define V2_S2_P0_C5      (16'sd2116)
`define V2_S2_P0_C6      (-16'sd1302)
`define V2_S2_P0_C7      (16'sd534)
`define V2_S2_P0_C8      (-16'sd115)

`define V2_S2_P1_C0      (-16'sd203)
`define V2_S2_P1_C1      (16'sd1233)
`define V2_S2_P1_C2      (-16'sd4595)
`define V2_S2_P1_C3      (16'sd19945)
`define V2_S2_P1_C4      (16'sd19945)
`define V2_S2_P1_C5      (-16'sd4595)
`define V2_S2_P1_C6      (16'sd1233)
`define V2_S2_P1_C7      (-16'sd203)

`define V2_S3_P0_C0      (15'sd202)
`define V2_S3_P0_C1      (-15'sd1636)
`define V2_S3_P0_C2      (15'sd9625)
`define V2_S3_P0_C3      (15'sd9625)
`define V2_S3_P0_C4      (-15'sd1636)
`define V2_S3_P0_C5      (15'sd202)

`define V2_S3_P1_C0      (-15'sd74)
`define V2_S3_P1_C1      (15'sd261)
`define V2_S3_P1_C2      (15'sd16008)
`define V2_S3_P1_C3      (15'sd261)
`define V2_S3_P1_C4      (-15'sd74)

`endif
