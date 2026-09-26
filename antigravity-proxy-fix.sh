#!/bin/bash
# ============================================================================
#  Antigravity 黑屏修复 (macOS 版) —— 自动走代理
#
#  与 Windows 版 antigravity-proxy-fix.ps1 等价的 macOS 实现。
#  黑屏根因相同：Antigravity 的语言服务器（Go 后端）不读系统代理，只认
#  HTTP_PROXY / HTTPS_PROXY 环境变量；连不上 Google 就黑屏。
#
#  本脚本做四件事：
#    1) 定位 Antigravity.app（/Applications、~/Applications，Spotlight 兜底）
#    2) 探测本地代理端口：先读系统代理(scutil --proxy)，再用 curl 实测常见端口
#    3) 在 ~/Applications 生成包装 App「Antigravity (Proxy).app」，
#       双击它即带着代理环境变量启动 Antigravity（不影响系统与其它应用）
#    4) 在桌面创建指向包装 App 的替身；（可选）重启 Antigravity 完成修复
#
#  用法：
#    bash antigravity-proxy-fix.sh                    # 自动探测 + 修复 + 重启
#    bash antigravity-proxy-fix.sh --port 7890        # 明确指定端口
#    bash antigravity-proxy-fix.sh --probe-only       # 只探测，不修改
#    bash antigravity-proxy-fix.sh --skip-relaunch    # 不重启
# ============================================================================

ScriptVersion='1.1.0'
SELF="$(basename "$0")"

# 防止被 sh/dash 执行（脚本用到了 bash 特性，如 printf %q）
if [ -z "${BASH_VERSION:-}" ]; then
  exec bash "$0" "$@"
fi

# ---------- 输出（非终端时自动降级为纯文本） ----------
if [ -t 1 ]; then
  C_C=$'\033[36m'; C_G=$'\033[32m'; C_Y=$'\033[33m'; C_R=$'\033[31m'; C_0=$'\033[0m'
else
  C_C=''; C_G=''; C_Y=''; C_R=''; C_0=''
fi
step(){ printf '%s[*]%s %s\n' "$C_C" "$C_0" "$1"; }
ok(){   printf '%s[+]%s %s\n' "$C_G" "$C_0" "$1"; }
warn(){ printf '%s[!]%s %s\n' "$C_Y" "$C_0" "$1"; }
err(){  printf '%s[x]%s %s\n' "$C_R" "$C_0" "$1"; }

usage() {
  cat <<USAGE
用法: bash $SELF [选项]

  -p, --port <端口>    指定代理端口，跳过自动探测
      --probe-only     只探测并打印结果，不修改任何东西
      --skip-relaunch  生成包装 App 后不重启 Antigravity
  -h, --help           显示本帮助
USAGE
}

# ---------- 1) 定位 Antigravity.app ----------
find_antigravity() {
  local base p
  local dirs=("/Applications" "$HOME/Applications")

  # 先找准确名字（APFS 默认大小写不敏感，这里再显式做一次模糊匹配兜底）
  for base in "${dirs[@]}"; do
    p="$base/Antigravity.app"
    [ -d "$p" ] && { printf '%s' "$p"; return 0; }
  done
  for base in "${dirs[@]}"; do
    for p in "$base/"*ntigravity*.app; do
      [ -d "$p" ] || continue
      case "$p" in *" (Proxy).app") continue ;; esac   # 排除本脚本生成的包装 App 自己
      printf '%s' "$p"; return 0
    done
  done

  # Spotlight 兜底（索引被关时静默跳过；同样排除包装 App）
  if command -v mdfind >/dev/null 2>&1; then
    p="$(mdfind "kMDItemFSName == 'Antigravity.app'c" 2>/dev/null | grep -v ' (Proxy)\.app$' | head -n 1)"
    [ -n "$p" ] && [ -d "$p" ] && { printf '%s' "$p"; return 0; }
  fi
  return 1
}

