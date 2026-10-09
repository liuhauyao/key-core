#!/usr/bin/env bash
# SQLite 原生库预下载与缓存
# 将 sqlite3 的预编译 dylib 下载到 scripts/vendor/sqlite3/，并在构建前复制到 hook 缓存目录
# 从而避免每次构建都从 GitHub 下载
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
VENDOR_DIR="$SCRIPT_DIR/vendor/sqlite3"

# sqlite3 包的版本和下载参数（与 package 版本对齐）
# 如需升级 sqlite3 包版本，同步修改此处
RELEASE_TAG="sqlite3-3.1.0"
BASE_URL="https://github.com/simolus3/sqlite3.dart/releases/download/${RELEASE_TAG}"

# macOS 需要两种架构
ARCHES=("arm64" "x64")

# 下载单个 dylib
download_dylib() {
  local arch="$1"
  local filename="libsqlite3.${arch}.macos.dylib"
  local target="$VENDOR_DIR/$filename"

  if [[ -f "$target" ]]; then
    echo "  ✓ ${filename} 已存在"
    return 0
  fi

  local url="${BASE_URL}/${filename}"
  echo "  ↓ 下载 ${filename}..."

  # 优先使用 GITHUB_PROXY，其次 HTTPS_PROXY，最后直连
  local curl_args=(-fsSL)
  if [[ -n "${GITHUB_PROXY:-}" ]]; then
    # GITHUB_PROXY 是 GitHub 镜像地址（如 https://ghproxy.com）
    # 将原始 URL 拼到镜像后面
    local proxy_url="${GITHUB_PROXY%/}/${url}"
    echo "    通过镜像: ${GITHUB_PROXY}"
    curl "${curl_args[@]}" -o "$target" "$proxy_url" && { echo "  ✓ ${filename} 下载完成"; return 0; }
    echo "    镜像失败，尝试直连..."
  fi

  curl "${curl_args[@]}" -o "$target" "$url" && { echo "  ✓ ${filename} 下载完成"; return 0; }

  echo "  ✗ ${filename} 下载失败"
  rm -f "$target"
  return 1
}

# 计算 hook 缓存目录的 hash
# 模拟 Dart 的 Object.hash(os, arch_name, type, releaseTag)
compute_hash() {
  local arch="$1"
  # Dart 的 Object.hash 使用特定算法，我们直接查表（预先计算好）
  # macOS + arm64 + sqlite3 + sqlite3-3.1.0
  # macOS + x64   + sqlite3 + sqlite3-3.1.0
  case "$arch" in
    arm64) echo "download-b3da26b" ;;
    x64)   echo "download-1e79c268" ;;
    *)     echo "unknown"; return 1 ;;
  esac
}

# 将 vendored dylib 复制到 hook 缓存目录
setup_hook_cache() {
  local all_ok=true

  for arch in "${ARCHES[@]}"; do
    local filename="libsqlite3.${arch}.macos.dylib"
    local vendor_file="$VENDOR_DIR/$filename"
    local hash_dir
    hash_dir="$(compute_hash "$arch")"
    local hook_dir="$PROJECT_DIR/.dart_tool/hooks_runner/shared/sqlite3/build/${hash_dir}"
    local hook_target="$hook_dir/$filename"

    if [[ ! -f "$vendor_file" ]]; then
      echo "  ⚠ ${filename} 未下载，跳过 hook 缓存"
      all_ok=false
      continue
    fi

    mkdir -p "$hook_dir"
    cp "$vendor_file" "$hook_target"
    echo "  ✓ 已缓存 ${filename} → ${hash_dir}/"
  done

  $all_ok && return 0 || return 1
}

# 检查所有 dylib 是否都已下载
check_all_downloaded() {
  for arch in "${ARCHES[@]}"; do
    local filename="libsqlite3.${arch}.macos.dylib"
    if [[ ! -f "$VENDOR_DIR/$filename" ]]; then
      return 1
    fi
  done
  return 0
}

# ──────────────────────────────────────────────
# 主流程
# ──────────────────────────────────────────────

echo ""
echo "SQLite 原生库缓存工具"
echo "═══════════════════════════════════════"

# 确保 vendor 目录
mkdir -p "$VENDOR_DIR"

# 检查是否已全部下载
if check_all_downloaded; then
  echo "所有原生库已缓存"
else
  echo "需要下载的原生库:"
  echo ""
  for arch in "${ARCHES[@]}"; do
    filename="libsqlite3.${arch}.macos.dylib"
    if [[ -f "$VENDOR_DIR/$filename" ]]; then
      echo "  ✓ ${filename}"
    else
      echo "  ☐ ${filename}"
    fi
  done
  echo ""

  # 下载缺失的
  download_ok=true
  for arch in "${ARCHES[@]}"; do
    download_dylib "$arch" || download_ok=false
  done

  if ! $download_ok; then
    echo ""
    echo "部分下载失败，可尝试设置代理后重试："
    echo "  export HTTPS_PROXY=http://127.0.0.1:7890"
    echo "  export GITHUB_PROXY=https://ghproxy.com"
    echo ""
    echo "或手动下载后放到 ${VENDOR_DIR}/"
    echo "  ${BASE_URL}/libsqlite3.arm64.macos.dylib"
    echo "  ${BASE_URL}/libsqlite3.x64.macos.dylib"
    exit 1
  fi
fi

echo ""
echo "设置 hook 缓存..."
setup_hook_cache

echo ""
echo "═══════════════════════════════════════"
echo "SQLite 原生库缓存就绪"
echo "═══════════════════════════════════════"
