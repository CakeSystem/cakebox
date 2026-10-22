# CakeBox

**HashCake 矿场端客户端：在矿场侧建立加密隧道，把矿机流量安全转回中心 HashCake 矿池代理。**

CakeBox 部署在矿机所在网络中，接收矿机连接，并通过加密隧道把流量转回中心 HashCake 服务器。矿场与服务器跨地域、或不想把 HashCake 端口直接暴露公网时，用它把公网入口收敛到一条加密隧道；本机同时支持 amd64、arm64 和 Windows。

## 适用场景

- **异地矿场接入**：远端矿场只运行 CakeBox，矿机连本地入口，隧道回中心 HashCake。
- **公网收敛**：HashCake 不必对公网开放代理端口，跨地域接入只依赖隧道入口。
- **多矿场统一管理**：每台 CakeBox 在 HashCake 后台作为一个站点，统一查看在线状态与流量。
- **不改变现有矿机配置**：矿机仍按本地 Stratum 地址连接，由 CakeBox 负责加密转发。

## 常见问题

**CakeBox 可以单独使用吗？**
不能。CakeBox 是矿场侧客户端，需要配合中心 [HashCake 服务端](https://github.com/hashultra/hashcake) 使用。

**隧道加密令牌从哪来？**
由 HashCake 后台签发，安装后在 CakeBox 后台网页的「令牌」页面粘贴即可，不需要写进命令行。

**支持哪些平台？**
Linux amd64、Linux arm64（如 Armbian）与 Windows x64，安装器会自动识别 Linux 架构。

**会不会影响矿机原有连接方式？**
CakeBox 只做入口与加密转发，矿机仍按本地 Stratum 地址连接；更新会保留端口、安全访问路径、Web访问令牌、隧道加密令牌和状态目录。

## 配套项目

- HashCake 服务端：https://github.com/hashultra/hashcake

## 首次安装

在 Linux 服务器上执行（脚本会自动识别 CPU 架构；当前提供 amd64 与 arm64 产物）：

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hashultra/cakebox/main/install.sh) install
```

安装脚本会自动下载程序、安装 sidecar 依赖、写入并启动 systemd 服务，并打印后台地址、安全访问路径和 Web访问令牌。**隧道加密令牌请到后台网页里填写**（见下一节），不需要在命令行里传。

运行要求：Linux amd64 或 arm64、GLIBC 2.31 或更高（Ubuntu 20.04+ / Debian 11+ / Armbian 均可；0.1.9 起两个 Linux 架构都改用固定 Zig 编译，实测最高只要求 GLIBC 2.30）、systemd 240 或更高、root 权限，安装目录所在文件系统需支持 `O_TMPFILE`（ext4/xfs 等本地磁盘）。

如果服务器不能使用 `bash <(...)`，也可以分两步：

```bash
curl -fsSL https://raw.githubusercontent.com/hashultra/cakebox/main/install.sh -o install-cakebox.sh
sudo bash install-cakebox.sh install
```

### 国内服务器

无法稳定访问 GitHub 的服务器使用下面的通用管理入口。该命令不绑定当前已安装版本；不带动作启动时进入管理菜单，在菜单中选择安装或更新时会自动查找最新稳定版并按 SHA256SUMS 校验：

```bash
CAKEBOX_RELEASE_MIRROR_BASE=https://cdn.jsdmirror.com/gh/hashultra/cakebox@main bash <(curl -fsSL https://cdn.jsdmirror.com/gh/hashultra/cakebox@3ebf55609c495af7e2d9429ee4f3ecabece6d7ef/install.sh)
```

国内镜像的清单缓存可能滞后：安装器会在解析版本时与 GitHub 清单比对，镜像落后时按更新的版本安装，下载仍优先使用国内镜像。sing-box sidecar 走安装器内置的 GitHub 代理源，并按 CakeBox 二进制内置的 SHA-256 契约逐字节校验；校验不通过即安装失败。

## 更新程序

```bash
sudo bash install-cakebox.sh update
```

更新会保留已有 Web 端口、安全访问路径、Web访问令牌、隧道加密令牌和状态目录。

## 接入隧道加密令牌

**推荐在后台网页里完成。** 在能访问这台机器的电脑或手机浏览器里打开安装结果中打印的地址（形如 `http://192.168.1.10:34567/cb-xxxxxxxx/`）：

