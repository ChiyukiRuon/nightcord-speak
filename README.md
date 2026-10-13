# Nightcord Speak

第三方 TeamSpeak 3 / TeamSpeak 6 客户端。开发中

Flutter 提供桌面与 Web 界面，Rust Core 负责服务器连接、聊天和语音。
Web 界面支持 PC 与手机，每个浏览器设备使用独立身份。

## 桌面安装与更新

从 [GitHub Releases](https://github.com/ChiyukiRuon/nightcord-speak/releases) 下载客户端：

- Windows：运行 `windows-x64-setup.exe`，默认安装到当前用户目录，无需管理员权限。
  安装界面按系统显示语言默认选择中文（简体/繁体）、日文、英文或韩文，也可手动切换。
  可在系统“已安装的应用”中卸载；卸载保留身份、设置与自定义音效。
  ZIP 包仍可作为便携版使用。
- macOS：按处理器选择 `macos-arm64.zip`（Apple Silicon）或 `macos-x64.zip`（Intel），
  解压后将 `Nightcord Speak.app` 复制到“应用程序”。

Windows 和 macOS 可在“设置 → 关于 → 检查更新”找到新版本，点击“下载更新”，
下载校验完成后点击“安装并重启”，客户端会正常退出、完成更新并重新启动。
支持 Windows 安装版与便携版、macOS Apple Silicon 与 Intel，保留身份、设置与自定义音效。
macOS 应用应放在当前用户可写的本地目录中。普通版本只提示不带 alpha/beta/rc 后缀的更新，
预览版本也检查这些预览发布；`0.x` 公开测试版正常参与检查。

## Web 使用

正式网页部署步骤见 [DEPLOY.md](DEPLOY.md)，包含 Docker Compose 网关、HTTPS／WSS
与 Cloudflare Pages／自托管网页。

在仓库根目录启动网关（默认免 Token，仅监听本机）：

```bash
cargo run -p nightcord-gateway
```

另一个终端启动 Web 客户端：

```bash
cd apps/client
flutter run -d web-server --release --web-hostname 0.0.0.0 --web-port 5173
```

电脑打开 `http://localhost:5173`，网关地址为 `ws://localhost:8787/ws`。
首次构建须准备 Flutter 与字体，详见 [Web 客户端使用与部署](docs/web-client.md)。

手机语音需要 **HTTPS 页面 + WSS 网关**；局域网 HTTP 仅适合验证页面与连接。
Cloudflare Pages、临时 HTTPS 隧道及可选 Token 的配置见上述文档。

### Docker Compose 网关

网关可通过根目录的 `docker-compose.yaml` 独立部署到 Docker，设备身份和设置保存在持久化卷中：

```bash
cp .env.example .env
docker compose up -d --build --pull never
```

默认仅暴露 `127.0.0.1:8787`。按需编辑 `.env` 中的 Token、允许的网页来源和端口。
镜像首次发布后也可执行 `docker compose pull && docker compose up -d --no-build`，
使用 `ghcr.io/chiyukiruon/nightcord-speak-gateway:main`，支持 Linux amd64 与 arm64。
完整配置、更新与数据备份见 [网关部署](docs/gateway.md#docker-compose-部署)。

---

## 许可

MIT OR Apache-2.0

> `vendor/tsclientlib` 遵循其自身的 MIT OR Apache-2.0 许可
