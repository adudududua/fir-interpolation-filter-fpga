# 218-LUT 24/20/20 发布配置

该目录存放 2026-08-11 实板验证成功版本的机器可读发布配置。唯一 MATLAB
配置入口为 `../nf_release_218_config.m`；`nf_release_218_config.json` 由
`publish_release_218_config.m` 生成，不应手工修改。

数值配置 ID 保持为 `NF-P3-STAGE123-24-20-20-CANDIDATE-R1`，以与已签核金标准
manifest 严格一致；物理板发布状态由 `release_status=board-verified`、板测日期和
Git board-pass 标签独立记录。
