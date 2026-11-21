# Cachy Auto Update

Actualiza repositorios, AUR y Flatpak con `cachy-update` sin confirmaciones,
mostrando el avance y los errores. También actualiza paquetes npm globales,
elimina huérfanos, limpia cachés y reinicia servicios. No reinicia el equipo.

**Requisitos:** CachyOS con `cachy-update` 4.4.x, `sudo` y `paru`;
`npm` y Node.js para los CLIs; Konsole para el lanzador. Flatpak y pip son opcionales.

## Instalación

```bash
git clone https://github.com/RT-Soldat/Auto-CachyOs-Update.git
cd Auto-CachyOs-Update
bash install.sh
```

Abre **Cachy Auto Update** desde el menú de aplicaciones o ejecuta
`./cachy-auto-update.sh`. Añade `--devel` para revisar paquetes `-git` del AUR.
La instalación es por usuario y no requiere sudo.

Registros: `~/.local/state/cachy-auto-update/logs/` (conserva los últimos dos).

## Pruebas

```bash
bash tests/auto-update.sh
bash tests/cache-cleanup.sh
```
