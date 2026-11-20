# Antigravity 黑屏修复（自动走代理）

当前版本：`1.2.1`

> 一键修复 Antigravity（Google Gemini 编码工具）启动后**窗口黑屏 / 空白**的问题。
> 自动定位 Antigravity 安装位置、自动探测本地代理端口，生成可双击的代理启动入口。

## 为什么会黑屏？

Antigravity 的语言服务器（一个 Go 编写的后端程序）**不读取“系统代理”设置**（Windows 注册表代理、macOS 系统代理都一样不读），它只认 `HTTP_PROXY` / `HTTPS_PROXY` 环境变量。Windows 和 macOS 上黑屏的根因与修法完全一致。

如果你的网络无法直接访问 Google（需要代理才能上），就会出现这种情况：

- 系统代理明明开着（浏览器能上 Google），但 Antigravity 依然**裸连** Google 的服务器；
- 连不上 → 它的内部登录页一直加载超时（日志里表现为 `ERR_TIMED_OUT`、`dial tcp ... connectex`）；
- 结果就是：进程在跑、窗口标题在，但**页面黑屏 / 一片空白**。

## Windows 版做了什么

1. **自动定位** `Antigravity.exe`（读取注册表中的 `DisplayIcon` / `InstallLocation`，并扫描常见安装目录）；
2. **自动探测**你的本地代理端口（先读系统代理设置，再用 `curl` 实测 7890 / 7897 / 7899 / 7891 / 10809 / 10808 / 10811 / 1080 / 8888 / 2080 等常见端口能否连到 Google，连不上就跳过继续试下一个）；
3. 在 `fix-antigravity.cmd` 所在文件夹生成可双击的 `launch-antigravity.cmd` 和同目录的 `start-antigravity.ps1`，兼容中文路径和 `Program Files` 中的安装。脚本通过可见的控制台执行，遵循当前 PowerShell 执行策略，并只向 Antigravity 进程和它的子进程传入 `HTTP_PROXY`、`HTTPS_PROXY` 和 `ALL_PROXY`。
4. 默认请求当前会话的 Antigravity 窗口正常退出，再带着代理环境变量启动。若旧实例仍在运行，脚本会提示完全退出后再双击 `launch-antigravity.cmd`。

## 给普通用户：双击运行（推荐）

下载与当前源码对应的 [antigravity-proxy-fix.zip](release/antigravity-proxy-fix.zip)，或在 [Releases](../../releases) 选择已发布的版本。解压到当前用户可写的文件夹，然后按平台进入对应子目录：

```
antigravity-proxy-fix/
├── README.md / VERSION / LICENSE
├── windows/    # Windows 版（fix-antigravity.cmd + antigravity-proxy-fix.ps1）
└── macos/      # macOS 版（fix-antigravity-mac.command + antigravity-proxy-fix.sh）
```

**Windows**：进入 `windows/` 目录，以普通用户身份双击 **`fix-antigravity.cmd`**。从源码运行时，直接双击仓库根目录里的同名文件。按任意键开始配置，随后可双击脚本输出的 `launch-antigravity.cmd` 打开应用。Windows PowerShell 的执行策略须允许加载脚本。

**macOS**：见下方「macOS 用户」一节。

> 同一目录里的入口脚本和主脚本要放在一起（`.cmd` 会调用同目录的 `.ps1`，`.command` 会调用同目录的 `.sh`），整个子目录一起移动即可。

运行**前提**：Antigravity 已安装，且你的**代理客户端（如 Clash Verge / Clash / v2rayN 等）正在运行**。

## macOS 用户：终端运行

Mac 上黑屏的根因和 Windows 完全一样，修复思路也一样。下载 zip 解压后，打开「终端」，`cd` 进入 `macos/` 目录（或克隆仓库后进入仓库根目录）运行：

```bash
# 双击运行等价（也可在 Finder 里双击 .command 文件）
bash fix-antigravity-mac.command

# 或直接运行主脚本
bash antigravity-proxy-fix.sh                 # 自动探测 + 修复 + 重启
bash antigravity-proxy-fix.sh --port 7890     # 明确指定端口
bash antigravity-proxy-fix.sh --probe-only    # 只探测，不改动任何东西
bash antigravity-proxy-fix.sh --skip-relaunch # 只生成包装 App + 替身，不重启
```

运行**前提**：Antigravity 已装在 `/Applications`（或 `~/Applications`），且代理客户端正在运行。

### macOS 版做了什么

1. **自动定位** `Antigravity.app`（依次查 `/Applications`、`~/Applications`，目录名模糊匹配，最后用 Spotlight 兜底）；
2. **自动探测**本地代理端口：先读 macOS 系统代理（`scutil --proxy`），再逐一 `curl` 实测常见端口（Clash 系 7890/7897/7899/7891、Surge 6152/6153、v2rayN/sing-box 10809/10808/10811、老 ClashX 1087、Shadowsocks 1080 等），实测通到 Google 才算数；只开 SOCKS 的端口也能自动识别，并以 `socks5://` 方式注入；
3. 在 `~/Applications` 生成**包装 App：`Antigravity (Proxy).app`**。双击它会为 Antigravity 进程和子进程设置 `HTTP_PROXY / HTTPS_PROXY / ALL_PROXY`。图标自动取自 Antigravity 本体；
4. 在**桌面**创建指向包装 App 的替身（alias；若系统拒绝了 Finder 自动化权限，则自动退化为符号链接）；可以把包装 App 拖进 Dock 或启动台使用；
5. （默认）结束 Antigravity 进程并经包装 App 重启，完成修复。

