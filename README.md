# Cachy Auto Update

Actualiza repositorios, AUR y Flatpak con `cachy-update` sin confirmaciones,
mostrando el avance y los errores. También actualiza paquetes npm globales,
elimina huérfanos, limpia cachés y reinicia servicios. No reinicia el equipo.

**Requisitos:** CachyOS con `cachy-update` 4.4.x, `sudo` y `paru`;
`npm` y Node.js para los CLIs; Konsole para el lanzador. Flatpak y pip son opcionales.

## Uso

```bash
git clone https://github.com/RT-Soldat/Auto-CachyOs-Update.git
cd Auto-CachyOs-Update
./cachy-auto-update.sh
```

No requiere instalación. También puedes abrir `cachy-auto-update.desktop`
desde la carpeta del proyecto. Añade `--devel` al script para revisar paquetes
`-git` del AUR.

Registros: `~/.local/state/cachy-auto-update/logs/` (conserva los últimos dos).

## Pruebas

```bash
bash tests/auto-update.sh
bash tests/cache-cleanup.sh
```
