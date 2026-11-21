#!/usr/bin/env bash
# Actualiza a @latest los paquetes npm globales del usuario (~/.npm-global) que
# esten desactualizados: claude, codex, opencode y cualquier otro CLI que se
# instale ahi con `npm i -g`. cachy-update (pacman/AUR/flatpak) no los ve. Lo
# llaman cachy-auto-update.sh y el timer de usuario ai-clis-update.timer
# (~/.config/systemd/user/).
set -uo pipefail

# El packument de claude-code es pesado y a veces corta con ETIMEDOUT con los defaults.
export npm_config_fetch_timeout=600000 npm_config_fetch_retries=5

# `npm outdated` sale con codigo 1 cuando hay algo desactualizado: no es un error.
json="$(npm outdated -g --depth=0 --json 2>/dev/null)"
[[ -n "$json" ]] || json="{}"

# Una linea por paquete: nombre, version instalada y ultima version.
if ! report="$(printf '%s' "$json" | node -e '
  const d = JSON.parse(require("fs").readFileSync(0, "utf8") || "{}");
  if (d.error) {
    console.error(d.error.summary || "npm outdated fallo");
    process.exit(1);
  }
  for (const [name, info] of Object.entries(d)) {
    if (name === "npm" || name === "corepack" || !info.current) continue;
    if (info.current !== info.latest) console.log(`${name}\t${info.current}\t${info.latest}`);
  }
')"; then
  echo "No se pudo consultar si hay versiones nuevas en npm." >&2
  exit 1
fi

if [[ -z "$report" ]]; then
  echo "CLIs npm al dia."
  exit 0
fi

pkgs=()
while IFS=$'\t' read -r name current latest; do
  printf '%s %s -> %s\n' "$name" "$current" "$latest"
  pkgs+=("${name}@latest")
done <<< "$report"

# Solo se reinstala lo que cambio; los demas CLIs quedan como estan.
npm install -g "${pkgs[@]}" || exit 1
npm ls -g --depth=0
