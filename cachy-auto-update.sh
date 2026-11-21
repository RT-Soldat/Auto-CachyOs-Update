#!/usr/bin/env bash
# Actualiza CachyOS con cachy-update respondiendo solo las preguntas habituales.
# Muestra el avance en una sola pantalla; el detalle completo queda en el
# registro (se guardan los ultimos 2).
set -uo pipefail

SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)"
AUTO_LIBDIR="${SCRIPT_DIR}/arch-update-auto-lib"
UPSTREAM_LIBDIR="/usr/share/arch-update/lib"
LOG_DIR="${XDG_STATE_HOME:-${HOME}/.local/state}/cachy-auto-update/logs"
LOGS_TO_KEEP=2

bold=$'\e[1m'
dim=$'\e[2m'
blue=$'\e[1;34m'
green=$'\e[1;32m'
yellow=$'\e[1;33m'
red=$'\e[1;31m'
reset=$'\e[0m'

# Quita barras de progreso redibujadas, colores y secuencias de terminal.
CLEAN_SED='s#\r+$##; s#.*\r##; s#\x1b\][^\x07\x1b]*(\x07|\x1b\\)##g; s#\x1b\[[0-9;?]*[ -/]*[@-~]##g; s#\x1b[()][0-9A-Za-z]##g'

SUDO_KEEPALIVE_PID=""
LIBDIR=""
EVENTS=""
LOG=""
UI_LIVE=false
NEEDS_CLEAR=true
CANCELLED=false
TICK=0
SIDE_OUTPUT=""
TTY_STATE=""

STAGES=(check repos aur flatpak orphans cache services npm usercache)
NOTICES=(news reboot) # solo aparecen cuando hay algo que avisar
declare -A LABEL=(
  [check]="Buscar actualizaciones"
  [repos]="Repositorios"
  [aur]="AUR"
  [flatpak]="Flatpak"
  [orphans]="Huérfanos"
  [cache]="Caché de pacman"
  [services]="Servicios"
  [npm]="CLIs de IA (npm)"
  [usercache]="Cachés de usuario"
  [news]="Noticia de Arch"
  [reboot]="Reinicio"
)
declare -A STATE=() DETAIL=() TOTAL=()
SPINNER=(⠋ ⠙ ⠹ ⠸ ⠼ ⠴ ⠦ ⠧ ⠇ ⠏)

# --- Utilidades --------------------------------------------------------------

fail() {
  printf '%s==> ERROR:%s%s %s%s\n' "$red" "$reset" "$bold" "$*" "$reset" >&2
}

pause_at_end() {
  printf '\n'
  read -r -p "Presiona Enter para cerrar esta ventana..." _ || true
}

stop_sudo_keepalive() {
  if [[ -n "$SUDO_KEEPALIVE_PID" ]]; then
    kill "$SUDO_KEEPALIVE_PID" >/dev/null 2>&1 || true
    SUDO_KEEPALIVE_PID=""
  fi
}

# Mientras se muestra la pantalla no se ve lo que se teclea ni el cursor.
ui_start() {
  TTY_STATE="$(stty -g 2>/dev/null)"
  stty -echo 2>/dev/null
  printf '\e[?25l'
}

ui_stop() {
  [[ -n "$TTY_STATE" ]] && stty "$TTY_STATE" 2>/dev/null
  TTY_STATE=""
  printf '\e[?25h'
}

# Descarta teclas presionadas durante la actualizacion, para que un Enter
# temprano no cierre la ventana antes de ver el resumen.
flush_input() {
  while read -r -s -t 0.05 -n 1024 _; do :; done
}

