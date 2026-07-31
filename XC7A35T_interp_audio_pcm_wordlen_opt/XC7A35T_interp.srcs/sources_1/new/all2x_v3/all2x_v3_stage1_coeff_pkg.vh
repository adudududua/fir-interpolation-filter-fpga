`ifndef ALL2X_V3_STAGE1_COEFF_PKG_VH
`define ALL2X_V3_STAGE1_COEFF_PKG_VH

//=============================================================
// 文件名       : all2x_v3_stage1_coeff_pkg.vh
// 功能简述     : Stage 1 strict-halfband true-polyphase 系数。
//                本文件由 v3_02_export_stage1_rtl.m 自动生成。
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-11
// 版本         : V2018.3
// 开发工具     : MATLAB / Vivado
// 修订记录     :
//                2026-07-11：新增 Stage 1 严格半带系数。
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

// Route 2B: 97-tap strict-halfband Stage1, Q16.  The direct phase remains
// an unscaled one-sample delay; these 24 values are the unique coefficients
// of the filtered phase.
`define R2_S1_TAPS          97
`define R2_S1_FRAC_W        16
`define R2_S1_COEFF_W       18
`define R2_S1_ACC_W         42
`define R2_S1_HISTORY_LEN   48
`define R2_S1_PAIR_COUNT    24
`define R2_S1_DELAY_INDEX   23

`define R2_S1_C00 (-18'sd19)
`define R2_S1_C01 (18'sd25)
`define R2_S1_C02 (-18'sd41)
`define R2_S1_C03 (18'sd63)
`define R2_S1_C04 (-18'sd93)
`define R2_S1_C05 (18'sd132)
`define R2_S1_C06 (-18'sd182)
`define R2_S1_C07 (18'sd245)
`define R2_S1_C08 (-18'sd324)
`define R2_S1_C09 (18'sd422)
`define R2_S1_C10 (-18'sd541)
`define R2_S1_C11 (18'sd686)
`define R2_S1_C12 (-18'sd861)
`define R2_S1_C13 (18'sd1074)
`define R2_S1_C14 (-18'sd1332)
`define R2_S1_C15 (18'sd1650)
`define R2_S1_C16 (-18'sd2046)
`define R2_S1_C17 (18'sd2551)
`define R2_S1_C18 (-18'sd3220)
`define R2_S1_C19 (18'sd4157)
`define R2_S1_C20 (-18'sd5581)
`define R2_S1_C21 (18'sd8069)
`define R2_S1_C22 (-18'sd13741)
`define R2_S1_C23 (18'sd41675)

`endif
