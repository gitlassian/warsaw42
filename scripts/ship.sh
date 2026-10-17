#!/usr/bin/env bash
# Ships the current branch to main so that it can be undone with one command:
# merge fresh main, run the checks for the touched areas, merge the PR as a single
# merge commit and tag the main it was merged into. Undo with scripts/rollback.sh.
# Details: scripts/README.md.
set -euo pipefail
. "$(dirname "$0")/lib.sh"

usage() {
  cat <<'EOF'
Usage: scripts/ship.sh [--dry-run] [--yes] [--title "Заголовок PR"]

Выкладывает текущую ветку в main через PR с merge-коммитом и тегом для отката.
  --dry-run   всё проверить, но ничего не пушить и не сливать
  --yes       не спрашивать подтверждение для рискованных файлов
  --title     заголовок PR (по умолчанию — последний коммит ветки)
EOF
}

is_safe() {
  case "$1" in
    docs/*|fixtures/*|postman/*) return 0 ;;
    scripts/ship.sh|scripts/rollback.sh|scripts/lib.sh|scripts/README.md) return 0 ;;
    *) return 1 ;;
  esac
}

check() {
  local dir="$1"
  shift
  info "Проверка: (cd $dir && $*)"
  (cd "$dir" && "$@") || die "Проверка упала: $*. Ничего не запушено."
}

# The whole body lives in main(): `git merge` below may rewrite this very file while it runs.
main() {
  local DRY_RUN=0 TITLE=""
  ASSUME_YES=0
  while [ $# -gt 0 ]; do
    case "$1" in
      --dry-run) DRY_RUN=1 ;;
      --yes) ASSUME_YES=1 ;;
      --title) [ $# -ge 2 ] || die "--title требует значение."; TITLE="$2"; shift ;;
      -h|--help) usage; exit 0 ;;
      *) usage >&2; die "Неизвестный аргумент: $1" ;;
    esac
    shift
  done
  export ASSUME_YES

  cd "$(repo_root)"

  # ---------------------------------------------------------------- 1. preconditions
  local BRANCH
  BRANCH=$(git symbolic-ref --quiet --short HEAD) || die "HEAD не на ветке. Переключись на свою ветку."
  [ "$BRANCH" != main ] || die "Выкладка идёт из своей ветки, а не из main. Создай ветку: git switch -c <имя>"
  [ -z "$(git status --porcelain)" ] || die "Рабочее дерево не чистое. Закоммить или убери изменения (git status)."
  [ "$DRY_RUN" = 1 ] || require_gh

  # ---------------------------------------------------------------- 2. fresh main
  info "Подтягиваю свежий main"
  git_gh fetch --quiet origin
  START=$(git rev-parse HEAD)
  if [ "$DRY_RUN" = 1 ]; then
    # A dry run may merge main locally to test the result; the branch is put back on exit.
    trap 'git reset --quiet --hard "$START"' EXIT
  fi
  if ! git merge-base --is-ancestor origin/main HEAD; then
    if ! git merge --quiet --no-edit origin/main >/dev/null 2>&1; then
      local CONFLICTS
      CONFLICTS=$(git diff --name-only --diff-filter=U)
      git merge --abort
      die "Конфликт с main в файлах:
$CONFLICTS
Ничего не запушено. Разреши конфликт вручную (git merge origin/main), закоммить и запусти снова."
    fi
  fi
  local BASE
  BASE=$(git rev-parse origin/main)

  # A rollback of this branch's earlier ship, now merged in from main, would silently drop
  # the branch's work from the PR.
  local x
  for x in $(git log --format=%B "$START..HEAD" | sed -n 's/^This reverts commit \([0-9a-f]\{40\}\).*/\1/p'); do
    if git rev-parse --quiet --verify "$x^2" >/dev/null && git merge-base --is-ancestor "$x^2" "$START"; then
      die "Изменения этой ветки уже выкладывались и были откачены (коммит $(git rev-parse --short "$x")).
Чтобы выложить их снова, сначала верни их: git revert <sha коммита отката>, либо сделай новую ветку от main."
    fi
  done

  # ---------------------------------------------------------------- 3. what changes
  local CHANGED
  CHANGED=$(git diff --name-only --no-renames "$BASE" HEAD)
  if [ -z "$CHANGED" ]; then
    info "Нечего выкладывать: ветка не отличается от main."
    exit 0
  fi

  # ---------------------------------------------------------------- 4. safe or risky
  local RISKY="" f
  while IFS= read -r f; do
    is_safe "$f" || RISKY="$RISKY  $f
"
  done <<<"$CHANGED"

  info "Меняются файлы ($(wc -l <<<"$CHANGED" | tr -d ' ')):"
  sed 's/^/  /' <<<"$CHANGED"
  if grep -qE '^backend/supabase/(migrations/|seed\.sql)' <<<"$CHANGED"; then
    warn "Есть миграции или seed.sql. Слияние их не применяет, а git revert НЕ откатит то, что уже применено к базе Supabase.
    Если откатишь уже применённую миграцию, supabase db push потребует: supabase migration repair --status reverted <версия>."
  fi
  if grep -qE '^\.github/' <<<"$CHANGED"; then
    warn "Меняется .github/: это влияет на автоматические задачи в репозитории."
  fi
  if [ -n "$RISKY" ]; then
    warn "Эти файлы относятся к коду приложения или инфраструктуре:"
    printf '%s' "$RISKY" >&2
    confirm "Выкладывать изменения в коде?"
  fi

  # ---------------------------------------------------------------- 5. checks
  check backend npm test --silent
  check backend python3 -m pytest -q tests
  if grep -qE '^fixtures/' <<<"$CHANGED"; then
    check . python3 fixtures/check_fixtures.py
  fi
  while IFS= read -r f; do
    if [ -f "$f" ]; then
      check . python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$f"
    fi
  done <<<"$(grep -E '^postman/.*\.json$' <<<"$CHANGED" || true)"
  if grep -qE '^frontend/web/' <<<"$CHANGED"; then
    [ -d frontend/web/node_modules ] || check frontend/web npm ci --no-audit --no-fund
    check frontend/web npm test
    check frontend/web npm run build
    check frontend/web npm run lint
  fi
  if grep -qE '^frontend/mobile/' <<<"$CHANGED"; then
    command -v flutter >/dev/null 2>&1 || die "Меняется frontend/mobile, но flutter не установлен."
    check frontend/mobile flutter pub get
    check frontend/mobile flutter analyze --no-fatal-infos
    check frontend/mobile flutter test
  fi
  [ -z "$(git status --porcelain)" ] \
    || die "Проверки изменили файлы в репозитории (git status). Закоммить их или откати и запусти снова."

  if [ "$DRY_RUN" = 1 ]; then
    info "Пробный прогон: проверки прошли. Без --dry-run скрипт запушит ветку $BRANCH, создаст или возьмёт PR,"
    info "сольёт его merge-коммитом и поставит тег отката. Сейчас ничего не запушено."
    exit 0
  fi

  # ---------------------------------------------------------------- 6. push and PR
  local HEAD_SHA PR
  HEAD_SHA=$(git rev-parse HEAD)
  info "Пушу ветку $BRANCH"
  git_gh push --quiet -u origin "$BRANCH"

  PR=$(gh pr list --head "$BRANCH" --base main --state open --json number --jq '.[0].number // empty')
  if [ -z "$PR" ]; then
    [ -n "$TITLE" ] || TITLE=$(git log -1 --no-merges --format=%s "$HEAD_SHA")
    local BODY PR_URL
    BODY=$(printf 'Выложено через `scripts/ship.sh`.\n\nФайлы:\n%s\n' "$(sed 's/^/- `/; s/$/`/' <<<"$CHANGED")")
    PR_URL=$(gh pr create --base main --head "$BRANCH" --title "$TITLE" --body "$BODY")
    PR=${PR_URL##*/}
    info "Создан PR #$PR: $PR_URL"
  else
    info "Беру открытый PR #$PR"
  fi

  # GitHub needs a moment after a push to compute mergeability.
  local state="" tries=0
  while :; do
    state=$(gh pr view "$PR" --json mergeable,headRefOid --jq '.mergeable + " " + .headRefOid')
    case "$state" in
      "MERGEABLE $HEAD_SHA") break ;;
      CONFLICTING*) die "GitHub видит конфликт в PR #$PR. Запусти scripts/ship.sh ещё раз." ;;
    esac
    tries=$((tries + 1))
    [ "$tries" -lt 20 ] || die "GitHub не подтвердил, что PR #$PR можно слить ($state). PR открыт, не слит."
    sleep 3
  done

  # ---------------------------------------------------------------- 7. merge, then tag
  git_gh fetch --quiet origin
  if [ "$(git rev-parse origin/main)" != "$BASE" ]; then
    local MOVED
    MOVED=$(git diff --name-only "$BASE" origin/main | grep -vE '^backend/data/' || true)
    if [ -n "$MOVED" ]; then
      die "Пока шли проверки, в main появились новые изменения в коде:
