#!/usr/bin/env bash
# 科研模式卸载脚本（macOS / Linux）
set -u

DSH_DIR="${DSH_HOME:-$HOME/.dsh}"
BR_HOME="${BIORESEARCH_HOME:-$HOME/bioresearch}"
PATH_MARKER="$HOME/.bioresearch-paths"
if [ -f "$PATH_MARKER" ]; then
  BR_SAVED="$(grep '^BR_HOME=' "$PATH_MARKER" 2>/dev/null | head -n1 | cut -d= -f2- || true)"
  DS_SAVED="$(grep '^DSH_DIR=' "$PATH_MARKER" 2>/dev/null | head -n1 | cut -d= -f2- || true)"
  [ -z "${BIORESEARCH_HOME:-}" ] && [ -n "$BR_SAVED" ] && BR_HOME="$BR_SAVED"
  [ -z "${DSH_HOME:-}" ] && [ -n "$DS_SAVED" ] && DSH_DIR="$DS_SAVED"
fi

echo "将删除："
echo "  1) 预设目录   $DSH_DIR/.agent-presets/bioresearch"
echo "  2) 安装目录   $BR_HOME（含文献检索 MCP 与便携 Node）"
echo "  3) 快捷方式   $HOME/Applications/deepseek-dsh.app（macOS）"
echo
echo "不受影响：工作区里的 research-log 研究日志、API Key（$DSH_DIR/.credentials.yaml）。"
printf "确认卸载？[y/N] "
read -r ANS
case "$ANS" in
  y|Y) ;;
  *) exit 0 ;;
esac

rm -rf "$DSH_DIR/.agent-presets/bioresearch"
rm -rf "$BR_HOME"
rm -rf "$HOME/Applications/deepseek-dsh.app"
rm -f "$PATH_MARKER"
echo "已卸载。"
echo "如需移除 DeepSeek Harness 本体，请运行：npm rm -g @deepseek-ai/dsh"
