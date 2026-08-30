# XC7A35T 百兆网络板级验证演示工程

这是赛题的完整板级演示工程，包含插值滤波器、100BASE-TX RGMII、ARP、UDP 双向通信、任意 24 位波形上传、ACK、DAC 前 24 位数字节点回传和 PySide6 测量上位机。

## 快速开始

1. 将电脑有线网卡设为 `192.168.1.20`、掩码 `255.255.255.0`，网关和 DNS 留空；
2. 用 Vivado 2025.2 下载 `network_capture/results/implementation/board_network.bit`；
3. 在 VS Code 中运行“DAC24 板级测量 GUI”；
4. 确认界面收到 `192.168.1.10` 的 FPGA 包；
5. 使用“一键正式冲激测量”，或在“波形源/上传”页设置正弦、方波、双音、噪声、CSV/WAV 后点击“输入到板卡”。

详细网卡配置、GUI 操作、协议、判据与故障排查见 [network_capture/README.md](network_capture/README.md)。

## 关键文件

- Vivado 工程：`XC7A35T_interp.xpr`
- 板级顶层：`XC7A35T_interp.srcs/sources_1/new/board_demo_competition_dac8_top.v`
- 正式 XDC：`XC7A35T_interp.srcs/constrs_1/new/board_demo_competition_dac8_top.xdc`
- 网络 RTL：`network_capture/rtl/`
- 上位机：`network_capture/host/gui_app.py`
- 正式位流和签核报告：`network_capture/results/implementation/`
- 清理说明：`CLEANUP_MANIFEST.md`
- 注释审计：`VERILOG_COMMENT_AUDIT.md`

## 证据边界

UDP 4000 回传的是 FPGA 内部、AD9708 截位前的 24 位数字样本。它能够验证 RTL 实现、上传事务与数字频响，但不能替代 DAC、模拟滤波器或功放输出端的仪器测量。