cleanup() {
  stop_sudo_keepalive
  if "$UI_LIVE"; then
    ui_stop
  fi
  [[ -n "$EVENTS" ]] && rm -f -- "$EVENTS"
  if [[ -n "$LIBDIR" ]]; then
    rm -f -- "$LIBDIR"/*.sh
    rmdir -- "$LIBDIR"
  fi
}

needs_sudo_ticket() {
  case "${1:-}" in
    -h|--help|-V|--version|-l|--list|-n|--news|-c|--check|--show-config|--gen-config|--edit-config|--tray)
      return 1
      ;;
    *)
      return 0
      ;;
  esac
}

# Solo la actualizacion completa usa la pantalla resumida.
is_update_run() {
  case "${1:-}" in
    ""|-d|--devel) return 0 ;;
    *) return 1 ;;
  esac
}

start_sudo_keepalive() {
  if [[ "${EUID}" -eq 0 ]] || ! command -v sudo >/dev/null 2>&1; then
    return
  fi

  if ! sudo -v; then
    fail "No se pudo validar sudo"
    pause_at_end
    exit 1
  fi

  while true; do
    sudo -n true >/dev/null 2>&1 || exit
    sleep 60
  done &
  SUDO_KEEPALIVE_PID="$!"
}

# Se conservan los ultimos LOGS_TO_KEEP registros, contando el que se va a crear.
rotate_logs() {
  local old
  find "$LOG_DIR" -maxdepth 1 -type f -name '*.log' -printf '%f\n' | sort -r |
    tail -n +"$LOGS_TO_KEEP" | while IFS= read -r old; do
      rm -f -- "${LOG_DIR}/${old}"
    done
}

event() {
  printf '%s\t%s\t%s\n' "$1" "$2" "${3:-}" >> "$EVENTS"
}

load_events() {
  local id state detail
  STATE=()
  DETAIL=()
  TOTAL=()
  while IFS=$'\t' read -r id state detail; do
    if [[ "$state" == total ]]; then
      TOTAL[$id]="$detail"
      continue
    fi
    STATE[$id]="$state"
    # Al pasar a "run" sin detalle se mantiene el anterior ("3 pendientes").
    [[ "$state" == run && -z "$detail" ]] || DETAIL[$id]="$detail"
  done < "$EVENTS"
}

# Mensaje de pacman con un %s (en el idioma del sistema) -> regex con un grupo.
pacman_regex() {
  local msg
  msg="$(TEXTDOMAIN=pacman gettext "$1")"
  msg="$(sed -E 's/[][\.*^$(){}?+|/]/\\&/g' <<< "$msg")"
  printf '^%s$' "${msg/\%s/(.+)}"
}

RE_INSTALLS=(
  "$(pacman_regex $'installing %s...\n')"
  "$(pacman_regex $'upgrading %s...\n')"
  "$(pacman_regex $'reinstalling %s...\n')"
  "$(pacman_regex $'downgrading %s...\n')"
)
RE_INSTALL="$(IFS='|'; printf '%s' "${RE_INSTALLS[*]}")"
RE_DOWNLOAD="$(pacman_regex $' %s downloading...\n')"
MAKING_PREFIX="==> $(TEXTDOMAIN=pacman-scripts gettext "Making package: %s")"
MAKING_PREFIX="${MAKING_PREFIX%\%s}"

# --- Pantalla ------------------------------------------------------------------

repeat_char() {
  local out="" i
  for ((i = 0; i < $2; i++)); do out+="$1"; done
  printf '%s' "$out"
}

progress_bar() {
  local done="$1" total="$2" width=16 filled
  (( total < done )) && total="$done"
  (( total > 0 )) || total=1
  filled=$((done * width / total))
  printf '%s%s %s/%s' "$(repeat_char █ "$filled")" "$(repeat_char ░ $((width - filled)))" "$done" "$total"
}

# Avance de pacman: descargas, paquetes instalados y el paquete en curso.
repos_progress() {
  local installed downloaded header current total re name=""
  {
    read -r installed downloaded header
    IFS= read -r current
  } < <(RI="$RE_INSTALL" RD="$RE_DOWNLOAD" awk '
      $0 ~ ENVIRON["RI"] { n++; cur = $0 }
      $0 ~ ENVIRON["RD"] { d++ }
      !h && /^[[:alpha:]]+ \([0-9]+\)/ { s = $0; sub(/^[^(]*\(/, "", s); sub(/\).*/, "", s); h = s }
      END { print n + 0, d + 0, h + 0; print cur }' "$LOG")

  total="${header:-0}"
  (( total > 0 )) || total="${TOTAL[repos]:-0}"
  if (( installed > 0 )); then
    for re in "${RE_INSTALLS[@]}"; do
      if [[ "$current" =~ $re ]]; then
        name="${BASH_REMATCH[1]}"
        break
      fi
    done
    printf '%s  %s' "$(progress_bar "$installed" "$total")" "$name"
  elif (( downloaded > 0 )); then
    printf 'descargando %s/%s' "$downloaded" "$total"
  else
    printf 'preparando'
  fi
}

# Avance de paru: paquete que se esta construyendo y cuantos van.
aur_progress() {
  local line name last="" count=0
  local -A seen=()
  while IFS= read -r line; do
    name="${line#*"$MAKING_PREFIX"}"
    name="${name%% *}"
    [[ -n "$name" && -z "${seen[$name]:-}" ]] || continue
    seen[$name]=1
    last="$name"
    count=$((count + 1))
  done < <(grep -aF -- "$MAKING_PREFIX" "$LOG")

  if [[ -n "$last" ]]; then
    printf 'construyendo %s (%s/%s)' "$last" "$count" "${TOTAL[aur]:-$count}"
  else
    printf 'preparando'
  fi
}

