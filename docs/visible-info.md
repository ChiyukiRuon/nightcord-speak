# 可见信息：第三方客户端能看到什么

> 本文回答一个问题：**一个第三方客户端，能从服务器上看到其他用户（尤其是官方客户端用户）的哪些信息？**
> 结论全部来自 2026-10-09 在真实服务器上抓的原始协议报文，不是从文档抄的；
> 每条都标了「实测收到」还是「实测被拒」。
>
> 相关：[`screen-sharing.md`](screen-sharing.md)（TS6 扩展）、[`ts3.md`](ts3.md)（TS3 后端）

**证据基础**

| 项 | 内容 |
| --- | --- |
| 工具 | `run/avatar-probe`（`run/` 被 git 忽略，独立于产品代码）：用与产品**同一份** tsclientlib 连接，打开原始命令日志（`log_commands(true)` + `RUST_LOG=tsproto=debug`） |
| 身份 | 每次运行都是全新身份、**匿名访客**，没有任何服务器权限 |
| 服务器 A | `192.168.31.128:9987` —— TeamSpeak 3 Server **3.13.8**（Linux） |
| 服务器 B | `xypp.cc` —— TeamSpeak 6 Server **6.0.0-beta13.1**（Linux），同服样本包含：官方 TS6 客户端 **6.0.0-beta4.1**、一个 tsclientlib 系 bot、一个 ServerQuery 连接 |
| 下载校验 | MD5 用 `md5sum` 比对服务器公布的哈希；图片用肉眼确认过 |

「✅」＝实测收到，「❌」＝实测被拒（附服务器回的权限号）。

---

## 1. 结论

**服务器把同服每个在线客户端的画像，主动推给每一个还连着的客户端**——不需要任何权限、
不需要对方同意。昵称、身份、所在频道与群组、离开消息、自我介绍、国家、客户端软件版本、
头像引用、myTeamSpeak 账号引用……全在推送里。

主动查询还能再拿到：**空闲时长、账号注册时间、上次连接时间、总连接次数、流量统计、身份
公钥**。

默认访客被拒的只有三类，且都是「历史/目录」类：服务器数据库资料（`clientdbinfo`）、
全体登记身份表（`clientdblist`）、**根文件库的目录列表**（`ftgetfilelist cid=0`）。

头像两条路都实测能拿，见 §4——其中服务器文件库那条**不需要任何权限**（按名字下载单个
文件是放行的，只有列目录被拒，见 §3 的不对称）。

---

## 2. 被动推送：不用问就能拿到的

### 2.1 `notifycliententerview` —— 有人进入你的视野

TS3 共 **34 个 `client_*` 字段**（外加 `cfid` / `ctid` / `reasonid` / `clid` 四个信封字段），
TS6 再多两个。按用途分组：

| 组 | 字段 | 说明 |
| --- | --- | --- |
| 身份 | `client_unique_identifier` | 身份公钥派生值，跨服务器不变——**换身份才变** |
| | `client_database_id` | 在该服务器数据库里的编号 |
| | `client_nickname` / `_nickname_phonetic` | 昵称 / 注音 |
| | `client_type` | 0＝普通客户端，1＝ServerQuery |
| 状态 | `client_input_muted` / `_output_muted` / `_outputonly_muted` | 客户端自报的静音状态 |
| | `client_input_hardware` / `_output_hardware` | 「麦克风/扬声器开关」 |
| | `client_away` / `client_away_message` | 离开标记与那句话说给别人听 |
| | `client_is_recording` | 是否在录音（旧字段） |
| | `client_is_streaming`（**TS6 独有**） | 是否在直播 |
| | `client_is_talker` / `_talk_power` / `_talk_request` / `_talk_request_msg` | 说话权相关 |
| | `client_unread_messages` | 未读消息数 |
| 归属 | `client_channel_group_id` / `_channel_group_inherited_channel_id` / `_servergroups` | 频道组 / 继承的频道组 / 服务器组列表 |
| | `client_icon_id` | 群组图标编号 |
| 展示 | `client_description` | 自我介绍正文 |
| | `client_country` | 国家——服务端按 IP 判定，**不看客户端申报**；有没有值由服务器决定（同一批客户端实测：TS3 服务器全为空，TS6 服务器全是 `CN`） |
| | `client_flag_avatar` | **头像图片的 MD5**（§4.1）；空＝服务器上没有头像 |
| | `client_myteamspeak_id` | myTeamSpeak 账号 ID；空＝未登录/未验证 |
| | `client_myteamspeak_avatar` | myTS 云头像引用（§4.2）；空＝没有。TS3 与 TS6 服务器上都会出现（实测） |
| | `client_badges` / `client_signed_badges` | 徽章 |
| | `client_integrations` | 第三方集成 |
| | `client_user_tag`（**TS6 独有**） | JSON：`myts_token`（签名凭据）+ 账号标签 + 更新时间 |
| 其它 | `client_meta_data` | 客户端自由写入的元数据；TS6 官方客户端在这里放账号标签 |
| | `client_needed_serverquery_view_power` | 查看 ServerQuery 用户所需的 power |

