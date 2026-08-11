# Vivado 2025.2 218-LUT 发布配置闭环执行反馈

## 1. 目标与基线

2026-08-11 用户确认 218-LUT 24/20/20 版本物理板测成功后，先在提交
`c130115` 归档板测结论，并创建不可变回退标签
`nf-vivado2025.2-218lut-365ff-4dsp-2bram-24-20-20-board-pass`。本轮只修复
发布配置、金标准和工程门禁漂移，不修改滤波系数、舍入、饱和、采样率或板级接口。

## 2. 实施内容

1. 新增 `nf_release_218_config.m`，对不可变 P4-D 系数/累加器证明执行基线 ID
   断言，再明确覆盖 24/20/20 bridge、Stage2、联合 Stage3 补偿、资源和实板产物哈希。
2. 新增 `release_218/nf_release_218_config.json`，由 MATLAB 发布脚本生成，不再手工维护
   一套易漂移 JSON。
3. 位真模型改为从 218 发布配置取得 bridge、Stage2、Stage3 和 CIC 字长。
4. 生成并纳入版本管理的 `vectors/release_218_smoke`；9 个文件与原工具签核
   24/20/20 Smoke 金标准的 SHA-256 逐文件一致。
5. RTL 回归默认使用 Vivado 2025.2、24/20/20 和稳定金标准；历史 24/22/20 仅在
   显式传入 `-StageWordLength 24_22_20` 时启用。
6. GUI 模拟文件集指向稳定 218 Smoke 向量，源文件集显式固定
   `USE_NATIONAL_FINALS_STAGE2_DATA_W=20`。
7. Vivado 完整构建新增配置指纹、CDC 和 Methodology 报告，并把资源回归
   上限收紧到 218 LUT / 365 FF。

## 3. 验证结果

- MATLAB 配置发布：`NF_RELEASE_218_CONFIG_PASS`；
- 新旧 Smoke 向量：9/9 文件 SHA-256 一致；
- 默认 RTL Smoke：**17/17 PASS**，运行目录
  `matlab_fir/national_finals/_work/rtl_regression/20260811_231341`；
- 端到端：冲激 + 1 个固定随机 seed，4x/8x/128x 全部 **0 LSB**；
- 复位恢复：8/8 PASS；不停机动态切档：10 次 PASS；
- Vivado 2025.2 完整构建：`VIVADO_2025_2_FULL_BUILD_PASS`，结果目录
  `XC7A35T_interp_opt_2025.2/tools/vivado_2025_2/results/20260811_231722`；
- 路由后：**218 LUT / 365 FF / 4 DSP48E1 / 4 RAMB18E1 / 2 MMCM**；
- WNS/WHS=`+45.279/+0.079 ns`，路由失败网络=0，DRC Error=0，bitstream 生成成功。

## 4. CDC 与 Methodology 审计

CDC 报告中的 2 个 `CDC-13 Critical` 精确对应 `BUFGMUX_CTRL` 的 S0/S1 选择脚，
已有精确 false-path，并由 100 次时钟族切换无窄脉冲回归覆盖。4 个 `CDC-15`
对应保持到 ACK 的两位 bundled-data，已有 50 ns `set_max_delay -datapath_only`和
`set_bus_skew`，并由 1200 次原子提交回归覆盖。这些是已知并经定向验证的结构，
不是新引入问题。

Methodology 报告只有 1 个 ROM 输出寄存器建议和 8 个 DAC 数据延迟告警。XDC 已对
`dac_data[7:0]` 在两个互斥 DAC 时钟下施加 max/min output delay；当前板测基线不因
方法学工具对双生成时钟端口的报告行为而改变 XDC 语义。

## 5. 结论

发布配置闭环没有改变数值或硬件结果，默认回归、GUI 向量、源文件集泛型、
MATLAB 模型和完整构建现在都明确指向同一 218-LUT 24/20/20 配置。
