# CakeBox v0.1.7

- Linux AMD64、Linux ARM64 与 Windows x64 版本统一采用压缩加密封装，下载体积更小，并在启动时校验文件完整性。
- 主程序与配套 cakebox-noise 同步更新；继续使用 sing-box 1.13.12。
- Windows 版提供自签名 EXE，系统可能提示发布者不受信任，请遵循本机或组织的应用运行策略。

Windows 的 noise 组件仍需手动更新：先停止组件，再替换同版本文件。Linux 用户可通过现有安装器更新。

Linux 加密程序需要支持匿名临时执行文件的磁盘目录；普通 Linux 主机通常可使用默认目录，容器部署需要挂载支持该能力的磁盘卷。
