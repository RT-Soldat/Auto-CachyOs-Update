#!/usr/bin/env bash
# Prueba el lanzador completo con el arch-update real del sistema y pacman,
# paru, flatpak, sudo, npm, etc. falsos. No toca el sistema: estado,
# registros y caches van a un directorio temporal, y el "sudo" falso solo
# ejecuta las herramientas falsas.
set -euo pipefail

project_dir="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
fixture="$(mktemp -d)"
trap 'find -P "$fixture" -depth -delete' EXIT
bin="$fixture/bin"
mkdir -p "$bin" "$fixture/state" "$fixture/run" "$fixture/cache" "$fixture/config"

fake() {
  cat > "$bin/$1"
  chmod +x "$bin/$1"
}

fake sudo <<EOF
#!/usr/bin/env bash
[[ "\$1" == -v || "\$1" == -n ]] && exit 0
[[ "\$(command -v "\$1")" == "$bin/"* ]] && exec "\$@"
echo "FAKE sudo \$*"
EOF
fake cachy-update <<'EOF'
#!/usr/bin/env bash
exec /usr/bin/arch-update "$@"
EOF
fake flock <<'EOF'
#!/usr/bin/env bash
exit 0
EOF
fake checkupdates <<'EOF'
#!/usr/bin/env bash
[[ "${FAKE_MODE:-}" == none ]] && exit 2
printf 'foo 1-1 -> 2-1\nbar 1-1 -> 1-2\n'
EOF
fake pacman <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *-Qtdq*) [[ -n "${FAKE_ORPHANS:-}" && ! -e "$XDG_RUNTIME_DIR/orphans-removed" ]] && echo "$FAKE_ORPHANS"; exit 0 ;;
  *-Rns*) echo "FAKE pacman $*"; touch "$XDG_RUNTIME_DIR/orphans-removed" ;;
  *-Syu*)
    printf 'Paquete (2)  Versión antigua  Versión nueva\n\n'
    printf ' descargando foo-2-1...\n descargando bar-1-2...\n'
    sleep 1
    echo "actualizando foo..."
    sleep 1
    echo "actualizando bar..."
    sleep 0.5
    [[ "${FAKE_MODE:-}" != repofail ]] ;;
  "-Q "*) exit 1 ;;
esac
EOF
fake paru <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *-Qua*) [[ "${FAKE_MODE:-}" == none ]] || echo "rustdesk 1.5.0-0 -> 1.5.3-1" ;;
  *-Syu*)
    echo "==> Creando el paquete: rustdesk 1.5.3-1 (vie 20 nov 2026)"
    sleep 1
    echo "error: no se pudo realizar la operación (archivos en conflicto)"
    echo "rustdesk: /usr/share/applications/rustdesk.desktop existe en el sistema de archivos"
    exit 1 ;;
esac
EOF
fake flatpak <<'EOF'
#!/usr/bin/env bash
case "$*" in
  "list --user") echo "org.example.App" ;;
  "remote-ls --updates --cached --columns=name,version") [[ "${FAKE_MODE:-}" == none ]] || printf 'App\t2.0\n' ;;
  "uninstall --unused") echo "Nothing unused to uninstall" ;;
  "update -y --noninteractive") echo "Updating App" ;;
esac
EOF
fake paccache <<'EOF'
#!/usr/bin/env bash
case "$*" in
  *-dk*) echo "==> finished dry run: 3 candidates (disk space saved: 1 MiB)" ;;
  *-duk*) echo "==> no candidate packages found for pruning" ;;
  *) echo "==> finished: 3 packages removed" ;;
esac
EOF
fake checkservices <<'EOF'
#!/usr/bin/env bash
echo "Found: 'fake.service'"
EOF
fake curl <<'EOF'
#!/usr/bin/env bash
[[ -n "${FAKE_NEWS:-}" ]] || exit 1
printf '<a title="View: %s" href="/news/x/">x</a><table><tr><td>2099-01-01</td></tr></table>\n' "$FAKE_NEWS"
EOF
fake npm <<'EOF'
#!/usr/bin/env bash
[[ "$1 $2" == "outdated -g" ]] && printf '{"@openai/codex":{"current":"0.171.0","latest":"0.172.0"}}'
exit 0
EOF
fake pip <<'EOF'
#!/usr/bin/env bash
exit 1
EOF

# Corre el lanzador y devuelve lo que se vio en pantalla, sin colores.
test_env=(env -u CACHY_AUTO_EVENTS PATH="$bin:$PATH" LANG=es_MX.UTF-8 LC_ALL= LANGUAGE=
  XDG_STATE_HOME="$fixture/state" XDG_RUNTIME_DIR="$fixture/run" XDG_CACHE_HOME="$fixture/cache"
  XDG_CONFIG_HOME="$fixture/config" COLUMNS=120)