1. 首次打开是「CakeBox 首次设置」页：粘贴安装结果里打印的 **Web访问令牌**（损坏或丢失时可在机器上执行 `cat /opt/cakebox/state/web-token` 取回），同时设置管理员用户名和密码，点「创建账户并登录」。
2. 登录后打开「令牌」页面，粘贴 HashCake 签发给这台机器的 **隧道加密令牌**，点「安装」。
3. 页面提示安装成功后，矿机入口自动打开，矿机即可连接。

> 注意区分两种令牌：`Web访问令牌` 是本机后台的登录凭据，只用于首次创建账户；`隧道加密令牌` 是 HashCake 签发的 `cakebox1.…` 字符串，决定矿机接入哪个矿场。后台页面会分别提示，不要填错。

命令行方式仍然保留，适合没有浏览器的服务器或自动化部署，不推荐日常使用：

```bash
sudo CAKEBOX_TOKEN='你的隧道加密令牌' bash install-cakebox.sh install-token     # 首次写入
sudo CONFIRM_REPLACE_TOKEN=yes CAKEBOX_TOKEN='新的隧道加密令牌' bash install-cakebox.sh replace-token    # 替换
```

## Windows 下载

Windows amd64 版本可在 Release 页面下载：

```text
https://github.com/hashultra/cakebox/releases/download/v0.1.16/cakebox-0.1.16-windows.exe
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

- `CAKEBOX_VERSION=v0.1.0`：安装指定版本；不指定时自动识别本机架构，并选择该平台目录下的最新版本。
- `CAKEBOX_RELEASE_BRANCH=main`：读取发布文件的 Git 分支。
- `CAKEBOX_TOKEN='...'`：可选。安装时直接写入隧道加密令牌；正常流程建议装好后在后台网页里填写。
- `CAKEBOX_DOWNLOAD_URL=https://...`：从指定地址下载主程序。
- `SING_BOX_DOWNLOAD_URL=https://...`：从自定义镜像下载 sing-box archive；必须同时提供 `SING_BOX_ARCHIVE_SHA256`。
- `SING_BOX_ARCHIVE_SHA256=64位十六进制`：授权一个精确的自定义 sing-box archive；解压后的 binary 默认仍必须匹配 requirement 官方摘要。
- `SIDECAR_BIN_SOURCE=/path/to/binary`：使用本地 sidecar；必须同时提供 `SIDECAR_BIN_SHA256`。
- `SIDECAR_BIN_SHA256=64位十六进制`：授权一个精确的定制 sidecar binary，安装后会持久化到 systemd 运行参数。
- `CAKEBOX_WEB_BIND=0.0.0.0:12345`：首次安装或修改 Web 设置时指定后台监听地址。
- `CAKEBOX_URL_PREFIX=mirage`：首次安装或修改 Web 设置时指定安全访问路径。

## 发布文件

- \`linux-amd64/cakebox-0.1.16-linux-amd64\`：linux-amd64（x86_64 服务器） 主程序。
- \`linux-amd64/cakebox-sidecar-requirement-0.1.16-linux-amd64.json\`：linux-amd64（x86_64 服务器） 的 sing-box sidecar schema、平台、版本与双 SHA-256 契约。
- \`linux-arm64/cakebox-0.1.16-linux-arm64\`：linux-arm64（aarch64 / ARM64 服务器，如 Armbian） 主程序。
- \`linux-arm64/cakebox-sidecar-requirement-0.1.16-linux-arm64.json\`：linux-arm64（aarch64 / ARM64 服务器，如 Armbian） 的 sing-box sidecar schema、平台、版本与双 SHA-256 契约。
- `install.sh`：仓库根目录的一键安装和管理脚本。
- Release 资产：上传各平台的二进制文件和已生成的签名 manifest。
- `SHA256SUMS`：本地发布文件校验和，路径按本地发布目录记录。
