# Web 网关（§71）

## 为什么是它，而不是「再写一个 Web 客户端」

`DEVELOPMENT.md` §48/§79 原本画的是 React Web 前端，2026-09-30 改为
**Flutter 六端一致**（见 `AGENTS.md`「前端架构」与那两节的修订注）。目标一变，
网关的职责就窄了：它**不是**另一个产品，只是把同一套 `ts-core` 接到 WebSocket 上，
让浏览器够得着它。

因此这里没有一行协议代码：TS3/TS6 的行为、会话管理、音频管线，全部是桌面端
正在用的那些 crate。网关多出来的东西只有两样——**一个 socket** 和
**一份共用的词汇**（`ts-wire`）。

---

## 形状：一 core、N 浏览器连接

```text
  浏览器 A ─┐
  浏览器 B ─┼─ WebSocket ─┐
  浏览器 C ─┘             │
                          ▼
                   nightcord-gateway
                   ├── ts-gateway（连接、扇出、语音）
                   ├── ts-core / ts-session / ts-protocol
                   └── 一个 TS 身份，一份 settings.json / bookmarks.json
```

**不是托管服务**，这是设计边界而不是尚未实现的功能：一个网关 = 一台机器上的
**一个** TS 身份，浏览器是它的遥控器。多用户托管是另一个产品，问题也不同
（每访客身份、服务端混音、账号体系）。

推论之一：**多标签页同权**。命令结果走广播而不是点对点应答，所以第二个标签页
看得见第一个标签页发出的每条命令结果（`every_connection_sees_every_result`）。
v1 就这样，并且是写明的——要改成「谁问谁收」得先有会话归属的概念。

---

## 三个 crate

| crate | 是什么 | 不是什么 |
| --- | --- | --- |
| `ts-wire` | 命令与事件的 JSON 词汇：`Command`、`FfiEvent`、`AudioDirection` | 没有队列、没有传输、没有入口点 |
| `ts-gateway` | WebSocket 前端：握手、鉴权、扇出、语音桥、调试页 | 不是静态文件服务器，不是托管服务 |
| `nightcord-gateway`（`apps/gateway`） | 可执行文件：参数、日志、退出码 | 不含行为 |

`ts-wire` 是从 `ts-ffi` 里**搬出来**的，不是新写的：`command.rs` 与 `event.rs`
原本住在 `ts-ffi`，现在两个宿主共用一份。这就是 §52「Web 能做的和桌面能做的是同一件事」
变成代码性质而不是承诺的地方——加一条命令只有一处要改。

搬动的代价是给 `Command` 加了 serde 派生（网关的信封
`{"command": …, "payload": …}` 是它的 adjacent-tagged 形式）；C ABI 那边仍然
**手工**拼装每一个变体，从不序列化一个 `Command`。

---

## 一条 socket 上的三层

| 层 | 方向 | 形态 | 内容 |
| --- | --- | --- | --- |
| Control | 服务器→浏览器 | 文本 `{"kind": …}` | `hello`、`welcome`、`error`、`lagged` |
| Control | 浏览器→服务器 | 文本 `{"kind": "auth", "token": …}` | 第一帧，且必须是第一帧 |
| Commands | 浏览器→服务器 | 文本 `{"command": …}` | `ts-wire` 的 `Command` |
| Commands | 服务器→浏览器 | 文本 | `ts-wire` 的 `FfiEvent`，与 FFI 同形 |
| Audio | 双向 | 二进制，首字节是 tag | `1` = 上行 PCM，`2` = 下行 PCM |

**为什么 token 走第一帧而不是 URL**：浏览器不能给 WebSocket 设请求头，
而放进 URL 会漏进访问日志和 `Referer`。第一帧是剩下唯一的位置，也是更干净的一个。

事件走广播、命令结果也走广播（见上），所以**未鉴权的连接是被直接拒掉的，不是被
小心答复的**——鉴权前收到的任何东西都回一个错误然后关连接。

---

## 安全边界

| 措施 | 值 | 挡什么 |
| --- | --- | --- |
| `Origin` 校验 | 握手回调内，默认只允许 loopback 页面 | 公网页面连本机端口（WebSocket 版的 CSRF） |
| Token | 必填，16 字节 OS 熵 → 32 位十六进制 | 本机其他进程 / 其他用户 |
| 绑定地址 | 默认只绑 `127.0.0.1` 与 `[::1]` | 默认不暴露到网络 |
| 鉴权超时 | 10 秒 | 占着任务和编号不说话的连接 |
| 单条消息上限 | 64 KiB | 一次分配打满内存 |
| Token 比较 | 定长比较（长度不等即拒） | 时序侧信道（looback 上不现实，但代价只有六行） |

