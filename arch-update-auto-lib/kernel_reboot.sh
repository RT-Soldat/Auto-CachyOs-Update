#!/usr/bin/env bash
source /usr/share/arch-update/lib/kernel_reboot.sh

# Solo se avisa: el reinicio se responde siempre que no.
if ! [ -f "/usr/lib/modules/$(uname -r)/vmlinuz" ]; then
  auto_event reboot warn "kernel nuevo instalado: reinicia cuando puedas"
fi
