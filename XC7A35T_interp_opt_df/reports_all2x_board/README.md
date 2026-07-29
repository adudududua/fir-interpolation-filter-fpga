# 全 2x 板级版本说明

## 1. 当前版本

当前板级工程固定使用 44.1 kHz 采样率家族：

```text
20 MHz 板载时钟
    -> clk_wiz_audio_44k1
    -> 5.6448 MHz 音频时钟
    -> 2x × 2x × 2x × 2x × 2x × 2x × 2x
    -> AD9708
```

48 kHz Clock Wizard 已从工程文件集和运行项中移除。原 IP 文件仍保留在磁盘，当前设计不会实例化或综合它。

## 2. 下载文件

使用 Vivado Hardware Manager 下载：

```text
board_demo_competition_dac8_top_all2x.bit
```

## 3. 上电和按键

上电默认进入 128x 模式，理论 `DA_CLK` 为 `5.6448 MHz`。

| 按键 | 输出节点 | DA_CLK |
|---|---:|---:|
| SW1 或 SW5 | 4x | 176.4 kHz |
| SW2 或 SW6 | 8x | 352.8 kHz |
| SW3、SW4、SW7 或 SW8 | 128x | 5.6448 MHz |

蜂鸣器控制固定为高电平，正常情况下上电不响。

## 4. MATLAB 与 RTL 验证

| 项目 | 结果 |
|---|---:|
| 通带最大绝对误差 | 0.00729793 dB |
| 阻带衰减 | 77.67936345 dB |
| 冲激 RTL 对拍 | 0 LSB |
| 随机 PCM RTL 对拍 | 0 LSB |

## 5. 布局布线结果

| 项目 | 结果 |
|---|---:|
| LUT | 6426 / 20800，30.89% |
| FF | 4416 / 41600，10.62% |
| DSP | 1 / 90，1.11% |
| BRAM | 0 |
| WNS | +44.635 ns |
| TNS | 0 ns |
| WHS | +0.093 ns |
| THS | 0 ns |
| 估算总功耗 | 0.168 W |

功耗采用无仿真活动文件的向量无关估算，置信度为 Low，只适合作为初步参考。

## 6. DRC 说明

bitstream 生成前 DRC 为 `0 Error / 4 Warning`。四条 Warning 均为 Stage 1 单 DSP MAC 未使用 DSP 内部输入或输出流水寄存器的性能建议。当前 5.6448 MHz 音频域 post-route setup 余量为 `+77.167 ns`，不影响本版本时序通过。
