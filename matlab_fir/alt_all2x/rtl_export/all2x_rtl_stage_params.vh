//=============================================================
// 文件名       : all2x_rtl_stage_params.vh
// 功能简述     : 全 2x 级联 128 倍插值链路的自动导出 RTL 参数。
//                本文件由 export_all2x_rtl_files.m 生成。
//
// 设计作者     : kafeizizi
// 创建日期     : 2026-07-10
// 版本         : V2018.3
// 开发工具     : Vivado
// 修订记录     :
//                2026-07-10：自动导出全 2x 逐级 RTL 参数。
//=============================================================

localparam integer STAGE1_TAPS    = 93;
localparam integer STAGE1_COEFF_W = 17;
localparam integer STAGE1_FRAC_W  = 16;
localparam integer STAGE1_ACC_W   = 43;

localparam integer STAGE2_TAPS    = 17;
localparam integer STAGE2_COEFF_W = 16;
localparam integer STAGE2_FRAC_W  = 15;
localparam integer STAGE2_ACC_W   = 41;

localparam integer STAGE3_TAPS    = 11;
localparam integer STAGE3_COEFF_W = 15;
localparam integer STAGE3_FRAC_W  = 14;
localparam integer STAGE3_ACC_W   = 40;

localparam integer STAGE4_TAPS    = 7;
localparam integer STAGE4_COEFF_W = 16;
localparam integer STAGE4_FRAC_W  = 15;
localparam integer STAGE4_ACC_W   = 41;

localparam integer STAGE5_TAPS    = 7;
localparam integer STAGE5_COEFF_W = 14;
localparam integer STAGE5_FRAC_W  = 13;
localparam integer STAGE5_ACC_W   = 39;

localparam integer STAGE6_TAPS    = 7;
localparam integer STAGE6_COEFF_W = 13;
localparam integer STAGE6_FRAC_W  = 12;
localparam integer STAGE6_ACC_W   = 38;

localparam integer STAGE7_TAPS    = 7;
localparam integer STAGE7_COEFF_W = 14;
localparam integer STAGE7_FRAC_W  = 12;
localparam integer STAGE7_ACC_W   = 38;

