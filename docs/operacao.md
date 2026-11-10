# Guia de operação

Manutenção do dia a dia de um servidor já instalado: backup, restauração,
atualização, mods, firewall e diagnóstico. Para a instalação, veja o
[README](../README.md).

Os comandos rodam **no host** (a VPS), como `root`. Os caminhos usam os
padrões do compose; se você mudou `PZ_DATA_DIR`/`PZ_SERVER_DIR`, ajuste.

## Onde fica cada coisa

| Host | Conteúdo | Backup? |
|---|---|---|
| `/srv/zomboid/data/Server/` | `<SERVER_NAME>.ini`, `_SandboxVars.lua`, `_spawnregions.lua` | **sim** |
| `/srv/zomboid/data/Saves/Multiplayer/` | o mundo e os personagens | **sim** |
| `/srv/zomboid/data/db/` | contas, admins, banimentos | **sim** |
| `/srv/zomboid/data/Logs/` | logs do jogo | não |
| `/srv/zomboid/server/` | instalação do jogo + mods da Workshop | não (é baixado de novo) |
| `/srv/zomboid/backups/` | arquivos gerados pelo `pz-backup` | copie para fora da VPS |

## Comandos do dia a dia

```bash
docker logs -f --tail 50 zomboid               # acompanhar o servidor
docker stats --no-stream zomboid               # CPU e memória
docker exec zomboid pz-console save            # forçar um save
docker exec zomboid pz-console 'servermsg "Reinicio em 5 minutos"'
docker exec zomboid pz-console players         # quem está online (saída nos logs)

docker restart zomboid                          # reinicia salvando o mundo
docker stop zomboid                             # para salvando o mundo (até 2 min)
docker start zomboid
```

O servidor está pronto quando os logs mostram `*** SERVER STARTED ****` e
`Server is listening on port 16261`.

`docker stop`/`restart` enviam `quit` ao jogo, que **salva o mundo antes de
sair** — os logs mostram `Stopping server: sending 'quit'` e `Server stopped`.

## Reiniciar a VPS com segurança

O botão de reinício do painel da Hostinger equivale a tirar da tomada: o jogo
não salva. E mesmo um `reboot` normal dá ao Docker só ~15 s para parar os
containers. Por isso:

```bash
docker stop zomboid   # salva o mundo
reboot
```

O container volta sozinho depois do boot **se estava rodando**; se você o
parou manualmente, ele continua parado até um `docker start zomboid`.

## Backup

O script [`scripts/pz-backup`](../scripts/pz-backup) avisa os jogadores no
chat, para o servidor (o mundo é salvo), compacta os dados, religa o servidor
e mantém só os backups mais recentes. O servidor fica fora do ar por poucos
segundos além do tempo do save.

**Instalação no host** (uma vez):

```bash
curl -fsSL https://raw.githubusercontent.com/Jefersonnnn/zomboid-dedicated-server/main/scripts/pz-backup \
  -o /usr/local/bin/pz-backup && chmod 755 /usr/local/bin/pz-backup
pz-backup --help
```

Repita o mesmo comando para atualizar o script.

**Uso:**

```bash
pz-backup create        # gera /srv/zomboid/backups/pz-backup-AAAAMMDD-HHMMSS.tar.gz
pz-backup list          # lista os backups
```

Configuração por variáveis de ambiente (opcional): `PZ_BACKUP_KEEP` (quantos
manter, padrão 7), `PZ_WARN_SECONDS` (aviso no chat antes de parar, padrão 30;
`0` desliga), `PZ_BACKUP_DIR`, `PZ_DATA_DIR`, `PZ_CONTAINER`.

Ficam de fora do arquivo `Logs/` e `backups/` (backups internos do jogo).
A instalação do jogo e os mods não entram: são baixados de novo.

**Agendamento diário** — o relógio da VPS está em UTC, então `0 8` = 05:00
em Brasília. Em `crontab -e`:

```cron
0 8 * * * PZ_WARN_SECONDS=60 /usr/local/bin/pz-backup create >> /var/log/pz-backup.log 2>&1
```

Isso também serve de reinício diário, que ajuda a liberar memória do Java.

**Copie os backups para fora da VPS.** Um backup no mesmo disco não protege
contra perda da VPS — e restaurar um snapshot do provedor volta *tudo* para a
data dele. Do seu computador:

