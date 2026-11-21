#!/usr/bin/env bash
auto_event check run
source /usr/share/arch-update/lib/list_packages.sh

# Cuantas actualizaciones hay de cada tipo, para la pantalla de cachy-auto-update.sh.
auto_count_repos=$(grep -c . <<< "${packages}")
auto_count_aur=$(grep -c . <<< "${aur_packages}")
auto_count_flatpak=${#flatpak_packages[@]}
auto_summary=()
for auto_kind in repos aur flatpak; do
  auto_n="auto_count_${auto_kind}"
  auto_n="${!auto_n}"
  if [ "${auto_n}" -gt 0 ]; then
    auto_event "${auto_kind}" pending "$(auto_plural "${auto_n}" pendiente pendientes)"
    auto_event "${auto_kind}" total "${auto_n}"
  else
    auto_event "${auto_kind}" skip "al día"
  fi
done
[ "${auto_count_repos}" -gt 0 ] && auto_summary+=("${auto_count_repos} repos")
[ "${auto_count_aur}" -gt 0 ] && auto_summary+=("${auto_count_aur} AUR")
[ "${auto_count_flatpak}" -gt 0 ] && auto_summary+=("${auto_count_flatpak} Flatpak")
if [ "${#auto_summary[@]}" -gt 0 ]; then
  auto_event check ok "$(auto_join "${auto_summary[@]}")"
else
  auto_event check ok "todo al día"
fi
