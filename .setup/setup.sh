#!/usr/bin/env bash
# =============================================================================
# setup.sh  —  roda os 4 passos do ambiente claude-box em sequência
# =============================================================================
#
# QUANDO USAR
#   Ao chegar numa máquina NOVA (WSL2 + Docker Desktop já instalados):
#
#       git clone <seu-repo> && cd <seu-repo>/docs/setup
#       ./setup.sh
#       source ~/.bashrc
#
#   Depois disso, o dia a dia é só:  cd ~/projects/meu-projeto && claude-box
#
# O QUE CADA PASSO FAZ
#   1  01-build-image.sh           constrói a imagem Docker "claude-box"
#                                  (ai-jail + ai-memory + Claude Code).
#   2  02-test-bwrap.sh            testa se o bubblewrap funciona dentro do
#                                  container (precisa imprimir BWRAP_OK).
#   3  03-claude-box-function.sh   INSTALA a função "claude-box" no ~/.bashrc
#                                  (este arquivo é "carregado", não executado).
#   4  04-dry-run.sh               mostra o comando de sandbox que seria usado,
#                                  sem iniciar o Claude (conferência final).
#   5  05-git-identity.sh          grava user.name/user.email do git no volume
#                                  claude-home (commits dentro do jail). Usa
#                                  git-identity.env ou o git config do host.
#                                  Se falhar, só avisa (não aborta o setup).
#
# USO
#   ./setup.sh            roda os passos 1, 2, 3, 4 e 5
#   ./setup.sh 3          roda só o passo 3 (ex.: depois de um git pull)
#   ./setup.sh 1 2        roda só os passos 1 e 2
#   ./setup.sh -h         mostra esta ajuda
#
# SEGURANÇA DE REEXECUÇÃO
#   Pode rodar quantas vezes quiser: o build reaproveita o cache do Docker, e o
#   passo 3 mantém UM único bloco no ~/.bashrc (faz backup em ~/.bashrc.bak-claude-box
#   na primeira alteração).
#
# O QUE O SCRIPT NÃO FAZ (de propósito)
#   - Não faz o login do Claude (acontece na primeira execução do claude-box).
#   - Não registra o MCP do ai-memory (use depois:  claude-box --mcp-setup).
# =============================================================================
set -euo pipefail

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

usage() { sed -n '2,/^set -euo/p' "${BASH_SOURCE[0]}" | sed '$d' | sed 's/^# \{0,1\}//'; }

# --- argumentos: lista de passos (padrão: todos) ------------------------------
steps=()
for a in "$@"; do
  case "$a" in
    -h|--help) usage; exit 0 ;;
    1|2|3|4|5) steps+=("$a") ;;
    *) echo "argumento inválido: $a (use 1, 2, 3, 4, 5 ou -h)" >&2; exit 2 ;;
  esac
