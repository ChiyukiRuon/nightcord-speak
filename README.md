# Nightcord Speak

第三方 TeamSpeak 3 / TeamSpeak 6 客户端。开发中

Flutter 提供桌面与 Web 界面，Rust Core 负责服务器连接、聊天和语音。
Web 界面支持 PC 与手机，每个浏览器设备使用独立身份。

## Web 使用

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

---

## 许可

MIT OR Apache-2.0

> `vendor/tsclientlib` 遵循其自身的 MIT OR Apache-2.0 许可
