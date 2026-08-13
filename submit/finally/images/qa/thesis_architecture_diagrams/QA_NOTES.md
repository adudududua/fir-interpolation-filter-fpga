# 论文结构框图图组 QA 记录

检查日期：2026-08-13

## 构建结果

- 六个TikZ源均由XeLaTeX编译成功；
- 每图已生成矢量PDF、轮廓化SVG和600 dpi PNG；
- 合并PDF共6页；
- 六个SVG均不含嵌入位图，也不依赖外部字体文本元素；
- LaTeX日志未发现Undefined control sequence、Package Error、Overfull/Underfull box。

## 内容核对

- 当前2-DSP配置采用完整板级布局布线后口径：268 LUT / 417 FF / 2 DSP48E1 / 4 RAMB18E1 / 2 MMCM；
- 2个DSP分别归属Stage1及Stage2/Stage3共享MAC；CIC mode 0为0 DSP；
- 核心3个RAMB18分别为Stage1历史、Stage2/3统一历史和统一FIR系数；第4个RAMB18为板级测试音ROM；
- 板级图已将`family_sel`请求、MMCM锁定、`family_active`无毛刺选择和音频复位分开表达；`audio_mute`仅作用于下降沿IOB输出寄存器并强制DAC中码128；
- 268版状态统一为“工具验证完成、物理板待验证”；218版和239版仅声明用户确认的物理板功能现象；
- E1--E3明确归属于218-LUT归档的24/20/20数值与位真基线，且E1的0 LSB特指“定点模型与稳定RTL向量”之间的比较；268版通过定向等价与独立RTL复验建立衔接；
- 未将扁平化网表中的LUT/FF人为拆分为模块独立面积；
- 未将数字域频响、OOC资源或用户功能板测外推为模拟仪器级指标。

## 视觉核对

- 已逐图检查标题、模块边界、箭头方向、文字裁切、组框语义和图例；
- 已修复raw旁路、核心与输出MUX重叠、8倍抽头定点边界、主链接口标签压线、验证卡片重叠、测试矩阵行标签和资源分组等问题；
- 最终独立视觉审查结论为PASS ×6；最终技术内容审查结论为PASS，未发现提交阻断项；
- 推荐在A4论文中按通栏宽度使用PDF；若Word对PDF支持不稳定，使用600 dpi PNG；SVG适合后续矢量编辑。

## 复现

构建脚本：`submit/finally/images/work/thesis_architecture_diagrams/build_all.ps1`

所有中间文件仅位于`images/work/thesis_architecture_diagrams/build`，工程根目录未产生LaTeX/Vivado临时文件。
