# CakeBox v0.1.6

- 修复异常矿机连接长期占用接入名额，导致新矿机无法正常接入的问题。
- 改善网络中断、后端切换和旧连接清理后的恢复，减少无效连接残留。
- 连接清理时保留已经收到的矿机响应，避免最后一条回执丢失。

本次提供 Linux AMD64、Linux ARM64 和 Windows x64 的 CakeBox 主程序、配套 cakebox-noise，以及对应的 sing-box 版本与校验信息，继续使用 sing-box 1.13.12。

已安装用户可通过原安装器执行更新；更新前请妥善保存现有站点配置。

Windows 用户可在本次 Release 下载 `cakebox-0.1.6-windows.exe`、`cakebox-noise-0.1.6-windows.exe` 和对应的 sidecar 校验信息。

Windows 版暂不支持运行中自动替换 cakebox-noise；更新该组件时请先停止它，再手动替换为同版本的 Windows 文件。