# 取 App 内真正要 exec 的可执行文件路径
app_executable() {
  local app="$1" name f
  name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$app/Contents/Info.plist" 2>/dev/null || true)"
  if [ -n "$name" ] && [ -x "$app/Contents/MacOS/$name" ]; then
    printf '%s' "$app/Contents/MacOS/$name"
    return 0
  fi
  # 兜底：Contents/MacOS 下第一个可执行文件
  for f in "$app/Contents/MacOS/"*; do
    [ -f "$f" ] && [ -x "$f" ] || continue
    printf '%s' "$f"
    return 0
  done
  return 1
}

# ---------- 2) 探测代理端口 ----------
# 用 curl 经代理访问 Google，能返回真实 HTTP 状态码 => 代理可用（能穿透到 Google）。
# 必须同时检查 curl 退出码：连接失败时 -w 也会输出 000，若只看状态码，
# 死端口会被误判可用，导致端口扫描永远停在第一个端口上（Windows 版踩过的坑）。
test_proxy_port() {
  local port="$1" scheme="$2" code
  [ -n "$port" ] || return 1
  code="$(curl -x "${scheme}://127.0.0.1:${port}" -s -o /dev/null \
            --connect-timeout 4 -m 12 -w '%{http_code}' \
            'https://oauth2.googleapis.com/' 2>/dev/null)"
  [ $? -eq 0 ] || return 1
  case "$code" in [1-9][0-9][0-9]) return 0 ;; esac   # 200/301/302/404... 都算通，000=没连上
  return 1
}

# 先按 HTTP 代理测，再按 SOCKS5 测（Shadowsocks / sing-box 常只开 SOCKS 口）。
# 命中时把全局 PROXY_SCHEME 置为对应 scheme。
test_port_any() {
  local p="$1"
  if test_proxy_port "$p" http;    then PROXY_SCHEME='http';    return 0; fi
  if test_proxy_port "$p" socks5h; then PROXY_SCHEME='socks5h'; return 0; fi
  return 1
}

# 读 macOS 系统代理设置（对应 Windows 版读注册表 ProxyServer），
# 输出所有「已启用」协议的端口，每行一个、去重。
system_proxy_ports() {
  scutil --proxy 2>/dev/null | awk -F': *' '
    /^ *HTTPEnable/  { he = ($2 == 1) }
    /^ *HTTPSEnable/ { hs = ($2 == 1) }
    /^ *SOCKSEnable/ { ss = ($2 == 1) }
    /^ *HTTPPort/    { if (he) print $2 }
    /^ *HTTPSPort/   { if (hs) print $2 }
    /^ *SOCKSPort/   { if (ss) print $2 }
  ' | awk '!seen[$0]++'
}

# 人类可读的系统代理摘要（探测模式展示用）
system_proxy_summary() {
  scutil --proxy 2>/dev/null | awk -F': *' '
    /^ *HTTPEnable/  { he = ($2 == 1) }
    /^ *HTTPSEnable/ { hs = ($2 == 1) }
    /^ *SOCKSEnable/ { ss = ($2 == 1) }
    /^ *HTTPProxy/   { hp  = $2 }
    /^ *HTTPSProxy/  { hsp = $2 }
    /^ *SOCKSProxy/  { sp  = $2 }
    /^ *HTTPPort/    { hpt  = $2 }
    /^ *HTTPSPort/   { hspt = $2 }
    /^ *SOCKSPort/   { spt  = $2 }
    END {
      s = ""
      if (he) s = s "HTTP " hp ":" hpt "  "
      if (hs) s = s "HTTPS " hsp ":" hspt "  "
      if (ss) s = s "SOCKS " sp ":" spt
      if (s == "") s = "未启用"
      print s
    }'
}

