# 论文算子级信流图

本目录中的图按用户指定的经典信流图语言绘制：主图由求和节点 `Σ`、乘法/系数节点、`z^-1` 延时、寄存器、MUX及反馈支路组成。它们与`thesis_architecture_diagrams`中的系统框图属于不同抽象层级。

1. `01_cic_algorithm_signal_flow.tex`：CIC算法级等效信流图；
2. `02_cic_rtl_signal_flow.tex`：CIC串行差分、Hold16及两级Fabric积分的RTL实现级信流图；
3. `03_stage1_polyphase_signal_flow.tex`：Stage1严格半带两相结构及52项串行MAC映射；
4. `04_stage23_shared_mac_signal_flow.tex`：Stage2/Stage3共享DSP48E1的乘法—累加反馈环与任务选择。

所有图均对应当前268-LUT/2-DSP目标实现配置。CIC图不得理解为占用DSP；Stage2与Stage3不得理解为各自占用一颗DSP；Stage1的52项逻辑求和由同一DSP按时间展开，而不是52个并行乘法器。
