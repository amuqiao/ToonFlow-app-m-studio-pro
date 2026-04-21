#!/usr/bin/env bash

set -euo pipefail

# 清理 Toonflow 图片生成失败记录。
# 默认作用于 Electron GUI 开发环境正在使用的数据库：
#   ~/Library/Application Support/Electron/data/db2.sqlite
#
# 支持能力：
# - 删除 o_image 表中 state = "生成失败" 的记录
# - 清空 o_assets.imageId 对这些失败记录的引用
# - 如果失败记录残留了文件路径，则同时删除对应 OSS 文件
#
# 使用示例：
# - 先预览，不实际删除
#   bash scripts/cleanup-failed-images.sh --dry-run
# - 清理当前 GUI 开发库中的失败图
#   bash scripts/cleanup-failed-images.sh
# - 清理仓库自带 data/db2.sqlite 中的失败图
#   bash scripts/cleanup-failed-images.sh --repo-db
#
# 参数说明：
# - --electron-db  清理 Electron 开发库，默认值
# - --repo-db      清理仓库 data/db2.sqlite
# - --dry-run      只预览，不实际删除
# - --help         显示帮助

# 项目根目录。用于定位仓库自带 data 目录，并固定脚本执行上下文。
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

cd "$ROOT_DIR"

# 通过内联 Python 处理 SQLite 和文件清理，避免依赖额外脚本文件。
python3 - "$ROOT_DIR" "$@" <<'EOF'
import os
import sqlite3
import sys
from pathlib import Path

root_dir = Path(sys.argv[1]).resolve()
args = sys.argv[2:]

# 解析清理目标和是否只预览。
mode = "electron"
dry_run = False

for arg in args:
    if arg == "--repo-db":
        mode = "repo"
    elif arg == "--electron-db":
        mode = "electron"
    elif arg == "--dry-run":
        dry_run = True
    elif arg in ("--help", "-h"):
        print("清理失败图片记录脚本")
        print("")
        print("用法:")
        print("  bash scripts/cleanup-failed-images.sh [--electron-db|--repo-db] [--dry-run]")
        print("")
        print("参数:")
        print("  --electron-db  清理 Electron 开发库，默认值")
        print("  --repo-db      清理仓库 data/db2.sqlite")
        print("  --dry-run      只预览，不实际删除")
        print("")
        print("示例:")
        print("  bash scripts/cleanup-failed-images.sh --dry-run")
        print("  bash scripts/cleanup-failed-images.sh")
        print("  bash scripts/cleanup-failed-images.sh --repo-db")
        sys.exit(0)
    else:
        raise SystemExit(f"清理失败: 未知参数: {arg}")

# 根据模式决定数据库和 OSS 根目录。Electron 模式清理当前 GUI 实际使用的数据目录。
if mode == "repo":
    data_root = root_dir / "data"
else:
    home = os.environ.get("HOME")
    if not home:
        raise SystemExit("清理失败: 未找到 HOME 环境变量")
    data_root = Path(home) / "Library" / "Application Support" / "Electron" / "data"

db_path = data_root / "db2.sqlite"
oss_root = data_root / "oss"

if not db_path.exists():
    raise SystemExit(f"清理失败: 数据库不存在: {db_path}")

# 失败图以数据库状态为准；历史坏图但状态为“已完成”的记录不在这个脚本的处理范围内。
conn = sqlite3.connect(str(db_path))
conn.row_factory = sqlite3.Row
rows = conn.execute(
    """
    SELECT id, assetsId, filePath, state, errorReason
    FROM o_image
    WHERE state = ?
    """,
    ("生成失败",),
).fetchall()

print(f"目标数据库: {db_path}")
print(f"模式: {mode}")
print(f"失败图片记录数: {len(rows)}")

if not rows:
    conn.close()
    sys.exit(0)

existing_file_rows = [row for row in rows if row["filePath"]]
if existing_file_rows:
    print(f"其中带文件路径的失败记录: {len(existing_file_rows)}")

if dry_run:
    for row in rows[:20]:
        print(
            f"- imageId={row['id']} assetsId={row['assetsId']} filePath={row['filePath']} reason={row['errorReason'] or ''}"
        )
    if len(rows) > 20:
        print(f"... 其余 {len(rows) - 20} 条省略")
    conn.close()
    sys.exit(0)

file_delete_count = 0

try:
    # 先清空 o_assets 对失败图的引用，再删除 o_image 记录，避免留下悬挂外键语义。
    conn.execute("BEGIN")
    for row in rows:
      conn.execute("UPDATE o_assets SET imageId = NULL WHERE imageId = ?", (row["id"],))
      conn.execute("DELETE FROM o_image WHERE id = ?", (row["id"],))

      # filePath 存的是 oss 相对路径，这里拼回绝对路径后再做一次越界校验，避免误删。
      file_path = row["filePath"]
      if file_path:
          normalized = file_path.lstrip("/\\").replace("/", os.sep)
          abs_path = (oss_root / normalized).resolve()
          if not str(abs_path).startswith(str(oss_root.resolve())):
              raise RuntimeError(f"检测到异常路径: {file_path}")
          if abs_path.is_file():
              abs_path.unlink()
              file_delete_count += 1
    conn.commit()
except Exception as exc:
    conn.rollback()
    conn.close()
    raise SystemExit(f"清理失败: {exc}")

conn.close()
print(f"已删除失败图片记录: {len(rows)}")
print(f"已删除失败图片文件: {file_delete_count}")
EOF
