#!/usr/bin/env bash
# 科研模式（生物医学文献检索助手）一键安装 —— macOS / Linux
# 用法：bash install.sh [--no-key] [--no-launch] [--no-dsh-install] [--skip-plugin]
#                      [--br-home <路径>] [--dsh-dir <路径>] [--api-key <key>]
# 兼容 bash 3.2（macOS 自带）；Windows 请用 install.bat。
# macOS 图形向导见 tools/install-mac-gui.sh（由「一键安装.command」驱动）。
set -u

PACK_VERSION="0.3.5"
DSH_VERSION="0.1.0-rc.6"

BR_HOME="${BIORESEARCH_HOME:-$HOME/bioresearch}"
DSH_DIR="${DSH_HOME:-$HOME/.dsh}"
PATH_MARKER="$HOME/.bioresearch-paths"
NO_KEY=0
NO_LAUNCH=0
NO_DSH_INSTALL=0
SKIP_PLUGIN=0
API_KEY_IN=""
while [ $# -gt 0 ]; do
  case "$1" in
    --no-key) NO_KEY=1 ;;
    --no-launch) NO_LAUNCH=1 ;;
    --no-dsh-install) NO_DSH_INSTALL=1 ;;
    --skip-plugin) SKIP_PLUGIN=1 ;;
    --br-home) [ $# -ge 2 ] || { echo "--br-home 需要路径参数"; exit 1; }; BIORESEARCH_HOME="$2"; shift ;;
    --dsh-dir) [ $# -ge 2 ] || { echo "--dsh-dir 需要路径参数"; exit 1; }; DSH_HOME="$2"; shift ;;
    --api-key) [ $# -ge 2 ] || { echo "--api-key 需要 Key 参数"; exit 1; }; API_KEY_IN="$2"; shift ;;
    *) echo "未知参数: $1" ; exit 1 ;;
  esac
  shift
done
BR_HOME="${BIORESEARCH_HOME:-$HOME/bioresearch}"
DSH_DIR="${DSH_HOME:-$HOME/.dsh}"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
TMPDIR_X="${TMPDIR:-/tmp}"

fail() { echo; echo "[失败] $1"; exit 1; }

# ---------- 0. 安装路径（环境变量 > 记忆 > 默认，可交互修改） ----------
if [ -f "$PATH_MARKER" ]; then
  BR_SAVED="$(grep '^BR_HOME=' "$PATH_MARKER" 2>/dev/null | head -n1 | cut -d= -f2- || true)"
  DS_SAVED="$(grep '^DSH_DIR=' "$PATH_MARKER" 2>/dev/null | head -n1 | cut -d= -f2- || true)"
  [ -z "${BIORESEARCH_HOME:-}" ] && [ -n "$BR_SAVED" ] && BR_HOME="$BR_SAVED"
  [ -z "${DSH_HOME:-}" ] && [ -n "$DS_SAVED" ] && DSH_DIR="$DS_SAVED"