**默认绑两个 loopback 地址**不是随手写的：本机的 IPv6 前缀策略让 `::1` 优先于
`::/0`，只绑其中一个的话，`localhost` 会有一半的解析结果拿到 `ECONNREFUSED`。

`Origin` 的默认策略是「页面来自本机」——scheme 与 host 比，**端口不比**，
因为端口是页面碰巧跑在哪。给 `--allow-origin` 传了值就**整体替换**默认策略，
不是追加；部署出去的页面必须显式列进来。没有 `Origin` 头的连接（测试客户端、
原生程序）一律放行——它不是被借用的页面，而 token 仍然要对。

**没有 TLS，是刻意的。** 网关假定跑在 `cloudflared`、反向代理或内网后面，
自己终结 TLS 会把证书管理变成每个人的问题。暴露到公网时
`ws://` 上的 token 与语音都是明文——所以 CLI 的提示是「优先用隧道」。

---

## 身份档：`profile = "web"`

网关的客户端**不用** `default` 档，浏览器也不能挑（`connect` 里的 profile 被强制覆写）。

原因很具体：TS3 **拒绝同一身份的第二条连接**。网关若与桌面端共用 `default`，
两边会为那条连接打架——而且是在服务器那一侧、以谁也看不懂的方式打。
所以一个网关是一个身份，这是设计，不是限制。

---

## 语音：第一阶段是 PCM over WebSocket

**Opus 不出 Rust**（§80 原则 4）。所以两侧的分工是：

| 方向 | 谁做 | 做什么 |
| --- | --- | --- |
| 上行 | 浏览器 | `pcm-worklet.js` 在**真实的 48 kHz 时钟**上攒够 960 个 mono 样本，发一帧 |
| 上行 | 网关 | `TransmitPolicy` 按模式开闸 → `OpusEncoder` 编码 → 每个会话一个包 |
| 下行 | 网关 | 后端解出的立体声 `f32` 交给 `WsAudioSink`，一帧一条二进制消息扇出给所有连接 |
| 下行 | 浏览器 | Web Audio 播放 |

网关用的是 `ts-audio` 的**零件**而不是它的 `VoiceEngine`：引擎焊死在 cpal 设备上，
而网关没有设备，只有 socket。两半正好是接缝——`TransmitPolicy`、`OpusEncoder`、
`rms`/`peak` 都是公共的，直接拿来用。

**混音**在网关侧：每个连接一个累加器，按帧 tick 取一次，`1/n` 缩放后按峰值钳位。
缩放的原因是两个人都满音量时不该削顶；没人说话的 tick 返回「没有」而不是静音帧，
因为那意味着**不该开闸**。

**为什么 PCM 不是最终格式**：48 kHz 立体声 f32 是未压缩的，一条 20 ms 帧
就是 7.7 KB，双向同时说话时每秒几百 KB 全花在「什么都没变」的静音上。
它作为**第一阶段可验证实现**存在（把整条链路先跑通，包括 Web Audio 的时钟问题），
最终形态要换成浏览器侧编解码，路线写在 `AGENTS.md`「前端架构」的路线图里。

**网关编码单声道，桌面编码立体声。** 浏览器送进来的是每帧 960 个单声道样本
（`pcm-worklet.js`），所以这一端用 Opus Voice；把它编成立体声等于为一个声道的信息
付两次带宽。桌面的采集恒为立体声，因此用 Opus Music。两边都固定在这条链路的最高档，
没有可调的东西（见 [`audio.md`](audio.md) §3.5）。播放侧不受影响：无论对端发的是
哪一档，解码器都输出立体声。

**单人音量在网关侧生效，因此是全局的。** `voice_set_client_volume` 作用在
`tsclientlib` 的混音队列上，而混音发生在网关——所以一个标签页调低的音量，所有
标签页都听得到。这是「多标签页同权」那条既有取舍的又一例，不是新问题，但它比
命令结果的广播更容易让人意外，所以写在这里。

**耳机的对错与麦克风的开关**：`deafened` 在网关侧也关掉上行闸门，与桌面端
同一个 `TransmitPolicy`——理由见 `docs/devices.md` 与 `ts-audio` 里那条注释：
服务器拒收已关闭扬声器的客户端的语音，不关闸门的话每帧都会变成一条
用户无能为力的 `VoiceError::NotConnected`。

