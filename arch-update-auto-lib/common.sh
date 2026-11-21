#!/usr/bin/env bash
source /usr/share/arch-update/lib/common.sh

# Respuestas automaticas para cachy-update.
#
# Cada pregunta se registra con su texto original de Arch-Update (msgid en
# ingles) y tambien traducida con eval_gettext. Asi coincide en cualquier
# idioma: con LANG=es_MX las preguntas llegan como "¿Desea ...? [s/N]" y el
# "si" que esperan los scripts es "s", no "y".
declare -gA arch_update_auto_reply=()

arch_update_auto_register() {
  local reply="$1" msgid
  shift
  for msgid in "$@"; do
    arch_update_auto_reply["$msgid"]="$reply"
    arch_update_auto_reply["$(eval_gettext "$msgid")"]="$reply"
  done
}

arch_update_auto_register "$(eval_gettext "y")" \
  "Proceed with update? [Y/n]" \
  "Would you like to remove this orphan package (and its potential dependencies) now? [y/N]" \
  "Would you like to remove these orphan packages (and their potential dependencies) now? [y/N]" \
  "Would you like to remove this Flatpak unused package now? [y/N]" \
  "Would you like to remove these Flatpak unused packages now? [y/N]" \
  "Would you like to remove it from the cache now? [Y/n]" \
  "Would you like to remove them from the cache now? [Y/n]" \
  "Would you like to process this file now? [Y/n]" \
  "Would you like to process these files now? [Y/n]"

# Nunca reiniciar el equipo. Tampoco correr junto a otra actualizacion en curso:
# dos pacman/paru a la vez chocan con el bloqueo de la base de datos.
arch_update_auto_register "n" \
  "Would you like to reboot now? [y/N]" \
  "Proceed anyway? [y/N]"

arch_update_auto_register "0" \
  'Select the service(s) to restart (e.g. 1 3 5), select 0 to restart them all or press "enter" to continue without restarting the service(s):'

arch_update_auto_register "" \
  'Select the news to read (e.g. 1 3 5), select 0 to read them all or press "enter" to quit:' \
  'Select the news to read (e.g. 1 3 5), select 0 to read them all or press "enter" to proceed with update:'

# Devuelve en "auto_reply" la respuesta registrada; falla si la pregunta es nueva.
arch_update_auto_lookup() {
  auto_reply=""
  [[ -n "${arch_update_auto_reply[$1]+set}" ]] || return 1
  auto_reply="${arch_update_auto_reply[$1]}"
}

arch_update_auto_show() {
  local msg="$1" reply="$2" known="$3" note=""
  [[ "$known" == true ]] || note=" (pregunta sin respuesta automatica: se usa la opcion por defecto)"
  echo -e "${blue}->${color_off}${bold} ${msg}${color_off} ${yellow}${reply:-Enter}${color_off}${note}"
}

ask_msg() {
  local known=true auto_reply
  arch_update_auto_lookup "$1" || known=false
  answer="$auto_reply"
  arch_update_auto_show "$1" "$answer" "$known"
}

ask_msg_array() {
  local known=true auto_reply
  arch_update_auto_lookup "$1" || known=false
  arch_update_auto_show "$1" "$auto_reply" "$known"

  if [[ -n "$auto_reply" ]]; then
    answer_array=("$auto_reply")
  else
    answer_array=()
  fi
}

continue_msg() {
  info_msg "Continuando automaticamente"
}

quit_msg() {
  info_msg "Proceso terminado"
}

# --- Pantalla resumida de cachy-auto-update.sh ----------------------------
# Cada etapa avisa su estado en CACHY_AUTO_EVENTS, una linea por cambio:
# "etapa<TAB>estado<TAB>detalle". Estados: pending, run, ok, error, warn, skip
# y total (el detalle es la cantidad usada para la barra de progreso).
auto_event() {
  [[ -n "${CACHY_AUTO_EVENTS:-}" ]] || return 0
  printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" >> "$CACHY_AUTO_EVENTS"
}

# auto_plural 3 "paquete actualizado" "paquetes actualizados" -> "3 paquetes actualizados"
auto_plural() {
  if [[ "$1" -eq 1 ]]; then
    printf '1 %s' "$2"
  else
    printf '%s %s' "$1" "$3"
  fi
}

# Une los elementos con ", ".
auto_join() {
  printf '%s' "$1"
  shift
  [[ "$#" -eq 0 ]] || printf ', %s' "$@"
}

# Lo que quitan orphan_packages.sh y flatpak_unused_packages.sh (pueden correr
# mas de una vez): se informa todo junto en la etapa "orphans".
auto_removed=()
auto_remove_failed=()

auto_orphans_report() {
  if [[ "${#auto_remove_failed[@]}" -gt 0 ]]; then
    auto_event orphans error "no se pudo quitar: $(auto_join "${auto_remove_failed[@]}")"
  elif [[ "${#auto_removed[@]}" -gt 0 ]]; then
    auto_event orphans ok "quitado: $(auto_join "${auto_removed[@]}")"
  else
    auto_event orphans ok "ninguno"
  fi
}

# En la pantalla resumida la salida completa va al registro: sin colores.
if [[ -n "${CACHY_AUTO_EVENTS:-}" ]]; then
  bold="" blue="" green="" yellow="" red="" color_off=""
  pacman_color_opt="never"
  contrib_color_opt=("--nocolor")
fi
