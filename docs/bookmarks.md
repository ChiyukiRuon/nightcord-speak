# 书签 / 服务器列表（§40）

## 为什么有它

`Bookmark` 结构体从**首次提交**起就躺在 `crates/ts-protocol/src/config.rs`：定义好了、
导出了、serde 齐了，**一次都没被构造过**。又是「铺好了路没人走」——但这次路本身铺错了
地方，而错在哪只有真去用它才会暴露。

## 模型搬了家（分层，不是口味）

`ts-protocol` 的章程是「能力拆分的 trait + `Backend`」；保存的服务器是用户数据。
更硬的是依赖方向：`ts-settings` 与 `ts-protocol` **同在层 2**，而同层互不依赖是
`docs/architecture.md` 的明文规则——所以设置**存不了**这个类型，除非打破分层。

现在 `Bookmark` / `BookmarkList` / `BookmarkStore` 住在 `ts-settings`，
`ts-protocol` 里那份删掉了（它没有别的引用）。

**顺带改名**：原本叫 `Server` 的打算立刻撞了两次——Dart 的 `models/domain.dart` 已经有
一个 `Server`，`ts-model` 也有。`analyze` 一跑就报出来了。§40 本来就叫它 Bookmark，
那个死掉的结构体也叫这个名，于是改回 `Bookmark`，两个语言里都不再撞。

---

## 文件

```text
<应用数据目录>/bookmarks.json
```

**为什么和 `settings.json` 分开**：这个文件里有**服务器密码**，而设置文件是用户最可能
贴进 bug 报告的那一个（拖一下灵敏度滑块就重写一次）。用文件把这条界限划出来，
`settings.json` 就仍然可以随手分享。

```json
{
  "version": 1,
  "bookmarks": [
    {
      "name": "家里的服务器",
      "host": "192.168.31.128",
      "port": 9987,
      "nickname": "Alice",
      "protocol": "ts3",
      "server_password": "hunter2"
    }
  ]
}
```

### 关于那个密码，说清楚

**它是明文。** 存储上没有加密，也不打算有。文件权限在 Unix 上是 `0600`，
Windows 上继承用户目录的 ACL——与隔壁的 `identity/`（里面是 base64 的私钥）同级保护，
不多不少。

这意味着：**任何能读到你用户目录的进程都能拿到你的服务器密码**。这是做出这个选择时
明知代价——§40 与那个死掉的结构体都写着「不是账号、不含凭证」，这一轮把它改成了存。
如果哪天想改回去，把 `server_password` 从结构体里删掉即可；它的 `serde(default)` 会让
旧文件仍然读得进来。

`Debug` 是手写的，密码打成 `<set>/<unset>`——§44 要求密码绝不进 `Debug`，
有一个测试专门盯着它。

### 地址在写入时归一化

用户输入的是**一个字符串**（`example.com`、`192.168.1.10:9987`、`ts3://host`、
`[::1]:9987`），存下来的却是分开的 `host` 与 `port`。中间那一步是
`ConnectionTarget::parse`——**连接时用的同一个解析器**，所以「存得下的条目一定连得上」。

解析在 core 里做（`nightcord_add_bookmark` 收的是用户原样输入的地址），
不是为了炫技：Dart 那边 `Uri.parse` 处理不了裸的 `host:port`（它会把 `example.com`
读成 scheme），再写一份解析就是让两份慢慢漂移。

**主机名本身不校验。** 解析器只拒绝空地址、未知 scheme、括号不配对、端口非法——
主机名的权威是 DNS，硬猜一套语法只会拒掉本来能用的地址。
粘贴 `https://example.com` 会被拒（scheme 不对），这正是它该拦住的错。

---

## 谁读它

| 场合 | 谁 | 做什么 |
| --- | --- | --- |
| 启动 | `ts-core::Client::new` | 读进缓存；读坏了就**空书签簿 + 一条 `warn`**，文件保留 |
| 列出 | FFI `nightcord_bookmarks` | `command_result` 名为 `bookmarks` |
| 整表替换 | FFI `nightcord_update_bookmarks` | 删除与重命名走这条 |
| 从地址新增 | FFI `nightcord_add_bookmark` | core 解析地址、upsert、存盘，**回答里带回新列表** |

新增走一条独立命令而不是让前端拼好整表：地址解析与「同地址就替换」这两条规则因此
只有一份实现。`upsert` 按 host+port 匹配而不是按名字——名字是用户随时会改的标签，
而同一台服务器在列表里出现两次，正是列表悄悄变脏的方式。

FFI 这条链路上**没有** `apply_*` 对应物（设置那边有）：书签不改变任何正在跑的东西。

---

## 界面上在哪

| 位置 | 行为 |
| --- | --- |
| 连接页 | 「已保存的服务器」列表在最上面；点一项**填入**表单（还可以改）再点连接 |
| 连接页 | 「保存这个服务器」把表单里的地址/昵称/密码存下来，只问一个名字 |
| 连接页 | 每行尾部菜单：重命名 / 删除 |
| 服务器切换器 | 「已保存」一段；点一项**直接连接** |

两处行为不同是刻意的：连接页是「新建连接」，所以填进去还能改；切换器是「再开一个」，
已经存下来的服务器没什么好改的。合并规则（书签有主张的地方用书签、其余用设置填）
只有一份实现，在 `ConnectRequest.fromBookmark`。

书签存下来时若昵称为空，表示「用设置里的默认昵称」——所以以后改默认昵称，
没单独设过的书签会跟着变。这正是默认值的意思。

---

## 已知取舍

- **不存身份档**。`Client::identities()` 的文档写着「so a front-end can list or forget
  profiles」，但 `IdentityStore` 根本没有列举 API，FFI 也没有任何身份命令。
  加这个字段之前得先补那套；现在每个连接都用设置里的档。
- **不存频道密码 / 特权码 / 默认频道**。连接页没有对应的输入框，
  加字段等于加一套没有入口的界面。
- **不能「保存当前正在连的服务器」**。从表单保存是这一轮做的；从会话保存更自然，
  但要先把地址与昵称从会话里取出来。
- **协议字段暂时是死的**。连接页的 TS3/TS6 选择器里 TS6 那一档是禁用的，
  所以界面上存不出 ts6 的条目——但字段留着，手改文件或以后的 CLI 能用。

---

## 相关

- `crates/ts-settings/src/bookmarks.rs` —— 模型与 store
- `crates/ts-settings/src/store.rs` —— 两个 store 共用的原子读写
- [`docs/settings.md`](settings.md) —— 另一个文件，住在同一个目录
- [`docs/architecture.md`](architecture.md) —— 为什么模型不能留在 `ts-protocol`