find_proxy_port() {
  local p

  if [ -n "$ARG_PORT" ]; then
    case "$ARG_PORT" in *[!0-9]*) err "端口号必须是纯数字: $ARG_PORT"; exit 1 ;; esac
    [ "$ARG_PORT" -ge 1 ] && [ "$ARG_PORT" -le 65535 ] || { err "端口号超出范围: $ARG_PORT"; exit 1; }
    PORT="$ARG_PORT"
    if test_port_any "$PORT"; then
      step "指定端口 $PORT 测试可用"
    else
      warn "指定端口 $PORT 实测不通，仍按你的指定继续"
    fi
    return 0
  fi

  # 先看系统代理设置
  local sysports
  sysports="$(system_proxy_ports)"
  if [ -n "$sysports" ]; then
    while read -r p; do
      [ -n "$p" ] || continue
      if test_port_any "$p"; then
        step "读取到系统代理端口 $p，测试可用"
        PORT="$p"
        return 0
      fi
      warn "系统代理端口 $p 存在但测试不通，继续扫描"
    done <<SYS
$sysports
SYS
  fi

  # macOS 常见代理客户端端口：Clash 系、Surge、v2rayN/sing-box、老 ClashX、Shadowsocks 等
  for p in 7890 7897 7899 7891 6152 6153 1087 10809 10808 10811 1080 8888 2080; do
    if test_port_any "$p"; then
      step "发现可用代理端口 $p"
      PORT="$p"
      return 0
    fi
  done
  return 1
}

# ---------- 3) 生成包装 App 启动器 ----------
# 对应 Windows 版的 launch-antigravity.bat。放在 ~/Applications（不在 Antigravity
# 安装目录里），因此 Antigravity 自动更新不会覆盖它；端口和 App 路径固化在启动
# 脚本里，端口变了 / 路径变了重跑本脚本即可。
make_wrapper() {
  mkdir -p "$WRAPPER/Contents/MacOS" "$WRAPPER/Contents/Resources" || return 1

  # --- 图标：优先读真实 App 的 CFBundleIconFile，找不到就取 Resources 下第一个 .icns ---
  local icon_name icon_src='' ICON_FILE='' f
  icon_name="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIconFile' "$REAL_APP/Contents/Info.plist" 2>/dev/null || true)"
  if [ -n "$icon_name" ]; then
    [ -f "$REAL_APP/Contents/Resources/$icon_name" ]     && icon_src="$REAL_APP/Contents/Resources/$icon_name"
    [ -z "$icon_src" ] && [ -f "$REAL_APP/Contents/Resources/$icon_name.icns" ] \
                                                         && icon_src="$REAL_APP/Contents/Resources/$icon_name.icns"
  fi
  if [ -z "$icon_src" ]; then
    for f in "$REAL_APP/Contents/Resources/"*.icns; do
      [ -f "$f" ] || continue
      icon_src="$f"
      break
    done
  fi
  if [ -n "$icon_src" ]; then
    cp -f "$icon_src" "$WRAPPER/Contents/Resources/" && ICON_FILE="$(basename "$icon_src")"
  fi

  # --- Info.plist（内容全 ASCII，避免编码问题） ---
  {
    cat <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
	<key>CFBundleExecutable</key>
	<string>launch-antigravity</string>
	<key>CFBundleIdentifier</key>
	<string>local.antigravity-proxy-fix.launcher</string>
	<key>CFBundleName</key>
	<string>Antigravity (Proxy)</string>
	<key>CFBundleDisplayName</key>
	<string>Antigravity (Proxy)</string>
	<key>CFBundlePackageType</key>
	<string>APPL</string>
	<key>CFBundleInfoDictionaryVersion</key>
	<string>6.0</string>
	<key>CFBundleShortVersionString</key>
	<string>1.1.0</string>
PLIST
    # 用 cat > 覆盖写，不删除重建整个 .app：已存在的替身(alias)按 inode 追踪，原地覆盖才不会失效
    [ -n "$ICON_FILE" ] && printf '\t<key>CFBundleIconFile</key>\n\t<string>%s</string>\n' "$ICON_FILE"
    cat <<'PLIST2'
	<key>NSHighResolutionCapable</key>
	<true/>
</dict>
</plist>
PLIST2
  } > "$WRAPPER/Contents/Info.plist" || return 1

  # --- 启动脚本：代理环境变量在这里注入，只作用于 Antigravity 进程树 ---
  # %q 负责转义，含空格 / 中文 / 单引号的路径都不会破坏脚本；
  # 生成内容保持全 ASCII 的中文注释一律不写（同 Windows 版 .bat 的编码教训）。
  local LAUNCHER="$WRAPPER/Contents/MacOS/launch-antigravity"
  {
    printf '#!/bin/bash\n'
    printf '# Antigravity proxy launcher - AUTO-GENERATED by antigravity-proxy-fix.sh v%s.\n' "$ScriptVersion"
    printf '# Do not edit by hand: re-run the fix script instead (proxy port / app path are baked in).\n'
    printf 'PROXY_URL=%q\n' "$PROXY_URL"
    printf 'REAL_APP=%q\n'  "$REAL_APP"
    printf 'REAL_BIN=%q\n'  "$REAL_BIN"
    cat <<'BODY'
export HTTP_PROXY="$PROXY_URL" HTTPS_PROXY="$PROXY_URL" ALL_PROXY="$PROXY_URL"
export http_proxy="$PROXY_URL" https_proxy="$PROXY_URL" all_proxy="$PROXY_URL"
export NO_PROXY="localhost,127.0.0.1,::1" no_proxy="localhost,127.0.0.1,::1"

if [ ! -x "$REAL_BIN" ]; then
  /usr/bin/osascript -e 'display alert "Antigravity launcher" message "Antigravity not found at the recorded path. Please re-run antigravity-proxy-fix.sh." as critical' >/dev/null 2>&1
  exit 1
fi
exec "$REAL_BIN"
BODY
  } > "$LAUNCHER" || return 1
  chmod +x "$LAUNCHER" || return 1
  return 0
}

