# docs/setup — ambiente claude-box

Container genérico para rodar `ai-jail` + `ai-memory` + Claude Code (`--yolo`) em qualquer projeto.

## Máquina nova

```bash
git clone <repo> && cd <repo>/docs/setup
./setup.sh            # passos 1-4
source ~/.bashrc
```

Requisitos: WSL2 + Docker Desktop (integração WSL ativa) + `openssl`.

## Arquivos

| Arquivo | Função |
|---|---|
| `setup.sh` | roda 1→4 (`./setup.sh 3` roda só o passo 3) |
| `01-build-image.sh` | constrói a imagem `claude-box` |
| `02-test-bwrap.sh` | testa o bubblewrap no container (`BWRAP_OK`) |
| `03-claude-box-function.sh` | funções `claude-box` e `claude-box-init` (carregadas pelo `~/.bashrc`) |
| `04-dry-run.sh` | mostra o comando do jail sem iniciar o Claude |

## Dia a dia

```bash
cd ~/projects/meu-projeto
claude-box-init            # cria .ai-memory.toml (memória isolada por projeto)
claude-box                 # inicia jail + memory + claude --yolo
claude-box --config        # reajusta as permissões do jail deste projeto
claude-box --show-config   # mostra a aprovação salva
claude-box --mcp-setup     # registra o MCP do ai-memory (uma vez por máquina)
```

Dois projetos ao mesmo tempo: `CLAUDE_BOX_MEM=1500m CLAUDE_BOX_CPUS=3 claude-box` em cada terminal.