> **`client_version` 不在这条推送里**——对方用什么客户端，要主动问（§3）。

### 2.2 `notifyclientupdated` —— 哪里变了推哪里

同一批字段的子集，按需推送。实测里由 `clientgetvariables` 触发的答复就走这条。

### 2.3 `initserver` —— 服务器对「你自己」的描述

只手你自己，字段与 2.1 同族，另有几样只发给本人的：`client_default_channel`、
`client_default_channel_password`、`client_server_password`（连接参数回显）、
`client_version_sign`、`client_security_hash`、`client_key_offset`、
`client_default_token`、`client_active_integrations_info`，以及 `acn` / `aclid` / `pv`。

### 2.4 其它推送

频道事件、聊天、戳一戳、屏幕共享信令等各有自己的消息，不属本文范围。

---

## 3. 主动查询：问了才给（以及问不到的）

在**两台服务器上、匿名访客身份**逐一实测：

| 命令 | 服务器 A（TS3 3.13.8） | 服务器 B（TS6 beta13.1） | 拿到什么 |
| --- | --- | --- | --- |
| `clientinfo clid=N` | ✅ | ✅ | §3.1 的加料字段 |
| `clientgetvariables clid=N` | ✅（答复走 `notifyclientupdated`） | ✅ | 版本、平台、注册时间、连接次数、流量 |
| `clientdbinfo cldbid=N` | ❌ `permid=33` | ❌ `permid=34` | 数据库资料（含 `client_lastip` 等，查询端才有） |
| `clientdblist` | ❌ `permid=31` | ❌ `permid=32` | 该服务器登记过的**全部身份** |
| `ftgetfilelist cid=0 path=/` | ❌ `permid=147` | ❌ `permid=151` | **根文件库目录**——图标与头像文件都住这里 |
| `ftgetfilelist cid=<自己频道>` | ✅（`1281` 空结果） | ✅（`1281` 空结果） | 频道目录——**权限上允许**（回的是「结果为空」而不是「权限不足」），只是没有文件可列；未见非空样本 |
| `permidgetbyname permsid=…` | ❌ `permid=5` | ❌ `permid=5` | 权限名 → 编号 |
| `ftinitdownload name=/avatar_…` | — | ✅ | **头像文件本体**（§4.1） |

**权限号说明**：编号随服务器版本漂移（同一条权限：TS3 是 31/33/147，TS6 是 32/34/151）。
31/33 与权限表里的 `b_virtualserver_client_dblist` / `b_virtualserver_client_dbinfo`
语义对得上（**推测**，未逐条验证）；147/151 的候选是图标管理一族
（`b_icon_manage` 附近），**未确认**。

**不对称条款（重要）**：根文件库**列不了目录**，但**按确切名字下载单个文件是放行的**——
`ftinitdownload` 两次成功。整个头像调查成立就靠这一条：名字可以从 UID 本地推导
（§4.1），不需要先看到目录。

### 3.1 `clientinfo` 在 2.1 之外多给了什么

