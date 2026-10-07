# CakeBox v0.1.8

本版本提供 Linux AMD64、Linux ARM64 与 Windows x64。

## 更新内容

- 不再需要单独安装和更新 cakebox-noise，相关功能已内置在 CakeBox 主程序中，可在 CakeBox 后台本地开启或关闭。
- 后台支持深色、浅色和跟随系统主题，登录页同样可选。
- 优化后台按钮、弹窗和键盘操作，手机上更容易点按。
- 修复设置保存、前缀修改、更新页登录后不刷新等问题。
- 改善异常连接的清理，减少矿机长时间占用接入名额。

## 升级说明

- 需要与 HashCake v0.1.11 配合使用，才能在 HashCake 后台看到 CakeBox 的混淆状态；只升级一端不影响矿机连接。
- Linux 用户使用安装脚本的 `update` 更新，原有配置、Web 端口、访问路径和令牌会保留。
- 旧版本留下的 cakebox-noise 文件不再使用，可以手动删除。
- Windows 下载同版本程序替换更新。系统可能提示发布者不受信任，请按本机或组织的策略处理。

## 安装

```bash
CAKEBOX_TOKEN='你的隧道令牌' bash <(curl -fsSL https://raw.githubusercontent.com/hashultra/cakebox/main/install.sh) install
```
