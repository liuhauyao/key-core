#!/usr/bin/env bash
# Key Core 发版公共函数（由根目录 release 与各子脚本 source，非独立入口）

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
BOLD='\033[1m'
DIM='\033[2m'
NC='\033[0m'

# 项目根目录（假设 source 此文件的脚本在 scripts/ 下）
SCRIPTS_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PROJECT_DIR="$(cd "$SCRIPTS_DIR/.." && pwd)"

BUNDLE_ID="cn.dlrow.keycore"
APP_NAME="Key Core"

# create-dmg 版本与 vendor 路径
CREATE_DMG_VERSION="1.2.3"
CREATE_DMG_DIR="$SCRIPTS_DIR/vendor/create-dmg-${CREATE_DMG_VERSION}"
CREATE_DMG_TOOL="$CREATE_DMG_DIR/create-dmg"

print_info()    { echo -e "${GREEN}[INFO]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error()   { echo -e "${RED}[ERROR]${NC} $1"; }

check_command() {
  if ! command -v "$1" &> /dev/null; then
    print_error "未找到命令: $1"
    exit 1
  fi
}

# 读取 pubspec.yaml 中的版本号
read_version() {
  grep '^version:' "$PROJECT_DIR/pubspec.yaml" | sed 's/version: //' | sed 's/+.*//'
}

# 读取完整版本字符串（含 build 号）
read_full_version() {
  grep '^version:' "$PROJECT_DIR/pubspec.yaml" | sed 's/version: //'
}

# 自动递增修订号：1.0.5+5 → 1.0.6+6
bump_patch_version() {
  local current="$1"
  local version_part build_part
  if [[ "$current" =~ ^([0-9]+\.[0-9]+\.[0-9]+)\+([0-9]+)$ ]]; then
    version_part="${BASH_REMATCH[1]}"
    build_part="${BASH_REMATCH[2]}"
  elif [[ "$current" =~ ^([0-9]+\.[0-9]+\.[0-9]+)$ ]]; then
    version_part="${BASH_REMATCH[1]}"
    build_part="0"
  else
    print_error "无法解析版本号: ${current}"
    return 1
  fi

  local major minor patch
  IFS='.' read -r major minor patch <<< "$version_part"
  patch=$((patch + 1))
  build_part=$((build_part + 1))
  echo "${major}.${minor}.${patch}+${build_part}"
}

# 设置版本号到 pubspec.yaml
set_version() {
  local new_version="$1"
  local pubspec="$PROJECT_DIR/pubspec.yaml"
  if [[ ! -f "$pubspec" ]]; then
    print_error "pubspec.yaml 不存在: ${pubspec}"
    return 1
  fi
  sed -i '' "s/^version:.*/version: ${new_version}/" "$pubspec"
  print_info "版本文件已更新: ${pubspec}"
}

# ──────────────────────────────────────────────
# Branded DMG 创建
# ──────────────────────────────────────────────

# 确保 create-dmg 工具可用（不存在则下载缓存）
ensure_create_dmg() {
  if [[ -x "$CREATE_DMG_TOOL" ]]; then
    echo "$CREATE_DMG_TOOL"
    return 0
  fi

  print_info "下载 create-dmg v${CREATE_DMG_VERSION}..."
  mkdir -p "$SCRIPTS_DIR/vendor"
  rm -rf "$CREATE_DMG_DIR"
  curl -fsSL "https://github.com/create-dmg/create-dmg/archive/refs/tags/v${CREATE_DMG_VERSION}.tar.gz" \
    | tar -xz -C "$SCRIPTS_DIR/vendor"
  if [[ ! -x "$CREATE_DMG_TOOL" ]]; then
    print_error "create-dmg 下载/解压失败"
    return 1
  fi
  chmod +x "$CREATE_DMG_TOOL"
  echo "$CREATE_DMG_TOOL"
}

# 生成 DMG 背景图（纯 Python，无外部依赖）
generate_dmg_background() {
  local bg_path="$1"
  python3 "$SCRIPTS_DIR/lib/dmg-background.py" "$bg_path"
}

# 创建 branded DMG（背景、图标布局、卷标）
create_branded_dmg() {
  local staging_dir="$1"   # 包含 .app 和 Applications 链接的目录
  local dmg_file="$2"      # 输出路径
  local volname="${3:-$APP_NAME}"

  local create_dmg bg_file dmg_dir
  create_dmg="$(ensure_create_dmg)" || return 1

  # 生成背景图（放在 dmg 同目录，create-dmg 会嵌入到 DMG 中）
  dmg_dir="$(dirname "$dmg_file")"
  bg_file="${dmg_dir}/.dmg-bg-$$.png"
  mkdir -p "$dmg_dir"
  generate_dmg_background "$bg_file" > /dev/null 2>&1

  if [[ ! -f "$bg_file" ]]; then
    print_warning "背景图生成失败，回退为简单 DMG"
    hdiutil create -volname "$volname" -srcfolder "$staging_dir" -ov -format UDZO "$dmg_file" >/dev/null
    return 0
  fi

  print_info "生成 branded DMG: $(basename "$dmg_file")"
  # 注意：不加 --skip-jenkins，否则 AppleScript 被跳过导致无背景/图标布局
  # Finder 会短暂打开（AppleScript 设置样式所需），完成后自动关闭
  # 勿加 --sandbox-safe：也会跳过 AppleScript
  "$create_dmg" \
    --volname "$volname" \
    --background "$bg_file" \
    --window-size 660 400 \
    --icon-size 128 \
    --icon "${APP_NAME}.app" 180 170 \
    --app-drop-link 480 170 \
    --bless \
    "$dmg_file" \
    "$staging_dir" 2>&1 | { grep -v "^$\|^hdiutil: WARNING\|^$\|^Device name:\|^Searching for\|^Mount dir:\|^Copying background\|^Making link\|^Will sleep for\|^Done running\|^Fixing\|^Done fixing\|^Deleting\.\|^Unmounting\|^Compressing\|^\." || true; }
  local result="${PIPESTATUS[0]}"
  rm -f "$bg_file" 2>/dev/null || true
  if [[ $result -ne 0 ]]; then
    print_warning "create-dmg 退出码 $result（AppleScript 可能失败）"
  fi
  return $result

  local result=$?
  rm -f "$bg_file" 2>/dev/null || true
  return $result
}

# 关闭所有与 DMG 相关的 Finder 窗口和已挂载卷（create-dmg AppleScript 可能会打开 Finder）
cleanup_dmg_finder() {
  local volname="${1:-$APP_NAME}"
  # 关闭 Finder 中显示该卷的窗口
  osascript -e "
    tell application \"Finder\"
      set windowList to every window
      repeat with w in windowList
        if (name of w as string) contains \"$volname\" or (name of w as string) contains \"dmg.\" then
          close w
        end if
      end repeat
    end tell" 2>/dev/null || true
  # 卸载残留的临时卷（匹配 dmg.xxxxxx 和卷名）
  local mounted
  mounted=$(hdiutil info 2>/dev/null | grep -i "/Volumes/$volname\|/Volumes/dmg\." | awk '{print $NF}')
  for vol in $mounted; do
    hdiutil detach "$vol" -force > /dev/null 2>&1 || true
  done
}

# ──────────────────────────────────────────────
# 进程检测与替换（macOS）
# ──────────────────────────────────────────────

# 检测 Key Core 是否正在运行
is_keycore_running() {
  local count
  count=$(pgrep -fi "Key Core" 2>/dev/null | grep -v pgrep | wc -l | tr -d ' ')
  [[ "$count" -gt 0 ]] && return 0 || return 1
}

# 等待进程退出（最多等待 N 秒）
wait_keycore_exit() {
  local timeout="${1:-30}"
  local waited=0
  while is_keycore_running && [[ "$waited" -lt "$timeout" ]]; do
    sleep 1
    waited=$((waited + 1))
  done
  if is_keycore_running; then
    return 1  # 超时仍未退出
  fi
  return 0
}

# 优雅终止 Key Core
stop_keycore_graceful() {
  print_info "正在关闭运行中的 Key Core..."
  # 先发送 SIGTERM
  pkill -i "Key Core" 2>/dev/null || true
  if wait_keycore_exit 15; then
    print_info "Key Core 已优雅退出"
    return 0
  fi
  print_warning "优雅退出超时，发送 SIGKILL..."
  pkill -9 -i "Key Core" 2>/dev/null || true
  sleep 1
  if is_keycore_running; then
    print_error "无法终止 Key Core 进程，请手动关闭后重试"
    return 1
  fi
  print_info "Key Core 已强制终止"
  return 0
}

# 强制终止 Key Core（不等待）
force_stop_keycore() {
  pkill -9 -i "Key Core" 2>/dev/null || true
  sleep 1
  if is_keycore_running; then
    print_error "无法终止 Key Core 进程"
    return 1
  fi
  print_info "Key Core 已终止"
  return 0
}

# 替换 /Applications 中的应用
replace_application() {
  local src_app="$1"       # 新构建的 .app 路径
  local dest_app="/Applications/${APP_NAME}.app"

  if [[ ! -d "$src_app" ]]; then
    print_error "源应用不存在: ${src_app}"
    return 1
  fi

  # 如果已安装，先删除旧版本
  if [[ -d "$dest_app" ]]; then
    print_info "删除旧版本应用: ${dest_app}"
    rm -rf "$dest_app"
    if [[ -d "$dest_app" ]]; then
      print_error "无法删除旧版本应用（权限不足？）"
      return 1
    fi
  fi

  print_info "复制新应用到 /Applications..."
  cp -R "$src_app" "$dest_app"
  if [[ $? -ne 0 ]]; then
    print_error "复制应用失败（权限不足？）"
    return 1
  fi

  print_info "修复扩展属性..."
  xattr -cr "$dest_app" 2>/dev/null || true

  print_info "应用已替换完成: ${dest_app}"
  return 0
}

# 打包并替换（供 macOS GitHub 构建脚本调用）
package_and_replace() {
  local dmg_file="$1"

  if [[ ! -f "$dmg_file" ]]; then
    print_error "DMG 文件不存在: ${dmg_file}"
    return 1
  fi

  local mount_point="/tmp/keycore-dmg-mount"
  mkdir -p "$mount_point"

  if ! hdiutil attach "$dmg_file" -nobrowse -mountpoint "$mount_point" > /dev/null 2>&1; then
    print_error "DMG 挂载失败"
    rm -rf "$mount_point"
    return 1
  fi

  # 确认挂载成功
  if [[ ! -d "$mount_point" ]] || [[ -z "$(ls -A "$mount_point" 2>/dev/null)" ]]; then
    print_error "DMG 挂载点无内容"
    hdiutil detach "$mount_point" 2>/dev/null || true
    rm -rf "$mount_point"
    return 1
  fi

  local src_app="$mount_point/${APP_NAME}.app"
  if [[ ! -d "$src_app" ]]; then
    print_error "DMG 中未找到应用: ${src_app}"
    hdiutil detach "$mount_point" 2>/dev/null || true
    return 1
  fi

  replace_application "$src_app"
  local replace_result=$?

  hdiutil detach "$mount_point" > /dev/null 2>&1 || true
  rm -rf "$mount_point" 2>/dev/null || true

  return $replace_result
}

# ──────────────────────────────────────────────
# 交互式菜单（参考 matrees-ai deploy-lib.sh）
# ──────────────────────────────────────────────

# 去掉 ANSI 转义，供菜单选中行纯文本高亮
strip_ansi() {
  local text
  text="$(printf '%b' "$1")"
  printf '%s' "$text" | sed 's/\x1b\[[0-9;]*[a-zA-Z]//g'
}

# 交互式菜单：↑↓ 移动、Enter 确认、或直接输入编号（1-9）
# 用法: select_menu "标题" "选项1" "选项2" ...
# 返回所选编号写入 REPLY 变量
select_menu() {
  local default_selected=1
  if [[ "${1:-}" == "--default" ]]; then
    default_selected="$2"
    shift 2
  fi
  local title="$1"
  shift
  local options=("$@")
  local count=${#options[@]}
  local selected=$default_selected
  local key seq
  local i plain

  if [[ "$count" -lt 1 ]]; then
    print_error "菜单选项为空"
    exit 1
  fi

  if (( default_selected < 1 || default_selected > count )); then
    print_error "默认选项无效: ${default_selected}（共 ${count} 项）"
    exit 1
  fi

  if [[ ! -t 0 ]] || [[ ! -t 1 ]]; then
    select_menu_fallback "$title" "$count" "${options[@]}"
    return
  fi

  local menu_height=$((8 + count))

  select_menu_draw() {
    echo ""
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo -e "${BLUE}          ${title}${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
    echo ""
    for ((i = 0; i < count; i++)); do
      local num=$((i + 1))
      plain="$(strip_ansi "${options[i]}")"
      if [[ "$num" -eq "$selected" ]]; then
        echo -e "  ${CYAN}${BOLD}› ${num}${NC}、${CYAN}${BOLD}${plain}${NC}"
      else
        echo -e "    ${DIM}${num}${NC}、${options[i]}"
      fi
    done
    echo ""
    echo -e "${DIM}  ↑↓ 移动 · Enter 确认 · 或直接输入编号 1-${count}${NC}"
    echo -e "${BLUE}════════════════════════════════════════${NC}"
  }

  select_menu_refresh() {
    if command -v tput &>/dev/null; then
      tput cuu "$menu_height" 2>/dev/null || printf '\033[%dA' "$menu_height"
      tput ed 2>/dev/null || printf '\033[J'
    else
      printf '\033[%dA\033[J' "$menu_height"
    fi
    select_menu_draw
  }

  tput civis 2>/dev/null || true
  select_menu_draw

  while true; do
    IFS= read -rsn1 key || key=""
    case "$key" in
      $'\e')
        IFS= read -rsn2 seq 2>/dev/null || seq=""
        case "$seq" in
          '[A'|'OA') selected=$((selected > 1 ? selected - 1 : count)) ;;
          '[B'|'OB') selected=$((selected < count ? selected + 1 : 1)) ;;
          *) continue ;;
        esac
        select_menu_refresh
        ;;
      ''|$'\n'|$'\r')
        break
        ;;
      [1-9])
        local num=$((10#$key))
        if (( num >= 1 && num <= count )); then
          selected=$num
          break
        fi
        ;;
      q|Q)
        tput cnorm 2>/dev/null || true
        print_warning "已取消"
        exit 0
        ;;
    esac
  done

  tput cnorm 2>/dev/null || true
  echo ""
  REPLY="$selected"
}

