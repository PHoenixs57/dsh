#!/usr/bin/env bash
# make-dsh-app.sh — 创建 macOS 快捷方式应用：~/Applications/deepseek-dsh.app
# 由 install.sh 在 macOS 上调用（第 7.5 步）；测试/非 macOS 环境可用 --force 强制生成。
# 用法：make-dsh-app.sh [--force]
set -u

PACK_VERSION="0.3.5"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
ASSETS_DIR="$(cd "$SCRIPT_DIR/../assets" && pwd)"
FORCE=0
[ "${1:-}" = "--force" ] && FORCE=1

if [ "$(uname -s)" != "Darwin" ] && [ "$FORCE" != "1" ]; then
  echo "非 macOS 系统，跳过「应用程序」快捷方式创建（测试可用 --force）。"
  exit 0
fi

APP_DIR="$HOME/Applications/deepseek-dsh.app"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources" \
  || { echo "[警告] 无法创建 $APP_DIR"; exit 0; }

# ---------- 可执行体：启动时读取安装路径记忆并运行 start.sh ----------
cat > "$APP_DIR/Contents/MacOS/deepseek-dsh" <<'SCRIPT'
#!/usr/bin/env bash
# deepseek-dsh 启动器（由安装器生成）
set -u
LOG="$HOME/Library/Logs/bioresearch-dsh.log"
mkdir -p "$(dirname "$LOG")" 2>/dev/null || true
exec >> "$LOG" 2>&1
BR_HOME=""
if [ -f "$HOME/.bioresearch-paths" ]; then
  BR_HOME="$(grep '^BR_HOME=' "$HOME/.bioresearch-paths" 2>/dev/null | head -n1 | cut -d= -f2- || true)"
fi
[ -n "$BR_HOME" ] || BR_HOME="$HOME/bioresearch"
if [ -x "$BR_HOME/start.sh" ]; then
  exec bash "$BR_HOME/start.sh"
fi
echo "未找到 $BR_HOME/start.sh，请重新运行安装程序。"
sleep 5
SCRIPT
chmod +x "$APP_DIR/Contents/MacOS/deepseek-dsh"

# ---------- Info.plist ----------
cat > "$APP_DIR/Contents/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleName</key><string>deepseek-dsh</string>
  <key>CFBundleDisplayName</key><string>科研模式</string>
  <key>CFBundleIdentifier</key><string>com.bioresearch.deepseek-dsh</string>
  <key>CFBundleVersion</key><string>$PACK_VERSION</string>
  <key>CFBundleShortVersionString</key><string>$PACK_VERSION</string>
  <key>CFBundlePackageType</key><string>APPL</string>
  <key>CFBundleExecutable</key><string>deepseek-dsh</string>
  <key>CFBundleIconFile</key><string>deepseek.icns</string>
  <key>LSMinimumSystemVersion</key><string>10.14</string>
  <key>NSHighResolutionCapable</key><true/>
</dict>
</plist>
PLIST

# ---------- 图标：优先 icns，缺失时用 sips 从 PNG 现场转换 ----------
ICNS_OK=0
if [ -f "$ASSETS_DIR/deepseek.icns" ]; then
  cp "$ASSETS_DIR/deepseek.icns" "$APP_DIR/Contents/Resources/deepseek.icns" && ICNS_OK=1
elif [ -f "$ASSETS_DIR/deepseek.png" ] && command -v sips >/dev/null 2>&1; then
  sips -s format icns "$ASSETS_DIR/deepseek.png" \
    --out "$APP_DIR/Contents/Resources/deepseek.icns" >/dev/null 2>&1 && ICNS_OK=1
fi
[ "$ICNS_OK" = "1" ] || echo "[警告] 未找到图标，快捷方式将使用系统默认图标。"

# 刷新 LaunchServices 缓存
touch "$APP_DIR"
echo "已创建快捷方式: $APP_DIR"
