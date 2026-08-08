# 276-LUT 板测后优化审计与执行反馈

日期：2026-08-08

正式基线提交：`aecc2b3`

正式标签：`nf-vivado2025.2-276lut-379ff-4dsp-2bram-17io-2mmcm-board-pass`

正式分支：`national-finals-v2025.2-4dsp-2bram-lut-opt`

后续试验分支：`national-finals-v2025.2-post276-lut-optimization`

## 1. 正式基线状态

用户已经完成 276-LUT bitstream 的物理板验证：44.1 kHz/48 kHz 两个输入采样率族下，
各公开插值档位的输出采样率均正确，DAC 输出波形均正常。因此该版本由工具签核候选升级为
正式实板通过版本，后续试验不得覆盖或改写该提交与标签。

| 阶段 | LUT | LUTRAM | FF | DSP | RAMB18E1 | BRAM Tile |
|---|---:|---:|---:|---:|---:|---:|
| 综合 | 341 | 0 | 387 | 4 | 4 | 2 |
| 布局布线 | **276** | **0** | **379** | **4** | **4** | **2** |

正式实现的 WNS/TNS 为 `+44.885/0 ns`，WHS/THS 为 `+0.112/0 ns`，DRC Error 为 0；
总/动态/静态功耗为 `0.271/0.199/0.072 W`。bitstream SHA-256 为
`1A6CDA833627AA197AB111EB426E6CA70405E69D657B3528C3B6D9CF1A0BCB2F`。

## 2. Routed DCP 深度审计

从正式 routed DCP 重新提取叶级资源后，确认 4 个 DSP48E1 分别承担 Stage1、共享
Stage2/3、CIC 首级积分器和 CIC 末级积分器；4 个 RAMB18E1 分别用于音频 ROM、Stage1
历史、Stage2/3 统一历史和统一系数存储。主要 Fabric 控制热点仍集中在 Stage1 串行调度、
Stage2/3 valid/pending 状态以及 CIC comb 串行活动控制。

工程采用 `flatten_hierarchy=full`，所以普通层次利用率报告只能看到顶层。叶原语审计中出现的
约 418 个逻辑 LUT 方程不是最终物理 LUT 数；Vivado 会通过 LUT6_2 双输出、跨层级逻辑合并、
常量传播和物理优化，把它们装入 276 个物理 LUT。资源表应以 routed utilization 的 276 LUT
为准，不能把叶级逻辑方程数量当成器件占用量。

## 3. RTL 候选：历史有效位粘滞化

### 思路

尝试把 Stage2/3 每次任务启动时的历史有效比较器改为粘滞有效状态：利用
`history_read_head + hist_index == 4'hF` 判断历史窗口首次填满，之后保持有效，希望删除任务
启动路径上的比较逻辑，同时维持 DSP PREG CE 门控的算术语义。

### 验证与结果

- Vivado 2025.2 RTL Smoke 回归：**17/17 PASS**；
- 全链冲激和随机输入的 4x/8x/128x 节点保持 0 LSB，复位、动态切档、ROM、DAC、BRAM、
  CDC、按键和双时钟族用例均通过；
- 回归目录：`matlab_fir/national_finals/_work/rtl_regression/20260808_140117`；
- 综合结果：**345 LUT / 388 FF / 4 DSP / 4 RAMB18E1**；
- 同一脚本重新综合正式 R5 基线为 **341 LUT / 387 FF / 4 DSP / 4 RAMB18E1**。

候选增加 4 LUT 和 1 FF，未进入实现，判定 **No-Go**。根因是新增粘滞状态及加法/终点译码
并未被工具合并，代价超过被替代的启动比较器。候选修改已完整回退，正式 RTL 仍与
`aecc2b3` 的板测版本一致。

## 4. 同一综合 DCP 的实现策略扫描

所有组合都从重新复现的同一份 `341 LUT / 387 FF` 综合 DCP 启动，避免把不同源码、缓存或
旧 run 混在一起比较。

| `opt_design` | `place_design` | Routed LUT | FF | WNS | WHS | DRC |
|---|---|---:|---:|---:|---:|---:|
| ExploreArea | Explore | **276** | 379 | +44.885 ns | +0.112 ns | 0 |
| AddRemap | Explore | 282 | 381 | +44.481 ns | +0.112 ns | 0 |
| Default | Explore | 282 | 381 | +44.481 ns | +0.112 ns | 0 |
| ExploreWithRemap | Explore | 282 | 379 | +44.555 ns | +0.112 ns | 0 |
| ExploreArea | ExtraPostPlacementOpt | **276** | 379 | +44.885 ns | +0.112 ns | 0 |
| ExploreArea | ExtraTimingOpt | **276** | 379 | +44.820 ns | +0.107 ns | 0 |
| ExploreArea | Default | **276** | 379 | +44.885 ns | +0.112 ns | 0 |

`ExploreArea + Explore` 已处在这份网表的实现策略最低点。其余能达到 276 LUT 的组合只是同一
物理结果，不能作为新的优化版本；另外三组反而增加到 282 LUT。因此本轮没有生成或发布新的
bitstream。

## 5. 结论和下一步边界

本轮没有找到低于 276 LUT 且保持 4 DSP、2 BRAM Tile、完整功能和安全时序的结果。正式推荐
继续使用已板测的 R5 版本，而不是为了个位数 LUT 使用尚未板测或资源退化的候选。

仍可继续试验的方向按风险排序如下：

1. 把 CIC `comb_active` 合并进阶段索引的空闲哨兵，理论上只可能节省约 0~1 LUT/FF，且译码
   逻辑可能抵消收益；必须先跑 17/17 回归再综合。
2. 重编码 Stage2/3 调度与 pending 状态。潜在收益略高，但早期 compact-state 候选曾使综合
   LUT 上升，且容易破坏输入到达、历史地址和 DSP 启停边界，风险较高。
3. 若希望出现明显下降，需要重新划分存储/控制架构或重新打包 BRAM；这属于较大结构改动。
   在明确保持 4 DSP 和 2 BRAM Tile 的限制下，收益没有保证，验证成本也显著高于当前微调。

## 6. 发布与工作区说明

审计脚本、DCP、策略扫描日志和回归生成物均放在被 Git 忽略的
`matlab_fir/national_finals/_work/post276_audit` 或 `_work/rtl_regression` 下，没有在仓库主目录
产生 `.Xil`、`vivado*.log/.jou`、`xsim.dir` 等临时文件。正式提交和标签已经在本地建立；本轮
推送曾分别通过代理和直连重试，但热点到 GitHub 的 TLS/443 连接失败或超时，不是仓库权限、
认证或 RTL 问题，待网络通路恢复后继续推送即可。
