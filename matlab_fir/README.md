# MATLAB FIR 文件说明

本文件夹只保留当前 FPGA 工程最终插值滤波器设计需要的 MATLAB 文件，用于复现系数设计、查看优化结果、检查系统级频响指标。

## 全 2x 方案与对比报告

- `alt_all2x/design_all2x_interp128_compare.m`
  - 用于设计和检查 44.1kHz 专用的全 2x 七级 128 倍插值方案。
  - 输出结果保存在 `alt_all2x/` 目录，包括每级系数、总链路 summary 和频响图。

- `interp128_scheme_analysis_report.md`
  - 记录 `4x + 5级2x` 与 `全2x七级` 的方案对比。
  - 包含 MATLAB 频响图、资源复杂度估算、等波纹法说明，以及当前全 2x RTL 进度。

## 最终设计文件

- `acc_opt/interp4_fixed155_sparse_prune.m`
  - 用于设计和检查最终 4 倍前级 FIR。
  - 当前 RTL 使用 155 tap、18 bit 系数、Q16 小数格式。
  - 生成的最终 4x 系数保存在 `acc_opt/interp4_fixed155_sparse_coeff_*.txt`。

- `opt/design_interp2_fir_common_wordlen_opt.m`
  - 用于设计和检查后级重复使用的 2 倍 FIR。
  - 当前 RTL 使用 29 tap、14 bit 系数、Q12 小数格式。
  - 生成的最终 2x 系数保存在 `opt/interp2_coeff_*_wordlen_opt.txt`。

## 系统级检查文件

- `check_interp8_total_chain.m`
  - 检查 `4x + 2x` 级联系统，对应 8 倍插值输出：
    - 44.1 kHz -> 352.8 kHz
    - 48 kHz -> 384 kHz

- `check_interp128_chain_common.m`
  - 检查 `4x + 5 级 2x` 级联系统，对应 128 倍插值输出：
    - 44.1 kHz -> 5.6448 MHz
    - 48 kHz -> 6.144 MHz
  - 运行后会自动把频响/群延迟图保存到 `figures/` 目录。

## 已清理内容

旧版探索脚本、过期系数文件、大体积 golden/RTL 对拍数据、未采用的半带搜索结果，以及 197 tap 的 4x 备选优化结果已经删除。

当前目录重点保留最终比赛方案相关内容：155 tap 4x FIR、29 tap 2x FIR、8x/128x 系统级指标检查。
