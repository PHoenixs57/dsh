#!/usr/bin/env bash
# 科研模式 macOS 一键安装入口（双击运行）
# 打开「终端」并启动图形安装向导；无图形环境自动回退文字安装。
cd "$(dirname "$0")" || exit 1
if [ -x "./tools/install-mac-gui.sh" ]; then
  bash "./tools/install-mac-gui.sh" "$@"
else
  bash "./install.sh" "$@"
fi
RC=$?
read -p "按回车键关闭窗口…" _ 2>/dev/null || true
exit $RC
