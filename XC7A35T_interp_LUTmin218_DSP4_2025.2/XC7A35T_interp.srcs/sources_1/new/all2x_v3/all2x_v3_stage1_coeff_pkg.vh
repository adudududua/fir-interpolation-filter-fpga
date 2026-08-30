`ifndef ALL2X_V3_STAGE1_COEFF_PKG_VH
`define ALL2X_V3_STAGE1_COEFF_PKG_VH

//=============================================================
// 文件名       : all2x_v3_stage1_coeff_pkg.vh
// 功能简述     : Stage 1 strict-halfband true-polyphase 系数。
//                本文件由 v3_02_export_stage1_rtl.m 自动生成。
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-11
// 版本         : V2025.2
// 开发工具     : MATLAB / Vivado 2025.2
// 修订记录     :
//                2026-07-11：新增 Stage 1 严格半带系数。
//                2026-08-16：统一正式交付版本与中文文件头口径；
//                            系数常量及位宽定义保持不变。
//=============================================================

`define V3_S1_TAPS          105
`define V3_S1_FRAC_W        15
`define V3_S1_COEFF_W       17
`define V3_S1_ACC_W         42
`define V3_S1_HISTORY_LEN   52
`define V3_S1_PAIR_COUNT    26
`define V3_S1_DELAY_INDEX   25

`define V3_S1_C00 (-17'sd5)
`define V3_S1_C01 (17'sd7)
`define V3_S1_C02 (-17'sd12)
`define V3_S1_C03 (17'sd19)
`define V3_S1_C04 (-17'sd29)
`define V3_S1_C05 (17'sd42)
`define V3_S1_C06 (-17'sd59)
`define V3_S1_C07 (17'sd80)
`define V3_S1_C08 (-17'sd107)
`define V3_S1_C09 (17'sd141)
`define V3_S1_C10 (-17'sd182)
`define V3_S1_C11 (17'sd233)
`define V3_S1_C12 (-17'sd293)
`define V3_S1_C13 (17'sd367)
`define V3_S1_C14 (-17'sd455)
`define V3_S1_C15 (17'sd562)
`define V3_S1_C16 (-17'sd691)
`define V3_S1_C17 (17'sd849)
`define V3_S1_C18 (-17'sd1045)
`define V3_S1_C19 (17'sd1296)
`define V3_S1_C20 (-17'sd1629)
`define V3_S1_C21 (17'sd2094)
`define V3_S1_C22 (-17'sd2803)
`define V3_S1_C23 (17'sd4044)
`define V3_S1_C24 (-17'sd6876)
`define V3_S1_C25 (17'sd20836)

`endif
