#!/usr/bin/env bash
source /usr/share/arch-update/lib/config.sh

update_check_timeout="${ARCH_UPDATE_AUTO_CHECK_TIMEOUT:-0}"

# Keep one cached version unless the user configured another retention policy.
if ! grep -Eq '^[[:space:]]*KeepOldPackages[[:space:]]*=' "${config_file}" 2>/dev/null; then
  old_packages_num=1
fi
