# Shared helpers for scripts/ship.sh and scripts/rollback.sh.
# Sourced, not executed. Written for the bash 3.2 that ships with macOS.

info() { printf '\033[1;34m==>\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m!!\033[0m  %s\n' "$*" >&2; }
die()  { printf '\033[1;31mxx\033[0m  %s\n' "$*" >&2; exit 1; }

repo_root() {
  git rev-parse --show-toplevel 2>/dev/null || die "Запускай скрипт внутри репозитория."
}

# git with gh as the credential helper for this one command; the global git config is untouched.
git_gh() {
  git -c credential.helper= -c 'credential.helper=!gh auth git-credential' "$@"
}

require_gh() {
  command -v gh >/dev/null 2>&1 || die "Нужен GitHub CLI: brew install gh"
  gh auth status >/dev/null 2>&1 || die "gh не залогинен. Выполни: gh auth login -h github.com"
}

# confirm "Вопрос?" — passes when ASSUME_YES=1, otherwise reads the answer from stdin.
confirm() {
  if [ "${ASSUME_YES:-0}" = 1 ]; then
    return 0
  fi
  printf '%s Введи yes, чтобы продолжить: ' "$1"
  local answer=""
  read -r answer || die "Нет ответа. Запусти с --yes, если уверен."
  [ "$answer" = yes ] || die "Отменено, ничего не изменено."
}
