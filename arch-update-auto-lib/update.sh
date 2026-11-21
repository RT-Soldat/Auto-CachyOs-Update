#!/usr/bin/env bash

# Keep Arch-Update's flow, but call package tools with non-interactive flags
# and report each step to the cachy-auto-update.sh screen.

if [ -n "${packages}" ]; then
  echo
  main_msg "$(eval_gettext "Updating Packages...\n")"
  auto_event repos run

  if ! "${su_cmd}" pacman --color "${pacman_color_opt}" -Syu --noconfirm; then
    auto_event repos error "pacman falló"
    echo
    error_msg "$(eval_gettext "An error has occurred during the update process\nThe update has been aborted\n")" && quit_msg
    exit 5
  else
    auto_event repos ok "$(auto_plural "$(grep -c . <<< "${packages}")" "paquete actualizado" "paquetes actualizados")"
    true > "${statedir}/last_updates_check_packages"
    cat "${statedir}"/last_updates_check_{packages,aur,flatpak} > "${statedir}/last_updates_check"
    packages_updated="true"
  fi
fi

if [ -n "${aur_packages}" ]; then
  echo
  source "${libdir}/orphan_packages.sh"

  main_msg "$(eval_gettext "Updating AUR Packages...\n")"
  auto_event aur run

  if [ "${aur_helper}" = "paru" ]; then
    aur_flags=(--noconfirm --skipreview --noupgrademenu --nonewsonupgrade --removemake --cleanafter --sudoloop)
  else
    aur_flags=(--noconfirm)
  fi

  if ! "${aur_helper}" --color "${pacman_color_opt}" "${devel_flag[@]}" -Syu "${aur_flags[@]}"; then
    # Name what is still pending so a package that fails every day is obvious.
    mapfile -t aur_pending < <(LC_ALL=C "${aur_helper}" --color never "${devel_flag[@]}" -Qua < /dev/null 2> /dev/null | sed 's/^ *//; s/ \+/ /g' | grep -vw "\[ignored\]$" | grep . | sed 's/ -> / → /')
    if [ "${#aur_pending[@]}" -gt 0 ]; then
      auto_event aur error "falló: $(auto_join "${aur_pending[@]}")"
    else
      auto_event aur error "falló"
    fi
    echo
    warning_msg "$(eval_gettext "An error has occurred during the update process\nThe update has been aborted\n")"
    error_during_update="true"
  else
    auto_event aur ok "$(auto_plural "$(grep -c . <<< "${aur_packages}")" "paquete actualizado" "paquetes actualizados")"
    true > "${statedir}/last_updates_check_aur"
    cat "${statedir}"/last_updates_check_{packages,aur,flatpak} > "${statedir}/last_updates_check"
    packages_updated="true"
  fi
fi

if [ -n "${flatpak_packages}" ]; then
  echo
  main_msg "$(eval_gettext "Updating Flatpak Packages...\n")"
  auto_event flatpak run

  if ! flatpak update -y --noninteractive; then
    auto_event flatpak error "flatpak falló"
    echo
    warning_msg "$(eval_gettext "An error has occurred during the update process\nThe update has been aborted\n")"
    error_during_update="true"
  else
    auto_event flatpak ok "$(auto_plural "${#flatpak_packages[@]}" "aplicación actualizada" "aplicaciones actualizadas")"
    true > "${statedir}/last_updates_check_flatpak"
    cat "${statedir}"/last_updates_check_{packages,aur,flatpak} > "${statedir}/last_updates_check"
  fi
fi

if [ -z "${error_during_update}" ]; then
  icon_up-to-date
  echo
  info_msg "$(eval_gettext "The update has been applied\n")"
fi
