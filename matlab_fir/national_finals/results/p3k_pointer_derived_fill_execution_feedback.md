# P3-K 环形指针推导历史填充状态优化执行反馈

## 1. 目标与验收条件

本轮从已签核的 P3-J Packed-ROM 版本 `424 LUT / 431 FF / 169 Slice / 4 DSP / 2 BRAM Tile / 2 MMCM` 出发，目标是在不改变滤波系数、字长、舍入、饱和、输出 valid 时序和板级接口的前提下继续降低 LUT。正式 Go 条件为：

- post-route LUT 小于 424；
- DSP=4、BRAM Tile=2、MMCM=2；
- FF 不增加，WNS/WHS 为正，TNS/THS=0；
- Release 级全链位真、短复位恢复、模式切换、RAMB18 原语、DRC/CDC 和 bitstream 全部通过。

## 2. 首个方案：复位后顺序清零历史 BRAM（No-Go）

首轮尝试用共享 6-bit 地址在复位释放后并行清零 Stage1 的 64 个历史地址和 Stage2/3 的 32 个历史地址，从而删除填充计数与读掩码。结构本身可以只增加 7 个控制 FF，但完整 Smoke 在全链位真处失败：正式 testbench 只保持复位 8 拍，并在释放后立即恢复输入；额外冻结 64 拍会丢失首批样点，使 4x/8x/128x 输出相位整体错位。

该失败说明“板上上电复位持续 65535 拍”不能替代 RTL 的短复位接口契约。若为兼容短复位增加输入 FIFO，新增的 24-bit 数据缓存和控制会抵消 FF/LUT 收益；若只依赖 RAMB18 上电 INIT，则无法覆盖运行中的采样率切换和中途复位。因此该路线在进入综合前撤销，没有降低验证标准。

## 3. 保留方案：由环形指针推导填充深度

最终方案复用已经存在的环形写指针，不清零 BRAM，也不延迟首样点：

1. Stage1 的 `wr_ptr` 从 0 递增。在首次回绕前，它本身就是已写历史深度；历史达到 52 点后只需一个粘滞 `history_full` 标志。原 `fill_count[5:0]` 和 `active_fill_count[5:0]` 两组 6-bit 状态被 1 bit 替代。
2. Stage2/3 的 `stage*_head` 从 0 反向移动。未填满时，`-job_history_head` 就是任务启动时的历史深度；达到各自 9/6 点后使用粘滞满标志。原两组 4-bit live fill 和一组 4-bit job fill 快照被两个 live full bit 与一个 job full bit 替代。
3. `job_history_head` 仍在任务边界快照，因此共享 DSP 执行 MAC 时不会受下一次环形写入影响；未写地址仍由读掩码强制为零，8 拍短复位语义保持不变。

状态位理论净减少 20 bit；Vivado 实际 post-route FF 从 431 降至 418，说明部分旧状态原本已与其他控制合并，但仍得到 13 FF 的真实下降。比较器改为复用指针及其补码，没有增加 DSP、BRAM 或 MMCM。

## 4. RTL 验证

- Smoke 回归：15/15 PASS；关键全链日志已归档为 `vivado_results/p3k_final_412lut_418ff_168slice_4dsp_2bram_pointerfill/rtl_smoke_full_chain_xsim.log`。
- Release 回归：15/15 PASS；CIC、全链、复位恢复和动态切换日志已随正式结果归档。原 `_work` 运行缓存已在归档后删除，避免项目目录累积临时文件。
- Release 全链输入：冲激、10 个固定随机 seed×4096、正/负满量程、997 Hz/−1 dBFS 强信号，共 14 组；4x/8x/128x 全部逐样本 0 LSB。
- 复位恢复：8 个内部状态场景，每个比较 4096 个 128x 输出，全部 PASS；正式 8 拍短复位未放宽。
- 动态模式：10 次倍率切换无 runt/X；RAMB18 历史与系数原语、CDC 1200 次事务及板级控制测试均 PASS。

滤波系数和定点运算未改变，因此六工况指标继承 P3-J 签核值：最差绝对通带偏差 0.007730 dB，最差峰峰纹波 0.006192 dB，最差阻带 72.371 dB，严格线性相位。

## 5. 综合、实现与策略扫描

固定配置为 `AreaOptimized_high / flatten full / resource_sharing on / Stage1 DSP48 preadder / CIC DSP mode 2 / P3 joint Stage3 / 单 BRAM Stage1 / 统一 BRAM Stage2-3`。

| 版本/策略 | Synth LUT/FF | Routed LUT/FF/Slice | DSP | BRAM Tile | MMCM | WNS/WHS | 功耗 |
|---|---:|---:|---:|---:|---:|---:|---:|
| 前一 424-LUT 签核版 | 453/433 | 424/431/169 | 4 | 2 | 2 | +45.042/+0.080 ns | 0.271 W |
| **指针推导，Default** | **449/420** | **412/418/168** | **4** | **2** | **2** | **+45.083/+0.056 ns** | **0.271 W** |
| 指针推导，AddRemap | 同一 DCP | 412/418/168 | 4 | 2 | 2 | +45.083/+0.056 ns | 0.271 W |
| 指针推导，Explore | 同一 DCP | 412/418/168 | 4 | 2 | 2 | +45.083/+0.056 ns | 0.271 W |
| 指针推导，ExploreWithRemap | 同一 DCP | 415/418/169 | 4 | 2 | 2 | +45.387/+0.121 ns | 0.271 W |

Default 相对前版净减 12 LUT、13 FF、1 Slice，DSP/BRAM/MMCM/功耗不变；TNS/THS=0，AD9708 setup/hold 仍为 +76.116/+78.117 ns，route error=0，DRC/CDC 门禁通过。ExploreWithRemap 的时序更松，但多 3 LUT/1 Slice，因此按面积目标选择 Default。

bitstream：`national_finals_dual_rate_4x8x128x_areaopt.bit`；SHA-256：`E7512D603231276CDCED13C5FEA3A7284558B941CF4102FA1E3339CD5F5EF1CF`。

## 6. Git 与回退路线

- 当前分支：`national-finals-p3k-4dsp-pointer-fill`。
- 正式标签：`nf-p3k-final-412lut-418ff-168slice-4dsp-2bram-pointerfill`。
- 前一稳定回退：`nf-p3j-final-424lut-431ff-169slice-4dsp-2bram-packedrom`。

分支、提交和标签均不使用 `codex/` 前缀。当前环境没有物理开发板，因此结论是 MATLAB/RTL/综合/实现/bitstream 工具侧签核通过，仍不能写成全国赛实物板已验证。
