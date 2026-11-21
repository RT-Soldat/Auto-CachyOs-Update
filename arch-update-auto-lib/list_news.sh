#!/usr/bin/env bash
source /usr/share/arch-update/lib/list_news.sh

# Una noticia nueva de Arch puede pedir pasos manuales: se muestra su titulo.
if [ -n "${show_news}" ] && [ "${news}" != "error" ] && [ -n "${news_titles}" ]; then
  auto_event news warn "$(head -n 1 <<< "${news_titles}")"
fi
