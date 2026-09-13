# CakeBox

CakeBox 是 HashCake 的矿场端客户端。它部署在矿机所在网络中，接收矿机连接，并通过加密隧道把流量转回中心 HashCake 服务器。

## 配套项目

- HashCake 服务端：https://github.com/hashultra/hashcake

## 首次安装

在 Linux amd64 服务器上执行：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hashultra/cakebox/main/install.sh) install
```

安装时可以直接传入隧道加密令牌：

```bash
CAKEBOX_TOKEN='你的隧道加密令牌' bash <(curl -fsSL https://raw.githubusercontent.com/hashultra/cakebox/main/install.sh) install
```

如果服务器不能使用 `bash <(...)`，也可以分两步：

```bash
curl -fsSL https://raw.githubusercontent.com/hashultra/cakebox/main/install.sh -o install-cakebox.sh
sudo CAKEBOX_TOKEN='你的隧道加密令牌' bash install-cakebox.sh install
```

## 更新程序

```bash
sudo bash install-cakebox.sh update
```

更新会保留已有 Web 端口、安全访问路径、Web访问令牌、隧道加密令牌和状态目录。

## 隧道加密令牌

首次安装后如果还没有写入令牌：

```bash
sudo CAKEBOX_TOKEN='你的隧道加密令牌' bash install-cakebox.sh install-token
```

替换已有令牌需要单独执行：

```bash
sudo CONFIRM_REPLACE_TOKEN=yes CAKEBOX_TOKEN='新的隧道加密令牌' bash install-cakebox.sh replace-token
```

## Windows 下载

Windows amd64 版本可在 Release 页面下载：

```text
https://github.com/hashultra/cakebox/releases/download/v0.1.4/cakebox-0.1.4-windows.exe
https://github.com/hashultra/cakebox/releases/download/v0.1.4/cakebox-noise-0.1.4-windows.exe
```

## 默认路径

- 安装目录：`/opt/cakebox`
- 状态目录：`/opt/cakebox/state`
- 日志目录：`/opt/cakebox/logs`
- systemd 服务名：`cakebox`
- Web UI：首次安装时在 `10000-60000` 内随机生成，默认绑定 `0.0.0.0`
- 安全访问路径：首次安装时随机生成，例如 `/cb-x7p4d2q8/`
- Web访问令牌：保存于 `/opt/cakebox/state/web-token`

## 环境变量

- `CAKEBOX_VERSION=v0.1.0`：安装指定版本，默认从 `linux-amd64/` 文件夹选择最新版本。
- `CAKEBOX_RELEASE_BRANCH=main`：读取发布文件的 Git 分支。
- `CAKEBOX_TOKEN='...'`：安装时写入隧道加密令牌。
- `CAKEBOX_DOWNLOAD_URL=https://...`：从指定地址下载主程序。
- `SING_BOX_DOWNLOAD_URL=https://...`：从自定义镜像下载 sing-box archive；必须同时提供 `SING_BOX_ARCHIVE_SHA256`。
- `SING_BOX_ARCHIVE_SHA256=64位十六进制`：授权一个精确的自定义 sing-box archive；解压后的 binary 默认仍必须匹配 requirement 官方摘要。
- `SIDECAR_BIN_SOURCE=/path/to/binary`：使用本地 sidecar；必须同时提供 `SIDECAR_BIN_SHA256`。
- `SIDECAR_BIN_SHA256=64位十六进制`：授权一个精确的定制 sidecar binary，安装后会持久化到 systemd 运行参数。
- `CAKEBOX_WEB_BIND=0.0.0.0:12345`：首次安装或修改 Web 设置时指定后台监听地址。
- `CAKEBOX_URL_PREFIX=mirage`：首次安装或修改 Web 设置时指定安全访问路径。

## 发布文件

- `linux-amd64/cakebox-0.1.4-linux-amd64`：linux-amd64 主程序。
- `linux-amd64/cakebox-noise-0.1.4-linux-amd64`：站点混淆/噪声辅助组件。
- `linux-amd64/cakebox-sidecar-requirement-0.1.4-linux-amd64.json`：sing-box sidecar schema、平台、版本与双 SHA-256 契约。
- `linux-amd64/cakebox-noise-0.1.4-linux-amd64-stable.manifest.json`：可选的 stable 通道签名升级 manifest，只有设置 `CAKEBOX_NOISE_UPDATE_SIGNING_KEY_HEX` 时生成。
- `linux-amd64/cakebox-noise-0.1.4-linux-amd64-canary.manifest.json`：可选的 canary 通道签名升级 manifest，设置 `CAKEBOX_NOISE_UPDATE_CHANNEL=canary` 时生成。
- `install.sh`：仓库根目录的一键安装和管理脚本。
- Release 资产：上传二进制文件和已生成的签名 manifest，例如 `cakebox-0.1.4-linux-amd64` 和 `cakebox-noise-0.1.4-linux-amd64`。
- `SHA256SUMS`：本地发布文件校验和，路径按本地发布目录记录。
