# CakeBox v0.1.10

本版本提供以下平台的 CakeBox 矿场端发布包：

- cakebox-0.1.10-linux-amd64：linux-amd64（x86_64 服务器） 主程序。
- cakebox-sidecar-requirement-0.1.10-linux-amd64.json：linux-amd64（x86_64 服务器） 固化的 sing-box 版本、平台、官方 archive 与 binary SHA-256 契约。
- cakebox-0.1.10-linux-arm64：linux-arm64（aarch64 / ARM64 服务器，如 Armbian） 主程序。
- cakebox-sidecar-requirement-0.1.10-linux-arm64.json：linux-arm64（aarch64 / ARM64 服务器，如 Armbian） 固化的 sing-box 版本、平台、官方 archive 与 binary SHA-256 契约。
- cakebox-0.1.10-windows.exe：Windows x64 主程序。
- cakebox-sidecar-requirement-0.1.10-windows.json：Windows x64 固化的 sing-box 版本、平台、官方 archive 与 binary SHA-256 契约。
Release 资产包含已内置混淆引擎的 CakeBox 二进制文件与 sidecar requirement JSON。混淆开关由 CakeBox 本地后台控制。安装脚本位于仓库根目录 `install.sh`，会自动识别当前主机的 CPU 架构。

## 安装

### Windows（单文件，双击即用）

只需一个 `cakebox-0.1.10-windows.exe`，**不需要**另外下载或放置 sing-box。

1. 把 `cakebox-0.1.10-windows.exe` 放到任意**可写**目录（例如 `D:\CakeBox`）。
2. 双击运行，保持窗口打开。首次启动会打印 Web 后台地址和一次性登录令牌。
3. 浏览器打开打印的地址，用一次性令牌设置管理员账号。
4. 在「令牌」页面粘贴 HashCake 签发的隧道加密令牌，CakeBox 会自动释放内置的 sing-box 并连接上游。

内置的 sing-box 会在首次需要时自动解包到程序同目录（文件名 `FactoryTelemetryAgent.exe`）。删掉它不影响使用，下次启动会自动重建；但**目录不可写时启动会失败**，不要放在 `C:\Program Files` 这类需要管理员权限的位置。

内置 sing-box 为 1.13.12，采用 GPL-3.0-or-later 许可，上游项目 https://github.com/SagerNet/sing-box 。

### Linux

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
