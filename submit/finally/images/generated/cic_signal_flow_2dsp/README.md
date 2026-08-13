# 16倍CIC等效信流图

- `cic-hold16-signal-flow.pdf`：矢量PDF，适合LaTeX或印刷归档。
- `cic-hold16-signal-flow.svg`：字体已转换为矢量轮廓，推荐插入Word/WPS。
- `cic-hold16-signal-flow.png`：600 dpi白底预览与兼容版本。
- 可编辑TikZ源文件位于 `../../source/cic_signal_flow_2dsp/cic-hold16-signal-flow.tex`。

建议图题：**16倍三级CIC的等效二阶差分—保持—二阶积分定点信流图**。

该图对应当前268-LUT/2-DSP目标实现配置：CIC内部采用0-DSP映射，二阶差分器、两级积分器均由Fabric/CARRY实现；整机2个DSP48E1用于前三级FIR。实线表示样值数据，虚线表示事件使能，点线表示物理资源复用关系。
