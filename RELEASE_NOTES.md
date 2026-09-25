# CakeBox v0.1.5

本版本提供以下平台的 CakeBox 矿场端发布包：

- cakebox-0.1.5-linux-amd64：linux-amd64（x86_64 服务器） 主程序。
- cakebox-noise-0.1.5-linux-amd64：linux-amd64（x86_64 服务器） 的站点混淆/噪声辅助组件。
- cakebox-sidecar-requirement-0.1.5-linux-amd64.json：linux-amd64（x86_64 服务器） 固化的 sing-box 版本、平台、官方 archive 与 binary SHA-256 契约。
- cakebox-0.1.5-linux-arm64：linux-arm64（aarch64 / ARM64 服务器，如 Armbian） 主程序。
- cakebox-noise-0.1.5-linux-arm64：linux-arm64（aarch64 / ARM64 服务器，如 Armbian） 的站点混淆/噪声辅助组件。
- cakebox-sidecar-requirement-0.1.5-linux-arm64.json：linux-arm64（aarch64 / ARM64 服务器，如 Armbian） 固化的 sing-box 版本、平台、官方 archive 与 binary SHA-256 契约。
Release 资产包含二进制文件、sidecar requirement JSON，以及已生成的 cakebox-noise 签名升级 manifest。安装脚本位于仓库根目录 `install.sh`，会自动识别当前主机的 CPU 架构。

## 安装

```bash
CAKEBOX_TOKEN='你的隧道加密令牌' bash <(curl -fsSL https://raw.githubusercontent.com/hashultra/cakebox/main/install.sh) install
```

首次安装会随机生成 CakeBox Web 端口、安全访问路径和 Web访问令牌。Web 默认绑定 `0.0.0.0`，方便矿场局域网访问。

## 配套项目

- HashCake：https://github.com/hashultra/hashcake
