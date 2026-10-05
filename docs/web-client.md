# Web 客户端使用与部署

## 准备

需要仓库固定版本的 Rust、Flutter 3.47.5+ 与字体。首次克隆后在仓库根目录运行：

```bash
bash scripts/fetch-fonts.sh
cargo build -p nightcord-gateway
```

Native 与 Web 共享频道、聊天、设置与状态管理。宽视口使用侧栏布局；窄视口主页
显示频道树，点击频道或成员进入聊天，返回回到频道树。移动设置先显示分类，再进入
具体设置，不依赖隐藏侧栏。

## 本机与局域网

仓库根目录启动网关：

```bash
cargo run -p nightcord-gateway
```

另一个终端启动页面：

```bash
cd apps/client
flutter run -d web-server --release --web-hostname 0.0.0.0 --web-port 5173
```

电脑打开 `http://localhost:5173`，填入 `ws://localhost:8787/ws`。
手机打开电脑局域网 IP 的 5173 端口；手机的 localhost 指向手机自己。
不预置地址时，连接表单默认使用页面主机的 8787 端口，HTTP 对应 WS、HTTPS 对应 WSS。

局域网访问还须让网关监听网卡地址，并允许页面来源，例如：

```bash
cargo run -p nightcord-gateway -- --bind 0.0.0.0:8787 --allow-origin http://192.168.1.100:5173
```

请替换示例 IP，并按操作系统提示允许局域网防火墙访问。
`--allow-origin` 非空时替换默认列表；同时使用 localhost 时也须把它列入。

**局域网 HTTP 只能验证页面、聊天和连接。** 麦克风与本项目的 AudioWorklet 播放
要求安全上下文；localhost 是开发例外，局域网 IP 不是。手机语音须 HTTPS 页面、
WSS 网关和受手机信任的证书，随后点击启用语音并允许麦克风权限。
参见 [getUserMedia](https://developer.mozilla.org/en-US/docs/Web/API/MediaDevices/getUserMedia)
与 [AudioWorklet](https://developer.mozilla.org/en-US/docs/Web/API/AudioWorklet)。

手机联调优先用上述 release web-server。启动页显示资源、引擎、应用阶段；
加载失败可重试，超过 30 秒会提示检查网络。HTTP 页面正常加载不代表音频可用。

## 环境变量与可选 Token

网关默认免 Token。需要限制进入网关时，在服务端设置非空
`NIGHTCORD_GATEWAY_TOKEN`；空值或未设置表示关闭鉴权。Token 不自动生成或打印。

构建 Web 时可以预置地址和可选 Token。PowerShell 示例：

```powershell
$env:NIGHTCORD_GATEWAY_URL = 'wss://gateway.example.com/ws'
# 可选；与服务端相同。不设置时，受保护网关会要求手动输入。
# $env:NIGHTCORD_GATEWAY_TOKEN = '<your-token>'
python scripts/build-web.py
```

产物位于 `apps/client/build/web/`，可由任意静态服务器托管。
`build-web.py` 使用临时 JSON 传给 Flutter，避免 Token 进入构建命令行，并自动清理。
直接 `flutter run/build` 不读取这些 shell 环境变量，需要显式 Dart define；推荐用脚本。

预置地址后页面自动连接。未预置地址时可手动填写，或使用 `?gw=wss://host/ws`。
预置了 Token 时查询参数不能覆盖目标网关。**静态产物里的 Token 对访问者可见**，
Cloudflare 的 Secret 标记不会使浏览器代码保密；公开站点可只配置服务端 Token，
由用户手动输入。手动输入的 Token 不写浏览器存储或 URL。

每个浏览器设备自动生成独立恢复凭据，不需要手动填写。
同设备刷新、重开页面复用身份；同设备标签页共享状态。
清除网站数据、无痕模式或换浏览器/站点/网关地址会产生新身份。
身份私钥保存在网关，详见 [网关设备边界](gateway.md)。

## Cloudflare Pages

| 配置 | 值 |
| --- | --- |
| Framework preset | None |
| Root directory | 仓库根目录（留空） |
| Build command | `bash scripts/build-pages.sh` |
| Build output directory | `apps/client/build/web` |
| `NIGHTCORD_GATEWAY_URL` | `wss://gateway.example.com/ws` |
| `NIGHTCORD_GATEWAY_TOKEN` | 可选 |

构建脚本下载缺少的 Flutter SDK（默认固定 3.47.5）、字体，再构建发布版。
Pages 构建不需要 Rust 工具链；网关仍在独立机器运行，通过 Tunnel/反向代理提供 WSS。
Pages 环境拒绝 WS 配置。网关须允许 Pages、自定义域名和需要使用的预览域名来源。
`web/_headers` 为启动与应用脚本配置重新验证缓存，更新环境变量后须重新部署。

参考 [Pages 构建配置](https://developers.cloudflare.com/pages/configuration/build-configuration/)。

## 临时 HTTPS：Quick Tunnel

安装官方 [cloudflared](https://developers.cloudflare.com/tunnel/get-started/quick-tunnels/)，
先保持网关与静态页面在本机运行，然后分别启动两个隧道：

```powershell
cloudflared tunnel --url http://127.0.0.1:5173
cloudflared tunnel --url http://127.0.0.1:8787
```

第二条命令须在另一个终端运行。记录各自打印的 HTTPS 地址：

1. 网关增加 `--allow-origin https://<页面隧道>.trycloudflare.com`，然后重启。
2. 将 `NIGHTCORD_GATEWAY_URL` 设为 `wss://<网关隧道>.trycloudflare.com/ws`，运行
   `python scripts/build-web.py`。若预置 Token，须与重启的网关一致。
3. 用静态服务器托管新产物，例如 `python -m http.server 5173 --bind 127.0.0.1 --directory apps/client/build/web`。
   已经运行且服务同一目录的静态服务器无需重复启动。
4. 手机打开页面隧道的 HTTPS 地址，点击启用语音并允许麦克风。

隧道自动提供受信任证书，不需要域名或账号；知道地址的人可以访问，因此按需要配置
网关 Token 或站点访问限制。流量经过 Cloudflare，适用于临时测试。
停止 cloudflared 后地址失效，重新启动地址会变化；届时须同步 Origin 与 Web 配置。
换页面 Origin 会创建新的浏览器设备身份。固定部署使用正式 Tunnel 与自有域名。

Windows PowerShell 5 的 `$ErrorActionPreference = 'Stop'` 会把原生程序 stderr 的普通
提示转换为异常。自定义自动化脚本应使用 `Start-Process -Wait -PassThru` 分别重定向
stdout/stderr，再按 `ExitCode` 判断构建结果；Wasm dry run 提示不表示构建失败。

## 平台能力

浏览器快捷键仅页面内生效；本地日志目录与本地崩溃报告不适用。
系统通知通过 Notification API，取决于浏览器权限与支持。
设备选择使用浏览器能力，PCM 经 WebSocket 交给 Rust 编解码。

实测结果、手机真机语音与部署待办见 [AGENTS.md](../AGENTS.md)，不把浏览器模拟
等同于 iOS/Android 真机验收。
