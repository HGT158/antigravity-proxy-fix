#!/bin/bash
# ============================================================
#  Antigravity Proxy Fixer (macOS) - double-click launcher
#  在 Finder 中双击本文件会打开「终端」并调用同目录的主脚本。
#  命令行等价（也可直接带参数）：
#      bash fix-antigravity-mac.command --port 7890
#      bash fix-antigravity-mac.command --probe-only
# ============================================================
cd "$(dirname "$0")" || exit 1

echo
echo "  =================================================="
echo "    Antigravity Proxy Fixer (macOS)"
echo "  =================================================="
echo
echo "  [i] 请先确认代理客户端 (Clash Verge / ClashX / Surge"
echo "      / v2rayN ...) 正在运行，然后按回车继续。"
echo "      按 Ctrl+C 取消。"
printf '  按回车键继续... '
read -r _dummy

echo
echo "  [*] 运行修复脚本 ..."
echo
bash ./antigravity-proxy-fix.sh "$@"
_rc=$?

echo
if [ "$_rc" -eq 0 ]; then
  echo "  [OK] 完成。以后双击桌面上的「Antigravity (Proxy)」图标即可打开"
  echo "       Antigravity，使用时请保持代理客户端运行。"
else
  echo "  [FAILED] 退出码 $_rc。请查看上方提示。"
fi
echo
printf '  按回车键关闭窗口... '
read -r _dummy
exit "$_rc"
