#!/usr/bin/env bash

set -euo pipefail

# 启动 Toonflow GUI 开发环境。
# 这个脚本会准备 Electron 运行目录、同步内置资源、处理开发数据库，并最终以前台方式启动 GUI。

# 项目根目录。后续资源同步、数据库复制和 GUI 启动都以这个目录为基准。
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
RESET_DB=0
PREPARE_ONLY=0

# 解析启动参数。
for arg in "$@"; do
  case "$arg" in
    --reset-db)
      RESET_DB=1
      ;;
    --prepare-only)
      PREPARE_ONLY=1
      ;;
    *)
      echo "未知参数：$arg" >&2
      echo "用法：bash scripts/start-dev-gui.sh [--reset-db] [--prepare-only]" >&2
      exit 1
      ;;
  esac
done

# 保证启动脚本始终使用项目要求的 Node 版本。
# 这里读取根目录 .nvmrc，并通过 nvm 切换版本，避免新终端回落到系统默认 Node。
ensure_project_node_version() {
  local nvm_dir="${NVM_DIR:-$HOME/.nvm}"
  local nvm_script="$nvm_dir/nvm.sh"
  local nvmrc_path="$ROOT_DIR/.nvmrc"
  local expected_version current_version

  if [ ! -f "$nvmrc_path" ]; then
    return 0
  fi

  expected_version="$(tr -d '[:space:]' < "$nvmrc_path")"
  if [ -z "$expected_version" ]; then
    return 0
  fi

  if [ ! -s "$nvm_script" ]; then
    echo "未找到 nvm，无法自动切换到 Node $expected_version。" >&2
    echo "请先安装 nvm，或手动切换到正确版本后再启动。" >&2
    exit 1
  fi

  # shellcheck disable=SC1090
  . "$nvm_script"
  nvm use "$expected_version" >/dev/null

  current_version="$(node -v)"
  echo "当前 Node 版本：$current_version"
}

# 根据操作系统确定 Electron 用户数据目录。
# GUI 开发模式实际读写的是这个目录，而不是仓库内 data 目录。
case "$(uname -s)" in
  Darwin)
    ELECTRON_DATA_DIR="$HOME/Library/Application Support/Electron/data"
    ;;
  Linux)
    ELECTRON_DATA_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/Electron/data"
    ;;
  *)
    echo "当前系统暂不支持：$(uname -s)" >&2
    echo "这个脚本目前只支持 macOS 和 Linux。" >&2
    exit 1
    ;;
esac

SOURCE_DATA_DIR="$ROOT_DIR/data"
TARGET_DB_PATH="$ELECTRON_DATA_DIR/db2.sqlite"
SOURCE_DB_PATH="$SOURCE_DATA_DIR/db2.sqlite"
TIMESTAMP="$(date +%Y%m%d-%H%M%S)"

# 在执行 electron-rebuild 和 yarn dev:gui 之前，先切到项目要求的 Node 版本。
ensure_project_node_version

echo "[1/4] 正在重编译 Electron 原生模块：better-sqlite3"
"$ROOT_DIR/node_modules/.bin/electron-rebuild" -f -w better-sqlite3

echo "[2/4] 正在检查 Electron 用户数据目录"
mkdir -p "$ELECTRON_DATA_DIR"

echo "[3/4] 正在同步内置资源到 Electron 用户目录"
for entry in assets models skills vendor web; do
  if [ -e "$SOURCE_DATA_DIR/$entry" ]; then
    rsync -a "$SOURCE_DATA_DIR/$entry" "$ELECTRON_DATA_DIR/"
  fi
done

# 数据库首次缺失时复制基线库；显式要求重置时先备份再覆盖；其他情况保留当前开发数据。
if [ ! -f "$TARGET_DB_PATH" ]; then
  echo "[4/4] 正在复制基线开发数据库"
  cp "$SOURCE_DB_PATH" "$TARGET_DB_PATH"
elif [ "$RESET_DB" -eq 1 ]; then
  echo "[4/4] 正在重置 Electron 开发数据库"
  mv "$TARGET_DB_PATH" "$TARGET_DB_PATH.bak-$TIMESTAMP"
  cp "$SOURCE_DB_PATH" "$TARGET_DB_PATH"
else
  echo "[4/4] 保留现有 Electron 开发数据库"
fi

if [ "$PREPARE_ONLY" -eq 1 ]; then
  echo "环境准备完成。"
  exit 0
fi

# 以前台方式启动，便于直接观察 Electron/后端日志输出。
echo "正在启动 Toonflow GUI 开发模式"
cd "$ROOT_DIR"
exec yarn dev:gui
