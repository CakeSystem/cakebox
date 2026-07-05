# CakeBox

CakeBox 是 HashCake 的矿场端客户端。它部署在矿机所在网络中，接收矿机连接，并通过加密隧道把流量转回中心 HashCake 服务器。

## 配套项目

- HashCake 服务端：https://github.com/CakeSystem/hashcake

## 一键安装

在 Linux amd64 服务器上执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/CakeSystem/cakebox/main/install.sh)
```

安装时可以直接传入 Activation Token：

```bash
CAKEBOX_TOKEN='你的 Activation Token' bash <(curl -fsSL https://raw.githubusercontent.com/CakeSystem/cakebox/main/install.sh) install
```

如果服务器不能使用 `bash <(...)`，也可以分两步：

```bash
curl -fsSL https://raw.githubusercontent.com/CakeSystem/cakebox/main/install.sh -o install-cakebox.sh
sudo CAKEBOX_TOKEN='你的 Activation Token' bash install-cakebox.sh install
```

## Windows 下载

Windows amd64 版本可在 Release 页面下载：

```text
https://github.com/CakeSystem/cakebox/releases/download/v0.1.0/cakebox-0.1.0-windows-amd64.exe
https://github.com/CakeSystem/cakebox/releases/download/v0.1.0/cakebox-noise-0.1.0-windows-amd64.exe
```

## 默认路径

- 安装目录：`/opt/cakebox`
- 状态目录：`/opt/cakebox/state`
- 日志目录：`/opt/cakebox/logs`
- systemd 服务名：`cakebox`
- 本地 Web UI：`127.0.0.1:18080`

## 环境变量

- `CAKEBOX_VERSION=v0.1.0`：安装指定版本，默认从 `linux-amd64/` 文件夹选择最新版本。
- `CAKEBOX_RELEASE_BRANCH=main`：读取发布文件的 Git 分支。
- `CAKEBOX_TOKEN='...'`：安装时写入 Activation Token。
- `CAKEBOX_DOWNLOAD_URL=https://...`：从指定地址下载主程序。

## 发布文件

- `linux-amd64/cakebox-0.1.0-linux-amd64`：Linux amd64 主程序。
- `linux-amd64/cakebox-noise-0.1.0-linux-amd64`：站点混淆/噪声辅助组件。
- `install.sh`：仓库根目录的一键安装和管理脚本。
- Release 资产：只上传二进制文件，例如 `cakebox-0.1.0-linux-amd64` 和 `cakebox-noise-0.1.0-linux-amd64`。
- `SHA256SUMS`：本地发布文件校验和，路径按本地发布目录记录。
