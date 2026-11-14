# Project Zomboid Dedicated Server — Build 42

Servidor dedicado de **Project Zomboid (Build 42 Stable)** em Docker, pronto
para o **Dokploy** ou para `docker compose`. Fork de
[Renegade-Master/zomboid-dedicated-server](https://github.com/Renegade-Master/zomboid-dedicated-server)
(GPL-3.0), refeito para a Build 42, com atualização controlada, desligamento
que salva o mundo e scripts de backup.

> Projeto não oficial: não é suportado pela Valve nem pela The Indie Stone.

- [Requisitos](#requisitos)
- [Instalação](#instalação)
- [Primeiro start](#primeiro-start)
- [Conectar pelo jogo](#conectar-pelo-jogo)
- [Painel de controle](#painel-de-controle)
- [Configuração](#configuração)
- [Operação: backup, restauração, atualização, mods](docs/operacao.md)
- [O que mudou em relação ao original](#o-que-mudou-em-relação-ao-original)

## Requisitos

| Item | Recomendado | Observação |
|---|---|---|
| Sistema | Linux x86-64 com Docker | testado em Ubuntu 24.04 |
| RAM | 8 GB no host | o container usa até `PZ_MEM_LIMIT` (padrão 6 GB) |
| CPU | 2 vCPU ou mais | o container usa até `PZ_CPUS` (padrão 1,5) |
| Disco | 15 GB livres | jogo (alguns GB) + mods + mundo + backups |
| Docker | Engine 24+ e **Compose 2.24+** | versões antigas rejeitam o `env_file` do compose |
| Rede | UDP **16261** e **16262** liberadas | ver [Firewall](docs/operacao.md#firewall) |

Testado com 4 jogadores numa VPS de 8 GB / 2 vCPU dividida com outros
serviços. Para menos RAM, reduza `MAX_RAM` e `PZ_MEM_LIMIT` juntos
(mantenha `PZ_MEM_LIMIT` ≥ `MAX_RAM` + 1,5 GB).

## Instalação

### Com Dokploy

1. **Create Service → Compose**. Fonte: este repositório (ou seu fork),
   branch `main`, Compose Path `./docker-compose.yaml`.
2. **Compose Type: Docker Compose** — *não* Stack. O modo Stack (Swarm)
   ignora `build`, `mem_limit` e `cpus`.
3. Aba **Environment**: cole o conteúdo de [`.env.example`](.env.example) e
   troque pelo menos `ADMIN_PASSWORD`, `SERVER_PASSWORD`, `RCON_PASSWORD`,
   `PANEL_URL` e `DOCKER_GID`.
4. Aba **Domains**: adicione um domínio **só para o serviço `panel`**, porta
   **3001**, com HTTPS. O serviço `zomboid` não leva domínio: o jogo usa UDP
   direto no host, não passa pelo Traefik.
5. **Deploy**.

## Painel de controle

O serviço `panel` roda o
[Zomboid Control Panel](https://github.com/fpsacha/zomboid-control-panel)
(MIT): console, jogadores, mods, configuração, agendamentos, backups e mapa
no navegador. Ele fala com o jogo por **RCON** na rede interna do compose
(`zomboid:27015`, nunca publicada no host) e liga/desliga o container pela
API do Docker; o `stop` continua mandando `quit`, então o mundo é salvo.

Primeiro acesso:

1. Pegue o token de setup: `docker logs zomboid-panel 2>&1 | grep "SETUP TOKEN"`.
2. Abra `PANEL_URL`, cole o token e crie a conta de admin do painel.
3. Em **Servers**, no perfil do servidor: caminho de instalação `/pz-server`,
   pasta de dados `/zomboid`, RCON `zomboid` / `27015` / `RCON_PASSWORD`,
   **Docker container** `zomboid`.
4. Não use o **Setup Wizard** nem a instalação/atualização do jogo pelo
   painel: quem instala e atualiza é o próprio container (`UPDATE_ON_START`).
   A pasta do jogo está montada só para leitura no painel.

O painel monta `/var/run/docker.sock`, o que dá controle sobre **todos** os
containers da VPS, inclusive o Dokploy: use uma senha forte. Para abrir mão
disso, apague a linha do socket no compose e defina
`PANEL_DOCKER_CONTROL_ENABLED=false` (o painel continua funcionando pelo RCON,
mas sem start/stop).

### Sem Dokploy

```bash
git clone https://github.com/Jefersonnnn/zomboid-dedicated-server.git
cd zomboid-dedicated-server
cp .env.example .env && nano .env      # senhas e ajustes
docker compose up -d --build
```

### Firewall

Libere **UDP 16261 e 16262**. Se o host usa UFW com
[`ufw-docker`](https://github.com/chaifeng/ufw-docker), as portas de
containers ficam bloqueadas até você criar uma regra de encaminhamento:

```bash
ufw route allow proto udp from any to any port 16261:16262 comment 'Project Zomboid'
```

Detalhes e outros cenários em [Firewall](docs/operacao.md#firewall). Use um
firewall só (o do host **ou** o do provedor).

## Primeiro start

O primeiro start leva de 5 a 15 minutos: baixa o jogo (alguns GB), gera os
arquivos de configuração, salva e reinicia com as suas configurações.
Acompanhe:

```bash
docker logs -f zomboid 2>&1 | grep -a -E '###|SERVER STARTED|listening'
```

Sequência esperada:

```
### Server not installed yet: installing.
### SteamCMD app_update 380870 (branch: public), attempt 1/3
### SteamCMD app_update 380870 (branch: public), attempt 2/3   <- normal na 1ª vez
### Installed build: 26486687
### First run: starting the server once to generate its config files.
### Stopping server: sending 'quit' (saves the world).
### Config files generated.
### Applying settings to /home/steam/Zomboid/Server/ZomboidServer.ini
### Starting Project Zomboid server 'ZomboidServer' on 172.x.x.x:16261
*** SERVER STARTED ****
Server is listening on port 16261 (for Steam connection) and port 16262 (for UDPRakNet connection)
```

Os logs do jogo têm muito ruído que **pode ser ignorado**: centenas de
`Could not find icon`, `Missing ThumpSound`, `duplicate texture`, e
`[S_API FAIL] Tried to access Steam interface ...` antes de `Steam is enabled`.
Lista completa em [Solução de problemas](docs/operacao.md#solução-de-problemas).

Os starts seguintes levam cerca de 1 minuto.

## Conectar pelo jogo

1. Jogo na versão **padrão da Steam** (sem beta) — precisa ser a mesma build
   do servidor.
2. **Entrar → Conexão direta** (ou **Favoritos → Adicionar**).
3. IP do servidor, porta **16261**, senha = `SERVER_PASSWORD`. O nome de
   usuário que você digitar vira sua conta no servidor.

Os mods do servidor são baixados automaticamente pelo jogo ao entrar.

Para administrar: entre com `ADMIN_USERNAME` / `ADMIN_PASSWORD` e use os
comandos de admin no chat (`/help`).

## Configuração

Todas as variáveis estão comentadas em [`.env.example`](.env.example).

**Sempre aplicadas:** `ADMIN_PASSWORD` (obrigatória), `ADMIN_USERNAME`,
`SERVER_NAME`, `MAX_RAM`, `JVM_GC`, `GAME_VERSION`, `UPDATE_ON_START`.

**Do compose:** `PZ_MEM_LIMIT`, `PZ_CPUS`, `PZ_CPU_SHARES`,
`PZ_SERVER_DIR`, `PZ_DATA_DIR`, `TZ`.

**Gravadas no `.ini` a cada start, só se estiverem definidas:**

| Variável | Chave no `.ini` |
|---|---|
| `SERVER_DISPLAY_NAME` | `PublicName` |
| `SERVER_PASSWORD` | `Password` |
| `MAX_PLAYERS` | `MaxPlayers` |
| `PUBLIC_SERVER` | `Open` (`true` = qualquer um com a senha) |
| `LIST_IN_BROWSER` | `Public` (listar no navegador de servidores) |
| `PAUSE_ON_EMPTY` | `PauseEmpty` |
| `AUTOSAVE_INTERVAL` | `SaveWorldEveryMinutes` |
| `MOD_WORKSHOP_IDS` | `WorkshopItems` |
| `MOD_NAMES` | `Mods` |
| `MAP_NAMES` | `Map` |
| `DEFAULT_PORT` / `UDP_PORT` | `DefaultPort` / `UDPPort` |
| `RCON_PASSWORD` / `RCON_PORT` | `RCONPassword` / `RCONPort` (usadas pelo painel) |

Qualquer outra opção: edite `/srv/zomboid/data/Server/<SERVER_NAME>.ini` (ou
o `_SandboxVars.lua`, para as regras do mundo) e `docker restart zomboid`.
Variáveis não definidas nunca sobrescrevem o que você editou à mão.

**Mods** usam o formato da Build 42 — cada ID com `\` na frente, entre aspas
simples:

```
MOD_WORKSHOP_IDS='3171167894;2846036306'
MOD_NAMES='\damnlib;\92nissanGTR'
```

Como achar os IDs e as dependências: [Mods](docs/operacao.md#mods).

### Dados persistentes

| Host (padrão) | Container | Conteúdo |
|---|---|---|
| `/srv/zomboid/data` | `/home/steam/Zomboid` | configs, mundo, contas, logs — **faça backup** |
| `/srv/zomboid/server` | `/home/steam/ZomboidDedicatedServer` | jogo e mods da Workshop (baixados de novo se apagados) |

As pastas são criadas automaticamente com o dono certo (UID 1000).

## Operação

Tudo no [guia de operação](docs/operacao.md):

- [comandos do dia a dia](docs/operacao.md#comandos-do-dia-a-dia) e
  [reinício seguro da máquina](docs/operacao.md#reiniciar-a-vps-com-segurança)
- [backup](docs/operacao.md#backup) e [restauração](docs/operacao.md#restauração)
  com o script [`scripts/pz-backup`](scripts/pz-backup)
- [atualizar o jogo](docs/operacao.md#atualizar-o-jogo)
- [mods](docs/operacao.md#mods) e [mundo novo](docs/operacao.md#começar-um-mundo-novo)
- [recursos](docs/operacao.md#recursos) e
  [solução de problemas](docs/operacao.md#solução-de-problemas)

Resumo do essencial:

```bash
docker stop zomboid          # sempre antes de reiniciar a máquina: salva o mundo
pz-backup create             # backup (para, salva, compacta, religa)
```

## O que mudou em relação ao original

| Original | Este fork |
|---|---|
| Base `steamcmd-minimal` sobre Ubuntu sem suporte | `steamcmd/steamcmd:ubuntu-24`, reconstruída diariamente |
| Atualiza o jogo em **todo** start | Só instala se faltar; atualiza apenas com `UPDATE_ON_START=true` |
| Desligamento via RCON (binário ausente) ou `pkill` (sem salvar) | Envia `quit` pelo console do jogo → salva o mundo antes de sair |
| Primeiro start: mata o servidor após 60 s fixos | Espera os arquivos de config aparecerem e encerra com `quit` |
| Variáveis sobrescrevem o `.ini` sempre (inclusive com padrões) | Só sobrescrevem se a variável estiver **definida** |
| Reescreve o `.ini` inteiro e injeta `[ServerConfig]` | Edita só a linha da chave; avisa se a chave não existir |
| `sed` no `-XX:+Use*` podia apagar outras flags da JVM | Ajusta `-Xmx` e o coletor via JSON, preservando as demais flags |
| ZGC (padrão do jogo) reserva o heap inteiro de saída | G1 por padrão (`JVM_GC`): o heap cresce sob demanda |
| Sem limite de CPU | `PZ_CPUS`/`PZ_CPU_SHARES`: o servidor não trava os outros serviços |
| Pastas no host com dono errado → erro de permissão | Entrypoint corrige o dono e roda o jogo como `steam` (UID 1000) |
| Porta RCON 27015 publicada | RCON só na rede interna, para o painel; comandos também via `pz-console` |
| — | Painel web (Zomboid Control Panel) como serviço do mesmo compose |
| — | Script de backup/restauração com retenção e restauração não destrutiva |

## Desenvolvimento

```bash
python3 -m pytest tests/
shellcheck src/*.sh src/pz-console scripts/pz-backup
```

## Licença

GPL-3.0, como o projeto original — veja [LICENSE](LICENSE). Créditos ao
[Renegade-Master](https://github.com/Renegade-Master) e contribuidores do
projeto original.
