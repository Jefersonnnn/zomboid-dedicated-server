#!/usr/bin/env bash
#
#  Project Zomboid Dedicated Server - container entrypoint.
#  Copyright (C) 2021-2022 Renegade-Master; modified 2026. GPL-3.0 (see LICENSE).
#
#  Runs as root only to make sure the bind-mounted volumes belong to the
#  steam user (avoids the classic "permission denied" on first start),
#  then drops privileges and hands over to run_server.sh.
#

set -Eeuo pipefail

readonly RUN_USER="steam"
readonly HOME_DIR="/home/${RUN_USER}"
readonly VOLUMES=("${HOME_DIR}/ZomboidDedicatedServer" "${HOME_DIR}/Zomboid")

fix_volume_ownership() {
    local uid gid dir
    uid="$(id -u "$RUN_USER")"
    gid="$(id -g "$RUN_USER")"

    for dir in "${VOLUMES[@]}"; do
        mkdir -p "$dir"
        # Recursive chown only when needed: the install folder holds GBs.
        if [[ "$(stat -c '%u:%g' "$dir")" != "${uid}:${gid}" ]]; then
            printf '### Fixing ownership of %s\n' "$dir"
            chown -R "${uid}:${gid}" "$dir"
        fi
    done
}

main() {
    if [[ "$(id -u)" -eq 0 ]]; then
        fix_volume_ownership
        export HOME="$HOME_DIR" USER="$RUN_USER"
        exec setpriv --reuid="$RUN_USER" --regid="$RUN_USER" --init-groups \
            /usr/local/bin/run_server.sh "$@"
    fi

    # Already unprivileged (e.g. started with `user:`): just run.
    exec /usr/local/bin/run_server.sh "$@"
}

main "$@"