fi
if [ -z "${BIORESEARCH_HOME:-}" ]; then
  printf "安装目录（Node/MCP/启动脚本，回车用默认：%s）: " "$BR_HOME"
  read -r BR_IN
  if [ -n "$BR_IN" ]; then
    BR_HOME="${BR_IN/#~/$HOME}"
    case "$BR_HOME" in
      /*) ;;
      *) fail "无效的安装目录：$BR_HOME（需要绝对路径，如 /opt/bioresearch）" ;;
    esac
  fi
fi
if [ -z "${DSH_HOME:-}" ]; then
  printf "DSH 数据目录（预设/API Key，回车用默认：%s）: " "$DSH_DIR"
  read -r DS_IN
  if [ -n "$DS_IN" ]; then
    DSH_DIR="${DS_IN/#~/$HOME}"
    case "$DSH_DIR" in
      /*) ;;
      *) fail "无效的 DSH 数据目录：$DSH_DIR（需要绝对路径）" ;;
    esac
  fi
fi
# 统一归一化与校验（环境变量 / 参数 / 交互输入都走这里）
BR_HOME="${BR_HOME/#~/$HOME}"
DSH_DIR="${DSH_DIR/#~/$HOME}"
case "$BR_HOME" in /*) ;; *) fail "无效的安装目录：$BR_HOME（需要绝对路径，如 /opt/bioresearch）" ;; esac
case "$DSH_DIR" in /*) ;; *) fail "无效的 DSH 数据目录：$DSH_DIR（需要绝对路径）" ;; esac
mkdir -p "$BR_HOME" "$DSH_DIR" || fail "无法创建安装目录"
printf 'BR_HOME=%s\nDSH_DIR=%s\n' "$BR_HOME" "$DSH_DIR" > "$PATH_MARKER"

echo "=============================================================="
echo " 科研模式（生物医学文献检索助手）一键安装  v$PACK_VERSION"
echo " 安装目录 : $BR_HOME"
echo " DSH 数据 : $DSH_DIR"
echo "=============================================================="
echo

# ---------- 1. Node.js ----------
NODE_CMD="$(command -v node 2>/dev/null || true)"
NPM_CMD="$(command -v npm 2>/dev/null || true)"
NODE_MAJOR=""
if [ -n "$NODE_CMD" ]; then
  NODE_MAJOR="$("$NODE_CMD" -v 2>/dev/null | sed 's/^v//' | cut -d. -f1)"
fi
PORTABLE_NODE=0
if [ -z "$NODE_MAJOR" ] || [ "$NODE_MAJOR" -lt 22 ] 2>/dev/null; then
  if [ -n "$NODE_CMD" ]; then
    echo "[1/7] 检测到 Node $( "$NODE_CMD" -v 2>/dev/null || echo '?' )，版本低于 22，将安装便携版。"
  else
    echo "[1/7] 未检测到 Node.js，下载便携版 v22（npmmirror，失败自动回退 nodejs.org）..."
  fi
  OS_NAME="$(uname -s)"
  ARCH_NAME="$(uname -m)"
  case "$OS_NAME" in
    Linux) EXT="linux" ;;
    Darwin) EXT="darwin" ;;
    *) fail "不支持的系统: $OS_NAME（请手动安装 Node.js 22+ 后重跑）" ;;
  esac
  case "$ARCH_NAME" in
    x86_64|amd64) ARCH_NAME="x64" ;;
    aarch64|arm64) ARCH_NAME="arm64" ;;
    *) echo "[警告] 未知架构 $ARCH_NAME，按 x64 尝试。" ; ARCH_NAME="x64" ;;
  esac
  MIRROR="https://registry.npmmirror.com/-/binary/node"
  FALLBACK="https://nodejs.org/dist"
  NODE_V=""
  for BASE in "$MIRROR" "$FALLBACK"; do
    NODE_V="$(curl -fsSL --connect-timeout 15 "$BASE/index.json" 2>/dev/null \
      | grep -o '"version":"v22\.[0-9]*\.[0-9]*"' | head -n1 \
      | sed 's/.*"v\([^"]*\)".*/v\1/' || true)"
    [ -n "$NODE_V" ] && break
  done
  [ -n "$NODE_V" ] || fail "无法获取 Node.js 版本列表（网络受限），请手动安装 Node.js 22+"
  NODE_FILE="node-$NODE_V-$EXT-$ARCH_NAME.tar.xz"
  echo "下载: $NODE_V ($EXT-$ARCH_NAME)"
  curl -fL --connect-timeout 15 --retry 2 -o "$TMPDIR_X/$NODE_FILE" "$MIRROR/$NODE_V/$NODE_FILE" 2>/dev/null \
    || curl -fL --connect-timeout 15 --retry 2 -o "$TMPDIR_X/$NODE_FILE" "$FALLBACK/$NODE_V/$NODE_FILE" \
    || fail "Node.js 下载失败，请手动安装 Node.js 22+（https://nodejs.org）"
  rm -rf "$BR_HOME/node" "$BR_HOME/node-extract"
  mkdir -p "$BR_HOME/node-extract"
  tar -xJf "$TMPDIR_X/$NODE_FILE" -C "$BR_HOME/node-extract" --strip-components=1 || fail "解压 Node 失败"
  mv "$BR_HOME/node-extract" "$BR_HOME/node"
  rm -f "$TMPDIR_X/$NODE_FILE"
  NODE_CMD="$BR_HOME/node/bin/node"
  NPM_CMD="$BR_HOME/node/bin/npm"
  export PATH="$BR_HOME/node/bin:$PATH"
  PORTABLE_NODE=1
  echo "[1/7] 便携 Node 就绪: $NODE_CMD"
