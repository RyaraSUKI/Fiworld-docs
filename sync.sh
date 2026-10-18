#!/usr/bin/env bash
# 一条命令同步工作区：整理空目录 → 追加交接记录 → 提交 → 拉取 → 推送
#
# 用法：
#   bash sync.sh                              例行同步（自动生成记录）
#   bash sync.sh "做了什么"                    写明本次做了什么
#   bash sync.sh "做了什么" "下一步该做什么"    同时告诉下一个接手的 agent
#   bash sync.sh --local "做了什么"            只本地提交，不推送（无远端/离线时用）
#
# 约定：每次推送都会在《同步说明.md》的「变更记录」末尾追加一条，
#       记录谁、何时、改了什么、下一手该做什么。
set -euo pipefail
cd "$(dirname "$0")"

LOG_DOC='同步说明.md'
LOG_HEAD='## 九、变更记录'
LOCAL_ONLY=0
if [ "${1:-}" = "--local" ]; then LOCAL_ONLY=1; shift; fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "✗ 当前目录不是 git 仓库"; exit 1
fi
if [ "$LOCAL_ONLY" -eq 0 ] && ! git remote get-url origin >/dev/null 2>&1; then
  echo "✗ 尚未配置远端。先执行："
  echo "   git remote add origin git@github.com:<用户名>/<仓库名>.git"
  echo "  （仅想本地提交： bash sync.sh --local \"说明\"）"
  exit 1
fi

branch=$(git rev-parse --abbrev-ref HEAD)
# 设备名：优先用本仓库的本地配置 sync.device（不随仓库同步，每台设备各自设置）
device=$(git config --get sync.device 2>/dev/null || true)
[ -z "$device" ] && device=$(hostname 2>/dev/null || echo device)
now=$(date '+%Y-%m-%d %H:%M')

# ── 1) 空文件夹也纳入版本管理：给每个空目录放一个占位文件 ──
added=0
while IFS= read -r d; do
  [ "$d" = "." ] && continue
  if [ -z "$(find "$d" -type f -not -path './.git/*' -print -quit 2>/dev/null)" ]; then
    : > "$d/.gitkeep"
    echo "· 空目录占位：$d/.gitkeep"
    added=$((added+1))
  fi
done < <(find . -path ./.git -prune -o -type d -print | sort -r)
[ "$added" -eq 0 ] && echo "· 无需补充空目录占位"

# ── 2) 统计本次改动（在写记录之前抓，避免把记录本身算进去）──
changes=$(git status --porcelain -uall)
count=0
[ -n "$changes" ] && count=$(printf '%s\n' "$changes" | wc -l | tr -d ' ')

# ── 3) 追加交接记录 ──
msg="${1:-}"
next="${2:-}"
if [ -z "$msg" ] && [ "$count" -eq 0 ]; then
  echo "· 无本地改动，跳过交接记录"
else
  [ -z "$msg" ] && msg="例行同步（${count} 项改动）"
  [ -z "$next" ] && next="（未指定）——接手前先读《同步说明》第〇节，再按需继续。"
  [ -f "$LOG_DOC" ] || printf '# 跨设备同步方案（DSH 工作区）\n\n' > "$LOG_DOC"
  grep -q "^${LOG_HEAD}" "$LOG_DOC" || printf '\n---\n\n%s\n' "$LOG_HEAD" >> "$LOG_DOC"
  {
    printf '\n### %s · 设备 `%s`\n\n' "$now" "$device"
    printf -- '- **做了什么**：%s\n' "$msg"
    if [ "$count" -eq 0 ]; then
      printf -- '- **改动文件**：无（仅有记录追加）\n'
    else
      printf -- '- **改动文件**（%s）：\n\n```\n%s\n```\n' "$count" "$changes"
    fi
    printf -- '- **下一步**：%s\n' "$next"
  } >> "$LOG_DOC"
  echo "✓ 已追加交接记录（$count 项改动）"
fi

# ── 4) 提交 ──
if [ -n "$(git status --porcelain)" ]; then
  git add -A
  git commit -q -m "${msg}"
  echo "✓ 已提交：${msg}"
else
  echo "· 无内容可提交"
fi

[ "$LOCAL_ONLY" -eq 1 ] && { echo "✓ 仅本地提交（未推送）"; exit 0; }

# ── 5) 拉取（rebase，保持线性历史）──
if git fetch --prune origin >/dev/null 2>&1 && git rev-parse --verify -q "origin/$branch" >/dev/null; then
  if ! git rebase "origin/$branch"; then
    echo "✗ 有冲突。解决后执行："
    echo "   git add -A && git rebase --continue && bash sync.sh --local \"解决冲突\""
    exit 1
  fi
fi

# ── 6) 推送 ──
git push -u origin "$branch"
echo "✓ 已同步到 origin/$branch（共 $(git rev-list --count HEAD) 个提交）"
