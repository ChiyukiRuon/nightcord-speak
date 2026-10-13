# 网页部署指南

网页部署包含两部分：Flutter 静态网页和 Rust WebSocket 网关。本文以
**Cloudflare Pages 托管网页、Docker Compose 部署网关、Nginx 提供 WSS** 为主流程，
也提供自行托管静态网页的步骤。

所有命令未特别说明时均在仓库根目录执行。以下域名需要替换成自己的域名：

| 用途               | 示例地址                         |
| ------------------ | -------------------------------- |
| 用户访问的网页     | `https://speak.example.com`    |
| 网页连接的网关     | `wss://gateway.example.com/ws` |
| 宿主机上的网关入口 | `http://127.0.0.1:8787`        |

## 1. 准备环境

网关服务器需要 Linux amd64 或 arm64、Docker Engine 和 Docker Compose v2。
使用宿主机 Nginx 反向代理时，还需要 Nginx、Certbot，以及指向该服务器的
`gateway.example.com` DNS 记录。证书申请和 HTTPS 访问需要开放服务器的 TCP 80／443；
网关的 8787 保持仅监听宿主机回环地址。

网页与网关都要提供受浏览器信任的 HTTPS／WSS，才能在手机或其他远程设备上使用
麦克风与浏览器音频。本机 `localhost` 的开发例外不适用于局域网 IP。

使用已发布网关镜像时，服务器只需准备 `docker-compose.yaml` 和 `.env`
（从 `.env.example` 复制后修改），不需要 `apps/`、Rust 或完整源码。

需要从源码构建网关时，取得完整源码：

```bash
git clone --recurse-submodules https://github.com/ChiyukiRuon/nightcord-speak.git
cd nightcord-speak
```

已有工作目录则初始化子模块：

```bash
git submodule update --init --recursive
```

从源码构建网关镜像时必须有 `vendor/tsclientlib` 的嵌套 declarations 子模块。
网关镜像自带编译工具，不要求宿主机安装 Rust 或 Flutter。

## 2. 配置并启动网关

首次部署复制环境配置：

```bash
cp .env.example .env
```

编辑 `.env`，例如：

```dotenv
NIGHTCORD_GATEWAY_IMAGE=ghcr.io/chiyukiruon/nightcord-speak-gateway:main
NIGHTCORD_GATEWAY_HOST=127.0.0.1
NIGHTCORD_GATEWAY_PORT=8787
NIGHTCORD_GATEWAY_ORIGINS=https://speak.example.com
NIGHTCORD_GATEWAY_TOKEN=<替换为自己生成的随机Token>
NIGHTCORD_GATEWAY_PROFILE=web
NIGHTCORD_GATEWAY_LOG=info
NIGHTCORD_GATEWAY_TZ=Asia/Shanghai
```

### `.env` 变量说明

下面列出 `.env.example` 中的全部变量。默认值来自 `docker-compose.yaml`，未设置或
留空时使用该默认值；Token 和允许来源的空值行为见表中说明。

| 变量                          | 默认值                                               | 用途与配置示例                                                                                                                                                                                                                             |
| ----------------------------- | ---------------------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `NIGHTCORD_GATEWAY_IMAGE`   | `ghcr.io/chiyukiruon/nightcord-speak-gateway:main` | 指定要拉取、运行或本地构建所用的镜像名称与标签。`main` 跟随主分支，可改成完整版本、`sha-<完整提交哈希>` 或 `镜像名@sha256:<digest>` 固定部署版本。                                                                                   |
| `NIGHTCORD_GATEWAY_HOST`    | `127.0.0.1`                                        | 网关端口在**宿主机**上绑定的地址。默认供同机 Nginx 或隧道访问；局域网直连时可设为 `0.0.0.0`，监听所有 IPv4 网卡。这是监听地址，不是网页构建使用的网关 URL。                                                                        |
| `NIGHTCORD_GATEWAY_PORT`    | `8787`                                             | 发布到宿主机的 TCP 端口。容器内部仍使用 8787；例如设为`18787` 后，宿主机代理的上游改为 `http://127.0.0.1:18787`。                                                                                                                      |
| `NIGHTCORD_GATEWAY_ORIGINS` | 空                                                   | 允许访问网关的**浏览器网页来源**，多个值用逗号分隔且不加空格，例如 `https://speak.example.com,https://your-project.pages.dev`。非空时替换默认列表；留空只允许 `localhost`、`127.0.0.1`、`::1` 等本机来源，并非允许任意网站。 |
| `NIGHTCORD_GATEWAY_TOKEN`   | 空                                                   | 网关访问令牌，非空时要求客户端通过 Token 鉴权，空字符串表示关闭鉴权。预设网关地址的网页必须在构建时配置相同 Token。使用自己生成的随机值，不要使用示例占位文字。                                                                            |
| `NIGHTCORD_GATEWAY_PROFILE` | `web`                                              | 连接请求未指定档名时使用的默认身份档名。身份档由使用者在网页的「设置 → 连接 → 身份配置」里自选，各设备独立保存；修改本值只影响未指定档名的连接，已选定的设备不受影响。                                                                   |
| `NIGHTCORD_GATEWAY_LOG`     | `info`                                             | 网关日志过滤条件，Compose 将其传给容器的`RUST_LOG`。可设为 `warn`、`info`、`debug`，或使用 `info,ts_gateway=debug` 只提高网关模块的日志详细程度。                                                                                |
| `NIGHTCORD_GATEWAY_TZ`      | `Asia/Shanghai`                                    | 容器时区，影响日志时间及按本地日期轮转。可使用`Asia/Shanghai`、`Asia/Hong_Kong`、`UTC` 等时区名称。                                                                                                                                  |

