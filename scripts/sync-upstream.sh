#!/usr/bin/env bash
# 将原始仓库（upstream）的最新代码同步到当前 fork，同时保留本地修改。
#
# 用法：
#   scripts/sync-upstream.sh              # 合并 upstream/main 到当前分支
#   scripts/sync-upstream.sh --push       # 合并后推送到 origin
#   scripts/sync-upstream.sh --dry-run    # 只查看 upstream 有哪些新提交，不做修改
#   scripts/sync-upstream.sh --rebase     # 用 rebase 代替 merge（推送时需要强推）
#   scripts/sync-upstream.sh --stash      # 自动暂存未提交的修改，同步后恢复
#
# 环境变量：
#   UPSTREAM_URL     原始仓库地址（默认 bytedance/deer-flow）
#   UPSTREAM_BRANCH  要同步的上游分支（默认 main）

set -euo pipefail

UPSTREAM_URL="${UPSTREAM_URL:-https://github.com/bytedance/deer-flow.git}"
UPSTREAM_BRANCH="${UPSTREAM_BRANCH:-main}"

do_push=false
dry_run=false
use_rebase=false
use_stash=false

for arg in "$@"; do
  case "$arg" in
    --push) do_push=true ;;
    --dry-run) dry_run=true ;;
    --rebase) use_rebase=true ;;
    --stash) use_stash=true ;;
    -h|--help) sed -n '2,14p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "未知参数：$arg（使用 --help 查看用法）" >&2; exit 2 ;;
  esac
done

info()  { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn()  { printf '\033[1;33m警告：\033[0m%s\n' "$*" >&2; }
fail()  { printf '\033[1;31m错误：\033[0m%s\n' "$*" >&2; exit 1; }

# 切换到仓库根目录，保证从任意位置调用都能工作
repo_root="$(git rev-parse --show-toplevel 2>/dev/null)" || fail "当前不在 git 仓库中"
cd "$repo_root"

# 若有未完成的 merge/rebase，先让用户处理
git_dir="$(git rev-parse --git-dir)"
if [[ -f "$git_dir/MERGE_HEAD" || -d "$git_dir/rebase-merge" || -d "$git_dir/rebase-apply" ]]; then
  fail "存在未完成的 merge/rebase，请先解决冲突并提交，或执行 git merge --abort / git rebase --abort"
fi

current_branch="$(git symbolic-ref --short -q HEAD)" || fail "当前处于 detached HEAD 状态，请先切换到分支"

# 确保 upstream 远程存在
if ! git remote get-url upstream >/dev/null 2>&1; then
  info "添加 upstream 远程：$UPSTREAM_URL"
  git remote add upstream "$UPSTREAM_URL"
fi

info "拉取 upstream ..."
git fetch upstream --tags --prune
upstream_ref="upstream/$UPSTREAM_BRANCH"
git rev-parse --verify -q "$upstream_ref" >/dev/null || fail "上游分支 $upstream_ref 不存在"

# 统计双方差异：behind = 上游有而本地没有，ahead = 本地独有
read -r ahead behind < <(git rev-list --left-right --count "HEAD...$upstream_ref")
info "分支 $current_branch：本地独有 $ahead 个提交，上游新增 $behind 个提交"

if (( behind == 0 )); then
  info "已是最新，无需同步"
  if $do_push && (( ahead > 0 )); then
    info "推送到 origin/$current_branch ..."
    git push origin "$current_branch"
  fi
  exit 0
fi

if $dry_run; then
  info "上游新增的提交（最多显示 30 条）："
  git --no-pager log --oneline --no-decorate -n 30 "HEAD..$upstream_ref"
  # 预测可能冲突的文件：双方都改动过的文件
  base="$(git merge-base HEAD "$upstream_ref")"
  overlap="$(comm -12 <(git diff --name-only "$base" HEAD | sort) \
                      <(git diff --name-only "$base" "$upstream_ref" | sort))"
  if [[ -n "$overlap" ]]; then
    warn "以下文件双方都有修改，可能产生冲突："
    printf '  %s\n' $overlap
  fi
  exit 0
fi

# 检查已跟踪文件是否有未提交修改（未跟踪文件不影响合并）
stashed=false
if ! git diff --quiet || ! git diff --cached --quiet; then
  if $use_stash; then
    info "暂存未提交的修改 ..."
    git stash push -m "sync-upstream 自动暂存 $(date '+%F %T')"
    stashed=true
  else
    fail "存在未提交的修改。请先提交（git commit），或使用 --stash 自动暂存"
  fi
fi

# 记录同步前的位置，方便回滚
before="$(git rev-parse --short HEAD)"

sync_ok=true
if $use_rebase; then
  info "rebase 到 $upstream_ref ..."
  git rebase "$upstream_ref" || sync_ok=false
else
  info "合并 $upstream_ref ..."
  git merge --no-edit "$upstream_ref" -m "Merge $upstream_ref into $current_branch" || sync_ok=false
fi

if ! $sync_ok; then
  warn "同步出现冲突，以下文件需要手动解决："
  git diff --name-only --diff-filter=U | sed 's/^/  /' >&2
  if $use_rebase; then
    echo "解决后执行：git add <文件> && git rebase --continue；放弃：git rebase --abort" >&2
  else
    echo "解决后执行：git add <文件> && git commit；放弃：git merge --abort" >&2
  fi
  $stashed && echo "注意：你的未提交修改仍在 stash 中，处理完冲突后执行 git stash pop 恢复" >&2
  exit 1
fi

info "同步完成（同步前位于 $before，如需回滚：git reset --hard $before）"

if $stashed; then
  info "恢复暂存的修改 ..."
  git stash pop || warn "恢复 stash 时出现冲突，请手动解决（修改仍保存在 git stash list 中）"
fi

if $do_push; then
  info "推送到 origin/$current_branch ..."
  if $use_rebase; then
    git push --force-with-lease origin "$current_branch"
  else
    git push origin "$current_branch"
  fi
fi
