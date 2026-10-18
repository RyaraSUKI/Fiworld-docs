#!/usr/bin/env bash
# 一份命令同步工作区：提交本地改动 → 拉取远端 → 推到远端。
# 用法： ./sync.sh            正常同步
#        ./sync.sh "提交说明"  自定义提交信息
set -euo pipefail
cd "$(dirname "$0")"

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  echo "✗ 当前目录不是 git 仓库"; exit 1
fi
if ! git remote get-url origin >/dev/null 2>&1; then
  echo "✗ 尚未配置远端。先执行："
  echo "   git remote add origin <你的仓库地址>"
  exit 1
fi

branch=$(git rev-parse --abbrev-ref HEAD)

# 1) 本地有改动就先提交
if [ -n "$(git status --porcelain)" ]; then
  git add -A
  msg="${1:-sync: $(date '+%Y-%m-%d %H:%M:%S') @$(hostname 2>/dev/null || echo device)}"
  git commit -q -m "$msg"
  echo "✓ 已提交：$msg"
else
  echo "· 本地无改动"
fi

# 2) 拉远端（rebase，历史保持线性）
if git fetch --prune origin >/dev/null 2>&1; then
  if git rev-parse --verify -q "origin/$branch" >/dev/null; then
    if ! git rebase "origin/$branch"; then
      echo "✗ 有冲突。解决后执行： git add -A && git rebase --continue && ./sync.sh"
      exit 1
    fi
  fi
else
  echo "· 远端尚无该分支，跳过拉取"
fi

# 3) 推
git push -u origin "$branch"
echo "✓ 已同步到 origin/$branch（$(git rev-list --count HEAD) 个提交）"
