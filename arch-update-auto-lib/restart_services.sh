#!/usr/bin/env bash
auto_event services run
# Si un reinicio falla, el original termina con exit 11 y la pantalla lo marca.
source /usr/share/arch-update/lib/restart_services.sh

if [ -n "${services}" ]; then
  auto_event services ok "$(auto_plural "${services_num}" "servicio reiniciado" "servicios reiniciados")"
else
  auto_event services ok "ninguno pendiente"
fi