允许来源按协议与主机名匹配，当前实现不区分端口、不支持通配符；需要使用的每个
网页域名应分别列出。来源限制用于浏览器连接，Token 则用于网关鉴权。

Compose 优先使用启动命令所在 shell 中的同名环境变量，再读取 `.env`。如果文件
修改后仍使用旧值，也要检查 shell 是否保留了同名变量。修改 `.env` 后执行
`docker compose up -d --no-build` 应用运行配置；更换镜像版本时先执行
`docker compose pull`。

**网页构建变量不属于这份 Compose 配置：**`NIGHTCORD_GATEWAY_URL` 只在网页构建
平台或构建 shell 中设置。`NIGHTCORD_GATEWAY_TOKEN` 虽然同名，仍需要分别配置在
网关 `.env` 和网页构建环境中；复制 `.env` 不会自动把 Token 传给网页构建脚本。
`FLUTTER_VERSION`、`PYTHON_VERSION` 也用于网页构建环境，见第 4 节。

### 启动服务

允许多个网页来源时，用逗号分隔且不加空格，例如：

```dotenv
NIGHTCORD_GATEWAY_ORIGINS=https://speak.example.com,https://your-project.pages.dev
```

Origin 是网页的协议和域名，不是网关地址，不带路径或末尾 `/`。每个需要访问的
Pages 预览域名也必须单独加入。非空配置会替换默认的本机来源列表。

Token 非空时启用网关鉴权；不启用鉴权时将该项留空。`.env` 不提交到 Git。
**下面配置网页时，如果预设了网关地址并启用了鉴权，必须使用相同 Token。**

镜像已发布到 GHCR 时运行：

```bash
docker compose pull
docker compose up -d --no-build
```

镜像尚未发布或需要从当前源码部署时，在完整源码目录中显式叠加构建配置：

```bash
docker compose -f docker-compose.yaml -f docker-compose.build.yaml up -d --build --pull never
```

`docker compose` 自动读取根目录的 `docker-compose.yaml`。GHCR 包若为私有，
先登录 `docker login ghcr.io`；需要免登录拉取时由包所有者将包设为 Public。

检查服务：

```bash
docker compose ps
curl --fail http://127.0.0.1:8787/ --output /dev/null
docker compose logs --tail 100 gateway
```

`healthy` 表示网关已启动。8787 根路径是内嵌诊断页，产品网页在后面的步骤部署。
若宿主机端口冲突，修改 `NIGHTCORD_GATEWAY_PORT`，并同步修改反向代理的上游端口。

## 3. 为网关配置 WSS

以下示例在 **宿主机 Nginx** 上使用。将配置保存为
`/etc/nginx/conf.d/nightcord-gateway.conf`，替换域名和必要的上游端口：

```nginx
server {
    listen 80;
    server_name gateway.example.com;

    location = /ws {
        proxy_pass http://127.0.0.1:8787;
        proxy_http_version 1.1;
        proxy_set_header Host $host;
        proxy_set_header Origin $http_origin;
        proxy_set_header Upgrade $http_upgrade;
        proxy_set_header Connection "upgrade";
        proxy_read_timeout 3600s;
        proxy_send_timeout 3600s;
        proxy_buffering off;
    }

    location / {
        return 404;
    }
}
```