| 字段 | 说明 |
| --- | --- |
| `client_idle_time` | 空闲时长（毫秒） |
| `client_version` / `_platform` | **对方用什么客户端**——能直接区分官方客户端与第三方（实测：官方 TS6＝`6.0.0-beta4.1 [Build: …]`；tsclientlib 系＝`3.?.? [Build: 5680278000]`，是 tsclientlib 的默认暗号） |
| `client_version_sign` | 客户端版本签名 |
| `client_security_hash` | 身份安全等级（proof-of-work 的难度） |
| `client_login_name` | 登录名（一般空） |
| `client_created` / `_lastconnected` / `_totalconnections` | 注册时间 / 上次连接 / 总连接次数 |
| `client_month_bytes_uploaded` / `_downloaded` / `_total_…` | 月/总流量，四个数 |
| `client_default_channel` / `client_default_token` | 默认频道 / 默认 token（一般空） |
| `client_base64HashClientUID` | UID 的 a–p 编码（§4.1 的头像文件名就是它） |
| `client_public_key_raw`（**TS6 独有**） | 身份**公钥**（base64 DER，实测有值） |

> **自报字段不可信**：`client_version`、`client_platform`、`client_meta_data` 等都是客户端
> 自己说话，服务器照转。第三方客户端想让别人看到什么版本号，就写什么（tsclientlib
> 默认的 `3.?.?` 就是这么来的）。

---

## 4. 头像：两条路，都实测走通

### 4.1 服务器文件库头像（TS3 与 TS6 都有）

流程：

1. 被动或主动拿到 `client_flag_avatar`（图片的 MD5，空＝没有）与对方的
   `client_unique_identifier`；
2. 本地把 UID 的原始字节按 **a–p 编码**（每个半字节映射成 `a`+n，等价于
   ServerQuery 的 `client_base64HashClientUID`）拼出文件名
   `/avatar_<a-p 编码的 UID>`；
3. `ftinitdownload clientftfid=N name=/avatar_… cid=0 proto=1` → 服务器回 `ftkey` /
   `port`（30033）/ `size`；
4. 连 TCP、用 `ftkey` 取字节；
5. 用 `client_flag_avatar` 校验 MD5。

**实测记录（xypp.cc，2026-10-09）**：对同服一个第三方 bot 的头像完成全流程——
135,710 字节 JPEG，`md5sum` ＝ `49fc656b2604dd08b4b63ac4f0d25d6e`，与服务器公布值逐位一致；
全程匿名访客，无任何权限。

