#!/usr/bin/env bash
# Undoes one shipped merge on main with a new revert commit (history is not rewritten,
# teammates' commits stay). Works in a temporary worktree, so your checkout is untouched.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

usage() {
  cat <<'EOF'
Usage: scripts/rollback.sh [--dry-run] [--yes] [<номер PR> | <sha merge-коммита>]

Без аргумента показывает последние выкладки, которые можно откатить.
  --dry-run   сделать пробный откат и показать, что изменится, но не пушить
  --yes       не спрашивать подтверждение
EOF
}

WT=""
cleanup() {
  if [ -n "${WT:-}" ]; then
    git worktree remove --force "$WT" >/dev/null 2>&1 || true
    rm -rf "$(dirname "$WT")"
    git worktree prune
  fi
}

# Reverts $SHA on top of the current origin/main inside the worktree.
revert_in_worktree() {
  git -C "$WT" reset --quiet --hard origin/main
  if ! git -C "$WT" revert -m 1 --no-edit "$SHA" >/dev/null 2>&1; then
    local conflicts
    conflicts=$(git -C "$WT" diff --name-only --diff-filter=U)
    git -C "$WT" revert --abort >/dev/null 2>&1 || true
    if [ -z "$conflicts" ]; then
      die "Откатывать нечего: изменений этой выкладки в main уже нет."
    fi
    die "Автоматический откат невозможен: после этой выкладки в main меняли те же строки:
$conflicts
main не тронут. Нужна ручная правка: git revert -m 1 $SHORT"
  fi
}

main() {
  local DRY_RUN=0 TARGET=""
  ASSUME_YES=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --yes) ASSUME_YES=1 ;;
      -h|--help) usage; exit 0 ;;
      -*) usage >&2; die "Неизвестный аргумент: $1" ;;
      *) [ -z "$TARGET" ] || die "Укажи одну выкладку."; TARGET="$1" ;;
    esac
    shift
  done
  export ASSUME_YES

  cd "$(repo_root)"
  git_gh fetch --quiet origin

  if [ -z "$TARGET" ]; then
    info "Выкладки в main, которые можно откатить (последние 10):"
    git log origin/main --merges --grep='^Rollback-Tag: ' -n 10 \
      --date=format:'%d.%m %H:%M' --format='  %h  %ad  %s'
    printf '\nОткат: scripts/rollback.sh <номер PR или sha>\n'
    exit 0
  fi

  # -------------------------------------------------------------- which merge
  # Only PR merge commits are safe for `revert -m 1`: their first parent is main. A local
  # "Merge remote-tracking branch" commit has it the other way round and would wipe main.
  TARGET=${TARGET#\#}
  if grep -qE '^[0-9]{1,6}$' <<<"$TARGET"; then
    require_gh
    SHA=$(gh pr view "$TARGET" --json state,mergeCommit \
      --jq 'if .state == "MERGED" then .mergeCommit.oid else empty end') || die "Не нашёл PR #$TARGET."
    [ -n "$SHA" ] || die "PR #$TARGET ещё не слит, откатывать нечего."
  else
    SHA=$(git rev-parse --verify --quiet "$TARGET^{commit}") || die "Не нашёл коммит $TARGET."
    grep -q '^Rollback-Tag: ' <<<"$(git log -1 --format=%B "$SHA")" \
      || die "Коммит $(git rev-parse --short "$SHA") — не выкладка через ship.sh. Укажи номер PR: scripts/rollback.sh <номер>."
  fi
  SHORT=$(git rev-parse --short "$SHA")

  git merge-base --is-ancestor "$SHA" origin/main || die "Коммит $SHORT не входит в main."
  git rev-parse --quiet --verify "$SHA^2" >/dev/null && ! git rev-parse --quiet --verify "$SHA^3" >/dev/null \
    || die "Коммит $SHORT — не merge-коммит PR. Откатываются только выкладки."
  local already
  already=$(git log origin/main --format=%h --grep="This reverts commit $SHA" -n 1)
  [ -z "$already" ] || die "Выкладка $SHORT уже откачена коммитом $already."

  # -------------------------------------------------------------- trial revert in a temp worktree
  trap cleanup EXIT INT TERM
  WT="$(mktemp -d "${TMPDIR:-/tmp}/defiwawa-rollback.XXXXXX")/wt"
  git worktree add --quiet --detach "$WT" origin/main

  info "Пробный откат $SHORT: $(git log -1 --format=%s "$SHA")"
  revert_in_worktree
  git -C "$WT" show --stat --format='  %s' HEAD | sed '/^$/d'

  local db
  db=$(git diff --name-only --no-renames "$SHA^1" "$SHA" | grep -E '^backend/supabase/(migrations/|seed\.sql)' || true)
  if [ -n "$db" ]; then
    warn "Выкладка меняла миграции или seed.sql:
$db
Откат вернёт файлы, но изменения, уже применённые к базе Supabase, нужно откатить отдельно
(для миграции: supabase migration repair --status reverted <версия>)."
  fi

  if [ "$DRY_RUN" = 1 ]; then
    info "Пробный откат прошёл. Сейчас ничего не запушено; без --dry-run этот коммит уйдёт в main."
    exit 0
  fi
  confirm "Откатить выкладку $SHORT в main?"

  # -------------------------------------------------------------- push the revert
  if ! git_gh -C "$WT" push --quiet origin HEAD:main 2>/dev/null; then
    warn "Пока шёл откат, main сдвинулся. Подтягиваю свежий main и откатываю заново."
    git_gh -C "$WT" fetch --quiet origin
    revert_in_worktree
    git_gh -C "$WT" push --quiet origin HEAD:main || die "Не удалось запушить откат. main не тронут."
  fi
  local revert
  revert=$(git -C "$WT" rev-parse --short HEAD)
  git_gh fetch --quiet origin

  info "Готово: выкладка $SHORT откачена коммитом $revert в main."
  info "Вернуть изменения обратно: git revert $revert (повторно выложить ту же ветку без этого не получится)."
}

main "$@"
exit