# 非 TTY 回退菜单
select_menu_fallback() {
  local title="$1"
  local count="$2"
  shift 2
  local options=("$@")
  local i

  echo ""
  echo -e "${BLUE}════════════════════════════════════════${NC}"
  echo -e "${BLUE}          ${title}${NC}"
  echo -e "${BLUE}════════════════════════════════════════${NC}"
  echo ""
  for ((i = 0; i < count; i++)); do
    echo -e "  $((i + 1))、${options[i]}"
  done
  echo ""
  echo -e "${BLUE}════════════════════════════════════════${NC}"
  read -r -p "请输入选项 (1-${count}): " -n 1 -r REPLY
  echo ""
  if [[ ! "$REPLY" =~ ^[1-9]$ ]] || (( REPLY < 1 || REPLY > count )); then
    print_error "无效的选项"
    exit 1
  fi
}

# 是/否菜单
# 结果写入 REPLY：1=是，2=否
select_yes_no() {
  local title="$1"
  local yes_label="${2:-是}"
  local no_label="${3:-否}"
  local default_choice="${4:-1}"
  local yes_opt="${GREEN}${yes_label}${NC}"
  local no_opt="${YELLOW}${no_label}${NC}"
  if [[ "$default_choice" == "1" ]]; then
    yes_opt="${yes_opt} ${DIM}(默认)${NC}"
  else
    no_opt="${no_opt} ${DIM}(默认)${NC}"
  fi
  select_menu --default "$default_choice" "$title" "$yes_opt" "$no_opt"
}