```bash
scp root@SEU_IP:/srv/zomboid/backups/pz-backup-*.tar.gz .
```

## Restauração

```bash
pz-backup list
pz-backup restore /srv/zomboid/backups/pz-backup-20261109-050000.tar.gz
```

O script mostra o plano e pede confirmação (`--yes` pula a pergunta). Ele:

1. para o servidor (salvando o estado atual);
2. **move** os dados atuais para `/srv/zomboid/data.before-restore-<data>` —
   nada é apagado;
3. extrai o backup e religa o servidor.

Se a extração falhar, os dados anteriores voltam para o lugar e o servidor não
é iniciado com dados pela metade. Depois de conferir o mundo no jogo, apague a
cópia antiga:

```bash
rm -rf /srv/zomboid/data.before-restore-<data>
```

Restaurar em **outra máquina**: instale o servidor normalmente (README),
rode-o uma vez, pare-o e use `pz-backup restore` com o arquivo copiado.

## Atualizar o jogo

O servidor **não se atualiza sozinho** (`UPDATE_ON_START=false`). Quando sair
um patch, a Steam atualiza os clientes e eles deixam de conseguir entrar até o
servidor ser atualizado — esse é o sinal.

1. `pz-backup create`
2. No Dokploy (aba **Environment**): `UPDATE_ON_START=true` → **Deploy**.
3. Confira a versão nos logs:
   ```bash
   docker logs zomboid 2>&1 | grep -a 'Installed build' | tail -1
   ```
4. Volte para `UPDATE_ON_START=false` → **Deploy** (senão todo restart
   procura atualização).
5. Entre no jogo e confira o mundo e os mods. Se algo quebrou:
   `pz-backup restore` com o backup do passo 1.

Sem Dokploy: edite o `.env` e rode `docker compose up -d` em cada passo.

## Mods

Na aba **Environment** (ou no `.env`), sempre entre **aspas simples**:

```
MOD_WORKSHOP_IDS='3171167894;2846036306'
MOD_NAMES='\damnlib;\92nissanGTR'
```

- `MOD_WORKSHOP_IDS`: os números da Workshop (o `?id=` do link), separados
  por `;`. Só controla o **download**.
- `MOD_NAMES`: o `id=` do `mod.info` de cada mod, **cada um com `\` na
  frente** (formato da Build 42; sem a barra o jogo não carrega nada e não
  avisa). Controla a **ordem de carregamento**: bibliotecas e dependências
  primeiro.
- Um item da Workshop pode ter vários mods (variantes); ative só os que quer.

**Descobrir o `id=` e as dependências** de um mod já baixado pelo servidor:

```bash
W=2846036306   # Workshop ID
find /srv/zomboid/server/steamapps/workshop/content/108600/$W -name mod.info \
  -exec grep -HE '^(id|require|versionMin)=' {} \;
