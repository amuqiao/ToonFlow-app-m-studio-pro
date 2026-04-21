#!/usr/bin/env bash

set -euo pipefail

# 清理当前仓库对应的 GUI 开发进程。
# 默认只清理旧进程并保留最新一个；传入 --all 时停止全部 GUI 进程。

# 项目根目录。只处理命令行中带有当前仓库路径的 GUI 进程，避免误杀其他 Toonflow 副本。
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
KILL_ALL=0

# 解析脚本参数。
for arg in "$@"; do
  case "$arg" in
    --all)
      KILL_ALL=1
      ;;
    *)
      echo "未知参数：$arg" >&2
      echo "用法：bash scripts/cleanup-dev-gui.sh [--all]" >&2
      exit 1
      ;;
  esac
done

# 查找当前仓库启动的 GUI 主进程。匹配 scripts/main.ts，可区分不同本地项目副本。
find_gui_pids() {
  ps -axo pid=,command= | awk -v root="$ROOT_DIR" '
    index($0, root) > 0 && $0 ~ /scripts\/main\.ts/ { print $1 }
  ' | sort -n
}

# 查询指定进程的父进程 PID，用于定位 electronmon 外层监控进程。
get_ppid() {
  local pid="$1"
  ps -o ppid= -p "$pid" 2>/dev/null | awk '{print $1}'
}

# 读取指定进程的完整命令行，辅助判断是否需要一并停止外层进程。
get_cmd() {
  local pid="$1"
  ps -o command= -p "$pid" 2>/dev/null
}

# 用 kill -0 判断进程是否仍然存在。
is_alive() {
  local pid="$1"
  kill -0 "$pid" 2>/dev/null
}

# 优先发送正常退出信号，超时后再强制结束，避免遗留僵尸监听端口。
kill_pid() {
  local pid="$1"
  local label="$2"

  if ! is_alive "$pid"; then
    return
  fi

  echo "正在停止 ${label}：PID ${pid}"
  kill "$pid" 2>/dev/null || true

  for _ in 1 2 3 4 5; do
    if ! is_alive "$pid"; then
      return
    fi
    sleep 1
  done

  if is_alive "$pid"; then
    echo "${label} 未在预期时间内退出，正在强制结束：PID ${pid}"
    kill -9 "$pid" 2>/dev/null || true
  fi
}

# 收集当前仓库的全部 GUI 进程，并决定是保留最新一个还是全部清理。
GUI_PIDS="$(find_gui_pids)"

if [ -z "$GUI_PIDS" ]; then
  echo "当前没有检测到 Toonflow 的 GUI 开发进程。"
  exit 0
fi

KEEP_PID="$(printf '%s\n' "$GUI_PIDS" | tail -n 1)"

echo "检测到以下 GUI 开发进程："
while IFS= read -r pid; do
  [ -z "$pid" ] && continue
  echo "- PID $pid"
done <<< "$GUI_PIDS"
echo

if [ "$KILL_ALL" -eq 1 ]; then
  echo "本次将清理全部 GUI 开发进程。"
else
  echo "将保留最新启动的 GUI 进程：PID $KEEP_PID"
fi
echo

STOPPED=0

# 按顺序清理旧 GUI 进程；如果其父进程是 electronmon，也一并结束，避免自动拉起。
while IFS= read -r pid; do
  [ -z "$pid" ] && continue
  if [ "$KILL_ALL" -ne 1 ] && [ "$pid" = "$KEEP_PID" ]; then
    continue
  fi

  PARENT_PID="$(get_ppid "$pid")"
  PARENT_CMD="$(get_cmd "$PARENT_PID")"

  kill_pid "$pid" "旧 GUI 主进程"
  STOPPED=1

  if [ -n "$PARENT_PID" ] && [[ "$PARENT_CMD" == *"electronmon"* ]]; then
    kill_pid "$PARENT_PID" "对应的 electronmon 进程"
  fi
done <<< "$GUI_PIDS"

if [ "$STOPPED" -eq 0 ]; then
  echo "当前只有一个 GUI 开发进程，无需清理。"
  exit 0
fi

sleep 1

echo
if [ "$KILL_ALL" -eq 1 ]; then
  echo "清理完成。当前已停止全部 GUI 开发进程。"
else
  echo "清理完成。当前保留的 GUI 进程：PID $KEEP_PID"
fi
