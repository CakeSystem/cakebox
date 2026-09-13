# CakeBox v0.1.4

本版本提供 CakeBox 矿场端 linux-amd64 发布包。

## 文件

- cakebox-0.1.4-linux-amd64：CakeBox linux-amd64 主程序。
- cakebox-noise-0.1.4-linux-amd64：站点混淆/噪声辅助组件。
- cakebox-sidecar-requirement-0.1.4-linux-amd64.json：本次 CakeBox 固化的 sing-box 平台、版本、官方 archive 与 binary SHA-256 契约。

Release 资产包含二进制文件、sidecar requirement JSON，以及已生成的 cakebox-noise 签名升级 manifest。安装脚本位于仓库根目录 `install.sh`。

## 安装

```bash
CAKEBOX_TOKEN='你的隧道加密令牌' bash <(curl -fsSL https://raw.githubusercontent.com/hashultra/cakebox/main/install.sh) install
```

首次安装会随机生成 CakeBox Web 端口、安全访问路径和 Web访问令牌。Web 默认绑定 `0.0.0.0`，方便矿场局域网访问。

## 配套项目

- HashCake：https://github.com/hashultra/hashcake
