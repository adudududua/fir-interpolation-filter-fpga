# DAC24 准确测量与任意波形上传协议

## 1. 适用范围与当前能力边界

本文定义 PC 端分析程序的数值口径、正式频响验收方法，以及新位流中的
PC→FPGA 波形上传协议。它服务于 44.1 kHz/48 kHz 两个输入采样率家族和
4x/8x/128x 三个正式插值节点。

旧抓取位流只从 FPGA 向 UDP 4000 端口广播 4096 点 DAC24 输出帧，输入为
板内固定 ROM。包含上传控制器的新位流增加本文第 7 节 UDP 4001 接收协议、
16384 点双 bank 输入和 16384 点/64 包回传；必须重新生成并下载新 `.bit`，只更新
上位机不能获得这些能力。上位机没有收到 ACK 与匹配 transaction ID 回传之前，
不能声称任意波形经过了实物 FPGA。

## 2. 幅度单位

### 2.1 dBFS

有符号 24 位样本先按峰值满量程 `2^23` 归一化。离散正弦的峰值幅度为
`A_peak` 时：

```text
dBFS = 20 log10(A_peak / 2^23)
```

所以峰值为 `2^23` 的理想正弦是 0 dBFS，峰值为 `2^22` 的正弦是
-6.0206 dBFS。实际正样本最大值只有 `2^23-1`，这是整数表示不对称造成的，
不是测量误差。

FFT 谱线的 dBFS 必须补偿窗的相干增益和单边谱的两倍系数。DC 与 Nyquist
频点不能乘两倍。随机噪声还必须明确标成 `dBFS/bin` 或 `dBFS/Hz`；不能把
噪声谱密度和正弦谱线的 dBFS 混用。

### 2.2 dBc

dBc 表示某个镜像、谐波或杂散相对主载波的幅度：

```text
spur_dBc = spur_dBFS - carrier_dBFS
```

例如主音为 -10 dBFS、镜像为 -85 dBFS，则镜像为 -75 dBc。dBc 适合
单音演示，但它不是完整滤波器频率响应。

### 2.3 传递函数 H(f)

一般输入输出测量使用：

```text
H(f) = Y(f) / U(f)
gain_dB = 20 log10(|H(f)|)
```

其中 `U` 是与输出采样率相同的零插值输入，而不是直接把低采样率 `X` 和
高采样率 `Y` 的 FFT 数组逐点相除。只允许在 `|U|` 高于有效阈值的频点求商。
随机激励宜使用互谱估计 `H1 = S_yu/S_uu` 并同时报告相干度。

对插值倍率 `L` 的冲激，若低速输入冲激幅度为 `A`，正式归一化定义为：

```text
H_norm(f) = FFT{y[n]} / (A L)
```

这样理想通带位于 0 dB。频响图的纵轴应标为“增益 (dB)”或 `|H(f)| (dB)`，
不能标成 dBFS。

## 3. 单帧 Hann FFT 仅作为预览

旧位流的单帧输出长度为 4096；下表给出旧帧在各模式下的记录时长和频率间隔：

| 输入家族 | 节点 | 输出采样率 | 记录时长 | FFT 间隔 |
|---|---:|---:|---:|---:|
| 44.1 kHz | 4x | 176.4 kHz | 23.220 ms | 43.066 Hz |
| 44.1 kHz | 8x | 352.8 kHz | 11.610 ms | 86.133 Hz |
| 44.1 kHz | 128x | 5.6448 MHz | 0.726 ms | 1378.125 Hz |
| 48 kHz | 4x | 192 kHz | 21.333 ms | 46.875 Hz |
| 48 kHz | 8x | 384 kHz | 10.667 ms | 93.750 Hz |
| 48 kHz | 128x | 6.144 MHz | 0.667 ms | 1500.000 Hz |

因此 128x 下 10 Hz～20 kHz 通带只有约 14 个 FFT 栅格，10 Hz 下边界完全
无法解析。当前 Hann 预览也会受非相干采样、主瓣宽度和旁瓣影响，不能证明
±0.05 dB 通带或 70 dB 阻带。

抓取模块在发送一帧 UDP 数据期间暂停采集，相邻帧之间存在缺口；
不能把多个 `.npy` 文件直接拼成连续长记录。零填充只插值已有频谱，不会恢复
缺失信息或提高真实分辨率。

## 4. 正式完整冲激响应测试

### 4.1 激励、捕获与窗函数

