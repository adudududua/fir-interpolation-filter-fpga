# P3 RTL 架构冻结：模式化 Stage3 吸收独立均衡器

## 目标与基线

基线为 P4-D Release V2：479 LUT / 468 FF / 198 Slice / 4 DSP / 4 RAMB18E1（2 Tile）/ 2 MMCM。P3 的目标是在不增加 DSP、BRAM、MMCM的前提下，删除 `cic3_compensator_shiftadd_ce`，并让 post-route LUT 与 FF 同时低于基线。

本文件冻结第一版 RTL 的结构和 Stop/Go 边界。任何为了综合数字而改变字长、舍入、饱和或模式语义的修改，必须先更新 MATLAB config/golden。

## 已否决的永久补偿 Stage3

为避免模式 bank 和切换逻辑，曾检查是否可以让选中的补偿 Stage3 同时作为正式8x输出。用选中系数

```text
[561, 137, -4232, -1554, 20046, 35584,
 20046, -1554, -4232, 137, 561]
```

重新计算得到：

| 输入采样率 | 8x绝对通带最大误差 | 8x阻带衰减 | DC增益 |
|---:|---:|---:|---:|
| 44.1 kHz | 0.129853936 dB | 77.550717752 dB | -0.006363192 dB |
| 48 kHz | 0.112187676 dB | 77.550717752 dB | -0.006363192 dB |

两种采样率均超过±0.05 dB，故“所有模式永久使用补偿 Stage3”判为 No-Go。正式结构必须保留模式化系数语义。

## 冻结结构

```text
4x/8x mode:
  Stage2 -> flat Stage3 -> official y8

128x mode:
  Stage2 -> compensated Stage3 (signed-21) -> N3 Hold CIC
```

### 系数存储

继续使用 P4-D 的一块统一 `RAMB18E1`：

| 地址 | 内容 | 物理宽度 |
|---:|---|---:|
| 0～23 | Stage2 两相展开系数 | signed-18（原signed-16符号扩展） |
| 32～52 | flat Stage3 两相展开系数 | signed-18（原signed-16符号扩展） |
| 64～89 | Stage1 系数，Port A | signed-16 |
| 96～101 | compensated Stage3 phase0 | signed-18 |
| 112～116 | compensated Stage3 phase1 | signed-18 |

RAMB18 的主数据位保存低16位，parity 位保存高2位。中心系数35584因此不再被错误截成signed-16，也不新增 LUTROM 或 BRAM。

### 模式原子性

`stage3_compensated_mode` 在 Stage3 CE 事件进入 pending 时快照，在整个 MAC job 内保持不变。系数预取使用 pending/job 的快照位，不能直接读取会变化的板级 mode bus。

板级正式链只有一个 Stage3实例，模式来自音频域已经原子提交的 `mode_state==MODE_128X`。验证环境使用两个仅仿真的独立实例：flat实例提供4x/8x检查，compensated实例提供128x检查；这不会进入板级综合资源。

### 定点边界

- Stage3输入/历史：signed-20；
- Stage3系数：Q15/signed-18；
- Stage3 MAC：signed-38；
- Stage3补偿输出：signed-21；
- CIC输入：signed-21；
- CIC最终输出：signed-20并左移4位恢复24-bit PCM标度。

flat Stage3结果仍必须落在signed-20范围；正式8x调试输出取signed-21结果的低20位并左移4位，同时用仿真断言检查第20位是符号扩展。

### 资源和验收门槛

第一版不做实现策略扫描，先证明结构正确：

- 新config ID和golden；
- flat 4x/8x、compensated 128x逐样本0 LSB；
- 系数RAM全部128地址和primitive parity位通过；
- Stage3强信号无signed-21饱和；
- reset、stall和动态模式切换无X、无pending overwrite；
- Release回归全部通过。

进入默认候选的 post-route 门槛：LUT<479且FF<468，DSP=4，RAMB18=4，MMCM=2，WNS>0，WHS>=0.05 ns，DAC setup/hold各>=70 ns。若只减少一种资源或增加专用资源，则只保留为实验分支。
