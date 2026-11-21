#!/usr/bin/env bash
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'find -P "$fixture" -depth -delete' EXIT

export XDG_CACHE_HOME="$fixture/cache root"
export npm_config_cache="$fixture/npm cache"
export npm_config_prefix="$fixture/npm global"
export PIP_CACHE_DIR="$fixture/pip cache"
export XDG_CONFIG_HOME="$fixture/config"

mkdir -p "$XDG_CACHE_HOME/Shelly/build/src" "$XDG_CACHE_HOME/Shelly/build/pkg" \
  "$npm_config_cache/_cacache" "$npm_config_cache/_npx" \
  "$npm_config_prefix/lib/node_modules/tool" "$fixture/outside" \
  "$XDG_CONFIG_HOME/shelly" "$PIP_CACHE_DIR/http-v2" "$PIP_CACHE_DIR/wheels"
printf 'source\n' > "$XDG_CACHE_HOME/Shelly/build/src/source.deb"
printf 'built\n' > "$XDG_CACHE_HOME/Shelly/build/pkg/package"
printf 'cached\n' > "$npm_config_cache/_cacache/download"
printf 'cached npx\n' > "$npm_config_cache/_npx/download"
printf 'installed\n' > "$npm_config_prefix/lib/node_modules/tool/index.js"
printf 'settings\n' > "$XDG_CONFIG_HOME/shelly/settings.json"
printf 'preserve\n' > "$fixture/outside/data"
printf 'wheel\n' > "$PIP_CACHE_DIR/wheels/demo-1.0-py3-none-any.whl"
printf 'http\n' > "$PIP_CACHE_DIR/http-v2/download.body"
ln -s "$fixture/outside" "$XDG_CACHE_HOME/Shelly/link"

bash "$project_dir/clean-user-caches.sh" --dry-run
test -f "$XDG_CACHE_HOME/Shelly/build/src/source.deb"
test -f "$npm_config_cache/_cacache/download"
test -f "$PIP_CACHE_DIR/wheels/demo-1.0-py3-none-any.whl"

bash "$project_dir/clean-user-caches.sh"
test -d "$XDG_CACHE_HOME/Shelly"
test -z "$(find "$XDG_CACHE_HOME/Shelly" -mindepth 1 -print -quit)"
test ! -e "$npm_config_cache/_cacache/download"
test ! -e "$npm_config_cache/_npx/download"
test ! -e "$PIP_CACHE_DIR/wheels/demo-1.0-py3-none-any.whl"
test ! -e "$PIP_CACHE_DIR/http-v2/download.body"
test -f "$fixture/outside/data"
test -f "$XDG_CONFIG_HOME/shelly/settings.json"
test -f "$npm_config_prefix/lib/node_modules/tool/index.js"

rmdir "$XDG_CACHE_HOME/Shelly"
ln -s "$fixture/outside" "$XDG_CACHE_HOME/Shelly"
if bash "$project_dir/clean-user-caches.sh"; then
  printf 'ERROR: se acepto una raiz de cache enlazada\n' >&2
  exit 1
fi
test -f "$fixture/outside/data"

unlink "$XDG_CACHE_HOME/Shelly"
mkdir -p "$npm_config_prefix/_cacache"
export npm_config_cache="$npm_config_prefix"
if bash "$project_dir/clean-user-caches.sh"; then
  printf 'ERROR: se acepto limpiar el prefijo npm instalado\n' >&2
  exit 1
fi
test -f "$npm_config_prefix/lib/node_modules/tool/index.js"

(
  name=arch-update
  set +eu
  source "$project_dir/arch-update-auto-lib/config.sh"
  set -eu
  test "$old_packages_num" = 1
  test "$update_check_timeout" = 0
)
mkdir -p "$XDG_CONFIG_HOME/arch-update"
printf 'KeepOldPackages=2\n' > "$XDG_CONFIG_HOME/arch-update/arch-update.conf"
(
  name=arch-update
  set +eu
  source "$project_dir/arch-update-auto-lib/config.sh"
  set -eu
  test "$old_packages_num" = 2
)

printf '\nOK: simulacion, limpieza, enlaces, programas instalados y retencion.\n'
