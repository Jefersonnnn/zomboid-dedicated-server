# Project Zomboid Dedicated Server — Build 42 (fork)

Fork de [Renegade-Master/zomboid-dedicated-server](https://github.com/Renegade-Master/zomboid-dedicated-server)
(GPL-3.0), adaptado para a **Build 42 Stable** e para rodar no **Dokploy**.

> Imagem não oficial: não é suportada pela Valve nem pela The Indie Stone.

## O que mudou em relação ao original

| Original | Este fork |
|---|---|
| Base `steamcmd-minimal` sobre Ubuntu EOL (`old-releases`) | `steamcmd/steamcmd:ubuntu-24`, reconstruída diariamente |
| Atualiza o jogo em **todo** start | Só instala se faltar; atualiza apenas com `UPDATE_ON_START=true` |
| Desligamento via RCON (binário ausente) ou `pkill` (sem salvar) | Envia `quit` pelo console do servidor → salva o mundo antes de sair |
| Primeiro start: mata o servidor após 60 s fixos | Espera os arquivos de config aparecerem e encerra com `quit` |
| Variáveis sobrescrevem o `.ini` sempre (inclusive com padrões) | Só sobrescrevem se a variável estiver **definida** |
| Reescreve o `.ini` inteiro e injeta `[ServerConfig]` | Edita só a linha da chave; avisa se a chave não existir (B42) |
| `sed` no `-XX:+Use*` podia apagar outras flags da JVM | Ajusta apenas o `-Xmx` via JSON |
| Pastas no host com dono errado → erro de permissão | Entrypoint corrige o dono e roda o jogo como `steam` (UID 1000) |
| Porta RCON 27015 publicada | Sem RCON; comandos via `pz-console` |

## Uso com Dokploy

1. **Create Service → Compose**, fonte: este repositório (branch `main`).
2. Compose path: `./docker-compose.yaml`.
3. Aba **Environment**: copie o conteúdo de [`.env.example`](.env.example) e ajuste
   pelo menos `ADMIN_PASSWORD` e `SERVER_PASSWORD`.
4. **Deploy** e acompanhe os logs. O primeiro start baixa o jogo (alguns GB)
   e gera o mundo. Está pronto quando os logs mostram o servidor aceitando
   conexões e nenhum erro após `Starting Project Zomboid server`.
5. Libere **UDP 16261 e 16262** no firewall (Hostinger e, se ativo, UFW).

Sem Dokploy: `cp .env.example .env && docker compose up -d --build`.

## Dados persistentes

| Host | Container | Conteúdo |
|---|---|---|
| `/srv/zomboid/data` | `/home/steam/Zomboid` | `.ini`, SandboxVars, mundo (`Saves/`), banco de jogadores, logs, mods — **faça backup** |
| `/srv/zomboid/server` | `/home/steam/ZomboidDedicatedServer` | instalação do jogo (pode ser baixada de novo) |

## Variáveis

Veja os comentários em [`.env.example`](.env.example). Resumo:

- **Sempre aplicadas:** `ADMIN_PASSWORD` (obrigatória), `ADMIN_USERNAME`,
  `SERVER_NAME`, `MAX_RAM`, `GAME_VERSION`, `UPDATE_ON_START`.
- **Sobrescrevem o `.ini` só se definidas:** `SERVER_DISPLAY_NAME`→`PublicName`,
  `SERVER_PASSWORD`→`Password`, `MAX_PLAYERS`→`MaxPlayers`,
  `PUBLIC_SERVER`→`Open`, `LIST_IN_BROWSER`→`Public`,
  `PAUSE_ON_EMPTY`→`PauseEmpty`, `AUTOSAVE_INTERVAL`→`SaveWorldEveryMinutes`,
  `MOD_NAMES`→`Mods`, `MOD_WORKSHOP_IDS`→`WorkshopItems`, `MAP_NAMES`→`Map`,
  `DEFAULT_PORT`→`DefaultPort`, `UDP_PORT`→`UDPPort`.

Qualquer outra opção: edite `/srv/zomboid/data/Server/<SERVER_NAME>.ini`
e reinicie.

## Operação

```bash
# Comandos no console do servidor (saída aparece nos logs)
docker exec zomboid pz-console save
docker exec zomboid pz-console 'servermsg "Reiniciando em 5 minutos"'

# Parar salvando o mundo (o compose dá 2 min para o save)
docker stop zomboid
```

### Atualizar o jogo

1. Pare o servidor e faça backup de `/srv/zomboid/data`.
2. Defina `UPDATE_ON_START=true` e reinicie/redeploy.
3. Confira nos logs `Installed build: <id>`.
4. Volte `UPDATE_ON_START=false`.

## Testes

```bash
python3 -m pytest tests/
shellcheck src/*.sh src/pz-console
```
