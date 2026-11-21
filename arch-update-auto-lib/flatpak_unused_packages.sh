#!/usr/bin/env bash

# https://github.com/Antiz96/arch-update
# SPDX-License-Identifier: GPL-3.0-or-later
# Copia de Arch-Update 4.4.7 (flatpak_unused_packages.sh): agrega -y para que
# flatpak no vuelva a preguntar despues de la respuesta automatica, y avisa el
# resultado a la pantalla de cachy-auto-update.sh (auto_event).

auto_event orphans run
flatpak_unused=$(flatpak uninstall --unused | sed -n '/^ 1./,$p' | awk '{print $2}' | grep -v '^$' | sed '$d')

if [ -n "${flatpak_unused}" ]; then
	main_msg "$(eval_gettext "Flatpak Unused Packages:")"
	echo -e "${flatpak_unused}\n"

	if [ "$(echo "${flatpak_unused}" | wc -l)" -eq 1 ]; then
		ask_msg "$(eval_gettext "Would you like to remove this Flatpak unused package now? [y/N]")"
	else
		ask_msg "$(eval_gettext "Would you like to remove these Flatpak unused packages now? [y/N]")"
	fi

	# shellcheck disable=SC2154
	case "${answer}" in
		"$(eval_gettext "Y")"|"$(eval_gettext "y")")
			echo
			main_msg "$(eval_gettext "Removing Flatpak Unused Packages...")"

			if ! flatpak uninstall --unused -y; then
				mapfile -t -O "${#auto_remove_failed[@]}" auto_remove_failed <<< "${flatpak_unused}"
				auto_orphans_report
				echo
				error_msg "$(eval_gettext "An error has occurred during the removal process\nThe removal has been aborted\n")"
			else
				echo
				info_msg "$(eval_gettext "The removal has been applied\n")"
				mapfile -t -O "${#auto_removed[@]}" auto_removed <<< "${flatpak_unused}"
				auto_orphans_report
			fi
		;;
		*)
			echo
			info_msg "$(eval_gettext "The removal hasn't been applied\n")"
			auto_orphans_report
		;;
	esac
else
	info_msg "$(eval_gettext "No Flatpak unused package found\n")"
	auto_orphans_report
fi
