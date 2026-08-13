# 近年相关论文图示调研摘要

本图组的组织方式参考了近年采样率转换与 FPGA 实现论文常见的分层表达，但所有结构、数值与结论均来自本工程的 RTL、实现报告和测试记录。

- Shahabuddin 等（2022）将传统多相模型、面向硬件的 VLSI 架构、定点性能和资源结果分别成图/成表。这支持本图组将“算法链”“资源复用微体系结构”“资源与验证证据”分开呈现，而不把所有内容压入一幅总图。文献：S. Shahabuddin, P. Manninen, M. Juntti, *A Fractional Sample Rate Converter With Parallelized Multiphase Output: Algorithm and FPGA Implementation*, Journal of Signal Processing Systems, 2022。
- Galindo Guarch 等（2020）明确区分同步与异步采样率转换体系，并用单一处理时钟描述硬件架构。本工程据此把 $F_s$、$2F_s$、$4F_s$、$8F_s$ 和 $128F_s$标为“有效事件率”，而不是画成多个独立时钟域。文献：F. J. Galindo Guarch, P. Baudrenghien, J. M. Moreno Arostegui, *An Architecture for Real-Time Arbitrary and Variable Sampling Rate Conversion*, IEEE TCAS-I, 2020。
- Pinjerla 等关于混合 CIC—多相结构的工作采用“系统概览—数学模型—内部算子架构”的分级方式，说明混合滤波链需要同时给出等价关系和实现映射。本工程的算法图与此前两张 CIC 算子图沿用这一分层原则。文献：S. Pinjerla et al., *Multi-stage decimation with hybrid CIC-polyphase filtering for IoT gateway sample rate conversion*, Scientific Reports, 2026。
- AMD FIR Compiler PG149 的多相插值器说明强调相位、输入/输出采样率及运算量缩减。本文的三级 FIR 数据通路图因此在主链上显式标注相位 MAC 数、数据位宽和事件率，同时把物理 DSP 共享关系另行框出。

调研只影响图面层级、标签粒度和证据组织方式；没有从外部论文复制图形，也没有以其他器件或工具版本的数据替代本工程结果。
