# Antigravity 黑屏修复（自动走代理）

> 一键修复 Antigravity（Google Gemini 编码工具）启动后**窗口黑屏 / 空白**的问题。
> 自动定位 Antigravity 安装位置、自动探测本地代理端口，生成走代理的启动器并把快捷方式指过去，之后双击图标即可正常打开。

## 为什么会黑屏？

Antigravity 的语言服务器（一个 Go 编写的后端程序）**不读取 Windows 的“系统代理”设置**，它只认 `HTTP_PROXY` / `HTTPS_PROXY` 环境变量。

如果你的网络无法直接访问 Google（需要代理才能上），就会出现这种情况：

- 系统代理明明开着（浏览器能上 Google），但 Antigravity 依然**裸连** Google 的服务器；
- 连不上 → 它的内部登录页一直加载超时（日志里表现为 `ERR_TIMED_OUT`、`dial tcp ... connectex`）；
- 结果就是：进程在跑、窗口标题在，但**页面黑屏 / 一片空白**。

## 这个脚本做了什么

1. **自动定位** `Antigravity.exe`（读注册表 + 常见安装目录扫描）；
2. **自动探测**你的本地代理端口（先读系统代理设置，再用 `curl` 实测 7890 / 7897 / 7891 / 10809 / 10808 / 1080 / 8888 / 2080 等常见端口能否连到 Google）；
3. 在 Antigravity 安装目录生成启动器 `launch-antigravity.bat`，启动时自动注入 `HTTP_PROXY / HTTPS_PROXY / ALL_PROXY = http://127.0.0.1:<端口>`；
4. 把 **桌面** 与 **开始菜单** 的快捷方式都指向这个启动器；
5. （可选）重启 Antigravity 完成修复。

## 给普通用户：双击运行（推荐）

在 [Releases](../../releases) 页面下载最新版 `antigravity-proxy-fix.zip`：

1. 解压 zip（里面是 `fix-antigravity.cmd` + `antigravity-proxy-fix.ps1` + 本 README）；
2. 双击 **`fix-antigravity.cmd`**；
3. 按提示按任意键，脚本会自动定位 Antigravity、探测代理端口并完成修复。

> 不要把 `.cmd` 和 `.ps1` 分开移动 —— `.cmd` 会调用同目录下的 `.ps1`，两者要放在一起。

运行**前提**：Antigravity 已安装，且你的**代理客户端（如 Clash Verge / Clash / v2rayN 等）正在运行**。

## 给高级用户：直接跑 PowerShell

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

## 注意事项

- 本脚本**只改动用户自己的目录**（Antigravity 安装目录内生成一个 `.bat`、桌面/开始菜单快捷方式），**不需要管理员权限**，不写系统级环境变量，不会影响其它程序。
- 修改快捷方式前会自动跳过不存在的入口；**不会删除**任何原文件（脚本生成的 `launch-antigravity.bat` 是可选的，删掉它、把快捷方式指回 `Antigravity.exe` 即可还原）。
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
├── antigravity-proxy-fix.ps1     # 主脚本（PowerShell，UTF-8 with BOM）
├── fix-antigravity.cmd           # 鼠标双击入口（包装调用主脚本）
└── release/                      # GitHub Releases 产物
    └── antigravity-proxy-fix.zip # 解压后双击 fix-antigravity.cmd 即可
```

## License

MIT
