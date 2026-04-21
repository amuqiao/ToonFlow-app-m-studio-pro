#!/usr/bin/env bash

set -euo pipefail

# Toonflow GUI 开发总控脚本。
# 对外提供 start / stop / status / cleanup / restart 等统一入口，避免记忆多个子脚本。

# 项目根目录。所有子脚本都从这里派生，确保控制的是当前仓库而不是其他副本。
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

START_SCRIPT="$ROOT_DIR/scripts/start-dev-gui.sh"
STATUS_SCRIPT="$ROOT_DIR/scripts/show-dev-service.sh"
CLEANUP_SCRIPT="$ROOT_DIR/scripts/cleanup-dev-gui.sh"
STOP_SCRIPT="$ROOT_DIR/scripts/stop-dev-gui.sh"

# 输出命令级帮助，统一说明总控脚本支持的能力和常用场景。
usage() {
  echo "Toonflow GUI 开发总控脚本"
  echo
  echo "用法：bash scripts/dev-gui-manager.sh <命令> [附加参数]"
  echo
  echo "可用命令："
  echo "- start      启动 GUI 开发环境"
  echo "- stop       停止当前全部 GUI 开发进程"
  echo "- status     查看当前开发服务状态"
  echo "- cleanup    清理旧的 GUI 开发进程，仅保留最新一个"
  echo "- restart    清理全部旧 GUI 进程后，重新前台启动 GUI 开发环境"
  echo "- help       显示帮助信息"
  echo
  echo "完整示例："
  echo "- bash scripts/dev-gui-manager.sh start"
  echo "- bash scripts/dev-gui-manager.sh start --prepare-only"
  echo "- bash scripts/dev-gui-manager.sh start --reset-db"
  echo "- bash scripts/dev-gui-manager.sh stop"
  echo "- bash scripts/dev-gui-manager.sh status"
  echo "- bash scripts/dev-gui-manager.sh cleanup"
  echo "- bash scripts/dev-gui-manager.sh cleanup --all"
  echo "- bash scripts/dev-gui-manager.sh restart"
  echo "- bash scripts/dev-gui-manager.sh restart --reset-db"
  echo
  echo "常用场景："
  echo "- 正常启动开发环境：bash scripts/dev-gui-manager.sh start"
  echo "- 停止当前 GUI 开发环境：bash scripts/dev-gui-manager.sh stop"
  echo "- 查看当前访问地址和端口：bash scripts/dev-gui-manager.sh status"
  echo "- 清理旧 GUI，只保留最新一个：bash scripts/dev-gui-manager.sh cleanup"
  echo "- 彻底重启 GUI 开发环境：bash scripts/dev-gui-manager.sh restart"
  echo "- 怀疑本地数据库有问题时重启：bash scripts/dev-gui-manager.sh restart --reset-db"
}

# 启动前先检查依赖子脚本是否存在，避免运行到一半才因缺文件中断。
ensure_script_exists() {
  local path="$1"
  local label="$2"
  if [ ! -f "$path" ]; then
    echo "缺少必要脚本：$label" >&2
    echo "文件路径：$path" >&2
    exit 1
  fi
}

# 透传到 GUI 启动脚本。真正的资源同步、数据库准备和 GUI 启动逻辑都在 start 脚本中。
run_start() {
  bash "$START_SCRIPT" "$@"
}

# 查询当前开发服务状态，包括 PID、端口和访问地址。
run_status() {
  bash "$STATUS_SCRIPT"
}

# 清理旧 GUI 进程。默认保留最新一个，传 --all 时清空全部。
run_cleanup() {
  bash "$CLEANUP_SCRIPT" "$@"
}

# 停止当前仓库的全部 GUI 开发进程。
run_stop() {
  bash "$STOP_SCRIPT"
}

# restart 采用“先清理、再前台启动”的策略，适合代码改动后强制加载最新运行时资源。
run_restart() {
  echo "第 1 步：清理旧的 GUI 开发进程"
  run_cleanup --all
  echo
  echo "第 2 步：重新启动 GUI 开发环境"
  echo "说明：restart 会以前台方式启动。"
  echo "如果需要查看端口和访问地址，请在另一个终端执行："
  echo "bash scripts/dev-gui-manager.sh status"
  echo
  run_start "$@"
}

# 解析一级命令，其余参数继续透传给对应子脚本。
COMMAND="${1:-help}"
if [ "$#" -gt 0 ]; then
  shift
fi

ensure_script_exists "$START_SCRIPT" "start-dev-gui.sh"
ensure_script_exists "$STATUS_SCRIPT" "show-dev-service.sh"
ensure_script_exists "$CLEANUP_SCRIPT" "cleanup-dev-gui.sh"
ensure_script_exists "$STOP_SCRIPT" "stop-dev-gui.sh"

case "$COMMAND" in
  start)
    run_start "$@"
    ;;
  stop)
    if [ "$#" -gt 0 ]; then
      echo "stop 命令不接受附加参数。" >&2
      exit 1
    fi
    run_stop
    ;;
  status)
    if [ "$#" -gt 0 ]; then
      echo "status 命令不接受附加参数。" >&2
      exit 1
    fi
    run_status
    ;;
  cleanup)
    if [ "$#" -gt 1 ]; then
      echo "cleanup 命令最多只接受一个参数：--all" >&2
      exit 1
    fi
    if [ "$#" -eq 1 ] && [ "${1:-}" != "--all" ]; then
      echo "cleanup 命令只支持参数：--all" >&2
      exit 1
    fi
    run_cleanup "$@"
    ;;
  restart)
    run_restart "$@"
    ;;
  help|-h|--help)
    usage
    ;;
  *)
    echo "未知命令：$COMMAND" >&2
    echo >&2
    usage >&2
    exit 1
    ;;
esac
