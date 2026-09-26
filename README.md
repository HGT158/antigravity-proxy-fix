# Antigravity 黑屏修复（自动走代理）

当前版本：`1.1.0`

> 一键修复 Antigravity（Google Gemini 编码工具）启动后**窗口黑屏 / 空白**的问题。
> 自动定位 Antigravity 安装位置、自动探测本地代理端口，生成走代理的启动器并把快捷方式指过去，之后双击图标即可正常打开。

## 为什么会黑屏？

Antigravity 的语言服务器（一个 Go 编写的后端程序）**不读取“系统代理”设置**（Windows 注册表代理、macOS 系统代理都一样不读），它只认 `HTTP_PROXY` / `HTTPS_PROXY` 环境变量。Windows 和 macOS 上黑屏的根因与修法完全一致。

如果你的网络无法直接访问 Google（需要代理才能上），就会出现这种情况：

- 系统代理明明开着（浏览器能上 Google），但 Antigravity 依然**裸连** Google 的服务器；
- 连不上 → 它的内部登录页一直加载超时（日志里表现为 `ERR_TIMED_OUT`、`dial tcp ... connectex`）；
- 结果就是：进程在跑、窗口标题在，但**页面黑屏 / 一片空白**。

## 这个脚本做了什么

1. **自动定位** `Antigravity.exe`（读取注册表中的 `DisplayIcon` / `InstallLocation`，并扫描常见安装目录）；
2. **自动探测**你的本地代理端口（先读系统代理设置，再用 `curl` 实测 7890 / 7897 / 7899 / 7891 / 10809 / 10808 / 10811 / 1080 / 8888 / 2080 等常见端口能否连到 Google，连不上就跳过继续试下一个）；
3. 在 Antigravity 安装目录生成启动器 `launch-antigravity.bat`，启动时自动注入 `HTTP_PROXY / HTTPS_PROXY / ALL_PROXY = http://127.0.0.1:<端口>`；
   （启动器里用 `%~dp0` 定位同目录的 `Antigravity.exe`，不写死绝对路径，因此**中文用户名 / 中文安装路径**都能正常工作）
4. 把 **桌面** 与 **开始菜单** 的快捷方式都指向这个启动器；
5. （可选）重启 Antigravity 完成修复。

## 给普通用户：双击运行（推荐）

在 [Releases](../../releases) 页面下载最新版 `antigravity-proxy-fix.zip`：

1. 解压 zip（里面是 `fix-antigravity.cmd`、`antigravity-proxy-fix.ps1`、`VERSION`、本 README 和 LICENSE）；
2. 双击 **`fix-antigravity.cmd`**；
3. 按提示按任意键，脚本会自动定位 Antigravity、探测代理端口并完成修复。

> 不要把 `.cmd` 和 `.ps1` 分开移动 —— `.cmd` 会调用同目录下的 `.ps1`，两者要放在一起。

运行**前提**：Antigravity 已安装，且你的**代理客户端（如 Clash Verge / Clash / v2rayN 等）正在运行**。

## macOS 用户：终端运行

Mac 上黑屏的根因和 Windows 完全一样，修复思路也一样。下载 zip（或克隆仓库）解压后，打开「终端」，`cd` 进入目录运行：