### macOS 常见问题

- **“无法打开，因为无法验证开发者”**：右键该文件 →「打开」一次；或到 系统设置 → 隐私与安全性 → 点「仍要打开」。
- **双击 `.command` 没反应 / 提示没有执行权限**：个别解压工具会丢掉可执行位，用 `bash fix-antigravity-mac.command` 运行，或先执行 `chmod +x fix-antigravity-mac.command`。
- **想还原**：删掉 `~/Applications/Antigravity (Proxy).app` 和桌面上的替身，直接打开原 Antigravity 即可。
- **更新后又黑屏**：和 Windows 版一样，重跑一次本脚本即可（它会重新探测端口、重新生成包装 App）。

## 给高级用户：直接跑 PowerShell（Windows）

```powershell
# 自动探测 + 修复 + 重启（最常用）
powershell -NoProfile -File .\windows\antigravity-proxy-fix.ps1

# 明确指定代理端口（跳过自动探测）
powershell -NoProfile -File .\windows\antigravity-proxy-fix.ps1 -ProxyPort 7890

# 只探测，不改动任何东西
powershell -NoProfile -File .\windows\antigravity-proxy-fix.ps1 -ProbeOnly

# 只生成启动脚本，不重启 Antigravity
powershell -NoProfile -File .\windows\antigravity-proxy-fix.ps1 -SkipRelaunch
```

### 参数说明

| 参数 | 作用 |
|------|------|
| `-ProxyPort <端口>` | 手动指定 1 到 65535 之间的代理端口，跳过自动探测 |
| `-ProbeOnly` | 只检测（Antigravity 位置 / 代理端口），不做任何修改 |
| `-SkipRelaunch` | 只生成启动脚本，适合 Antigravity 正在工作时使用 |

### Windows 权限与启动排查

- **旧版只有以管理员身份运行才有效**。旧版会在 Antigravity 安装目录写入批处理，`Program Files` 等位置通常限制普通用户写入。请将新版修复脚本放在当前用户可写的文件夹中，再双击 `fix-antigravity.cmd`。启动器会生成在同一个位置。[GitHub Issue #1](../../issues/1)
- **提示旧实例仍在运行**。保存工作，通过 Antigravity 菜单完全退出，再双击 `launch-antigravity.cmd`。
- **Windows 要求以管理员身份启动 `Antigravity.exe`**。检查应用的「属性 → 兼容性」，包括「更改所有用户的设置」。若此前手动勾选了「以管理员身份运行此程序」，取消勾选后重试。如果管理员权限由安装版本或组织策略要求，请联系管理员。
- **旧的 `Antigravity (Proxy).lnk` 被隔离**。保留隔离状态，使用新版脚本在当前文件夹生成的 `launch-antigravity.cmd`。
- **PowerShell 策略拒绝加载脚本**。请按设备的脚本执行要求使用受信任的版本。由组织管理的设备可联系管理员。

## 修复之后

- 保持代理客户端运行，双击修复脚本旁的 `launch-antigravity.cmd` 打开应用。使用本地 HTTP 代理即可，TUN 模式可保持关闭。
- 代理端口或 Antigravity 安装路径变更后，重新运行脚本即可更新启动器。

要还原 Windows 的启动方式，可以直接打开原版 Antigravity，并移除生成的 `launch-antigravity.cmd` 和 `start-antigravity.ps1`。如果旧版更改过 `Antigravity` 快捷方式，可以用 `Antigravity.exe` 重新创建该快捷方式。

## 技术原理（简述）

Antigravity 界面由 Electron 加载本地的 `https://127.0.0.1:<动态端口>/` 页面；该页面由 `language_server.exe` 提供，而后端启动时要向 `oauth2.googleapis.com`、`daily-cloudcode-pa.googleapis.com`、`generativelanguage.googleapis.com` 请求鉴权与配置。

`language_server.exe` 是 Go 程序，遵循 Go 标准代理环境变量（`HTTP_PROXY` / `HTTPS_PROXY`），但**不读取 Windows 系统代理**。因此通过启动器注入这两个环境变量，让整个进程树（含 `language_server.exe`）走本地代理，鉴权成功 → 内部页面正常加载 → 不再黑屏。

验证成功的日志标志（`language_server.log`）：

```
Auth succeeded, refreshing features and managers
State refresh took 6xx ms
initialized server successfully in X.XXs
```

而修复前的典型报错：

```
Failed to load URL: https://127.0.0.1:xxxx/ with error: ERR_TIMED_OUT
dial tcp 64.233.188.95:443: connectex: A connection attempt failed ...
```

---

## 目录结构

```
antigravity-proxy-fix/
├── README.md                     # 本文档
├── antigravity-proxy-fix.ps1     # Windows 主脚本（PowerShell，UTF-8 with BOM）
├── fix-antigravity.cmd           # Windows 双击入口（包装调用主脚本）
├── antigravity-proxy-fix.sh      # macOS 主脚本（Bash，LF 换行）
├── fix-antigravity-mac.command   # macOS 双击入口（在终端中运行主脚本）
├── VERSION                       # 当前版本号
├── LICENSE                       # MIT 许可证
└── release/                      # GitHub Releases 产物
    └── antigravity-proxy-fix.zip # Windows：解压后双击 fix-antigravity.cmd
                                  # macOS  ：解压后运行 bash macos/fix-antigravity-mac.command
```

## License

MIT