# ---------- 4) 桌面替身（快捷方式的 mac 对应物） ----------
make_desktop_alias() {
  local dest="$HOME/Desktop/Antigravity (Proxy)"
  if [ -e "$dest" ] || [ -L "$dest" ]; then
    warn "桌面已存在 \"Antigravity (Proxy)\"，跳过替身创建"
    return 0
  fi
  # Finder 替身（alias）最正规；首次会弹「终端想控制 Finder」授权框，拒绝也不影响其余步骤
  if osascript -e 'on run argv
	set p to item 1 of argv
	tell application "Finder"
		set a to make alias file to (POSIX file p as alias) at (path to desktop folder)
		set name of a to "Antigravity (Proxy)"
	end tell
end run' "$WRAPPER" >/dev/null 2>&1; then
    ok "已在桌面创建替身: Antigravity (Proxy)"
    return 0
  fi
  # Finder 自动化被拒 / osascript 不可用时，退化为符号链接（双击同样能启动）
  if ln -s "$WRAPPER" "$dest" 2>/dev/null; then
    warn "Finder 替身创建失败（可能拒绝了自动化权限），已改用符号链接"
    return 0
  fi
  warn "未能创建桌面替身（不影响使用），包装 App 位于: $WRAPPER"
}

# ================= 主流程 =================
ARG_PORT='' PROBE_ONLY=0 SKIP_RELAUNCH=0
while [ $# -gt 0 ]; do
  case "$1" in
    -p|--port|--proxy-port)
      [ $# -ge 2 ] || { err "参数 $1 需要一个端口号"; usage; exit 1; }
      ARG_PORT="$2"; shift 2 ;;
    --port=*) ARG_PORT="${1#*=}"; shift ;;
    --probe-only)    PROBE_ONLY=1;    shift ;;
    --skip-relaunch) SKIP_RELAUNCH=1; shift ;;
    -h|--help) usage; exit 0 ;;
    *) err "未知参数: $1"; usage; exit 1 ;;
  esac
