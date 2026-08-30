# 百兆网络板级验证工程清理说明

## 1. 工程定位

本目录是赛题的 **Vivado 2025.2 百兆网络板级验证与现场演示工程**，不是只含滤波器核心的精简工程。

- 目标器件：`XC7A35T-FGG484-2`
- 工程文件：`XC7A35T_interp.xpr`
- 综合顶层：`board_demo_competition_dac8_top`
- 默认 RTL 仿真顶层：`tb_phase7_full_chain_bittrue`
- 正式约束：`XC7A35T_interp.srcs/constrs_1/new/board_demo_competition_dac8_top.xdc`
- 插值器定点字长：Stage1/Stage2/Stage3 = `24/20/20 bit`
- CIC 积分器配置：`CIC_INTEGRATOR_DSP_MODE=2`

本工程完整保留以下板级功能：

1. 固定 100BASE-TX RGMII 收发与约 2 ns TXC 相移；
2. ARP 应答，FPGA 固定地址 `02:35:24:00:00:01 / 192.168.1.10`；
3. PC→FPGA UDP 4001：BEGIN/WAVE/COMMIT、CRC32、重传与逐包 ACK；
4. 两组 16384×24 位上传 RAM及原子切换；
5. FPGA→PC UDP 4000：DAC 截位前 24 位节点的 16384 点、64 包抓取；
6. PySide6 上位机、任意波形上传、一键正式冲激频响和证据归档；
7. 板内 ROM 输入、44.1/48 kHz 采样率族以及 1×/4×/8×/128×输出模式。

## 2. 清理结果

清理前目录约有 **5162 个文件、1284.44 MB**，包含多代实验 RTL、Vivado 运行目录、仿真快照、临时日志和重复网络报告。

清理后目录约有 **187 个文件、19.38 MB**，保留：

- 57 个滤波器核心、板级顶层及必要仿真 Verilog 文件；
- 15 个正式网络 RTL 与 17 个网络专项/整链测试平台；
- 当前 XDC、黄金向量、Vivado 2025.2 构建与审计脚本；
- 上位机、测试、协议文档和 MATLAB/RTL 参考数据；
- 已签核的网络位流、布局布线 DCP、时序/CDC/资源/DRC 报告。

历史内容未永久删除，已整体移至可恢复备份：

`D:/FpgaProject/XilinxProject/XC7A35T/fir_interpolation/submit/finally/_cleanup_backup_XC7A35T_interp_LUTmin_df_20260816`

其中从纯核心模板临时带入、容易误导资源口径的 218-LUT `deliverables` 已移到备份下的
`_introduced_core_only_artifacts`；本次验证产生的 `.Xil`、cache、Vivado 日志等已移到
`_post_validation_generated_cache`。

## 3. 正式位流

现场演示可直接下载：

`network_capture/results/implementation/board_network.bit`

- Vivado：2025.2，SW Build 6299465
- 生成时间：2026-08-14 23:55:13
- 大小：2,192,155 字节
- SHA-256：`09920C71C64536EAD2C22B7F7687F387E5F03F748D06457F765281A86F54C5B1`
- WNS/WHS：`+0.185 ns / +0.047 ns`
- 完整网络构建资源：3091 LUT、3962 FF、39.5 BRAM Tile、4 DSP

身份、修复内容和签核数据见：

`network_capture/results/implementation/BUILD_INFO.md`

注意：上述资源是“插值器 + 百兆网络测量系统”的完整板级资源，不是独立滤波器核心 OOC 资源。

## 4. 工程自包含检查

- XPR 文件引用：73
- 缺失引用：0
- 工程外引用：0
- 已登记网络 RTL：15/15
- 综合顶层与仿真顶层已正确设置
- 项目内 `.v` 文件：89

因此工程可从当前目录直接用 Vivado 2025.2 打开，不依赖清理前目录中的 RTL。

## 5. 验证结果

### 5.1 网络整链

Vivado 2025.2 仿真通过：

`NETWORK_UPLOAD_END_TO_END_PASS: uploaded capture starts at index zero`

覆盖 RGMII 前导码/SFD、ARP、UDP 4001、DACU 重传、COMMIT、ACK、上传 RAM 播放以及 16384 点回传采集。

### 5.2 滤波器逐位对拍

全链冲激与固定随机向量的 4×/8×/128×节点均通过：

`PHASE7 FULL CHAIN BITTRUE PASS: impulse + 1 seeds, reset-zero prefixes and all nodes 0 LSB.`

### 5.3 上位机

- 上位机、GUI、网络路由与归档测试：50/50 通过；
- 正式测量参考算法：12/12 通过；
- 合计：62 项 Python 测试通过。

## 6. 推荐使用入口

1. 打开 `XC7A35T_interp.xpr` 查看或重新实现；
2. 现场演示优先下载已经签核的 `network_capture/results/implementation/board_network.bit`；
3. 按 `network_capture/README.md` 配置有线网卡为 `192.168.1.20/24`；
4. 在 VS Code 中选择“DAC24 板级测量 GUI”配置启动上位机；
5. 使用“一键正式冲激测量”或“波形源/上传”完成上传、ACK 和回传验证。

本工程的网络抓取证明的是 **FPGA 内部、DAC 截位前的 24 位数字节点**。AD9708、模拟重构滤波器和功放链路仍应使用示波器或频谱仪单独验证。
