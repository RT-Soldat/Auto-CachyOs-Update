#!/usr/bin/env bash
# Instala la app y genera el lanzador para el usuario actual, sin sudo.
set -euo pipefail

script_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
data_dir="${XDG_DATA_HOME:-${HOME}/.local/share}"
mkdir -p -- "$data_dir"
data_dir="$(cd -- "$data_dir" && pwd)"
app_dir="${data_dir}/cachy-auto-update"
applications_dir="${data_dir}/applications"

install -d -- "$app_dir/arch-update-auto-lib" "$applications_dir"
install -m 755 -- "$script_dir/cachy-auto-update.sh" \
  "$script_dir/update-ai-clis.sh" "$script_dir/clean-user-caches.sh" "$app_dir/"
install -m 644 -- "$script_dir/arch-update-auto-lib/"*.sh "$app_dir/arch-update-auto-lib/"

# Escapa el argumento para Exec (comillas) y despues para el valor .desktop.
desktop_path="${app_dir}/cachy-auto-update.sh"
desktop_path="${desktop_path//\\/\\\\}"
desktop_path="${desktop_path//\"/\\\"}"
desktop_path="${desktop_path//\$/\\\$}"
desktop_path="${desktop_path//\`/\\\`}"
desktop_path="${desktop_path//%/%%}"
desktop_path="${desktop_path//\\/\\\\}"

while IFS= read -r line; do
  case "$line" in
    Exec=*) printf 'Exec=konsole -e "%s"\n' "$desktop_path" ;;
    *) printf '%s\n' "$line" ;;
  esac
done < "$script_dir/cachy-auto-update.desktop" > "$applications_dir/cachy-auto-update.desktop"
chmod 644 -- "$applications_dir/cachy-auto-update.desktop"

printf 'Instalado. Abre Cachy Auto Update desde el menu de aplicaciones.\n'
