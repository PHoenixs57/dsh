#!/usr/bin/env bash
# 科研模式启动脚本（由 install.sh 复制到安装目录）
# 用法：start.sh [端口号，默认 3081]
set -u
cd "$(dirname "$0")"

# 恢复安装时选择的 DSH 数据目录（预设与 API Key 所在），保证 dsh 能找到预设
if [ -f "$HOME/.bioresearch-paths" ]; then
  DSH_DIR_CFG="$(grep '^DSH_DIR=' "$HOME/.bioresearch-paths" 2>/dev/null | head -n1 | cut -d= -f2- || true)"
  [ -n "$DSH_DIR_CFG" ] && [ -z "${DSH_HOME:-}" ] && export DSH_HOME="$DSH_DIR_CFG"
fi

DSH_CMD=""
if [ -x "./node/bin/dsh" ]; then
  export PATH="$(pwd)/node/bin:$PATH"
  DSH_CMD="$(pwd)/node/bin/dsh"
else
  DSH_CMD="$(command -v dsh 2>/dev/null || true)"
fi
[ -n "$DSH_CMD" ] || { echo "未找到 dsh 命令，请重新运行安装脚本 install.sh"; exit 1; }

PORT="${1:-3081}"
echo "正在启动科研模式（http://127.0.0.1:$PORT）..."

"$DSH_CMD" web --port "$PORT" &
DSH_PID=$!

if [ "$PORT" = "3081" ]; then
  i=0
  while [ $i -lt 30 ]; do
    curl -fsS -o /dev/null --connect-timeout 2 "http://127.0.0.1:$PORT/" 2>/dev/null && break
    i=$((i + 1))
    sleep 2
  done
else
  echo "等待服务启动（约 12 秒）..."
  sleep 12
fi

( sleep 2
  if command -v xdg-open >/dev/null 2>&1; then xdg-open "http://127.0.0.1:$PORT" 2>/dev/null
  elif command -v open >/dev/null 2>&1; then open "http://127.0.0.1:$PORT" 2>/dev/null
  fi ) &

echo "已在浏览器打开 http://127.0.0.1:$PORT（按 Ctrl+C 停止服务）"
wait "$DSH_PID"