```

Mods com uma pasta `42/` (ou `42.x/`, `common/`) têm versão para a Build 42;
mods só com `mod.info` na raiz são da Build 41. O campo `require=` lista as
dependências, que também precisam entrar nas duas variáveis.

**Adicionar ou remover:** edite as duas variáveis → **Deploy** → valide:

```bash
grep -nE '^(Mods|WorkshopItems)=' /srv/zomboid/data/Server/ZomboidServer.ini
docker logs --since 15m zomboid 2>&1 | grep -aiE 'SERVER STARTED|missing|require|failed to load' | tail -20
```

Adicione poucos mods por vez. Remover um mod de um mundo em andamento pode
quebrar itens/veículos dele já existentes no mapa — faça backup antes.
Veículos e itens de mods novos só aparecem em áreas ainda não exploradas.

**Atualizações de mods:** diferente do jogo, o servidor baixa a versão mais
nova dos mods **a cada start**. Se um autor atualizar um mod com o servidor
ligado, quem tentar entrar recebe erro de versão de mod diferente: basta
`docker restart zomboid`.

## Começar um mundo novo

Mantém configurações, mods e contas; apaga só o mapa e os personagens.

```bash
pz-backup create
docker stop zomboid
ls /srv/zomboid/data/Saves/Multiplayer/              # confira os nomes
cd /srv/zomboid/data/Saves/Multiplayer
for d in ZomboidServer*; do mv "$d" "/srv/zomboid/old-world-$(date +%F)-$d"; done
docker start zomboid
```

`ZomboidServer` é o `SERVER_NAME`. Para mudar as regras do mundo novo (zumbis,
loot, tempo), edite `/srv/zomboid/data/Server/ZomboidServer_SandboxVars.lua`
**antes** do `docker start`. Para zerar também as contas, mova
`/srv/zomboid/data/db/ZomboidServer.db` do mesmo jeito (o admin é recriado com
`ADMIN_USERNAME`/`ADMIN_PASSWORD`).

## Firewall

Precisam chegar ao container: **UDP 16261 e 16262**.

**UFW com [`ufw-docker`](https://github.com/chaifeng/ufw-docker)** (regras na
cadeia `DOCKER-USER`): esse arranjo bloqueia por padrão as portas publicadas
por containers, então `ufw allow` não basta — é preciso uma regra de
encaminhamento:

```bash
ufw route allow proto udp from any to any port 16261:16262 comment 'Project Zomboid'
```

O `to any` é proposital: o IP interno do container muda a cada deploy.

**UFW sem `ufw-docker`:** o Docker publica portas por fora do UFW, então elas
já ficam abertas (e regras `ufw deny` não as fecham).

**Firewall do provedor** (ex.: painel da Hostinger): use **um** firewall só.
Dois firewalls com regras diferentes geram falhas difíceis de diagnosticar —
neste servidor, ativar o da Hostinger por cima do UFW quebrou os logs e o
monitoramento do Dokploy.

Para ver se o firewall está barrando o jogo:

```bash
journalctl -k --since "-10min" | grep -a 'UFW DOCKER BLOCK' | grep -a 1626 | tail
```

## Recursos

Valores para uma VPS de 8 GB / 2 vCPU com outros serviços:

| Variável | Valor | Por quê |
|---|---|---|
| `MAX_RAM` | `4g` | heap do Java; folgado para 4 jogadores |
| `PZ_MEM_LIMIT` | `6g` | heap + ~1,5 GB de memória nativa do Java |
| `JVM_GC` | `G1GC` | o ZGC (padrão do jogo) reserva o heap inteiro de saída e estourou o limite |
| `PZ_CPUS` | `1.5` | instalação/atualização/geração de mundo usam todos os núcleos e travavam o Dokploy |
| `PZ_CPU_SHARES` | `512` | em disputa, os outros serviços são atendidos primeiro |

Conferir se o container chegou perto do limite de memória:

```bash
docker exec zomboid awk '/^(anon|shmem) /{printf "%-6s %6.0f MB\n",$1,$2/1048576}' /sys/fs/cgroup/memory.stat
docker inspect zomboid --format 'OOMKilled={{.State.OOMKilled}} Restarts={{.RestartCount}}'
```

`anon` + `shmem` perto de `PZ_MEM_LIMIT`, ou `OOMKilled=true`, pede mais
memória ou um `MAX_RAM` menor. O `MEM USAGE` do `docker stats` inclui cache de
disco e sozinho não indica problema.

## Solução de problemas

| Sintoma | Causa provável | O que fazer |
|---|---|---|
| Timeout ao conectar, nada nos logs | firewall | seção [Firewall](#firewall) |
| "Versão diferente" ao conectar | cliente atualizado pela Steam, servidor não | [Atualizar o jogo](#atualizar-o-jogo) |
| Erro de versão de **mod** ao conectar | mod atualizado com o servidor ligado | `docker restart zomboid` |
| Mod não carrega, sem erro | `MOD_NAMES` sem `\` ou com o nome em vez do `id=` | seção [Mods](#mods) |
| Painel do Dokploy lento durante deploy | instalação/geração de mundo usando toda a CPU | `PZ_CPUS` |
| Container reinicia sozinho, `OOMKilled=true` | memória | seção [Recursos](#recursos) |
| `ADMIN_PASSWORD must be set` | variável ausente | defina em **Environment** |
| `Key '...' not found ...; not added` | chave inexistente no `.ini` desta versão | remova a variável ou edite o `.ini` à mão |
| Primeira tentativa do SteamCMD falha | comum na primeira execução | nada: o script tenta de novo |

**Pode ignorar nos logs** (ruído normal de servidor sem interface): centenas
de `Could not find icon`, `Missing ThumpSound`, `duplicate texture`,
`[S_API FAIL] Tried to access Steam interface ...` antes do `Steam is enabled`,
`flock ... errno = 13` e `IsoPropertyTypeNotFoundException: ... WindowShape`.