- 输入使用一个幅度 `A = 2^22` 的 24 位正冲激，其余输入为零。
- 切换家族或模式后必须复位数据通路，并以事务 ID 和输出样本索引对齐冲激起点。
- 已签核 RTL 的非零冲激支撑长度约为：4x 225 点、8x 459 点、128x 7406 点。
- 最小完整捕获长度分别为：4x 512、8x 1024、128x 8192 个输出点。
- 推荐正式程序统一捕获 16384 点，并确认冲激最后至少连续 16 点归零；若没有归零
  则判为“捕获不完整”，不得计算 PASS。16 点只是检测截断的最小哨兵长度，不是
  对滤波器支撑长度的替代。
- 对完整、有限长且尾部归零的冲激响应**不加窗**。Hann、Blackman-Harris 等窗会
  改变被测系统本身的传递函数，不能用于此项验收。
- FFT 统一零填充到 `NFFT = 2^20`。必要时可在最差阻带峰附近用直接 DTFT/CZT
  加密搜索，但不能用零填充冒充更长实测记录。

旧 128x 的 4096 点 BRAM 装不下完整冲激响应。新位流的 16384 点帧可以容纳已签核
响应，但仍必须检查 transaction ID、连续索引和最后 16 点归零；有缺口的跨帧拼接不能替代它。

### 4.2 验收频段

对输入采样率 `Fs_in`、输出采样率 `Fs_out=L*Fs_in`：

- 通带：10 Hz～20 kHz；
- 过渡带：20 kHz～`Fs_in-20 kHz`；
- 阻带：`Fs_in-20 kHz`～`Fs_out/2`。

所以 44.1 kHz 家族的阻带起点为 24.1 kHz，48 kHz 家族为 28 kHz。
过渡带不参与通带和阻带极值判定。

### 4.3 必须输出的指标

令 `G(f)=20log10(|H_norm(f)|)`：

- `passband_max_db = max(G)`；
- `passband_min_db = min(G)`；
- `passband_max_abs_db = max(|G|)`；
- `passband_pp_db = passband_max_db-passband_min_db`；
- `stopband_attenuation_db = -max(G in stopband)`；
- 最差阻带峰的频率；
- DC 增益、最佳拟合群延迟和通带相位残差；
- 冲激支撑区的逐点对称误差。

频率指标 PASS 当且仅当：

```text
捕获完整
AND passband_max_abs_db <= 0.05 dB
AND stopband_attenuation_db >= 70 dB
```

正式六工况总 PASS 要求 44.1/48 kHz × 4x/8x/128x 全部通过。边界频率应包含
在对应频带内。若频带没有任何 FFT 栅格、归一化分母为零、存在 NaN/Inf、样本
丢失或顺序不连续，必须报测量无效，不能以 PASS 代替。

建议额外门限与现有签核保持一致：绝对 DC 增益误差不超过 0.01 dB、相对 4x
模式增益差不超过 0.01 dB、冲激对称误差为 0 LSB、通带线性相位残差小于
`1e-9 rad`。这些附加项应单列，不得隐含改变赛题的 ±0.05/70 dB 主门限。

## 5. 单音、多音和噪声测试

- 已知单音优先使用相干采样，或在指定频率上做正弦最小二乘/Goertzel；不能只取
  最近 FFT 栅格。预览窗使用 Hann 时必须补偿相干增益。
- 需要观察约 -70 dBc 的弱镜像时可用四项 Blackman-Harris 窗，并同时报告主音
  和镜像的 dBFS 以及相对 dBc。
- 多音必须选相干频点并控制峰均比；它只在有激励的频点估计 H，不能自动填补
  整个通带。
- 噪声测试使用 Welch 平均，建议每段 8192 或 16384 点、50% 重叠且至少八次
  平均，并显示相干度。
- 10 Hz 单音若观察 20 个周期需要约 2 s。128x 原始数据量很大，扫频宜在 FPGA
  端做锁相累加/Goertzel，只回传复数幅相。扫频适合作交叉检查，不替代完整冲激。

## 6. Bit-true 测试

PC 和 FPGA 必须使用同一份量化 24 位输入、采样率、倍率、复位起点和事务 ID。
按输出样本索引对齐后报告：

```text
mismatch_count == 0
max_abs_error_lsb == 0
```

建议覆盖冲激、固定种子随机向量、正/负满量程边界、997 Hz/-1 dBFS 单音和模式
切换。Bit-true 证明板上实现与已验收定点模型逐样本一致；完整冲激 H(f) 证明
频响指标，二者职责不同。

## 7. 建议的 PC→FPGA UDP 4001 V1 协议

本节是与上传 RTL 对齐的接口；只在重新生成并下载新位流后可用。所有多字节整数均为
小端。每个数据报使用固定 32 字节头：

