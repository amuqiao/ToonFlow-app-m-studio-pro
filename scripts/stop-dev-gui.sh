#!/usr/bin/env bash

set -euo pipefail

# 停止当前仓库的全部 GUI 开发进程。
# 这是 cleanup-dev-gui.sh --all 的轻量封装，便于直接记忆和调用。

# 项目根目录。用于定位真正执行清理动作的子脚本。
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLEANUP_SCRIPT="$ROOT_DIR/scripts/cleanup-dev-gui.sh"

# 启动前先确认依赖脚本存在，避免误以为已停止成功。
if [ ! -f "$CLEANUP_SCRIPT" ]; then
  echo "缺少必要脚本：cleanup-dev-gui.sh" >&2
  echo "文件路径：$CLEANUP_SCRIPT" >&2
  exit 1
fi

# stop 不接受附加参数，保持行为固定且可预期。
if [ "$#" -gt 0 ]; then
  echo "用法：bash scripts/stop-dev-gui.sh" >&2
  echo "说明：该命令会停止当前项目的全部 GUI 开发进程。" >&2
  exit 1
fi

echo "正在停止 Toonflow GUI 开发服务"
bash "$CLEANUP_SCRIPT" --all