else
  echo "[1/7] 检测到 Node $( "$NODE_CMD" -v 2>/dev/null )"
fi
[ -n "$NPM_CMD" ] || fail "未找到 npm，请检查 Node.js 安装"

# ---------- 2. npm 镜像（已是镜像则不动） ----------
CUR_REGISTRY="$("$NPM_CMD" config get registry 2>/dev/null | sed 's#/$##' || true)"
if [ "$CUR_REGISTRY" = "https://registry.npmmirror.com" ]; then
  echo "[2/7] npm 已使用 npmmirror 镜像，跳过。"
else
  echo "[2/7] 配置 npm 镜像（npmmirror）..."
  "$NPM_CMD" config set registry https://registry.npmmirror.com >/dev/null 2>&1 || true
fi

# ---------- 3. DSH ----------
DSH_CMD=""
if [ "$NO_DSH_INSTALL" = "1" ]; then
  DSH_CMD="$(command -v dsh 2>/dev/null || true)"
  [ -n "$DSH_CMD" ] || fail "--no-dsh-install 但未找到 dsh 命令"
  echo "[3/7] 跳过 DSH 安装（使用已装 dsh: $DSH_CMD）"
else
  # 先检查系统是否已装 DSH：版本与锁定版本一致就直接复用，避免每次重装
  EXISTING_DSH="$(command -v dsh 2>/dev/null || true)"
  if [ -z "$EXISTING_DSH" ] && [ -x "$BR_HOME/node/bin/dsh" ]; then
    EXISTING_DSH="$BR_HOME/node/bin/dsh"
  fi
  if [ -z "$EXISTING_DSH" ]; then
    NPMPREFIX_DSH="$("$NPM_CMD" prefix -g 2>/dev/null || true)/bin/dsh"
    [ -x "$NPMPREFIX_DSH" ] && EXISTING_DSH="$NPMPREFIX_DSH"
  fi
  NEED_INSTALL=1
  if [ -n "$EXISTING_DSH" ]; then
    DSH_VER_OUT="$("$EXISTING_DSH" --version 2>/dev/null | tr -d '\r' | head -n1)"
    if [ "$DSH_VER_OUT" = "$DSH_VERSION" ]; then
      echo "[3/7] 已安装 DeepSeek Harness $DSH_VERSION，跳过安装。"
      NEED_INSTALL=0
      DSH_CMD="$EXISTING_DSH"
    else
      echo "[3/7] 检测到 DeepSeek Harness ${DSH_VER_OUT:-未知版本}，将更新到 $DSH_VERSION ..."
    fi
  fi
  if [ "$NEED_INSTALL" = "1" ]; then
    echo "[3/7] 安装 DeepSeek Harness @deepseek-ai/dsh@$DSH_VERSION（首次约 1-3 分钟）..."
    "$NPM_CMD" install -g "@deepseek-ai/dsh@$DSH_VERSION" \
      || fail "DSH 安装失败。如因权限不足，请重试：sudo $NPM_CMD install -g @deepseek-ai/dsh@$DSH_VERSION"
  fi
fi
if [ -z "$DSH_CMD" ]; then
  if [ "$PORTABLE_NODE" = "1" ] && [ -x "$BR_HOME/node/bin/dsh" ]; then
    DSH_CMD="$BR_HOME/node/bin/dsh"
  else
    DSH_CMD="$(command -v dsh 2>/dev/null || true)"
  fi
  if [ -z "$DSH_CMD" ]; then
    NPMPREFIX="$("$NPM_CMD" prefix -g 2>/dev/null || true)"
    [ -x "$NPMPREFIX/bin/dsh" ] && DSH_CMD="$NPMPREFIX/bin/dsh"
  fi
fi
[ -n "$DSH_CMD" ] || echo "[警告] 未定位到 dsh 命令，启动时若失败请确认 npm 全局 bin 目录在 PATH 中"

# ---------- 4-6.5 预设 + MCP + 默认模式（--skip-plugin 时整体跳过） ----------
if [ "$SKIP_PLUGIN" = "1" ]; then
  echo "[4-6.5/7] 跳过「科研模式」插件安装（--skip-plugin），保留现有设置不动。"
