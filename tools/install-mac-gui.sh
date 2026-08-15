#!/usr/bin/env bash
# install-mac-gui.sh — 科研模式 macOS 图形安装向导
# 由「一键安装.command」调用；对话框用 osascript（display dialog / choose folder /
# choose from list），进度显示在终端窗口。无 GUI 环境（osascript 不可用、非 macOS）
# 自动回退到 install.sh 文字模式。
# 用法：bash tools/install-mac-gui.sh [--console]
set -u

PACK_VERSION="0.3.5"
DSH_VERSION="0.1.0-rc.6"

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PKG_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
ENGINE="$PKG_DIR/install.sh"
PATH_MARKER="$HOME/.bioresearch-paths"
APP_BUNDLE="$HOME/Applications/deepseek-dsh.app"
OSA="$(command -v osascript 2>/dev/null || true)"

info() { echo "[向导] $1"; }

esc() { printf '%s' "$1" | sed 's/\\/\\\\/g; s/"/\\"/g'; }
btn_of() { printf '%s' "$1" | sed -n 's/^button returned://p' | tr -d '\r'; }
text_of() { printf '%s' "$1" | sed -n 's/^.*text returned://p' | tr -d '\r'; }

# dlg <applescript>：输出 osascript 结果；0=确定，1=取消/失败，2=osascript 不可用
dlg() {
  [ -n "$OSA" ] || return 2
  "$OSA" "$1" 2>/dev/null
}

# 单按钮提示框
dlg_ok() {
  dlg "display dialog \"$(esc "$1")\" with title \"科研模式安装向导\" buttons {\"好\"} default button \"好\"" >/dev/null 2>&1 || true
}

# 按钮提问框（无输入框）：$1 文案 $2 按钮（已带引号）$3 默认 $4 取消
dlg_ask() {
  dlg "display dialog \"$(esc "$1")\" with title \"科研模式安装向导\" buttons {$2} default button \"$3\" cancel button \"$4\""
}

# 输入提问框：$1 文案 $2 按钮 $3 默认 $4 取消 $5 默认输入（可为空字符串）
dlg_input() {
  dlg "display dialog \"$(esc "$1")\" with title \"科研模式安装向导\" default answer \"$(esc "$5")\" buttons {$2} default button \"$3\" cancel button \"$4\""
}

# 密码输入框（API Key 遮码）：参数同 dlg_input
dlg_secret() {
  dlg "display dialog \"$(esc "$1")\" with title \"科研模式安装向导\" default answer \"$(esc "$5")\" with hidden answer buttons {$2} default button \"$3\" cancel button \"$4\""
}

# ---------- 状态检测（与 Windows 版「已安装」逻辑对应） ----------
BR_HOME="${BIORESEARCH_HOME:-}"
DSH_DIR="${DSH_HOME:-}"
if [ -f "$PATH_MARKER" ]; then
  BR_SAVED="$(grep '^BR_HOME=' "$PATH_MARKER" 2>/dev/null | head -n1 | cut -d= -f2- || true)"
  DS_SAVED="$(grep '^DSH_DIR=' "$PATH_MARKER" 2>/dev/null | head -n1 | cut -d= -f2- || true)"
  [ -z "$BR_HOME" ] && [ -n "$BR_SAVED" ] && BR_HOME="$BR_SAVED"
  [ -z "$DSH_DIR" ] && [ -n "$DS_SAVED" ] && DSH_DIR="$DS_SAVED"
fi
[ -n "$BR_HOME" ] || BR_HOME="$HOME/bioresearch"
[ -n "$DSH_DIR" ] || DSH_DIR="$HOME/.dsh"

INSTALLED=0
INSTALLED_VER=""
[ -f "$BR_HOME/VERSION" ] && INSTALLED_VER="$(tr -d '\r\n ' < "$BR_HOME/VERSION" || true)"
[ -x "$BR_HOME/start.sh" ] && [ -f "$DSH_DIR/.agent-presets/bioresearch/agent.cordis.yml" ] && INSTALLED=1

DSH_VER=""
DSH_BIN="$(command -v dsh 2>/dev/null || true)"
[ -z "$DSH_BIN" ] && [ -x "$BR_HOME/node/bin/dsh" ] && DSH_BIN="$BR_HOME/node/bin/dsh"
[ -n "$DSH_BIN" ] && DSH_VER="$("$DSH_BIN" --version 2>/dev/null | tr -d '\r' | head -n1 || true)"

