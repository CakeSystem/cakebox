# CakeBox v0.1.11

## 本次升级内容

**新增：隧道断线续传**

隧道短时间中断（例如网络抖动、线路切换）时，矿机连接不再断开；恢复后未送达的份额在新隧道上补发，且每个份额只提交一次。

**改进：份额提交更省流量**

隧道写入按消息类型合并，份额提交改用更紧凑的格式，降低流量和小包数量。

**新增：流量统计页**

后台新增「流量统计」页面，可查看最近 24 小时的隧道上下行流量。混淆设置新增「自动平衡上下行」选项。

**改进：隧道组件在建立连接过程中意外退出时，会立即自动重启**

> 断线续传和紧凑格式需要 HashCake 0.1.20 及以上配合；连接旧版 HashCake 时自动沿用原有方式，不影响使用。

## 下载

| 平台 | 文件 |
|---|---|
| Windows x64 | `cakebox-0.1.11-windows.exe` |
| Linux amd64 | `cakebox-0.1.11-linux-amd64` |
| Linux arm64 | `cakebox-0.1.11-linux-arm64` |

## Windows 使用方法

1. 把下载的 exe 放到任意可写目录（例如 `D:\CakeBox`），不要放在 `C:\Program Files`。
2. 双击运行，保持窗口打开。首次启动会显示后台网址和一次性登录令牌。
3. 用浏览器打开该网址，输入一次性令牌设置管理员账号。
4. 在「令牌」页面粘贴 HashCake 签发的隧道加密令牌，即可完成接入。

## Linux 安装

```bash
bash <(curl -fsSL https://raw.githubusercontent.com/hashultra/cakebox/main/install.sh) install
```

国内服务器可使用镜像入口：

```bash
CAKEBOX_RELEASE_MIRROR_BASE=https://cdn.jsdmirror.com/gh/hashultra/cakebox@main bash <(curl -fsSL https://cdn.jsdmirror.com/gh/hashultra/cakebox@3ebf55609c495af7e2d9429ee4f3ecabece6d7ef/install.sh)
```

## 配套项目

- HashCake 服务端：https://github.com/hashultra/hashcake