else
# ---------- 4. 预设 ----------
echo "[4/7] 安装「科研模式」预设 → $DSH_DIR/.agent-presets/bioresearch"
PRESET_DST="$DSH_DIR/.agent-presets/bioresearch"
mkdir -p "$PRESET_DST" || fail "无法创建 $PRESET_DST"
cp -R "$SCRIPT_DIR/preset/." "$PRESET_DST/" || fail "预设复制失败"

# ---------- 5. MCP（按 lockfile 哈希判断依赖是否已就绪） ----------
echo "[5/7] 同步文献检索 MCP → $BR_HOME/literature-search-mcp"
MCP_DST="$BR_HOME/literature-search-mcp"
mkdir -p "$MCP_DST" || fail "无法创建 $MCP_DST"
cp -R "$SCRIPT_DIR/mcp/." "$MCP_DST/" || fail "MCP 复制失败"
LOCK_HASH="$({ sha256sum "$MCP_DST/package-lock.json" 2>/dev/null || shasum -a 256 "$MCP_DST/package-lock.json" 2>/dev/null || true; } | awk '{print $1}')"
DEPS_MARKER="$MCP_DST/node_modules/.bioresearch-lockhash"
DEPS_OK=0
if [ -f "$DEPS_MARKER" ] && [ -n "$LOCK_HASH" ] && [ "$(cat "$DEPS_MARKER" 2>/dev/null)" = "$LOCK_HASH" ]; then
  DEPS_OK=1
fi
if [ "$DEPS_OK" = "1" ]; then
  echo "      MCP 依赖已就绪（哈希匹配），跳过安装。"
else
  echo "      安装 MCP 运行依赖（npm ci --omit=dev）..."
  (cd "$MCP_DST" && "$NPM_CMD" ci --omit=dev) || fail "MCP 依赖安装失败，请检查网络后重试"
  [ -n "$LOCK_HASH" ] && printf '%s' "$LOCK_HASH" > "$DEPS_MARKER"
fi

# ---------- 6. 写入绝对路径 ----------
escaped_node="$(printf '%s' "$NODE_CMD" | sed "s/'/''/g; s/&/\\&/g")"
escaped_mcp="$(printf '%s' "$MCP_DST/dist/server.js" | sed "s/'/''/g; s/&/\\&/g")"
sed -i.bak "s|{{NODE_PATH}}|$escaped_node|; s|{{MCP_SERVER_PATH}}|$escaped_mcp|" "$PRESET_DST/agent.cordis.yml" \
  && rm -f "$PRESET_DST/agent.cordis.yml.bak" \
  || fail "预设路径写入失败"
if grep -q '{{[A-Z0-9_]*}}' "$PRESET_DST/agent.cordis.yml"; then
  fail "预设中仍有未替换的占位符"
fi

# ---------- 6.5 默认会话模式 ----------
echo '[6.5/7] 设置「科研模式」为默认会话模式...'
SETTINGS_FILE="$DSH_DIR/settings.yaml"
touch "$SETTINGS_FILE"
awk '
  /^[[:space:]]*agent-presets[[:space:]]*:/ { found=1; print "agent-presets:"; next }
  found==1 && !done && /^[[:space:]]*default[[:space:]]*:/ { print "  default: bioresearch"; done=1; next }
  found==1 && !done && /^[^[:space:]]/ { print "  default: bioresearch"; done=1 }
  { print }
  END { if (!found) { print "agent-presets:"; print "  default: bioresearch" } else if (!done) { print "  default: bioresearch" } }
' "$SETTINGS_FILE" > "$SETTINGS_FILE.tmp" && mv "$SETTINGS_FILE.tmp" "$SETTINGS_FILE" \
  && echo '    已写入 agent-presets.default = bioresearch（可在网页 设置 中更改）' \
  || echo '    写入 settings.yaml 失败；可稍后在网页 设置 中手动把默认模式选为「科研模式」。'
fi  # SKIP_PLUGIN 结束

