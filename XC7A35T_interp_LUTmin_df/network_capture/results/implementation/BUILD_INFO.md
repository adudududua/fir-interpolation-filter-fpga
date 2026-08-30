# Phase 2 网络测量位流构建记录

## 位流身份

- 文件：`board_network.bit`
- 工具：Vivado 2025.2，SW Build 6299465
- 生成时间：2026-08-14 23:55:13（Asia/Shanghai）
- 文件大小：2,192,155 字节
- SHA-256：`09920C71C64536EAD2C22B7F7687F387E5F03F748D06457F765281A86F54C5B1`
- Vivado 工程默认下载文件
  `XC7A35T_interp.runs/impl_1/board_demo_competition_dac8_top.bit` 已同步为同一
  SHA-256，避免 Hardware Manager 误用 2026-08-14 00:11 的历史位流；历史
  `.bit/.bin` 已可恢复地移至 `backup_before_project_bit_sync_20260814/`；本次
  Methodology waiver 同步前的工程位流另备份在
  `network_capture/results/implementation/backup_before_methodology_waiver_20260814/`；
  本次“首次正式冲激”修复前的位流与报告备份在
  `network_capture/results/implementation/backup_before_first_impulse_fix_20260814/`。
- 器件：XC7A35T-FGG484-2
- 顶层：`board_demo_competition_dac8_top`

## 本位流包含的网络功能

- 固定 100BASE-TX RGMII 收发与约 2 ns TXC 偏移
- ARP 应答，FPGA 地址 `02:35:24:00:00:01 / 192.168.1.10`
- PC → FPGA UDP 4001：DACU BEGIN/WAVE/COMMIT、CRC32、重传与 ACK
- 两组 16384×24 位上传 RAM，原子切换到音频输入
- FPGA → PC UDP 4000：16384 点、64 包 DAC24 输出抓取
- 回传元数据：输入事务 ID、来源、状态、模式、采样率族和分支样本索引
- ROM/任意上传输入选择，以及严格的正式冲激频响证据链
- COMMIT 生效时同步重启抓帧 epoch，保证上传冲激的首帧从输出索引 0 开始
- COMMIT 采用新事务时先将上一事务残留在 `sample_out` 的样本清零，
  防止首次正式冲激叠加一份提前 128 个 128×输出点的旧响应
- 上传 RAM 只替换 1x 输入样本，输出倍率始终由实体 SW1～SW8 决定；
  上传事务不再锁死提交时的 4x/8x/128x 模式

## 布局布线签核

- WNS：`+0.185 ns`，TNS：`0`
- WHS：`+0.047 ns`，THS：`0`
- 所有用户时序约束满足
- Methodology：`TIMING-6/TIMING-7` 已按精确时钟对象审计豁免；最新报告
  `Checks waived: 2`，无 Critical Warning，且未使用会覆盖 bundled-data
  `max-delay/bus-skew` 的全局异步时钟组
- 5 组 bundled-data 总线偏斜约束全部 `MET`
- CDC 专项脚本：`CDC_AUDIT_2025_2_PASS`
- 最终 DCP 审计：`RELEASE_AUDIT_2025_2_PASS`；5 个 RX 采样寄存器均位于
  `ILOGIC/IFF`，RX 最差建立/保持裕量分别为 `+15.572 ns / +17.928 ns`
- DRC：0 Error、0 Critical Warning、0 条 REQP RAM 异步控制告警
- 剩余 Warning：11 条 DPIP-1、1 条 DPOP-1，均为原插值 DSP48 流水性能建议

## 资源

- LUT：3,091 / 20,800（14.86%）
- 寄存器：3,962 / 41,600（9.52%）
- Block RAM Tile：39.5 / 50（79.00%）
- DSP：4 / 90（4.44%）

## 验证结论

- UDP/IP/FCS 解析器单元仿真：`UDP_IPV4_RX_PARSER_PASS`
- 真正 RGMII 前导码 → ARP → UDP上传/重传 → COMMIT → ACK → 精确样本播放：
  `NETWORK_UPLOAD_END_TO_END_PASS`
- 上一事务保留非零样本后立即 COMMIT 新事务的首次冲激回归通过；
  新 epoch 开始前 `sample_out=0`，旧样本不再进入滤波链
- 上位机核心、GUI、网络预检共 46 项测试通过，测量参考算法 12 项测试通过
- GUI 后台线程回调已全部排队到 Qt 主线程；256 个连续 ACK 压力测试通过
- PySide6 离屏窗口、固定冲激门禁和正式 PNG/JSON/TXT 归档通过

本文件记录的是上述 SHA-256 对应位流。重新构建后必须重新计算并更新全部身份信息。
