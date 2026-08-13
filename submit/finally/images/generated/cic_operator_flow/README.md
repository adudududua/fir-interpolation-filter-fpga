# CIC算法级等效信流图

- `cic-operator-flow.pdf`：矢量PDF，适合LaTeX或印刷归档。
- `cic-operator-flow.svg`：字体已转换为矢量轮廓，推荐插入Word/WPS。
- `cic-operator-flow.png`：600 dpi白底预览与兼容版本。
- 可编辑TikZ源文件位于 `../../source/cic_operator_flow/cic-operator-flow.tex`。

建议图题：**16倍三级CIC插值器的算法级等效信流图**。

本图用于说明算法关系：传统三级CIC经多速率恒等变换后，表示为低速二阶差分、16点零阶保持与高速二阶积分。它与`cic_signal_flow_2dsp`目录中的实现级图配套；本图侧重数学算子与速率域，后者侧重RTL位宽、事件使能及物理资源复用。
