# tsclientlib fork 与局域网

## 现状（已核实）

`ChiyukiRuon/tsclientlib` 是 `Moepchi/tsclientlib` 的 fork，继承了它的全部三个分支：

| 分支 | commit | 是否有 TS6 透传 |
| --- | --- | --- |
| `master`（**默认**） | `0c855bd` | ❌ 0 处 `UnknownCommand` |
| `develop` | `62e069c` | — |
| `webspeak3` | `2e77949` | ✅ 3 处 `UnknownCommand` |

关键事实：**`master` 是 `webspeak3` 的严格祖先，落后 13 个 commit。**

也就是说 `master` 不是「另一个版本」，而是 `webspeak3` 线上的一个更早的点。它缺少：

- TS6 未知命令透传（`e9dd82e`）
- TS6 的 `client_is_streaming` 字段（`6df8ba1`）
- 两个安全修复（`7361a8d`：filetransfer SSRF、license 解析越界）
- declarations 子模块指向（`40e7c1a`、`5fdf15c`）
- 以及那个局域网拦截（`2e77949`）—— 正是我们要改的

**Fork 本身是对的，只是默认分支恰好是落后的那个。** 开发基线必须是 `webspeak3`。

> `crates.io` 上的 `tsclientlib` 停在 2021 年的 `0.2.0`，与上游差距太大，不能用。

---

## 需要在你的 fork 里做的事

### 1. 从 `webspeak3` 建开发分支

```bash
git clone https://github.com/ChiyukiRuon/tsclientlib.git
cd tsclientlib
git checkout webspeak3
git checkout -b nightcord          # 或你喜欢的名字
```

**不要**从 `master` 切，也不要把它设为基线。

### 2. ~~应用局域网改动~~ ✅ 已完成

分支 `nightcord`，提交 `df38c87`，已推送到 `ChiyukiRuon/tsclientlib`。

改动只有一个函数（`tsclientlib/src/resolver.rs`）：

```rust
pub fn is_allowed_target(ip: &IpAddr) -> bool {
	let strict = std::env::var("BLOCK_PRIVATE_TARGETS").is_ok_and(|v| v == "1");
	!strict || is_public_addr(ip)
}
```

即**把默认反过来**：原生客户端默认允许私有地址，`BLOCK_PRIVATE_TARGETS=1`
才恢复上游的严格行为。原 `ALLOW_PRIVATE_TARGETS=1` 不再需要。

补丁保留在 [`tsclientlib-fork.patch`](tsclientlib-fork.patch)，作为改动内容的记录。

### 3. 顺手修掉的一个问题

你的克隆里 `utils/tsproto-structs/declarations` 曾经停在 `83cb8a9`，
而 `webspeak3` 记录的是 `c2992f94` —— 即子模块被一次普通的
`submodule update` 带到了别的提交上。已用
`git submodule update --init --recursive --force` 复原。

这个如果不修，构建行为会与本仓库不一致（declarations 是编译期
`include_str!` 的输入）。

### 4. 本仓库已指向该 fork ✅

```text
.gitmodules
  url    = https://github.com/ChiyukiRuon/tsclientlib.git
  branch = nightcord
```

submodule 当前 pin 在 `df38c87`。本地的临时补丁已丢弃——改动现在是正式版本。

---

## 为什么这样改是安全的

上游默认拦截私有地址，是因为 **WebSpeak3 是服务端进程**：浏览器提交地址，
连接打到宿主内网就是 SSRF。**原生客户端没有这个威胁模型**——地址是坐在键盘前的
人自己填的，局域网服务器是常态。

文件传输那条**不受影响**。已核实调用点：

| 位置 | 用途 | 是否受影响 |
| --- | --- | --- |
| `tsclientlib/src/lib.rs:509` | 语音服务器地址 | ✅ 受影响 ← 要放宽的 |
| `tsclientlib/src/resolver.rs:450` | TSDNS 主机 | ✅ 受影响 |
| `tsclientlib/src/lib.rs:1520` | 文件传输重定向 | ❌ **不受影响** |

文件传输那条直接调用 `is_public_addr`，逻辑是「只有在语音对端本身就是内网地址时，
才接受服务器上报的内网传输地址」——它防的是**服务器**把连接引向别处，与上面的改动无关。

> **更正**：我早先说过「设环境变量会一并关掉 filetransfer 的 SSRF 防护」，**这是错的**。
> 上面的表格是核实后的结论。

---

## 为什么不用环境变量绕过

`nightcord_create()` 里调 `std::env::set_var` 在 edition 2024 下是 `unsafe`，
且必须在任何线程启动前调用——而 Flutter 引擎自身已有 UI/raster/IO 多个线程在跑，
与它们的 `getenv` 竞争正是该 API 被标记为 unsafe 的原因。fork 是唯一不需要 unsafe 的路。

---

## 状态：已完结

不再需要环境变量，也不再有本地补丁。已实测：
**不带 `ALLOW_PRIVATE_TARGETS`、不带 `BLOCK_PRIVATE_TARGETS`**，
直接连上 `192.168.31.128:9987`。

上溯关系：

```text
Moepchi/tsclientlib : webspeak3   (2e77949)
        │
        └── ChiyukiRuon/tsclientlib : nightcord   (df38c87)  ← 本仓库 pin 在这里
```

`webspeak3` 在 fork 里保持原样未动，所以以后从上游拉更新仍是一次快进。
局域网改动只存在于 `nightcord` 分支，不会混进上游分支。
