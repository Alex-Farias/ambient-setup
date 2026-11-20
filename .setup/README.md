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

## Modo `--local` (Ollama na GPU)

Opcional. `claude-box --local` roda o Claude Code com um modelo local no Ollama, em vez da nuvem. Sem a flag, `claude-box` continua igual (nuvem, sem GPU, sem Ollama). O ai-jail e o ai-memory seguem ativos nos dois modos.

**Instalação (o Ollama é opcional e não vem por padrão)**

    ./setup.sh --local-yes        # instala o claude-box JÁ com o Ollama (padrão: --local-no)
    claude-box --install-local    # já tem o claude-box? reconstrói a imagem com o Ollama (só a camada do Ollama)

Sem o Ollama a imagem fica como era: menor (~2,4 GB a menos) e sem o `curl | sh` de `ollama.com`. Se você rodar `claude-box --local` numa imagem sem Ollama, ele avisa e manda rodar `--install-local`. Para tirar o Ollama de novo: `./setup.sh 1` (sem `--local-yes`); os modelos do volume `ollama-models` ficam guardados.

**Como usar**

    claude-box --local                                  # modelo padrão: qwen3:8b
    CLAUDE_BOX_LOCAL_MODEL=qwen3:14b claude-box --local # trocar de modelo
    claude-box --local --resume                         # argumentos extras vão para o claude

Na primeira vez com cada modelo o `ollama pull` roda sozinho. Os modelos ficam no volume `ollama-models` (`/ollama-models`), compartilhado entre projetos: cada modelo baixa uma vez só.

**Variáveis**

| Variável | Padrão | Para quê |
|---|---|---|
| `CLAUDE_BOX_LOCAL_MODEL` | `qwen3:8b` | modelo usado e baixado |
| `CLAUDE_BOX_LOCAL_KEEP_ALIVE` | `2m` | tempo do modelo na VRAM após o uso (libera a GPU para o ComfyUI) |
| `CLAUDE_BOX_LOCAL_CTX` | `32768` | tamanho do contexto |
| `CLAUDE_BOX_MEM` | `6g` no `--local` | teto de RAM do container (3g no modo normal) |
| `CLAUDE_BOX_OLLAMA_URL` | vazio | ponto de extensão: se definida, não sobe o Ollama interno e usa essa URL (libere o host em `CLAUDE_BOX_JAIL_FLAGS`) |

**Como funciona:** `--gpus all`; o `ollama serve` sobe no container, fora do jail; o jail alcança `127.0.0.1:11434` com `--forward-port 11434` (o mesmo mecanismo do ai-memory); `ANTHROPIC_BASE_URL`, `ANTHROPIC_AUTH_TOKEN` e `ANTHROPIC_API_KEY` entram no jail pelo nome (`--env`). A GPU não vai para o jail.

**Isolamento do modo normal:** o `--local` usa um projeto próprio no ai-memory (`<projeto>-local`, mesmo servidor) e uma config própria do Claude em `~/.claude-local` (sessões, `settings.json`, `.claude.json`), declarando `--harness claude` ao ai-jail. Assim ele não muda a workstream que o `claude-box` normal retoma nem grava o modelo local no `~/.claude`. Não precisa de login.

**Limitações**
- Exige GPU NVIDIA com Docker Desktop (WSL2) e a imagem com Ollama (`--local-yes` ou `claude-box --install-local`).
- O Ollama do WSL (systemd) deve ficar desativado: `systemctl is-enabled ollama`.
- Um projeto local por vez: o Ollama usa a porta 11434 da rede do `ai-memory-server`.
- GPU e VRAM disputadas com o ComfyUI; com pouca VRAM livre o modelo cai parcialmente na CPU (`ollama ps` mostra a divisão).
- Qualidade de um modelo de 8B é bem inferior à do Claude da nuvem; use para tarefas simples.
- As sessões locais ficam em `~/.claude-local` e não entram no `claude-box --collect` (que lê o `~/.claude`).
- Não dá para trocar para o Opus dentro do `--local` (`/model`): todas as chamadas vão ao Ollama. Para usar o Claude da nuvem, saia e rode `claude-box`.
