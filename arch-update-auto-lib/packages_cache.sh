#!/usr/bin/env bash
auto_event cache run
source /usr/share/arch-update/lib/packages_cache.sh

if [ "${pacman_cache_total:-0}" -gt 0 ]; then
  auto_event cache ok "$(auto_plural "${pacman_cache_total}" "archivo eliminado" "archivos eliminados")"
else
  auto_event cache ok "nada que limpiar"
fi
