# 268-LUT / 2-DSP 当前工具签核记录

- 配置编号：`NF-P3-STAGE123-24-20-20-2DSP-PARETO-R1`；
- Vivado：2025.2；
- CIC 积分器 DSP 模式：`0`；
- 完整系统资源：268 LUT / 417 FF / 2 DSP48E1 / 4 RAMB18E1（2 BRAM Tile）/ 2 MMCM；
- 定点规格：Stage1/Stage2/Stage3 = 24/20/20 bit；
- RTL Smoke：17/17 PASS，运行目录 `matlab_fir/national_finals/_work/rtl_regression/20260812_172852`；
- 实现签核：WNS/WHS=`+44.389/+0.078 ns`，DRC Error=0；
- 独立构建 bitstream：`board_demo_competition_dac8_top_268lut_2dsp.bit`；
- 独立构建 bitstream SHA-256：`1F6DCF4A9CD81D4301AA18E6789B751873E9CA367739346F4E7E8F70E301E50B`；
- 独立构建 routed DCP SHA-256：`184CCB861EBC3B0B106FA983075F8445C351772F6BF2C5B89114AEB10A5E9F03`；
- 标准 GUI `synth_1/impl_1` bitstream SHA-256：`7A8542EA469EB9312B0AD87F4832455337C0616575C12A4860A3D9A26C6DF92A`；
- 标准 GUI routed DCP SHA-256：`B3F5ACB452812B958759FA89F0DE502D4ECC836783DA76EE78D5FAD546C6A603`；
- 当前状态：`tool-verified`，待物理板验证；
- 实板安全回退：标签 `nf-vivado2025.2-239lut-388ff-3dsp-2bram-24-20-20-board-pass`。

独立构建与标准 GUI 构建的资源、时序和 DRC 结果一致。bitstream 哈希不同源于两条构建
路径的生成环境与输出封装差异，不代表功能或资源配置不同。物理板验证完成前，本版本不得
标记为 `board-pass`。
