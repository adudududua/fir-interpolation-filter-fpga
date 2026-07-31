# Shared FIR MAC v1：No-Go 检查点

## 目标

在保持 48 MHz 主时钟以及 4x/8x/128x 位真接口不变的条件下，让 Stage1、Stage2、Stage3 共用一颗 DSP48E1，以期把 Route 1 的两颗 FIR DSP 降为一颗。

## 结论

该原型是明确的 **No-Go**，不能用于板级候选。Vivado 2018.3 已通过编译与展开，但 XSim 在全链路位真测试中正确捕获 `Shared FIR Stage1 result not ready`。问题不是 FIFO 深度，而是局部硬截止期不可满足。

## 64 拍局部截止期证明

Stage1 在其滤波相位产生任务，并必须在下一个 2x 相位到来前完成，实际只有 64 个主时钟；同一窗口内最低工作量为：

| 64 拍窗口内的工作 | 时钟数 |
|---|---:|
| Stage1：26 MAC + 精确舍入 | 27 |
| Stage2：9-MAC、8-MAC 两相 + 两次舍入 | 19 |
| Stage3：6/5/6/5 MAC 四相 + 四次舍入 | 26 |
| 合计 | **72** |

因此顺序执行至少需要 72 拍，比 64 拍截止期多 8 拍；调度优先级和缓存深度均无法修复。固定 9/9 与 6/6 工作长度会增加到 75 拍，同样不可行。

## 证据与回退路线

- `xvlog`：共享内核及全链包装编译 PASS；
- `xelab`：带 DSP48E1 UNISIM 模型展开 PASS；
- XSim：在全国赛全链路位真测试中捕获真实 Stage1 截止期失败；
- 原型保留在分支 `codex/national-finals-shared-fir-mac-v1`、提交 `354b890`，未混入正式板级路径；
- 正式路线回到 Route 1 的两颗 FIR DSP，并尝试把低速串行 CIC comb 从 DSP48E1 迁到 LUT 进位链。