# ---------- 启动科研模式 ----------
launch_app() {
  if [ -d "$APP_BUNDLE" ]; then
    open "$APP_BUNDLE" 2>/dev/null \
      || "$OSA" -e "tell application \"Terminal\" to do script \"bash '$BR_HOME/start.sh'\"" 2>/dev/null \
      || echo "请手动运行: bash $BR_HOME/start.sh"
    echo "已启动科研模式，浏览器将自动打开 http://127.0.0.1:3081"
  elif [ -x "$BR_HOME/start.sh" ]; then
    "$OSA" -e "tell application \"Terminal\" to do script \"bash '$BR_HOME/start.sh'\"" 2>/dev/null \
      || echo "请手动运行: bash $BR_HOME/start.sh"
  else
    dlg_ok "未找到启动脚本（$BR_HOME/start.sh），请先完成安装。"
    return 1
  fi
}

# ---------- 选择安装目录（默认值 + 浏览文件夹） ----------
pick_install_dir() {
  local res btn p res2
  while :; do
    res="$(dlg_input "安装目录（文献检索 MCP、启动脚本将安装到此处）：" \
      '"选择文件夹…","取消","继续"' "继续" "取消" "$BR_HOME")" || return 1
    btn="$(btn_of "$res")"
    [ "$btn" = "取消" ] && return 1
    if [ "$btn" = "选择文件夹…" ]; then
      p="$(dlg "POSIX path of (choose folder with prompt \"选择安装目录（将直接使用所选文件夹）\")" 2>/dev/null)" || continue
      p="${p%/}"
      res2="$(dlg_ask "安装目录：$p" '"重新选择","就用这里"' "就用这里" "重新选择")" || continue
      [ "$(btn_of "$res2")" = "重新选择" ] && continue
    else
      p="$(text_of "$res")"
    fi
    p="${p/#~/$HOME}"
    case "$p" in
      /*) [ -n "$p" ] && BR_HOME="$p" && return 0 ;;
      *) dlg_ok "路径需要是绝对路径（如 $HOME/bioresearch），请重新输入。" ;;
    esac
  done
}

# ---------- 选择组件（对应 Windows 版两个勾选框） ----------
pick_components() {
  local comp_list comp_res
  comp_list='"安装/更新 DeepSeek Harness","安装「科研模式」插件（预设 + 文献检索 MCP）"'
  comp_res="$(dlg "choose from list {$comp_list} with title \"科研模式安装向导\" with prompt \"勾选要安装的组件（已装好的会自动跳过）：\" with multiple selections allowed default items {$comp_list}")" || return 1
  INSTALL_DSH=0; INSTALL_PLUGIN=0
  printf '%s' "$comp_res" | grep -q "DeepSeek Harness" && INSTALL_DSH=1
  printf '%s' "$comp_res" | grep -q "科研模式" && INSTALL_PLUGIN=1
  if [ "$INSTALL_DSH" = "0" ] && [ "$INSTALL_PLUGIN" = "0" ]; then
    dlg_ok "未选择任何组件，按默认全部安装。"
    INSTALL_DSH=1; INSTALL_PLUGIN=1
  fi
  return 0
}

# ---------- API Key ----------
pick_api_key() {
  local res
  res="$(dlg_secret "请输入 DeepSeek API Key（platform.deepseek.com 创建；留空可稍后在网页 设置→模型 填写）：" \
    '"跳过","继续"' "继续" "跳过" "")" || { API_KEY=""; return 0; }
  API_KEY="$(text_of "$res")"
}

# ---------- 主流程 ----------
main() {
  if [ "${1:-}" = "--console" ]; then
    shift
    exec bash "$ENGINE" "$@"
  fi

  echo "=============================================================="
  echo " 科研模式（生物医学文献检索助手）macOS 一键安装  v$PACK_VERSION"
  echo "=============================================================="

  # 已安装：启动 / 重新安装 / 卸载
  if [ "$INSTALLED" = "1" ]; then
    info "检测到已安装：$([ -n "$INSTALLED_VER" ] && echo "v$INSTALLED_VER ")$([ -n "$DSH_VER" ] && echo "DeepSeek Harness $DSH_VER")"
    res="$(dlg "display dialog \"检测到已安装「科研模式」$([ -n "$INSTALLED_VER" ] && echo "v$INSTALLED_VER")。请选择下一步：\" with title \"科研模式安装向导\" buttons {\"启动科研模式\",\"重新安装\",\"卸载\"} default button \"启动科研模式\"")" || { echo "已取消。"; exit 0; }
    case "$(btn_of "$res")" in
      启动科研模式) launch_app; exit 0 ;;
      卸载) echo; bash "$PKG_DIR/uninstall.sh"; exit 0 ;;
      重新安装) info "重新安装（已装组件会自动跳过）..." ;;
      *) echo "已取消。"; exit 0 ;;
    esac
  else
    res="$(dlg_ask "本向导将安装 DeepSeek Harness 与「科研模式」（生物医学文献检索助手，接入 7 个学术数据库）。" \
      '"开始安装","取消"' "开始安装" "取消")" || { echo "已取消。"; exit 0; }
    [ "$(btn_of "$res")" = "取消" ] && { echo "已取消。"; exit 0; }
  fi

  pick_install_dir || { echo "已取消。"; exit 0; }
  info "安装目录: $BR_HOME"

  if ! pick_components; then
    info "组件选择取消，按默认全部安装。"
    INSTALL_DSH=1; INSTALL_PLUGIN=1
  fi
  info "组件: DeepSeek Harness=$([ "$INSTALL_DSH" = "1" ] && echo 是 || echo 否)，科研模式插件=$([ "$INSTALL_PLUGIN" = "1" ] && echo 是 || echo 否)"

  pick_api_key
  [ -n "$API_KEY" ] && info "已输入 API Key（将在线校验后保存）" || info "跳过 API Key（稍后可在网页 设置→模型 填写）"

  # 引擎参数
  ENGINE_ARGS=( --br-home "$BR_HOME" --dsh-dir "$DSH_DIR" --no-launch )
  [ "$INSTALL_DSH" = "0" ] && ENGINE_ARGS+=( --no-dsh-install )
  [ "$INSTALL_PLUGIN" = "0" ] && ENGINE_ARGS+=( --skip-plugin )
  if [ -n "$API_KEY" ]; then ENGINE_ARGS+=( --api-key "$API_KEY" ); else ENGINE_ARGS+=( --no-key ); fi

  ( "$OSA" 'display dialog "正在安装，请稍候…（进度见终端窗口）" with title "科研模式安装向导" buttons {"安装中…"} default button "安装中…" giving up after 6' >/dev/null 2>&1 ) &
  TOAST_PID=$!

  echo
  info "开始安装（进度如下）："
  bash "$ENGINE" "${ENGINE_ARGS[@]}"
  RC=$?
  kill "$TOAST_PID" 2>/dev/null || true
  wait "$TOAST_PID" 2>/dev/null || true

  if [ "$RC" != "0" ]; then
    echo
    echo "[失败] 安装脚本退出码 $RC。请把本窗口内容截图反馈。"
    dlg_ok "安装未完全成功，请把终端窗口内容截图反馈。"
    exit 1
  fi

  res="$(dlg "display dialog \"安装完成！已在「应用程序」创建 deepseek-dsh 快捷方式（科研模式图标），以后双击它即可使用。\" with title \"科研模式安装向导\" buttons {\"立即启动科研模式\",\"完成\"} default button \"立即启动科研模式\"")" || true
  if [ "$(btn_of "$res")" = "立即启动科研模式" ]; then
    launch_app
  else
    echo "安装完成。以后双击「应用程序」中的 deepseek-dsh 即可启动。"
  fi
}

# osascript 不可用 / 非 macOS / --console → 文字模式
if [ "${1:-}" = "--console" ] || [ -z "$OSA" ] || [ "$(uname -s)" != "Darwin" ]; then
  if [ "$(uname -s)" = "Darwin" ] && [ -z "$OSA" ]; then
    echo "[向导] 当前环境不支持图形对话框（osascript 不可用），改用文字模式安装。"
  fi
  [ "${1:-}" = "--console" ] && shift
  exec bash "$ENGINE" "$@"
fi

main "$@"