$(sed 's/^/  /' <<<"$MOVED")
PR #$PR открыт, но не слит. Запусти scripts/ship.sh ещё раз: он подтянет их и проверит заново."
    fi
    info "В main добавились только данные (backend/data/), продолжаю."
  fi

  local SAFE_BRANCH TAG MERGE_SHA
  SAFE_BRANCH=$(printf '%s' "$BRANCH" | tr -c 'A-Za-z0-9._-' '-')
  TAG="before-ship-$SAFE_BRANCH-$(date +%Y%m%d-%H%M%S)"
  info "Сливаю PR #$PR merge-коммитом"
  gh pr merge "$PR" --merge --match-head-commit "$HEAD_SHA" \
    --subject "Ship $BRANCH (#$PR)" \
    --body "$(printf 'Откат: scripts/rollback.sh %s\n\nRollback-Tag: %s\n' "$PR" "$TAG")"

  MERGE_SHA=$(gh pr view "$PR" --json mergeCommit --jq '.mergeCommit.oid')
  git_gh fetch --quiet origin
  # Tag the main this PR was merged into (first parent of the merge), not the one we tested.
  git tag -a "$TAG" "$MERGE_SHA^1" -m "main before shipping $BRANCH (PR #$PR)"
  git_gh push --quiet origin "refs/tags/$TAG"

  info "Готово: PR #$PR в main, merge-коммит $(git rev-parse --short "$MERGE_SHA"), тег $TAG."
  info "Если что-то сломалось, откат одной командой:"
  printf '\n  scripts/rollback.sh %s\n\n' "$PR"
}

main "$@"
exit