---

## HTTP：四个路由

| 路径 | 回答 |
| --- | --- |
| `/ws` | 交给 WebSocket 握手（**流不被消费**） |
| `/`、`/index.html` | 调试页 |
| `/pcm-worklet.js` | 采集 worklet |
| 其他 | 404；非 `GET` 也是 404 |

只有四个，所以没有框架、没有 router——手写一个 `match` 更短也更清楚。

**请求行是 `peek` 出来的，不是在 upgrade 回调里路由的**：`tungstenite` 的握手回调
只接受非 2xx 的响应，页面永远没法从那里发出去。`peek` 不消费数据，所以请求行
读完（循环读，TCP 分段会切在一行中间）之后，同一个流原样交给握手。

页面文件**编译进二进制**（`include_str!`），所以网关是一个文件就能跑。带
`--web-root` 时优先读磁盘，读失败**退回内嵌那份并记一条 `warn`**——页面是
「网关能不能用」的前提，而内嵌那份永远不会错，只是可能旧。

调试页（`crates/ts-gateway/web/`）与 Cloudflare Pages 部署上传的是**同一份文件**。
它按 `AGENTS.md` 的目标目录属于 `tools/web-debug/`：诊断与协议验证用，**不做产品 UI**。
产品 UI 是 Flutter Web，还没开始。

---

## 怎么跑

```bash
cargo run -p nightcord-gateway                 # 生成 token 并打印
cargo run -p nightcord-gateway -- --token <token> --allow-origin https://<project>.pages.dev
```

| 参数 | 默认 | 说明 |
| --- | --- | --- |
| `--bind <ADDR>` | `127.0.0.1:8787` + `[::1]:8787` | 可重复 |
| `--token` | 随机生成并打印 | 也读 `NIGHTCORD_GATEWAY_TOKEN`，免得出现在命令行里 |
| `--allow-origin <ORIGIN>` | loopback，任意端口 | 可重复；非空即替换默认 |
| `--profile` | `web` | 见上：不能是桌面端正在用的那个 |
| `--data-dir` | 平台默认 | 与 CLI 同一个 flag：把它指向别处就整份状态都搬走 |
| `--web-root` | 内嵌 | 改页面时用，省一次重编译 |

token 只在**生成它的那一次**打印，且打在 stdout 而不是日志里：那是启动者唯一
要亲手搬到浏览器的那件东西，而日志文件不是他看的地方
（`a_generated_token_is_the_one_that_gets_printed` 盯着这条）。

部署形态：页面放 Cloudflare Pages，网关留在自己机器上，中间用隧道连
（`https://<project>.pages.dev/?gw=wss://<tunnel-host>/ws`）。页面跑在 https 上时
不能连 `ws://localhost`（Chrome 的 Local Network Access），隧道顺带把这件事解决了。

---

## 已知取舍

- **没有 TLS**，见上。公网直连时 token 与语音都是明文。
- **没有每访客身份**：一个网关一个身份。多人共用一个网关等于共用一个 TS 身份。
- **多标签页同权**：命令结果广播给所有连接，不是只回给发问的那个。
- **没有会话归属**：谁都能对任何会话下命令，包括别人的标签页开的那个。
- **广播是「落后即丢」**：出站队列 1024 条，跟不上的连接收到一条 `lagged` 标记，
  中间的事件直接丢——无界的每访客内存更糟。
- **设备列表对浏览器没有意义**：远程传输会忽略设备参数，因为设备属于跑 core 的那台
  机器，不属于浏览器。
- **网关编单声道，桌面编立体声**：取决于喂进来的是什么，见上。两边都是各自链路的最高档。
- **单人音量是全局的**：混音在网关，见上。
- **语音只验证到「帧数与电平」**：与桌面端一样，音质没有用人耳确认过。

---

## 相关

- `crates/ts-wire/src/` —— 两个前端共用的词汇
- `crates/ts-gateway/src/{ws,http,worker,voice,config}.rs` —— 网关本体
- `crates/ts-gateway/web/` —— 调试页与 worklet，也是 Pages 部署的那两个文件
- `apps/client/lib/core/transport/client_transport.dart` —— 桌面这边对应的那个接口
- [`docs/architecture.md`](architecture.md) —— 分层与依赖方向
- [`docs/audio.md`](audio.md) —— `ts-audio` 的零件与引擎
- [`AGENTS.md`](../AGENTS.md) —— 「前端架构：Flutter 六端一致」与 Phase 7 的位置