# ---------- 7. API Key ----------
CRED="$DSH_DIR/.credentials.yaml"
save_key() {  # $1 = key；在线校验通过才写入（已存在则原位替换，不产生重复行）
  local KEY="$1" CODE
  CODE="$(curl -sS --connect-timeout 10 -o /dev/null -w '%{http_code}' \
    -H "Authorization: Bearer $KEY" https://api.deepseek.com/models 2>/dev/null || true)"
  case "$CODE" in
    200)
      mkdir -p "$DSH_DIR"
      chmod 700 "$DSH_DIR" 2>/dev/null || true
      if [ -f "$CRED" ] && grep -qE '^[[:space:]]*DEEPSEEK_API_KEY[[:space:]]*:' "$CRED"; then
        awk -v key="$KEY" '/^[[:space:]]*DEEPSEEK_API_KEY[[:space:]]*:/ { print "DEEPSEEK_API_KEY: " key; next } { print }' "$CRED" > "$CRED.tmp" \
          && mv "$CRED.tmp" "$CRED" && echo "API Key 已更新到 $CRED"
      else
        if [ -f "$CRED" ]; then cat "$CRED" > "$CRED.tmp" && printf '\n' >> "$CRED.tmp"; else : > "$CRED.tmp"; fi
        printf 'DEEPSEEK_API_KEY: %s\n' "$KEY" >> "$CRED.tmp"
        mv "$CRED.tmp" "$CRED"
        echo "API Key 已保存到 $CRED"
      fi
      chmod 600 "$CRED" 2>/dev/null || true
      ;;
    401|403)
      echo "Key 校验失败（HTTP $CODE）。未保存；可重新运行本脚本，或在网页 设置→模型 中填写。"
      ;;
    *)
      echo "无法连接 api.deepseek.com（HTTP ${CODE:-无响应}）。Key 未保存；之后可在网页 设置→模型 中填写。"
      ;;
  esac
}
if [ -n "$API_KEY_IN" ]; then
  echo "[7/7] 校验并写入 DeepSeek API Key..."
  save_key "$API_KEY_IN"
elif [ "$NO_KEY" = "0" ]; then
  echo "[7/7] 配置 DeepSeek API Key..."
  if [ -f "$CRED" ] && grep -qE '^[[:space:]]*DEEPSEEK_API_KEY[[:space:]]*:' "$CRED"; then
    echo "检测到已配置 DeepSeek API Key（$CRED），跳过。"
  else
    printf "是否现在输入 DeepSeek API Key？[y/N] "
    read -r ANS
    case "$ANS" in
      y|Y)
        printf "请输入 DeepSeek API Key（不回显）: "
        stty -echo 2>/dev/null || true
        read -r KEY
        stty echo 2>/dev/null || true
        echo
        if [ -n "$KEY" ]; then
          save_key "$KEY"
        else
          echo "输入为空，跳过。之后可在网页 设置→模型 中填写。"
        fi
        ;;
      *)
        echo "跳过。之后可在网页 设置→模型 中填写。"
        ;;
    esac
  fi
else
  echo "[7/7] 跳过 API Key 配置（--no-key）"
fi

cp "$SCRIPT_DIR/tools/start-template.sh" "$BR_HOME/start.sh" || fail "无法写入 $BR_HOME/start.sh"
chmod +x "$BR_HOME/start.sh"
cp "$SCRIPT_DIR/VERSION" "$BR_HOME/VERSION" 2>/dev/null || true

# ---------- 7.5 macOS 快捷方式 ----------
if [ "$SKIP_PLUGIN" != "1" ] && [ "$(uname -s)" = "Darwin" ] && [ -f "$SCRIPT_DIR/tools/make-dsh-app.sh" ]; then
  echo "[7.5/7] 创建「应用程序」快捷方式（deepseek-dsh）..."
  bash "$SCRIPT_DIR/tools/make-dsh-app.sh" \
    || echo "    快捷方式创建失败（不影响使用，运行 $BR_HOME/start.sh 即可启动）"
fi

echo
echo "=============================================================="
echo " 安装完成！"
if [ "$(uname -s)" = "Darwin" ]; then
  echo " 以后启动：双击「应用程序」中的 deepseek-dsh（或运行 $BR_HOME/start.sh）"
else
  echo " 以后启动：$BR_HOME/start.sh"
fi
if [ "$NO_LAUNCH" = "0" ]; then
  echo " 正在启动科研模式，浏览器将自动打开 http://127.0.0.1:3081 ..."
  "$BR_HOME/start.sh" &
fi
echo "=============================================================="