screen() {
  LC_ALL=C sed -E 's#\r##g; s#\x1b\[[0-9;?]*[ -/]*[@-~]##g' "$fixture/screen"
}

# Corre el lanzador sin terminal y devuelve lo que mostro, sin colores.
run() {
  local status
  set +e
  printf '\n' | "${test_env[@]}" "$@" "$project_dir/cachy-auto-update.sh" > "$fixture/screen" 2>&1
  status=$?
  set -e
  screen
  return "$status"
}

# Igual, pero dentro de una terminal virtual (pantalla en vivo). Envia un
# Enter a mitad de camino, que debe descartarse, y otro al final.
run_live() {
  local fifo="$fixture/input" pid status _
  mkfifo "$fifo"
  "${test_env[@]}" "$@" script --quiet --return --command "$project_dir/cachy-auto-update.sh" /dev/null \
    < "$fifo" > "$fixture/screen" 2>&1 &
  pid=$!
  exec 7> "$fifo"
  sleep 1
  printf '\n' >&7
  for _ in $(seq 300); do
    grep -q "Presiona Enter" "$fixture/screen" && break
    sleep 0.1
  done
  sleep 0.5
  if ! kill -0 "$pid" 2>/dev/null; then
    printf 'ERROR: un Enter durante la actualizacion cerro la ventana\n' >&2
    return 99
  fi
  printf '\n' >&7
  set +e
  wait "$pid"
  status=$?
  set -e
  exec 7>&-
  rm -f -- "$fifo"
  screen
  return "$status"
}

expect() {
  if ! grep -qF -- "$1" <<< "$2"; then
    printf 'ERROR: falta "%s" en:\n%s\n' "$1" "$2" >&2
    exit 1
  fi
}

# 1) Pantalla en vivo (dentro de una terminal virtual): avance de pacman y
#    paru, huerfanos, noticias, fallo de AUR y resumen final.
set +e
out="$(run_live FAKE_ORPHANS=python-pyelftools FAKE_NEWS="Intervencion manual en foo")"
status=$?
set -e
test "$status" -ne 99
if [[ "$status" -eq 0 ]]; then
  printf 'ERROR: un fallo de AUR termino con exito\n%s\n' "$out" >&2
  exit 1
fi
expect "descargando 2/2" "$out"
expect "1/2  foo" "$out"
expect "2/2  bar" "$out"
expect "construyendo rustdesk (1/1)" "$out"
expect "2 paquetes actualizados" "$out"
expect "falló: rustdesk 1.5.0-0 → 1.5.3-1" "$out"
expect "1 pendiente" "$out"
expect "1 aplicación actualizada" "$out"
expect "quitado: python-pyelftools" "$out"
if grep -qE ', *$' <<< "$(grep -F "quitado:" <<< "$out")"; then
  printf 'ERROR: lista con coma sobrante\n' >&2
  exit 1
fi
expect "3 archivos eliminados" "$out"
expect "1 servicio reiniciado" "$out"
expect "@openai/codex 0.171.0 → 0.172.0" "$out"
expect "Intervencion manual en foo" "$out"
expect "✖ Terminó con errores" "$out"
logs=("$fixture"/state/cachy-auto-update/logs/*.log)
test "${#logs[@]}" -eq 1
expect "existe en el sistema de archivos" "$(cat "${logs[0]}")"
expect "-Rns --noconfirm python-pyelftools" "$(cat "${logs[0]}")"
if grep -q $'\e' "${logs[0]}"; then
  printf 'ERROR: el registro conserva codigos de terminal\n' >&2
  exit 1
fi
test -z "$(find "$fixture/run" -maxdepth 1 -name 'cachy-auto-update*' -print -quit)"

# 2) Sin actualizaciones: todo al dia y sin error.
sleep 1
out="$(run FAKE_MODE=none)"
expect "todo al día" "$out"
expect "✔ Todo listo" "$out"

# 3) Si falla pacman se conserva el codigo de salida y no se limpian caches.
sleep 1
set +e
out="$(run FAKE_MODE=repofail)"
status=$?
set -e
test "$status" -eq 5
expect "pacman falló" "$out"
expect "se omite porque hubo errores" "$out"

# 4) Solo quedan los ultimos 2 registros.
logs=("$fixture"/state/cachy-auto-update/logs/*.log)
test "${#logs[@]}" -eq 2

printf '\nOK: pantalla en vivo, avance, huerfanos, noticias, errores y 2 registros.\n'