| 偏移 | 长度 | 字段 | 说明 |
|---:|---:|---|---|
| 0 | 4 | `magic` | ASCII `DACU` |
| 4 | 1 | `version` | 固定 1 |
| 5 | 1 | `msg_type` | CONTROL=0x01，WAVE=0x02，COMMIT=0x03，ACK=0x81，STATUS=0x82 |
| 6 | 1 | `flags` | 见下文 |
| 7 | 1 | `header_bytes` | 固定 32 |
| 8 | 4 | `transaction_id` | 上传事务编号 |
| 12 | 4 | `sequence` | 包序号，从 0 连续递增 |
| 16 | 4 | `total_samples` | 本事务输入总样本数 |
| 20 | 4 | `sample_offset` | WAVE 首样本偏移；ACK 时复用为 `next_offset` |
| 24 | 2 | `sample_count` | WAVE 有效样本数；ACK 时复用为 `status_code` |
| 26 | 1 | `sample_bits` | 固定 24 |
| 27 | 1 | `sample_format` | 固定 1，signed little-endian |
| 28 | 4 | `payload_crc32` | 仅覆盖 payload；空 payload 的 CRC32 为 0 |

头部没有保留字节。`payload_crc32` 固定在偏移 28，不能把它放到第 32 字节之后。
CRC 使用 IEEE/ZIP CRC-32：反射多项式 `0xEDB88320`、初值 `0xFFFFFFFF`、最终
异或 `0xFFFFFFFF`；字符串 `123456789` 的校验值应为 `0xCBF43926`。校验值本身
按 u32LE 写入头部。这与 Python `zlib.crc32(payload) & 0xffffffff` 一致。

### 7.1 标志与 CONTROL body

`flags` 低四位依次为：

- bit0 `ACK_REQUIRED`；
- bit1 `LOOP`；
- bit2 `RESET_PIPELINE`；
- bit3 `ONE_SHOT`。

CONTROL 头后跟固定 8 字节 body：

| 偏移（相对 body） | 长度 | 字段 | 编码 |
|---:|---:|---|---|
| 0 | 1 | `opcode` | BEGIN=1，ABORT=2，STOP=3，QUERY=4 |
| 1 | 1 | `family` | 0=44.1 kHz，1=48 kHz |
| 2 | 1 | `mode` | 0=1x，1=4x，2=8x，3=128x |
| 3 | 1 | `source` | 0=板内 ROM，1=上传 RAM |
| 4 | 4 | `repeat_count` | u32LE；0 仅在 LOOP 时表示无限循环 |

BEGIN 的 `transaction_id` 与 `total_samples` 仍取自通用头。保留位和未知 opcode
必须拒绝，不能静默解释。

### 7.2 WAVE、COMMIT 和 ACK

- WAVE payload 最多包含 256 个 `s24le` 样本，即最多 768 字节；
  `sample_count`、`sample_offset` 和 payload 长度必须彼此一致。
- 同一事务的 WAVE 包必须覆盖 `[0,total_samples)`，不能重叠或越界。FPGA 可只接受
  `sample_offset==next_offset` 的顺序上传，简化 RAM 写入和丢包恢复。
- COMMIT 没有 payload。只有总样本数、CRC、连续偏移和存储容量全部通过后才能使
  上传缓冲区变为可播放状态；`RESET_PIPELINE` 应在正式开始播放前建立确定起点。
- ACK 必须引用原 `transaction_id` 和 `sequence`；偏移 20 的 `next_offset` 表示
  FPGA 下一次期望的样本偏移，偏移 24 的 `status_code` 表示结果。
- 当前 RTL 状态码：0 OK，1 PROTOCOL_ERROR，2 NO_TRANSACTION，
  3 TRANSACTION_ID，4 SEQUENCE，5 OFFSET，6 RANGE，7 INCOMPLETE，8 CONTROL。
- PC 超时后重发完全相同的事务 ID/序号/偏移；FPGA 对重复的已提交包应返回相同
  ACK，不得重复写入或重复启动。ABORT、STOP 和 QUERY 应请求 ACK。

推荐命令顺序：

```text
CONTROL BEGIN(UPLOAD, ACK_REQUIRED)
WAVE seq=0 offset=0
WAVE seq=1 offset=256
...
COMMIT seq=N offset=total_samples (ACK_REQUIRED, RESET_PIPELINE, ONE_SHOT 或 LOOP)
等待 ACK/STATUS 后开始接收 UDP 4000 DAC24 输出帧
```

其中 `N` 为 WAVE 包数，因此实际序列固定为 BEGIN `seq=0`、WAVE
`seq=0..N-1`、COMMIT `seq=N`。

PC 应保存输入向量、事务 ID、各 ACK、输出起始样本索引、采样率和倍率，确保
任意输入分析以及 bit-true 对齐可复现。