done

if [ "$(uname -s)" != "Darwin" ]; then
  err "本脚本是 macOS 版，当前系统是 $(uname -s)。Windows 请使用 antigravity-proxy-fix.ps1。"
  exit 1
fi

printf '%s============================================%s\n' "$C_C" "$C_0"
printf '%s Antigravity 黑屏修复 (macOS · 自动走代理) v%s%s\n' "$C_C" "$ScriptVersion" "$C_0"
printf '%s============================================%s\n' "$C_C" "$C_0"

REAL_APP="$(find_antigravity)"
if [ -z "$REAL_APP" ]; then
  err "未找到 Antigravity.app，请先把 Antigravity 拖入 /Applications（或 ~/Applications）再运行本脚本。"
  exit 1
fi
# 保险：万一将来定位逻辑又把包装 App 当成目标，启动器会「exec 自己」无限循环，宁可直接报错
case "$REAL_APP" in *" (Proxy).app")
  err "定位到的是本脚本生成的包装 App（$REAL_APP），不是 Antigravity 本体。"
  exit 1 ;;
esac
step "已定位 Antigravity: $REAL_APP"

REAL_BIN="$(app_executable "$REAL_APP")"
if [ -z "$REAL_BIN" ]; then
  err "在 $REAL_APP/Contents/MacOS 下找不到可执行文件，App 可能不完整，请重装 Antigravity。"
  exit 1
fi

PORT='' PROXY_SCHEME='http'
if ! find_proxy_port; then
  err "未找到可用的本地代理端口。请先开启代理客户端(Clash Verge / ClashX / Surge 等)，或加 --port 指定端口后重试。"
  exit 1
fi
PROXY_URL="${PROXY_SCHEME}://127.0.0.1:${PORT}"
ok "使用代理: $PROXY_URL"

if [ "$PROBE_ONLY" -eq 1 ]; then
  printf '\n%s[探测模式] 只检测，不修改。结果为:%s\n' "$C_Y" "$C_0"
  printf '  Antigravity : %s\n' "$REAL_APP"
  printf '  代理端口    : %s (%s)\n' "$PORT" "$PROXY_SCHEME"
  printf '  系统代理    : %s\n' "$(system_proxy_summary)"
  exit 0
fi

WRAPPER="$HOME/Applications/Antigravity (Proxy).app"
if make_wrapper; then
  ok "已生成包装 App: $WRAPPER"
else
  err "生成包装 App 失败，请检查 $HOME/Applications 的写权限。"
  exit 1
fi

make_desktop_alias

# 重新启动（走代理）
if [ "$SKIP_RELAUNCH" -eq 0 ]; then
  step "结束当前 Antigravity / language_server 进程..."
  pkill -f "$REAL_APP/Contents" 2>/dev/null
  pkill -f 'language_server'    2>/dev/null
  sleep 2
  step "通过包装 App 重新启动 Antigravity (走代理 $PORT)..."
  if open "$WRAPPER" 2>/dev/null; then
    sleep 8
    if pgrep -f "$REAL_APP/Contents" >/dev/null 2>&1; then
      ok "Antigravity 已重新启动。窗口应正常显示，不再黑屏。"
    else
      warn "未检测到 Antigravity 进程，可能启动失败，请确认代理客户端正在运行。"
    fi
  else
    warn "启动包装 App 失败，请手动打开: $WRAPPER"
  fi
fi

printf '\n%s完成。以后打开 Antigravity 只需：代理客户端保持运行，双击桌面上的「Antigravity (Proxy)」图标（也可从 ~/Applications 或启动台打开，可拖进 Dock）。%s\n' "$C_G" "$C_0"
