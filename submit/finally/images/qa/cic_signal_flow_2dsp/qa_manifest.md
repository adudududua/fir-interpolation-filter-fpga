# CIC信流图质量核验

- 技术边界：当前268-LUT/2-DSP目标配置，`CIC_INTEGRATOR_DSP_MODE=0`。
- 数学结构：低速二阶差分、16点零阶保持、高速二阶积分；与传统三级CIC精确等效。
- 位宽链：21 → 22 → 23 → 23 → 26 → 29 → 20 bit。
- 资源映射：两级差分共享23-bit CARRY差分器；两级积分器均为Fabric/CARRY；CIC内部0 DSP48E1。
- 使能分层：`comb_active`控制串行差分，`first_output_event`锁存保持寄存器，`output_event`使能两级积分状态与输出寄存器。
- 量化：中点远离零舍入、算术右移8位并饱和到signed-20，不表述为直接截断。
- 图形规范：白底矢量输出，数据/反馈/使能/资源复用采用不同线型，兼容黑白打印。
- LaTeX构建：XeLaTeX成功；日志无字体、Overfull或Underfull警告。
- 输出：PDF、轮廓化SVG、600 dpi白底PNG均已生成。
