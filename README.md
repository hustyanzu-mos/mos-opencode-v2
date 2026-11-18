# OpenCode v2 MOS Plugin

在 **MOS NAS**（不可变、运行于 RAM 的 Devuan 系统）上安装并管理
[OpenCode](https://opencode.ai) v2 的插件实现。

这是 `mos-opencode` 的 v2 分支，重点解决：

- 官方插件的 `releases/latest` 仍指向 v1，点 Update 可能把 v2 降级
- OpenCode 自更新 / TUI 的 `/update` 会绕过 MOS 的版本记录
- OpenCode 二进制很大，60 秒的 MOS API 超时会截断下载
- OpenCode 的 background server 默认不应该开放

---

## 特性

- 从 GitHub Release 安装 `opencode-linux-{x64,arm64}.tar.gz`
- 校验 release 的 `SHA256SUMS`
- 版本选择取最高的稳定 `v2.x.y`，也可以 `pin_version`
- 异步安装，页面轮询进度，不受 60 秒 API 超时限制
- 二进制、config、data、state 全部持久化
- **禁用 OpenCode 自动更新**
- **TUI 的 `/update` 无法安装更新**
- **server 默认关闭**，不监听任何端口；需要时再打开
- server 支持 hostname / port / password / CORS
- 卸载二进制时保留 config、data、sessions

---

## 与官方 `mos-opencode` 的区别

| | 官方 `mos-opencode` | 本插件 |
| --- | --- | --- |
| 版本选择 | GitHub `releases/latest`（目前是 v1） | 最高稳定 v2 或 `pin_version` |
| 校验 | 无 | `SHA256SUMS` |
| 自动更新 | 未处理 | `update:disable` + 环境变量 |
| `/update` | 实际装不了，但可能提示更新 | 实际装不了，且后台检查也关闭 |
| server | 默认直接 `serve`，端口 4096 | 默认关闭；可选 `serve --service` |
| 下载 | 同步，可能 60 秒超时 | 异步后台下载 + 轮询 |
| 插件内部名 | `opencode` | `opencode-v2` |

本插件直接使用 `/usr/bin/opencode`，和官方 `mos-opencode` 一致。
安装前请确认没有同时安装官方 OpenCode 插件。

---

## 持久化

```text
/boot/optional/plugins/opencode-v2/
├── bin/opencode             # 持久化二进制
├── settings.json
├── opencode.log             # server 日志
├── install.log              # 安装日志
└── data/                    # data_home 为空时的 fallback
```

用户选择的 `data_home`：

```text
$data_home/opencode-v2/
├── config/opencode/         # XDG_CONFIG_HOME
├── data/                    # XDG_DATA_HOME
└── state/                   # XDG_STATE_HOME（service 注册）
```

运行时：

```text
/usr/bin/opencodeorig        # 从 /boot 复制，解决 noexec
/usr/bin/opencode            # wrapper
/var/run/mos-opencode.pid
```

| 内容 | 位置 | 重启后 |
| --- | --- | --- |
| 二进制 | `/boot/optional/plugins/opencode-v2/bin/opencode` | 保留 |
| 运行时副本 | `/usr/bin/opencodeorig` | RAM，`mos_start` 恢复 |
| 插件设置 | `/boot/optional/plugins/opencode-v2/settings.json` | 保留 |
| config | `$data_home/opencode-v2/config/opencode/` | 保留 |
| data | `$data_home/opencode-v2/data/` | 保留 |
| state | `$data_home/opencode-v2/state/` | 保留 |
| PID | `/var/run/mos-opencode.pid` | 丢失 |

---

## 安装

1. 在 MOS Hub 添加索引仓库：
   ```text
   https://github.com/hustyanzu-mos/mos-templates
   ```
2. 安装 **OpenCode v2** 插件。
3. 打开插件页面，设置 **Data directory**。
4. 点 **Install**。安装是异步的，页面会轮询进度。
5. 默认 server 关闭，不需要点 Start。

OpenCode 二进制约 242MB。`/boot` 需要至少 ~250MB 空间，`/usr`（RAM）
还需要一份运行时副本。安装前请确认：

```bash
df -h /boot /usr
```

---

## 自动更新为什么被禁用

OpenCode 有三条更新路径：

1. 后台自动更新
2. TUI 的 `/update`
3. `opencode upgrade` / `opencode update` CLI

本插件的处理：

- 启动和 wrapper 都设置 `OPENCODE_DISABLE_AUTOUPDATE=1`
- 在 `$data_home/opencode-v2/config/opencode/opencode.json` 写入
  `"update": "disable"`
- `/usr/bin/opencode` 拦截 `update` / `upgrade`
- 二进制放在 `/usr/bin/opencodeorig`，不是 OpenCode 认识的
  `$HOME/.opencode/bin/opencode`，所以 TUI 的 `/update` 只会提示
  “Could not detect the installation method”，不会安装

`/update` 命令本身仍然存在，无法通过配置隐藏；但它不会产生实际更新。
更新请使用插件页面的 **Install / Update**。

---

## Server

Server 默认 **关闭**：

- 不启动 `opencode serve --service`
- 不监听端口
- 不写 PID
- SSH 里直接运行 `opencode` 仍然可用；OpenCode 会走 standalone/local server

需要远程/Web 访问时：

1. 打开 **Server** 开关
2. 设置 hostname / port / password / CORS
3. 点 **Save**
4. 点 **Start**

默认监听 `127.0.0.1`。要 LAN 访问改成 `0.0.0.0`，并建议设置密码。
Server 配置写入：

```text
$data_home/opencode-v2/config/opencode/service.json
```

`service.json` 里的 `disabled` 会随状态变化：

- server 关闭：`disabled: true`，TUI 使用 standalone/local server
- server 开启且正在运行：`disabled: false`，TUI 连接插件的后台 service
- server 开启但已停止：`disabled: true`，TUI 不会偷偷拉起 service

插件页面的 **Start** 会显式启动 service。

---

## 更新 / 卸载

更新：

- 插件页面 **Check updates** → **Update**
- 默认取最高稳定 v2；也可以 `pin_version` 固定版本
- 如果 server 在运行，会先 stop，替换二进制后 restart
- 运行中的 OpenCode 会话会随 server 重启结束；请先保存工作

卸载：

- **Uninstall binary** 只删除 `/boot` 里的二进制和 `/usr/bin/opencodeorig`
- config、data、sessions 保留
- 要彻底删除数据，手动删除 `$data_home/opencode-v2`

---

## 构建

```bash
./build.sh              # 版本取 page/plugin.config.js
./build.sh 0.1.1        # 指定版本
SKIP_PAGE=1 ./build.sh  # 复用 page/dist
```

产物：

```text
build/opencode-v2-<version>-1+mos-plugin_all.deb
build/opencode-v2-<version>-1+mos-plugin_all.deb.md5
```

GitHub Actions 在 push `X.Y.Z` tag 时构建并发布同样的 `.deb` + `.md5`。

---

## 许可

本仓库基于 `ich777/mos-opencode`（GPL-3.0）修改，继续使用 GPL-3.0。
OpenCode 本身按其上游 MIT 许可证发布，见 `THIRD_PARTY.md`。