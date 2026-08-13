# 算子信流图QA记录

检查日期：2026-08-14

- 四个TikZ源均由XeLaTeX编译成功；每图均输出PDF、轮廓化SVG及600 dpi PNG；合并PDF为4页。
- 图形语言采用黑白`Σ`、乘法器、`z^-1`、MUX、寄存器与反馈回路，不再以大模块框作为主体。
- CIC算法图的两级差分、Hold16、两级积分、位宽及事件率与正式RTL等价结构一致。
- CIC实现图明确显示$R_{op}$差分结果反馈、$R_{d1}\rightarrow R_{d0}$历史轮换、同一23-bit CARRY减法器两拍复用、独立保持寄存器和26/29-bit积分反馈；图中不存在正式RTL未使用的历史MUX。
- Stage1图采用数学中心延时`z^-26`；同时注明RTL索引25的跨事件寄存器对齐；52项为单DSP时间展开。
- Stage2/Stage3图经版面重排后采用“上层任务调度与双RAM并行读取、下层单DSP水平数据通路”的两层布局；仲裁、任务寄存器、地址生成、RAM同步读寄存器和结果DEMUX之间均保留明确净距。
- Stage2/Stage3图显示pending优先级、$R_{job}\{stage,\phi,head,i,full\}$、Stage3模式事件锁存、同步历史/系数RAM读取、共享DSP的$M/P/C\rightarrow ALU\rightarrow PREG$反馈，以及DSP内ROUND/CLAMP和20/21-bit结果分配。
- Stage2/Stage3图完整标注$hist\_valid=full\lor(i<fill)$与$CEP=(MAC\land hist\_valid)\lor ROUND\lor(CLAMP\land overflow)$，避免将启动期无效历史抽头、无条件ROUND写回和条件CLAMP写回混为同一使能语义。
- Stage2/Stage3最终图自然宽约161 mm，按16 cm论文版心插入时缩放系数约0.994；最小辅助字号约8 pt，未发现文字遮挡、节点重叠、箭头反向或边缘裁切。
- Stage2/Stage3局部复核进一步将模式锁存接入系数地址选择，将PATDET检测线改为由PREG高位正交引入，分离求和器的P/C反馈端口，并独立布置`R_job.stage`到结果DEMUX的控制箭头；OPMODE三态明确为`M+P`、`P+C+carry`或`C`。
- 技术内容已按当前268-LUT/2-DSP RTL逐项复核；四图缩入16 cm论文版心后的文字与连线另行完成视觉检查。
- 中间编译文件仅保存在`images/work/thesis_signal_flow_diagrams/build`，工程主目录未生成LaTeX临时文件。
