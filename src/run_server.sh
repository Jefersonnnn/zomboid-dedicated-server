#!/usr/bin/env bash
#
#  Project Zomboid Dedicated Server using SteamCMD Docker Image.
#  Copyright (C) 2021-2022 Renegade-Master [renegade.master.dev@protonmail.com]
#  Contributors: JohnEarle, ramielrowe
#  Modified 2026 by Jeferson: Build 42 support, opt-in updates, graceful
#  shutdown through the server console, config applied only when set.
#
#  This program is free software: you can redistribute it and/or modify
#  it under the terms of the GNU General Public License as published by
#  the Free Software Foundation, either version 3 of the License, or
#  (at your option) any later version.
#
#  This program is distributed in the hope that it will be useful,
#  but WITHOUT ANY WARRANTY; without even the implied warranty of
#  MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#  GNU General Public License for more details.
#
#  You should have received a copy of the GNU General Public License
#  along with this program.  If not, see <https://www.gnu.org/licenses/>.
#
#  Flow: load settings -> install (always) / update (only if
#  UPDATE_ON_START=true) -> first run generates config files -> apply
#  settings -> run server until it exits or the container is stopped.
#

set -Eeuo pipefail

readonly APP_ID="380870"
readonly INSTALL_DIR="${HOME}/ZomboidDedicatedServer"
readonly DATA_DIR="${HOME}/Zomboid"
readonly CONSOLE_FIFO="${PZ_CONSOLE_FIFO:-${HOME}/.run/console.fifo}"
readonly PZCONFIG="/usr/local/lib/pzconfig.py"
readonly STEAMCMD_RETRIES=3

# Environment variable -> key in <SERVER_NAME>.ini.
# Applied on every start ONLY when the variable is defined, so any key not
# listed here (or left undefined) can be edited directly in the .ini file.
readonly INI_OVERRIDES=(
    "SERVER_DISPLAY_NAME:PublicName"
    "SERVER_PASSWORD:Password"
    "MAX_PLAYERS:MaxPlayers"
    "PUBLIC_SERVER:Open"
    "LIST_IN_BROWSER:Public"
    "PAUSE_ON_EMPTY:PauseEmpty"
    "AUTOSAVE_INTERVAL:SaveWorldEveryMinutes"
    "MOD_NAMES:Mods"
    "MOD_WORKSHOP_IDS:WorkshopItems"
    "MAP_NAMES:Map"
    "DEFAULT_PORT:DefaultPort"
    "UDP_PORT:UDPPort"
)

SERVER_PID=""

log() { printf '\n### [%s] %s\n' "$(date '+%F %T')" "$*"; }
warn() { log "WARNING: $*" >&2; }
die() { log "ERROR: $*" >&2; exit 1; }

load_settings() {
    : "${SERVER_NAME:=ZomboidServer}"
    : "${ADMIN_USERNAME:=admin}"
    : "${ADMIN_PASSWORD:=}"
    : "${GAME_VERSION:=public}"
    : "${UPDATE_ON_START:=false}"
    : "${MAX_RAM:=4g}"
    # G1 grows the heap on demand. The game's default (ZGC) reserves the
    # whole heap as shared memory up front, which exhausts small containers.
    : "${JVM_GC:=G1GC}"
    : "${DEFAULT_PORT:=16261}"
    : "${UDP_PORT:=16262}"
    : "${STEAM_VAC:=true}"
    : "${USE_STEAM:=true}"
    : "${FIRST_RUN_TIMEOUT:=900}"
    : "${SHUTDOWN_TIMEOUT:=90}"

    [[ -n "$ADMIN_PASSWORD" ]] || die "ADMIN_PASSWORD must be set."
    [[ "$ADMIN_PASSWORD" != "changeme" ]] || warn "ADMIN_PASSWORD is still the default value."

    # Project Zomboid cannot bind to 0.0.0.0: use the container address.
    if [[ -z "${BIND_IP:-}" || "$BIND_IP" == "0.0.0.0" ]]; then
        BIND_IP="$(hostname -I | awk '{print $1}')"
    fi

    SERVER_INI="${DATA_DIR}/Server/${SERVER_NAME}.ini"
    SERVER_SANDBOX="${DATA_DIR}/Server/${SERVER_NAME}_SandboxVars.lua"
    JVM_CONFIG="${INSTALL_DIR}/ProjectZomboid64.json"
}

# ---------------------------------------------------------------- install --

is_installed() { [[ -x "${INSTALL_DIR}/start-server.sh" ]]; }

installed_build() {
    local manifest="${INSTALL_DIR}/steamapps/appmanifest_${APP_ID}.acf"
    if [[ -f "$manifest" ]]; then
        awk -F'"' '/"buildid"/ {print $4; exit}' "$manifest"
    else
        echo "unknown"
    fi
}

