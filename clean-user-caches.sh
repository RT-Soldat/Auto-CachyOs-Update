#!/usr/bin/env bash
set -uo pipefail

dry_run=false
case "${1:-}" in
  --dry-run) dry_run=true ;;
  "") ;;
  *) printf 'Uso: bash %s [--dry-run]\n' "$0" >&2; exit 2 ;;
esac

status=0
total_saved=0
cache_home="${XDG_CACHE_HOME:-${HOME}/.cache}"

busy() {
  pgrep -u "$UID" -x "$1" >/dev/null 2>&1
}

cache_size() {
  local size=0
  read -r size _ < <(du -sk -- "$1" 2>/dev/null)
  printf '%s' "${size:-0}"
}

report_saved() {
  local before="$1" after="$2" saved
  saved=$((before > after ? before - after : 0))
  total_saved=$((total_saved + saved))
  printf 'Liberados: %s\n' "$(numfmt --from-unit=1024 --to=iec-i --suffix=B --format='%.2f' "$saved")"
}

clean_shelly() {
  local cache="${cache_home}/Shelly" before
  [[ -d "$cache" ]] || return 0

  # Do not follow a cache root redirected outside Shelly's own directory.
  if [[ -L "$cache" || ! -O "$cache" || "$cache" != /* ]]; then
    printf 'Shelly: se omite una ruta de cache enlazada, ajena o relativa.\n' >&2
    return 1
  fi
  if busy 'shelly|shelly-ui|makepkg'; then
    printf 'Shelly esta en uso; su cache se limpiara en la proxima ejecucion.\n'
    return 0
  fi

  printf '\nCache de Shelly\n'
  du -sh -- "$cache"
  "$dry_run" && return 0
  before="$(cache_size "$cache")"
  # Cache entries can be regenerated. Keep the root and never follow symlinks.
  find -P "$cache" -xdev -depth -mindepth 1 -delete || return 1
  report_saved "$before" "$(cache_size "$cache")"
}

clean_npm() {
  local cache prefix cache_real prefix_real before
  command -v npm >/dev/null 2>&1 || return 0
  if busy 'npm( .*)?|npx( .*)?'; then
    printf 'npm/npx esta en uso; su cache se limpiara en la proxima ejecucion.\n'
    return 0
  fi
  cache="$(npm config get cache)" || return 1
  [[ -d "$cache" ]] || return 0
  [[ -d "$cache/_cacache" || -d "$cache/_npx" ]] || return 0
  prefix="$(npm config get prefix)" || return 1
  cache_real="$(realpath -m -- "$cache")" || return 1
  prefix_real="$(realpath -m -- "$prefix")" || return 1
  if [[ -L "$cache" || ! -O "$cache" || "${HOME}/" == "${cache_real}/"* || "${prefix_real}/" == "${cache_real}/"* ]]; then
    printf 'npm: se omite una ruta de cache que puede contener programas o datos.\n' >&2
    return 1
  fi

  printf '\nCache de npm\n'
  du -sh -- "$cache"
  "$dry_run" && return 0
  before="$(cache_size "$cache")"
  npm cache clean --force --loglevel=error || return 1
  # Older npm releases clean _cacache only; recent ones also clean _npx.
  if [[ -d "$cache/_npx" ]] && npm cache --help | grep -q 'npx rm'; then
    npm cache npx rm --force --loglevel=error || return 1
  fi
  report_saved "$before" "$(cache_size "$cache")"
}

clean_pip() {
  local cache before
  command -v pip >/dev/null 2>&1 || return 0
  if busy 'pip([0-9.]*)?'; then
    printf 'pip esta en uso; su cache se limpiara en la proxima ejecucion.\n'
    return 0
  fi
  cache="$(pip cache dir 2>/dev/null)" || return 0
  [[ -d "$cache" && ! -L "$cache" && -O "$cache" ]] || return 0

  printf '\nCache de pip\n'
  du -sh -- "$cache"
  "$dry_run" && return 0
  before="$(cache_size "$cache")"
  pip cache purge || return 1
  report_saved "$before" "$(cache_size "$cache")"
}

clean_shelly || status=1
clean_npm || status=1
clean_pip || status=1

# Resumen para la pantalla de cachy-auto-update.sh.
if ! "$dry_run"; then
  if [[ "$total_saved" -gt 0 ]]; then
    printf '\nTotal liberado: %s\n' "$(numfmt --from-unit=1024 --to=iec-i --suffix=B --format='%.2f' "$total_saved")"
  else
    printf '\nTotal liberado: 0\n'
  fi
fi
exit "$status"