live_detail() {
  case "$1" in
    repos) repos_progress ;;
    aur) aur_progress ;;
    flatpak) printf 'actualizando %s' "${TOTAL[flatpak]:-}" ;;
    check) printf 'consultando repos, AUR y Flatpak' ;;
    *) printf '%s' "${DETAIL[$1]:-}" ;;
  esac
}

# Ultima linea con texto del registro, para ver que sigue avanzando.
last_activity() {
  local line
  line="$(tail -n 5 "$LOG" 2>/dev/null | LC_ALL=C sed -E "$CLEAN_SED" | grep -v '^[[:space:]]*$' | tail -n 1)"
  printf '%s' "${line#"${line%%[![:space:]]*}"}"
}

fit() {
  local text="$1" width="$2"
  if (( ${#text} > width )); then
    printf '%s…' "${text:0:width-1}"
  else
    printf '%s' "$text"
  fi
}

pad() {
  printf '%s%*s' "$1" $(($2 - ${#1})) ''
}

render() {
  local footer="${1:-}" cols width eol out="" id state detail icon color
  cols="$(tput cols 2>/dev/null || echo 80)"
  width=$((cols - 30))
  (( width < 12 )) && width=12

  if "$UI_LIVE"; then
    eol=$'\e[K\n'
    "$NEEDS_CLEAR" && out+=$'\e[2J'
    NEEDS_CLEAR=false
    out+=$'\e[H'
  else
    eol=$'\n'
  fi

  out+=" ${bold}Cachy Auto Update${reset}  ${dim}${STARTED_AT}${reset}${eol}${eol}"
  for id in "${STAGES[@]}" "${NOTICES[@]}"; do
    state="${STATE[$id]:-}"
    if [[ -z "$state" ]]; then
      [[ " ${NOTICES[*]} " == *" $id "* ]] && continue
      state=pending
    fi
    detail="${DETAIL[$id]:-}"
    color=""
    case "$state" in
      run) icon="${blue}${SPINNER[TICK % ${#SPINNER[@]}]}${reset}"; detail="$(live_detail "$id")" ;;
      ok) icon="${green}✔${reset}" ;;
      error) icon="${red}✖${reset}"; color="$red" ;;
      warn) icon="${yellow}!${reset}"; color="$yellow" ;;
      skip) icon="${dim}–${reset}"; color="$dim" ;;
      *) icon="${dim}·${reset}"; color="$dim" ;;
    esac
    out+="  ${icon}  $(pad "${LABEL[$id]}" 23) ${color}$(fit "$detail" "$width")${color:+$reset}${eol}"
  done
  out+="$eol"

  if [[ -n "$footer" ]]; then
    out+="$footer"
  else
    out+="  ${dim}› $(fit "$(last_activity)" $((cols - 6)))${reset}${eol}"
  fi
  "$UI_LIVE" && out+=$'\e[J'
  printf '%s' "$out"
}

# Redibuja hasta que termine el proceso y devuelve su codigo de salida.
watch_until_done() {
  local pid="$1"
  while kill -0 "$pid" 2>/dev/null; do
    if "$UI_LIVE"; then
      load_events
      render
    fi
    sleep 0.25
    TICK=$((TICK + 1))
  done
  wait "$pid"
}

# Etapas propias (npm, caches): salida al registro y copia en SIDE_OUTPUT.
run_side_stage() {
  local id="$1" out pid status
  shift
  out="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/cachy-auto-update.XXXXXX")" || return 1
  event "$id" run
  printf '\n==> %s\n' "${LABEL[$id]}" >> "$LOG"
  { env --default-signal=INT "$@" 2>&1 | tee "$out"; } >> "$LOG" < /dev/null &
  pid="$!"
  watch_until_done "$pid"
  status=$?
  SIDE_OUTPUT="$(<"$out")"
  rm -f -- "$out"
  return "$status"
}

# Cierra las etapas de cachy-update que quedaron abiertas.
settle_cachy_stages() {
  local status="$1" id
  load_events
  for id in check repos aur flatpak orphans cache services; do
    case "${STATE[$id]:-pending}" in
      run)
        if "$CANCELLED"; then
          event "$id" error "cancelado"
        elif (( status != 0 )); then
          event "$id" error "falló (ver registro)"
        else
          event "$id" ok "${DETAIL[$id]:-}"
        fi
        ;;
      pending)
        if "$CANCELLED"; then
          event "$id" skip "cancelado"
        elif (( status != 0 )); then
          event "$id" skip "no se ejecutó"
        else
          event "$id" skip "sin cambios"
        fi
        ;;
    esac
  done
}

npm_summary() {
  local changes
  changes="$(grep -E ' -> ' <<< "$SIDE_OUTPUT" | sed 's/ -> / → /')"
  if [[ -n "$changes" ]]; then
    printf '%s' "$(paste -sd ',' <<< "$changes" | sed 's/,/, /g')"
  else
    printf 'al día'
  fi
}

