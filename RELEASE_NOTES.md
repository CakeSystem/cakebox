# CakeBox v0.1.9

本版本提供以下平台的 CakeBox 矿场端发布包：

- cakebox-0.1.9-linux-amd64：linux-amd64（x86_64 服务器） 主程序。
- cakebox-sidecar-requirement-0.1.9-linux-amd64.json：linux-amd64（x86_64 服务器） 固化的 sing-box 版本、平台、官方 archive 与 binary SHA-256 契约。
- cakebox-0.1.9-linux-arm64：linux-arm64（aarch64 / ARM64 服务器，如 Armbian） 主程序。
- cakebox-sidecar-requirement-0.1.9-linux-arm64.json：linux-arm64（aarch64 / ARM64 服务器，如 Armbian） 固化的 sing-box 版本、平台、官方 archive 与 binary SHA-256 契约。
- cakebox-0.1.9-windows.exe：Windows x64 主程序。
- cakebox-sidecar-requirement-0.1.9-windows.json：Windows x64 固化的 sing-box 版本、平台、官方 archive 与 binary SHA-256 契约。
Release 资产包含已内置混淆引擎的 CakeBox 二进制文件与 sidecar requirement JSON。混淆开关由 CakeBox 本地后台控制。安装脚本位于仓库根目录 `install.sh`，会自动识别当前主机的 CPU 架构。

## 安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hashultra/cakebox/main/install.sh) install
```

首次安装会随机生成 CakeBox Web 端口、安全访问路径和 Web访问令牌。Web 默认绑定 `0.0.0.0`，方便矿场局域网访问。装好后在浏览器打开安装结果里打印的地址，先设置管理员账号，再在「令牌」页面粘贴 HashCake 签发的隧道加密令牌即可完成接入。

### 国内服务器

无法稳定访问 GitHub 的服务器使用下面的通用管理入口。不带动作启动时进入管理菜单，在菜单中选择安装或更新时会自动查找最新稳定版并按 SHA256SUMS 校验；镜像清单缓存可能滞后，安装器会与 GitHub 清单比对后按更新的版本安装，下载仍优先使用国内镜像：

```bash
CAKEBOX_RELEASE_MIRROR_BASE=https://cdn.jsdmirror.com/gh/hashultra/cakebox@main bash <(curl -fsSL https://cdn.jsdmirror.com/gh/hashultra/cakebox@3ebf55609c495af7e2d9429ee4f3ecabece6d7ef/install.sh)
```

sing-box sidecar 走安装器内置的 GitHub 代理源，并按 CakeBox 二进制内置的 SHA-256 契约逐字节校验；校验不通过即安装失败。

## 配套项目

- HashCake：https://github.com/hashultra/hashcake