run_steamcmd() {
    local attempt
    for ((attempt = 1; attempt <= STEAMCMD_RETRIES; attempt++)); do
        log "SteamCMD app_update ${APP_ID} (branch: ${GAME_VERSION}), attempt ${attempt}/${STEAMCMD_RETRIES}"
        # SteamCMD exit codes are unreliable; the install check below decides.
        steamcmd +force_install_dir "$INSTALL_DIR" +login anonymous \
            +app_update "$APP_ID" -beta "$GAME_VERSION" validate +quit || true
        is_installed && return 0
    done
    die "SteamCMD could not install the server after ${STEAMCMD_RETRIES} attempts."
}

install_or_update() {
    if ! is_installed; then
        log "Server not installed yet: installing."
        run_steamcmd
    elif [[ "$UPDATE_ON_START" == "true" ]]; then
        log "UPDATE_ON_START=true: updating from build $(installed_build)."
        run_steamcmd
    else
        log "Skipping update (UPDATE_ON_START=${UPDATE_ON_START})."
    fi
    log "Installed build: $(installed_build)"
}

# ----------------------------------------------------------------- server --

start_server() {
    local steam_flag=()
    [[ "$USE_STEAM" == "true" ]] || steam_flag=("-nosteam")

    # The server reads console commands from stdin. Feeding it from a FIFO
    # lets us (and `pz-console`) send commands such as "quit" at any time.
    mkdir -p "$(dirname "$CONSOLE_FIFO")"
    rm -f "$CONSOLE_FIFO"
    mkfifo -m 600 "$CONSOLE_FIFO"
    exec 3<>"$CONSOLE_FIFO"

    log "Starting Project Zomboid server '${SERVER_NAME}' on ${BIND_IP}:${DEFAULT_PORT}"
    "${INSTALL_DIR}/start-server.sh" \
        -cachedir="$DATA_DIR" \
        -adminusername "$ADMIN_USERNAME" \
        -adminpassword "$ADMIN_PASSWORD" \
        -ip "$BIND_IP" -port "$DEFAULT_PORT" \
        -servername "$SERVER_NAME" \
        -steamvac "$STEAM_VAC" "${steam_flag[@]}" <&3 &
    SERVER_PID=$!
}

is_server_running() { [[ -n "$SERVER_PID" ]] && kill -0 "$SERVER_PID" 2>/dev/null; }

# Waits up to $1 seconds for the server process to exit.
wait_for_exit() {
    local remaining="$1"
    while is_server_running && ((remaining-- > 0)); do
        sleep 1
    done
    ! is_server_running
}

stop_server() {
    is_server_running || return 0

    log "Stopping server: sending 'quit' (saves the world)."
    printf 'quit\n' >&3
    if ! wait_for_exit "$SHUTDOWN_TIMEOUT"; then
        warn "Server did not stop within ${SHUTDOWN_TIMEOUT}s: sending SIGTERM."
        kill -TERM "$SERVER_PID" 2>/dev/null || true
        wait_for_exit 15 || kill -KILL "$SERVER_PID" 2>/dev/null || true
    fi
    wait "$SERVER_PID" 2>/dev/null || true
    log "Server stopped."
}

# ------------------------------------------------------------ first run --

config_exists() { [[ -f "$SERVER_INI" && -f "$SERVER_SANDBOX" ]]; }

generate_initial_config() {
    config_exists && return 0

    log "First run: starting the server once to generate its config files."
    start_server
    local remaining="$FIRST_RUN_TIMEOUT"
    while ! config_exists && is_server_running && ((remaining-- > 0)); do
        sleep 1
    done
    stop_server
    config_exists || die "Config files were not generated (${SERVER_INI})."
    log "Config files generated."
}

# ----------------------------------------------------------------- config --

apply_settings() {
    local pair var key
    log "Applying settings to ${SERVER_INI}"
    for pair in "${INI_OVERRIDES[@]}"; do
        var="${pair%%:*}"
        key="${pair#*:}"
        if [[ -n "${!var+set}" ]]; then
            python3 "$PZCONFIG" ini-set "$SERVER_INI" "$key" "${!var}" \
                || warn "Could not set ${key} (from ${var})."
        fi
    done

    # SteamCMD "validate" restores this file, so the JVM settings are
    # re-applied on every start.
    python3 "$PZCONFIG" jvm "$JVM_CONFIG" --heap "$MAX_RAM" --gc "$JVM_GC" \
        || warn "Could not apply JVM settings (heap ${MAX_RAM}, GC ${JVM_GC})."
}

# ------------------------------------------------------------------- main --

# shellcheck disable=SC2329  # invoked through `trap`
on_signal() {
    stop_server
    exit 0
}

main() {
    trap on_signal SIGTERM SIGINT

    load_settings
    install_or_update
    generate_initial_config
    apply_settings
    start_server

    # `wait` returns early when a trapped signal arrives; the trap handler
    # then performs the graceful shutdown and exits.
    local status=0
    wait "$SERVER_PID" || status=$?
    log "Server process exited with status ${status}."
    exit "$status"
}

main "$@"
