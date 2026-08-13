# 当前结构的论文级算子信流图

本目录保存当前268-LUT/2-DSP目标实现配置的四张黑白LaTeX/TikZ算子信流图。与系统结构框图不同，这组图以`Σ`、系数乘法、`z^-1`、MUX、寄存器和反馈环作为主要视觉语言。

1. `01_cic_algorithm_signal_flow`：CIC算法级等效结构；
2. `02_cic_rtl_signal_flow`：CIC两拍共享差分器、Hold16和两级Fabric积分器；
3. `03_stage1_polyphase_signal_flow`：第一级半带FIR两相结构与52项串行MAC；
4. `04_stage23_shared_mac_signal_flow`：第二级/第三级共享DSP48E1乘加反馈环。

每张图提供矢量PDF、轮廓化SVG和600 dpi PNG；`thesis_signal_flow_diagram_set.pdf`为四页合并图集。论文优先插入PDF；Word/WPS兼容性不足时可用600 dpi PNG。

准确性边界：Stage1数学中心延时为`z^-26`，RTL使用扫描索引25并通过跨事件寄存器对齐；Stage2/Stage3只共享一颗DSP；CIC为0 DSP。图中的时间展开不代表并行复制算子。
