#!/usr/bin/env bash

set -euo pipefail

# 展示当前仓库的开发服务状态。
# 会同时检查 GUI 模式（Electron）和纯后端模式（yarn dev）的进程与监听端口。

# 项目根目录。通过命令行是否包含当前仓库路径来区分不同本地副本的进程。
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

# 输出状态页头，方便在多个终端间快速确认当前正在检查哪个仓库。
print_header() {
  echo "Toonflow 开发服务状态"
  echo "项目目录：$ROOT_DIR"
  echo
}

# 查询指定 PID 当前监听的 TCP 端口，用于推断访问地址和 API 地址。
find_ports_by_pid() {
  local pid="$1"
  lsof -nP -a -p "$pid" -iTCP -sTCP:LISTEN 2>/dev/null \
    | awk 'NR > 1 { print $9 }' \
    | sed -E 's/.*:([0-9]+)$/\1/' \
    | sort -u || true
}

# 按单个服务块输出模式、PID 和端口信息。
print_service_block() {
  local mode="$1"
  local pid="$2"
  local ports="$3"

  echo "模式：$mode"
  echo "进程 PID：$pid"

  if [ -z "$ports" ]; then
    echo "监听端口：未检测到"
    echo "状态说明：进程存在，但当前没有监听端口，可能正在启动中、已卡死，或已残留未退出。"
    echo
    return
  fi

  echo "监听端口："
  while IFS= read -r port; do
    [ -z "$port" ] && continue
    echo "- $port"
    if [ "$mode" = "GUI 模式（yarn dev:gui）" ]; then
      echo "  页面地址：http://localhost:$port/#/login"
      echo "  后端接口：http://localhost:$port/api"
    else
      echo "  页面地址：http://localhost:$port/#/login"
      echo "  后端接口：http://localhost:$port/api"
    fi
  done <<< "$ports"
  echo
}

print_header

# 查找 GUI 模式进程：Electron 加载 scripts/main.ts。
GUI_PIDS="$(ps -axo pid=,command= | awk -v root="$ROOT_DIR" '
  index($0, root) > 0 && $0 ~ /scripts\/main\.ts/ { print $1 }
' || true)"

# 查找后端模式进程：直接运行 src/app.ts。
DEV_PIDS="$(ps -axo pid=,command= | awk -v root="$ROOT_DIR" '
  index($0, root) > 0 && $0 ~ /src\/app\.ts/ { print $1 }
' || true)"

FOUND=0

if [ -n "$GUI_PIDS" ]; then
  while IFS= read -r pid; do
    [ -z "$pid" ] && continue
    FOUND=1
    PORTS="$(find_ports_by_pid "$pid")"
    print_service_block "GUI 模式（yarn dev:gui）" "$pid" "$PORTS"
  done <<< "$GUI_PIDS"
fi

if [ -n "$DEV_PIDS" ]; then
  while IFS= read -r pid; do
    [ -z "$pid" ] && continue
    FOUND=1
    PORTS="$(find_ports_by_pid "$pid")"
    print_service_block "后端模式（yarn dev）" "$pid" "$PORTS"
  done <<< "$DEV_PIDS"
fi

if [ "$FOUND" -eq 0 ]; then
  echo "当前未检测到 Toonflow 开发服务。"
  echo
  echo "你可以尝试启动："
  echo "- yarn dev"
  echo "- yarn dev:gui"
fi

exit 0