done
[ ${#steps[@]} -gt 0 ] || steps=(1 2 3 4 5)

has_step() { local s; for s in "${steps[@]}"; do [ "$s" = "$1" ] && return 0; done; return 1; }

say()  { printf '\n\033[1;36m==> %s\033[0m\n' "$*"; }
fail() { printf '\n\033[1;31mERRO: %s\033[0m\n' "$*" >&2; exit 1; }

# --- pré-requisitos ------------------------------------------------------------
say "Verificando pré-requisitos"
command -v docker  >/dev/null 2>&1 || fail "docker não encontrado. Instale o Docker Desktop e ative a integração com esta distro WSL (Settings > Resources > WSL integration)."
docker info >/dev/null 2>&1        || fail "o Docker não responde. Abra o Docker Desktop, espere ele iniciar e tente de novo."
command -v openssl >/dev/null 2>&1 || fail "openssl não encontrado (a função claude-box usa para gerar o token). Instale com: sudo apt install -y openssl"
# Os passos 2 e 4 usam 'docker run -it', que exige um terminal de verdade.
if has_step 2 || has_step 4; then
  [ -t 0 ] && [ -t 1 ] || fail "os passos 2 e 4 precisam de um terminal interativo (TTY). Rode direto no terminal, não por pipe/script."
fi
echo "docker, daemon e openssl OK"

# --- passo 1 -------------------------------------------------------------------
if has_step 1; then
  say "Passo 1/4 — construindo a imagem claude-box (a 1ª vez demora; baixa ai-jail, ai-memory e Claude)"
  bash "$DIR/01-build-image.sh"
fi

# --- passo 2 -------------------------------------------------------------------
if has_step 2; then
  say "Passo 2/4 — testando o bubblewrap dentro do container (esperado: BWRAP_OK)"
  out=$(bash "$DIR/02-test-bwrap.sh" 2>&1 | tee /dev/stderr) || true
  grep -q BWRAP_OK <<<"$out" || fail "o teste do bwrap não imprimiu BWRAP_OK. Veja a saída acima (o ai-jail não vai funcionar nesta máquina sem isso)."
fi

# --- passo 3 -------------------------------------------------------------------
if has_step 3; then
  say "Passo 3/4 — instalando a função claude-box no ~/.bashrc"
  SRC="$DIR/03-claude-box-function.sh"
  [ -f "$SRC" ] || fail "arquivo não encontrado: $SRC"
  BASHRC="$HOME/.bashrc"
  BEGIN="# >>> claude-box >>>"
  END="# <<< claude-box <<<"
  touch "$BASHRC"

  # Backup único (só na primeira vez).
  [ -f "$BASHRC.bak-claude-box" ] || cp "$BASHRC" "$BASHRC.bak-claude-box"

  # Remove (1) um bloco anterior deste script e (2) a linha antiga manual
  # "source ~/claude-box/03-claude-box-function.sh", para não carregar duas vezes.
  tmp=$(mktemp)
  awk -v b="$BEGIN" -v e="$END" '
    $0==b {skip=1; next}
    $0==e {skip=0; next}
    !skip {print}
  ' "$BASHRC" | grep -v 'claude-box/03-claude-box-function.sh' > "$tmp" || true
  cat "$tmp" > "$BASHRC"; rm -f "$tmp"

  # Acrescenta o bloco novo. O "[ -f ... ] &&" evita erro no terminal se o repo
  # for movido/apagado.
  {
    echo "$BEGIN"
    echo "[ -f \"$SRC\" ] && source \"$SRC\""
    echo "$END"
  } >> "$BASHRC"

  # Confere que o arquivo carrega e define as funções.
  bash -c "source '$SRC' && type claude-box >/dev/null && type claude-box-init >/dev/null" \
    || fail "o 03-claude-box-function.sh não carregou corretamente."
  echo "instalado: $BASHRC carrega $SRC"
fi

# --- passo 4 -------------------------------------------------------------------
if has_step 4; then
  say "Passo 4/4 — dry-run do ai-jail (só mostra o comando, não inicia o Claude)"
  ( cd "$DIR" && bash "$DIR/04-dry-run.sh" )
fi

# --- passo 5 (não fatal) -------------------------------------------------------
if has_step 5; then
  say "Passo 5/5 — identidade do git no volume claude-home"
  bash "$DIR/05-git-identity.sh" || printf '\033[1;33mAVISO: passo 5 falhou; crie .setup/git-identity.env (veja o .example) e rode ./setup.sh 5\033[0m\n' >&2
fi

# --- fim -----------------------------------------------------------------------
say "Pronto"
cat <<'MSG'
Próximos passos:
  1. Recarregue o shell:           source ~/.bashrc
  2. Em cada projeto novo:         cd ~/projects/meu-projeto
                                   claude-box-init          # isola a memória do projeto
                                   claude-box               # 1ª vez: faça o login do Claude
  3. Uma vez por máquina:          claude-box --mcp-setup   # registra o MCP do ai-memory
  Reajustar permissões do jail:    claude-box --config
MSG