**官方客户端佐证**：该机器上官方 TS6 客户端的本地缓存
（`%LOCALAPPDATA%\TeamSpeak\Cache\Default\<server>\clients\`）里，躺着**同名文件**、
同样 135,710 字节、同样 MD5——官方客户端与第三方客户端取到的是同一个对象、同一套命名。
（这条闭掉了「文件命名只是第三方自己的约定」这个疑虑。）

### 4.2 myTS 云头像（TS6 官方客户端）

TS6 官方客户端在服务器上设置的头像不进服务器文件库，而是由客户端把 **myTeamSpeak 云
头像的完整 HTTPS URL** 写进 `client_myteamspeak_avatar`，形状：

```
client_myteamspeak_avatar = 2,https://storage.googleapis.com/ts-sys-myts-avatars/<uuid>/<version>
```

（前缀 `2,` 的含义未确认；URL 里带账号级 uuid 与一个版本号。）

服务器把它**原样转发给每个客户端**。实测：对同服一位官方 TS6 客户端用户
（`client_flag_avatar` 为空、`client_myteamspeak_avatar` 非空）直接 `curl` 该 URL——
**HTTP 200、无需任何凭据**，159,378 字节 320×320 PNG（GCS 公开对象）。

**跨服务器实测（补测）**：同一位用户带着同一个官方客户端连到 **TS3 服务器**
（`192.168.31.128:9987`），我们拿到的 `client_myteamspeak_avatar` 是**同一个 URL**，
而 `client_flag_avatar` 仍然为空——这台 TS3 服务器上同样只有 myTS 那一条路，没有经典
头像。也就是说：「新官方客户端只维护账号头像、不往服务器文件库传」是**客户端行为，
与服务器是 TS3 还是 TS6 无关**（样本：1 位用户 / 1 个客户端版本）。

> 这条推翻了本仓库早先「myTS 头像第三方拿不到」的推断。至少在这台服务器 + 这个客户端
> 版本上，URL 是随协议明文发布、且对象公开可读的。**未来官方若改成需要签名的 URL，
> 这条路就会断**——目前没有反例，也没有承诺。

### 4.3 两条路的取舍

| | 4.1 文件库 | 4.2 myTS |
| --- | --- | --- |
| 谁的头像 | 在服务器上设过头像的（TS3 风格，也含不少第三方客户端） | 登录了 myTS 的官方 TS6 客户端 |
| 读取方式 | 文件传输（TCP 30033） | HTTPS GET |
| 权限 | 匿名可用（实测） | 无鉴权（实测） |
| 校验 | MD5（服务器公布） | 无哈希；URL 即版本 |

**2026-10-09 已纳入产品范围**：有效服务器 MD5 头像优先，否则读取公开 myTS 云头像。
前端只接收不透明版本与图片字节；公开 URL 留在适配层。云下载限定上述 Google Storage
命名空间，不跟随重定向；每张图片上限 2 MiB，文件库头像另校验 MD5。
缓存按会话、客户端 ID、稳定身份与版本隔离，最多 128 张/16 MiB，最多三个并发下载。
频道成员与聊天发送者显示头像，缺失或失败保留首字母；发言圆弧照常显示。

### 4.4 上传与移除（2026-10-09 实现）

点击底栏自身头像可查看、上传、编辑和移除。选择图片或编辑当前头像时，支持拖动定位、
缩放、旋转与重置，圆形预览裁剪区域；确认后导出至多 256×256、不超过 200 KiB 的
正方形 PNG。取消不上传；自身头像是客户端全局设置，会同步到每个服务器，不写 myTeamSpeak 云账号。
原图（最多 10 MiB）与旋转、缩放、取景位置一同保存在 Core 的 `avatar.json`，重新编辑
恢复上次裁剪位置，也可以重置后重新取景；原图不上传至 TeamSpeak 服务器。旧头像及
从服务器迁移的头像没有原图，编辑时需重新选择原文件。移除头像会一并清除保存的原图。

1. `ftinitupload cid=0 name=/avatar`，覆盖已有文件，实际传输完成后继续。
2. 对上传字节计算 MD5，发送 `clientupdate client_flag_avatar=<MD5>`。
3. 查询自身 `clientgetvariables`，以服务器返回的版本驱动头像刷新；其他客户端通过
   服务器推送获得更新。

移除时尝试 `ftdeletefile cid=0 name=/avatar`，再用 `clientupdate client_flag_avatar=`
清空标记；文件删除失败不阻止清空标记。上传与更新仍受服务器权限控制。
初次连接也查询自身变量，因为 `initserver` 不提供自己的头像哈希。

**全局头像决定（2026-10-09，用户要求）**：客户端在 `avatar.json` 保存一份自身头像，
更换、编辑或移除一次即同步所有已连接服务器；之后新连接或重连也自动应用。各服务器的
文件库仍独立，客户端分别上传；其中一服拒绝不会阻止其他服，错误按所属服务器报告。
自身 UI 使用统一保存的图片，他人仍按 §4.3 读取。显式移除保存空头像状态，以免重启后
恢复旧图；未设置过全局头像时，首次读到的现有自身 PNG/JPEG 头像会自动迁移。
TS3 与 TS6 的同时同步、新连接自动应用、一次更换和一次移除均已用临时身份实测通过。

产品适配层在 TS3、TS6 服务器上均实测完成上传、自身更新、下载逐字节比对与移除；
TS6 还下载了 §4.1 的 bot 头像。公开云 URL 的下载证据来自 §4.2 调查，本轮尚未完成
产品中的在线官方客户端云头像验收。完整实现与验证记录见 AGENTS.md 同日头像实现节。

---

## 5. 与 myTeamSpeak 账号有关的暴露

同一批推送里，同服**所有人**都能看到（实测值就不抄进仓库了，形态如下）：

| 字段 | 内容 |
| --- | --- |
| `client_myteamspeak_id` | 账号 ID |
| `client_meta_data` | `{"tag":"<账号>@myteamspeak.com"}` |
| `client_user_tag`（TS6） | `{"myts_token":"<签名凭据>","tag":"…","updated":…}` |
| `client_myteamspeak_avatar` | 头像 URL（§4.2） |
| `client_signed_badges` | 徽章签名 |

「已验证账号」徽章、账号标签就是这么工作的。反过来说：**我们的用户在同服别人眼里也是
这个样子**——所以 §4.5 的规则（身份、凭据、用户内容不进日志）对这条链上的数据同样适用。

---

## 6. 边界与未验证

- **权限可收紧**：本文结论是「这两台服务器的默认访客组」。服务器管理员可以拒绝
  `clientinfo`（`b_client_info_view`）等；换了服务器要重测。
- **视野**：`notifycliententerview` 只推订阅频道内的人。我们是订阅全部频道的
  （既有行为，见 §7 的历史记录），一般服务器上等于「全服务器」。
- **离线用户不可见**：他们不在推送里；`clientdblist` / `clientdbinfo` 能补，但默认被拒。
- **TS3 侧已有真人样本**（2026-10-09 补测）：同一台 TS3 服务器上同时连着一个官方
  客户端（TS6 客户端 6.0.0-beta4.1，带账号头像）、一个第三方客户端（tsclientlib 系，
  自报 `3.?.?`，无头像）和探针；字段集与取值都按实测记录。**仍然缺**两样：TS3 官方
  客户端（3.6.x）自己的样本；以及「**由官方客户端上传进文件库**的头像」——§4.1 里
  文件库那条路的**上传者是第三方**（官方客户端只贡献了缓存侧佐证），
  而 4.2 里官方客户端的头像只走 myTS、不进文件库。
- **权限名是推测**：编号实测、名字按权限表推断（§3 已注明）。
- **没测**：ServerQuery 登录后的视角、跨服务器差异、官方客户端在 TS3 上的样本、
  `client_lastip`（在拿不到的 `clientdbinfo` 里）。

---

## 7. 对项目的意义

**能做的**（信息都已在手上）：头像（两条路）、国家、描述、离开消息、徽章、
客户端软件/版本、myTS 账号引用——头像版本与图片获取已映射，其他新增信息尚未因此实现。

**别做的**：把 §5 的凭据类字段（`myts_token` 等）当普通文本处理——它们是签名材料，
日志、`Debug`、FFI 一视同仁按 §4.5 对待。

**范围决定**：用户于 2026-10-09 授权实现头像显示与上传，已移出 AGENTS.md §74 的
「明确不做」清单；账号登录、云同步与 myTeamSpeak 云头像写入仍不在本次范围内。

---

## 8. 复现方法

```bash
cd run/avatar-probe
CARGO_TARGET_DIR=../../target CMAKE_GENERATOR="Visual Studio 16 2019" cargo build
RUST_LOG=tsclientlib=info,tsproto=debug ../../target/debug/avatar-probe.exe <地址> [昵称]
```

探针会：连上 → 列出可见客户端与头像哈希 → 逐一 `clientinfo` / `clientgetvariables` /
`clientdbinfo` → `clientdblist` → 列根目录与所在频道 → 查权限名 → 下载能下到的头像到
`out/`。原始报文都在日志里；**日志带 ANSI 颜色码，先剥掉再 grep**：

```bash
sed 's/\x1b\[[0-9;]*m//g' log > log.plain
# 某条消息的完整字段表：
grep -o 'content="[^"]*"' log.plain | tr '|' '\n' | grep '^clid=<id> ' \
  | sed 's/ client_/\nclient_/g' | sed 's/=.*//' | awk '!s[$0]++'
```

**注意**：`content="…"` 遇到值里带转义引号的字段（`client_meta_data` 的 JSON）会被截断，
要拿全字段就在原始行上按 `|` 分片，别用引号配对的正则。