usercache_summary() {
  local freed
  freed="$(sed -n 's/^Total liberado: //p' <<< "$SIDE_OUTPUT" | tail -n 1)"
  if [[ -z "$freed" || "$freed" == 0 ]]; then
    printf 'nada que liberar'
  else
    printf '%s liberados' "$freed"
  fi
}

# --- Ejecucion -------------------------------------------------------------------

# arch-update carga todas sus bibliotecas desde un mismo directorio. Se arma
# uno temporal con enlaces a las originales, reemplazando las que modifica
# este proyecto (arch-update-auto-lib).
build_libdir() {
  local lib
  LIBDIR="$(mktemp -d "${XDG_RUNTIME_DIR:-/tmp}/cachy-auto-update-lib.XXXXXX")" || return 1
  for lib in "$UPSTREAM_LIBDIR"/*.sh "$AUTO_LIBDIR"/*.sh; do
    ln -sf -- "$lib" "$LIBDIR/" || return 1
  done
}

trap cleanup EXIT
if [[ ! -d "$UPSTREAM_LIBDIR" || ! -d "$AUTO_LIBDIR" ]] || ! build_libdir; then
  fail "No se encontraron las bibliotecas de cachy-update o de ${AUTO_LIBDIR}"
  pause_at_end
  exit 1
fi
export ARCH_UPDATE_LIBDIR="$LIBDIR"

# Otras opciones (--list, --services, --help...): cachy-update tal cual.
if ! is_update_run "${1:-}"; then
  needs_sudo_ticket "${1:-}" && start_sudo_keepalive
  cachy-update "$@"
  status=$?
  stop_sudo_keepalive
  pause_at_end
  exit "$status"
fi

printf ' %sCachy Auto Update%s\n\n' "$bold" "$reset"
start_sudo_keepalive

[[ -t 1 ]] && UI_LIVE=true
STARTED_AT="$(date '+%a %d %b, %H:%M')"
mkdir -p -- "$LOG_DIR" || exit 1
rotate_logs
LOG="${LOG_DIR}/$(date +%F_%H%M%S).log"
: > "$LOG"
EVENTS="$(mktemp "${XDG_RUNTIME_DIR:-/tmp}/cachy-auto-update.XXXXXX")" || exit 1
export CACHY_AUTO_EVENTS="$EVENTS"

trap 'CANCELLED=true' INT
trap 'NEEDS_CLEAR=true' WINCH
if "$UI_LIVE"; then
  ui_start
fi

event check run
env --default-signal=INT cachy-update "$@" >> "$LOG" 2>&1 < /dev/null &
watch_until_done "$!"
status=$?
settle_cachy_stages "$status"

# Los CLIs de IA (claude, codex, opencode) van por npm global y cachy-update no los ve.
if "$CANCELLED"; then
  event npm skip "cancelado"
elif (( status == 17 )); then
  event npm skip "no se ejecutó"
elif run_side_stage npm "${SCRIPT_DIR}/update-ai-clis.sh"; then
  event npm ok "$(npm_summary)"
else
  event npm error "$("$CANCELLED" && echo "cancelado" || echo "no se pudieron actualizar")"
fi

if "$CANCELLED"; then
  event usercache skip "cancelado"
elif (( status != 0 )); then
  event usercache skip "se omite porque hubo errores"
elif run_side_stage usercache bash "${SCRIPT_DIR}/clean-user-caches.sh"; then
  event usercache ok "$(usercache_summary)"
else
  event usercache error "$("$CANCELLED" && echo "cancelado" || echo "no se pudo limpiar todo")"
fi
stop_sudo_keepalive

load_events
errors=0
for id in "${STAGES[@]}"; do
  [[ "${STATE[$id]:-}" == error ]] && errors=$((errors + 1))
done

eol=$'\n'
"$UI_LIVE" && eol=$'\e[K\n'
if "$CANCELLED"; then
  result="  ${red}✖ Cancelado${reset}"
  status=130
elif (( status == 17 )); then
  result="  ${red}✖ Ya había otra actualización en curso; esta no hizo cambios${reset}"
elif (( errors > 0 || status != 0 )); then
  result="  ${red}✖ Terminó con errores${reset}"
  (( status == 0 )) && status=1
else
  result="  ${green}✔ Todo listo${reset}"
fi
footer="${result}${eol}  ${dim}Registro: ${LOG/#"$HOME"/\~}${reset}${eol}${eol}"
footer+="  ${dim}Presiona Enter para cerrar${reset}"
render "$footer"
LC_ALL=C sed -i -E "$CLEAN_SED" "$LOG"

if "$UI_LIVE"; then
  flush_input
  ui_stop
fi
read -r _ || true
printf '\n'
exit "$status"
