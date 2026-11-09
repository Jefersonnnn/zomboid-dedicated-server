#   Project Zomboid Dedicated Server using SteamCMD Docker Image.
#   Copyright (C) 2021-2022 Renegade-Master [renegade.master.dev@protonmail.com]
#   Modified 2026 by Jeferson: Build 42 support, maintained base image,
#   opt-in updates, graceful shutdown.
#
#   This program is free software: you can redistribute it and/or modify
#   it under the terms of the GNU General Public License as published by
#   the Free Software Foundation, either version 3 of the License, or
#   (at your option) any later version.
#
#   This program is distributed in the hope that it will be useful,
#   but WITHOUT ANY WARRANTY; without even the implied warranty of
#   MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
#   GNU General Public License for more details.
#
#   You should have received a copy of the GNU General Public License
#   along with this program.  If not, see <https://www.gnu.org/licenses/>.

# Maintained SteamCMD base (rebuilt daily upstream: github.com/steamcmd/docker)
ARG BASE_IMAGE="docker.io/steamcmd/steamcmd:ubuntu-24"
FROM ${BASE_IMAGE}

SHELL ["/bin/bash", "-o", "pipefail", "-c"]
ARG DEBIAN_FRONTEND=noninteractive
ARG STEAM_UID=1000

RUN apt-get update \
    && apt-get install -y --no-install-recommends python3 tzdata \
    && rm -rf /var/lib/apt/lists/*

# Unprivileged user that owns and runs the game. Ubuntu 24.04 ships a
# default "ubuntu" user on UID 1000; remove it so "steam" can take that UID.
RUN (userdel --remove ubuntu 2>/dev/null || true) \
    && useradd --uid "${STEAM_UID}" --create-home --shell /bin/bash steam

# Bootstrap SteamCMD for the steam user and expose the Steam client
# libraries where the game server expects them (~/.steam/sdk64).
USER steam
ENV HOME=/home/steam USER=steam
RUN (steamcmd +quit || true) \
    && mkdir -p "$HOME/.steam" "$HOME/ZomboidDedicatedServer" "$HOME/Zomboid" \
    && ln -sfn "$HOME/.local/share/Steam/steamcmd/linux32" "$HOME/.steam/sdk32" \
    && ln -sfn "$HOME/.local/share/Steam/steamcmd/linux64" "$HOME/.steam/sdk64" \
    && test -f "$HOME/.steam/sdk64/steamclient.so"

# The entrypoint starts as root only to fix volume ownership, then drops
# to the steam user before anything else runs.
USER root
COPY --chown=root:root --chmod=755 src/entrypoint.sh src/run_server.sh src/pz-console /usr/local/bin/
COPY --chown=root:root --chmod=644 src/pzconfig.py /usr/local/lib/pzconfig.py

EXPOSE 16261/udp 16262/udp
ENTRYPOINT ["/usr/local/bin/entrypoint.sh"]
CMD []
