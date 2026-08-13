# 论文结构框图图组

本目录用于保存当前2-DSP目标配置的论文级结构与验证图。每幅图均提供：

- `.pdf`：首选论文插图格式，保留矢量图元；
- `.svg`：文字已轮廓化，便于跨机排版与二次组合；
- `.png`：600 dpi预览与Word兼容版本；
- `thesis_architecture_diagram_set.pdf`：六幅图按推荐叙事顺序合并的多页PDF。

## 图名与用途

1. `board_system_architecture`：板级时钟、控制与数据协同架构；
2. `fir_cic_multirate_chain`：三级FIR--CIC主数据通路、位宽和事件率；
3. `shared_resource_microarchitecture`：两条DSP通道与三块核心RAMB18的复用；
4. `resource_allocation_2dsp`：资源角色、器件占用率和三个Pareto端点；
5. `verification_evidence_chain`：MATLAB、RTL、实现与物理板的分层证据链；
6. `test_matrix_results`：双采样率六工况、RTL回归和待闭合项目。

板级图中，采样率族切换请求须经过保护逻辑并结合所选MMCM锁定状态，随后以`family_active`控制BUFGMUX，同时产生音频域复位；模式CDC单独产生`audio_mute`，在下降沿IOB输出寄存器处强制DAC中码128。测试图中的E1“6/6、最大0 LSB”仅表示定点模型与稳定RTL向量逐样本一致，不表示浮点模型与定点模型之间不存在量化误差。

资源口径说明：268 LUT/417 FF/2 DSP/4 RAMB18E1/2 MMCM为Vivado 2025.2完整板级布局布线后总量。图中的DSP、RAMB18和MMCM角色可由实例明确核对；LUT/FF没有按模块人为分摊。218-LUT/4-DSP和239-LUT/3-DSP端点已完成用户确认的物理板功能验证，268-LUT/2-DSP端点为工具验证完成、物理板待验证。

源文件位于 `../../source/thesis_architecture_diagrams/`，构建脚本位于 `../../work/thesis_architecture_diagrams/build_all.ps1`。
