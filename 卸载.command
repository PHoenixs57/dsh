#!/usr/bin/env bash
# 科研模式 macOS 卸载入口（双击运行）
cd "$(dirname "$0")" || exit 1
if [ -x "./uninstall.sh" ]; then
  bash "./uninstall.sh"
else
  echo "未找到 uninstall.sh，请确认安装包文件完整。"
fi
read -p "按回车键关闭窗口…" _ 2>/dev/null || true
exit 0