```bash
# 双击运行等价（推荐普通用户；也可在 Finder 里双击 .command 文件）
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
3. 在 `~/Applications` 生成**包装 App：`Antigravity (Proxy).app`**（对应 Windows 版的 `launch-antigravity.bat`）。双击它 = 带着 `HTTP_PROXY / HTTPS_PROXY / ALL_PROXY` 环境变量启动 Antigravity，环境变量只作用于 Antigravity 进程树，不污染系统、不影响其它 App；图标自动取自 Antigravity 本体；
4. 在**桌面**创建指向包装 App 的替身（alias；若系统拒绝了 Finder 自动化权限，则自动退化为符号链接）；可以把包装 App 拖进 Dock 或启动台使用；
5. （默认）结束 Antigravity 进程并经包装 App 重启，完成修复。

### macOS 常见问题

- **“无法打开，因为无法验证开发者”**：右键该文件 →「打开」一次；或到 系统设置 → 隐私与安全性 → 点「仍要打开」。
- **双击 `.command` 没反应 / 提示没有执行权限**：从 Windows 打包的 zip 会丢失可执行位，请用 `bash fix-antigravity-mac.command` 运行，或先执行 `chmod +x fix-antigravity-mac.command`。
- **想还原**：删掉 `~/Applications/Antigravity (Proxy).app` 和桌面上的替身，直接打开原 Antigravity 即可。
- **更新后又黑屏**：和 Windows 版一样，重跑一次本脚本即可（它会重新探测端口、重新生成包装 App）。

## 给高级用户：直接跑 PowerShell（Windows）

```powershell
# 自动探测 + 修复 + 重启（最常用）
powershell -ExecutionPolicy Bypass -File .\antigravity-proxy-fix.ps1

# 明确指定代理端口（跳过自动探测）
powershell -ExecutionPolicy Bypass -File .\antigravity-proxy-fix.ps1 -ProxyPort 7890

# 只探测，不改动任何东西
powershell -ExecutionPolicy Bypass -File .\antigravity-proxy-fix.ps1 -ProbeOnly

# 只生成启动器和快捷方式，不重启 Antigravity
powershell -ExecutionPolicy Bypass -File .\antigravity-proxy-fix.ps1 -SkipRelaunch
```

### 参数说明

| 参数 | 作用 |
|------|------|
| `-ProxyPort <端口>` | 手动指定代理端口，跳过自动探测 |
| `-ProbeOnly` | 只检测（Antigravity 位置 / 代理端口），不做任何修改 |
| `-SkipRelaunch` | 只生成启动器 + 改快捷方式，不结束进程、不重启 |

## 修复之后

- **以后打开 Antigravity 只需两步**：① 代理客户端保持运行；② 双击桌面图标。
- 不再需要为 Antigravity 手动开 TUN 模式 —— 它走的是 HTTP 代理，不依赖 TUN。
- 系统代理开关对 Antigravity 无效（它不读），但请保留给浏览器等其它软件用。

## 又黑屏了？重跑一次脚本就行

已经修复过、用了一段时间后又出现黑屏，基本都是这两种情况：

1. **Antigravity 更新或重装**：自动更新会覆盖安装目录里的 `launch-antigravity.bat`，还可能把桌面 / 开始菜单的快捷方式重置回原始的 `Antigravity.exe`（不带代理环境变量），于是又恢复成裸连。
2. **代理端口变了**：换了代理客户端、或改过端口设置，启动器里写死的旧端口就失效了。

两种情况都不用排查，**双击 `fix-antigravity.cmd` 重跑一次本脚本即可**：它会重新探测当前可用的代理端口、重新生成启动器，并把快捷方式重新指过去。建议每次 Antigravity 更新之后都重跑一次。

## 注意事项

- 本脚本**只改动用户自己的目录**（Antigravity 安装目录内生成一个 `.bat`、桌面/开始菜单快捷方式），**不需要管理员权限**，不写系统级环境变量，不会影响其它程序。
- 修改快捷方式前会自动跳过不存在的入口；**不会删除**任何原文件（脚本生成的 `launch-antigravity.bat` 是可选的，删掉它、把快捷方式指回 `Antigravity.exe` 即可还原）。
- **中文用户名 / 中文路径已适配**：启动器用 `%~dp0` 定位 `Antigravity.exe`，不把含中文的绝对路径写进 `.bat`（Windows 的 `cmd.exe` 按代码页读批处理，中文字符可能变成 `?` 导致找不到程序）。注册表路径支持引号、图标索引和环境变量，目录扫描使用字面路径并只接受真实文件；桌面目录也改为向系统查询，兼容 OneDrive 重定向等情况。
- 本脚本与 Google / Antigravity 官方无任何关联，仅供学习交流。

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
                                  # macOS  ：解压后运行 bash fix-antigravity-mac.command
```

## License

MIT