这里保留原始 `Origin`，由网关校验网页来源，并显式转发 WebSocket 升级头。
仅代理 `/ws`，网关诊断页继续在本机访问。Nginx 的 WebSocket 转发要求见
[官方说明](https://nginx.org/en/docs/http/websocket.html)。

检查并加载配置：

```bash
sudo nginx -t
sudo systemctl reload nginx
```

按照 [Certbot 的 Nginx 安装说明](https://certbot.eff.org/instructions?ws=nginx&os=snap)
安装 Certbot 后，申请证书并让其配置 HTTPS：

```bash
sudo certbot --nginx -d gateway.example.com
sudo nginx -t
sudo certbot renew --dry-run
```

证书配置完成后，网页使用 `wss://gateway.example.com/ws`。Certbot 管理证书续期，
保留它安装的自动续期任务。若已有证书或 HTTPS 反向代理，可将上述 `/ws` 转发配置
加入现有 HTTPS 站点。

如果 Nginx 运行在另一个容器中，需要接入网关的 Compose 网络，并使用
`http://gateway:8787` 作为上游；容器里的 `127.0.0.1` 指向它自身。
也可使用已有的正式 HTTPS 隧道提供网关入口，网页的 WSS 地址与允许来源仍按本文配置。

## 4. 部署网页

### 方式 A：Cloudflare Pages

在 Cloudflare 控制台创建 Pages 项目，连接包含部署脚本的 GitHub 仓库。
按以下内容配置构建：

| 配置项                              | 值                               |
| ----------------------------------- | -------------------------------- |
| 生产分支                            | `main`                         |
| Framework preset                    | `None`                         |
| Root directory                      | 仓库根目录，留空                 |
| Build command                       | `bash scripts/build-pages.sh`  |
| Build output directory              | `apps/client/build/web`        |
| 环境变量`FLUTTER_VERSION`         | `3.47.5`                       |
| 环境变量`PYTHON_VERSION`          | `3.12`                         |
| 环境变量`NIGHTCORD_GATEWAY_URL`   | `wss://gateway.example.com/ws` |
| 环境变量`NIGHTCORD_GATEWAY_TOKEN` | 与网关相同；网关免 Token 时留空  |

构建脚本准备 Flutter SDK 和字体，并调用现有发布构建脚本。Pages 不需要编译 Rust。
构建配置与 Python 版本选择参见 [Pages 构建配置](https://developers.cloudflare.com/pages/configuration/build-configuration/)
和 [构建环境](https://developers.cloudflare.com/pages/configuration/build-image/)。

部署成功后，可以使用分配的 `https://your-project.pages.dev`，或在项目的 Custom
domains 中绑定 `speak.example.com`。按控制台提示配置 DNS；应先在 Pages 中添加
自定义域名，再完成相应 DNS 记录。操作参见
[Pages 自定义域名](https://developers.cloudflare.com/pages/configuration/custom-domains/)。

把实际使用的网页 Origin 加入网关 `.env` 的 `NIGHTCORD_GATEWAY_ORIGINS`，再运行：

```bash
docker compose up -d --no-build
```

生产与预览环境分别配置构建变量。使用预览站点时，网关也需允许该预览域名。

### 方式 B：自行托管静态网页

构建机器需要 Flutter `3.47.5` 或兼容版本、Python 3 和 Bash。安装 Flutter 后，在
仓库根目录准备字体，并通过环境变量预填网关地址：

```bash
bash scripts/fetch-fonts.sh
export NIGHTCORD_GATEWAY_URL='wss://gateway.example.com/ws'
export NIGHTCORD_GATEWAY_TOKEN='<与网关相同的Token，免Token时改为空字符串>'
python3 scripts/build-web.py
```

Windows 使用 Git Bash 执行字体脚本，其余构建命令也可在 PowerShell 中运行：

```powershell
$env:NIGHTCORD_GATEWAY_URL = 'wss://gateway.example.com/ws'
$env:NIGHTCORD_GATEWAY_TOKEN = '<与网关相同的Token，免Token时改为空字符串>'
python scripts/build-web.py
```

将 `apps/client/build/web/` 中的**全部文件和子目录**上传到静态服务器，例如
`/srv/nightcord/web/`，并确保 Nginx 用户可以读取。上传的是构建产物，不是
`apps/client/web/` 源码目录。

使用宿主机 Nginx 时，可另建 `/etc/nginx/conf.d/nightcord-web.conf`：

```nginx
server {
    listen 80;
    server_name speak.example.com;
    root /srv/nightcord/web;
    index index.html;

    add_header Cache-Control "no-cache" always;

    location / {
        try_files $uri $uri/ /index.html;
    }
}
```

让 `speak.example.com` 指向静态服务器，然后检查配置并配置 HTTPS：

```bash
sudo nginx -t
sudo systemctl reload nginx
sudo certbot --nginx -d speak.example.com
```

该示例将网页托管在域名根路径。前端与网关可在同一服务器或分别部署，浏览器始终
通过公开的 WSS 域名连接网关。

## 5. 网关地址与 Token 的生效方式

`NIGHTCORD_GATEWAY_URL` 和网页的 `NIGHTCORD_GATEWAY_TOKEN` 在**构建时**写入静态
产物。修改服务器环境变量不会改变已发布的网页，需要重新构建和上传，Pages 上则
重新触发部署。网关的 `.env` 是**运行时**配置，修改后通过 Compose 重建服务生效。
网页构建脚本不会自动读取 Compose 的 `.env`，须按上面的步骤设置构建平台或 shell
环境变量。

构建时预设了网关地址，页面会自动连接，首次加载、断线、鉴权失败或连接超时都不会
显示地址／Token 填写页；失败时只能重试原配置。预设地址也不会被 URL 的 `gw` 参数
覆盖。开启 Token 的网关和预设地址的网页必须配置相同 Token，否则部署后无法连接。

静态网页中的 Token 对访问者可见，将其在构建平台标记为 Secret 也无法隐藏浏览器
收到的值。如果需要让访问者手动输入 Token，应使用**未预设网关地址**的构建，
让访问者在连接页填写地址和 Token。免 Token 部署则让网页和网关两端均保持空值。

## 6. 验证部署

1. `docker compose ps` 中网关为 `healthy`。
2. 浏览器通过 HTTPS 打开网页，证书有效。
3. 浏览器开发者工具中，对 `wss://gateway.example.com/ws` 的连接得到 `101` 升级响应，
   随后收到网关 `welcome`；仅得到 `101` 不代表 Token／设备鉴权已完成。
4. 网页可以连接 TS 服务器、读取频道、发送消息。
5. 点击启用语音并允许麦克风权限，验证语音收发；屏幕共享还需浏览器采集授权。
6. 刷新网页后设备身份仍可恢复。换站点域名、网关 URL、浏览器资料或清除网站数据
   会改变浏览器设备边界，应保持正式部署地址稳定。

## 7. 更新、备份与排查

### 更新网关

默认 `main` 镜像由 `.github/workflows/gateway-image.yml` 自动构建；生产部署也可在
`.env` 中固定完整版本、`sha-<完整提交哈希>` 或镜像 digest。发布需要该工作流已在
远端启用并成功执行，添加 workflow 文件本身不会立即生成可拉取的镜像。

使用远端镜像时更新：

```bash
docker compose pull
docker compose up -d --no-build
```

从源码部署时，更新源码和子模块后重新执行
`docker compose -f docker-compose.yaml -f docker-compose.build.yaml up -d --build --pull never`。网页更新后重新部署完整静态产物，
Pages Git 集成则按其配置触发新部署。更换 Token 时，网关和网页需同步更新。

### 保留与备份数据

具名卷 `nightcord-gateway_gateway-data` 保存网关设备恢复凭据、TS 身份和设置。
数据位于容器 `/data/devices/`，日志位于 `/data/config/nightcord-speak/logs/`。
容器更新、重建及普通 `docker compose down` 都保留该卷。

备份前停止网关，再备份数据卷；恢复时保留 UID/GID `10001:10001` 的文件所有权。
`docker compose down --volumes` 会删除身份和设置，普通更新不要使用。
网页服务器书签保存在浏览器 localStorage，网关卷备份不包含它们。

### 常见问题

| 现象                         | 检查内容                                                                   |
| ---------------------------- | -------------------------------------------------------------------------- |
| Compose 拉取镜像失败         | 镜像工作流是否已发布；私有包是否已登录；也可从源码构建                     |
| 网关 unhealthy 或反复重启    | `docker compose logs --tail 100 gateway`；数据卷权限及宿主机端口是否可用 |
| WebSocket 返回`403`        | 网关允许来源是否包含当前网页的协议与域名；代理是否保留`Origin`           |
| WebSocket 已升级但连接失败   | 网页和服务端 Token 是否一致；是否重新构建并发布了网页                      |
| 固定地址连接失败却没有填写页 | 这是预设地址构建的行为；修正部署变量后重建，或恢复网关后重试               |
| 手机页面正常但没有语音       | 页面是否 HTTPS、网关是否 WSS、证书是否受信任、是否授权麦克风并启用音频     |
| 网页仍连接旧网关             | 是否重新部署构建产物并刷新；代理缓存是否沿用了旧脚本                       |

详细参数与设备边界见 [网关文档](docs/gateway.md)，本机／临时 HTTPS 联调见
[Web 客户端文档](docs/web-client.md)。
