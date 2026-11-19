#!/usr/bin/env bash
# =============================================================================
# 06-collect-telemetry.sh: junta, numa pasta só, os dados do Claude Code e do
# ai-memory dos repos que têm .ai-memory.toml (criado pelo claude-box-init).
# =============================================================================
#   Roda no HOST (WSL), nunca dentro do jail. NUNCA apaga nada da origem.
#
#   USO
#     bash 06-collect-telemetry.sh --dry-run   só mostra o que faria
#     bash 06-collect-telemetry.sh             coleta de verdade
#
#   VARIÁVEIS (opcionais)
#     COLLECT_ROOT  onde procurar marcadores   (padrão: ~/projects)
#     COLLECT_DEST  destino                    (padrão: ~/projects/telemetry/data/raw)
#
#   O QUE COLETA
#     DEST/claude/      histórico de cada repo (projects/<pasta>/*.jsonl) e os
#                       arquivos globais (history.jsonl, file-history, ...).
#                       Fora: .credentials.json, settings.json, plugins, skills.
#     DEST/ai-memory/   snapshot do banco (backup-*.tar.gz) e um export OKF por
#                       projeto (okf-<workspace>-<projeto>.tar.gz).
#     DEST/repos.tsv    caminho, workspace, projeto e pasta de histórico.
#
#   ATENÇÃO
#     - O backup e o export do ai-memory são pedidos AO SERVIDOR (ele precisa
#       estar no ar; o script o liga se estiver parado). Nada é parado: parar o
#       ai-memory-server derruba a rede de todos os claude-box abertos.
#     - Os arquivos têm suas conversas inteiras e o config.toml do ai-memory.
#       O script NÃO confere o .gitignore: o destino pode ir para um repo
#       privado. Quem publicar assume o risco (veja a conversa sobre segurança).
# =============================================================================
set -euo pipefail

ROOT="${COLLECT_ROOT:-$HOME/projects}"
DEST="${COLLECT_DEST:-$HOME/projects/telemetry/data/raw}"
IMAGE="claude-box"
SERVER="ai-memory-server"
DRY=0
case "${1:-}" in
  "") ;;
  --dry-run) DRY=1 ;;
  -h|--help) sed -n '2,/^set -euo/p' "$0" | sed '$d' | sed 's/^# \{0,1\}//'; exit 0 ;;
  *) echo "argumento inválido: $1 (use --dry-run ou -h)" >&2; exit 2 ;;
esac

say()  { printf '\n==> %s\n' "$*"; }
warn() { printf 'AVISO: %s\n' "$*" >&2; }
fail() { printf 'ERRO: %s\n' "$*" >&2; exit 1; }

command -v docker >/dev/null 2>&1 || fail "docker não encontrado."
docker info >/dev/null 2>&1       || fail "o Docker não responde (abra o Docker Desktop)."
docker image inspect "$IMAGE" >/dev/null 2>&1       || fail "imagem $IMAGE não existe (rode o passo 1 do setup)."
docker volume inspect claude-home >/dev/null 2>&1    || fail "volume claude-home não existe."
docker volume inspect ai-memory-data >/dev/null 2>&1 || fail "volume ai-memory-data não existe."

# --- 1. repos com marcador -----------------------------------------------------
say "Repos com .ai-memory.toml em $ROOT"
repos=()   # cada item: caminho|workspace|projeto|pasta-de-histórico
while IFS= read -r f; do
  d=$(dirname "$f")
  ws=$(sed -n 's/^workspace *= *"\([^"]*\)".*/\1/p' "$f" | head -1)
  pj=$(sed -n 's/^project *= *"\([^"]*\)".*/\1/p' "$f" | head -1)
  [ -n "$ws" ] || ws=default
  if [ -z "$pj" ] || ! printf '%s%s' "$ws" "$pj" | grep -Eq '^[A-Za-z0-9._-]+$'; then
    warn "marcador ignorado (nome vazio ou com caracteres fora de A-Za-z0-9._-): $f"; continue
  fi
  # o Claude Code nomeia a pasta de histórico trocando tudo que não é letra/número por "-"
  enc=$(printf '%s' "$d" | sed 's/[^A-Za-z0-9]/-/g')
  repos+=("$d|$ws|$pj|$enc")
done < <(find "$ROOT" -maxdepth 4 -name .ai-memory.toml -not -path '*/node_modules/*' 2>/dev/null | sort)
[ ${#repos[@]} -gt 0 ] || fail "nenhum .ai-memory.toml válido em $ROOT."

# --- 2. o que existe no volume claude-home (leitura) ---------------------------
top=$(docker run --rm -u 1000 -v claude-home:/home/dev:ro "$IMAGE" ls -1a /home/dev/.claude 2>/dev/null || true)
have=$(docker run --rm -u 1000 -v claude-home:/home/dev:ro "$IMAGE" ls -1 /home/dev/.claude/projects 2>/dev/null || true)
paths=()
for p in history.jsonl file-history paste-cache plans sessions session-env shell-snapshots; do
  if printf '%s\n' "$top" | grep -qxF -- "$p"; then paths+=("$p"); fi
done
for r in "${repos[@]}"; do
  IFS='|' read -r d ws pj enc <<<"$r"
  if printf '%s\n' "$have" | grep -qxF -- "$enc"; then st="histórico ok"; paths+=("projects/$enc"); else st="sem histórico no volume"; fi
  printf '  %-48s %s/%s  [%s]\n' "$d" "$ws" "$pj" "$st"
done

if [ "$DRY" -eq 1 ]; then
  say "Dry-run: nada foi copiado nem parado"
  printf '  copiaria do claude-home: %s\n' "${paths[@]}"
  echo "  destino: $DEST"
  echo "  ai-memory: 1 backup + 1 export-okf por projeto, pedidos ao servidor (nada é parado)"
  exit 0
fi

# --- 3. destino ----------------------------------------------------------------
mkdir -p "$DEST/claude" "$DEST/ai-memory"
chmod 700 "$DEST" "$DEST/claude" "$DEST/ai-memory"

# --- 4. Claude Code: cópia (volume somente leitura) ----------------------------
say "Copiando histórico do Claude Code"
docker run --rm -u 1000 -v claude-home:/home/dev:ro "$IMAGE" \
  tar cf - -C /home/dev/.claude "${paths[@]}" | tar xf - -C "$DEST/claude"
printf '%s\n' "${repos[@]}" | tr '|' '\t' > "$DEST/repos.tsv"

# --- 5. ai-memory: backup + export por projeto (pedidos ao servidor) -----------
say "Exportando o ai-memory"
stamp=$(date +%Y%m%d-%H%M%S)
[ -f "$HOME/.claude-box-token" ] || fail "token do ai-memory não encontrado (~/.claude-box-token)."
export AI_MEMORY_AUTH_TOKEN="$(cat "$HOME/.claude-box-token")"
if [ "$(docker inspect -f '{{.State.Running}}' "$SERVER" 2>/dev/null || echo false)" != true ]; then
  docker start "$SERVER" >/dev/null 2>&1 || fail "não consegui ligar $SERVER."
  sleep 3
fi

mem() {  # $1 = comando ai-memory, executado na rede do servidor (127.0.0.1:49374)
  local out rc=0
  out=$(docker run --rm --user "$(id -u):$(id -g)" --network "container:$SERVER" \
    -e AI_MEMORY_AUTH_TOKEN -v "$DEST/ai-memory":/out "$IMAGE" sh -c "$1" 2>&1) || rc=$?
  printf '%s\n' "$out" | grep -v ' INFO ' || true
  return "$rc"
}
mem "ai-memory backup --to /out/backup-$stamp.tar.gz" || warn "backup do banco falhou"
while IFS='|' read -r ws pj; do
  mem "ai-memory export-okf --workspace $ws --project $pj --to /out/okf-$ws-$pj.tar.gz" \
    || warn "export-okf falhou para $ws/$pj"
done < <(printf '%s\n' "${repos[@]}" | cut -d'|' -f2,3 | sort -u)

find "$DEST/ai-memory" -type f -exec chmod 600 {} + || warn "não consegui ajustar as permissões dos pacotes"

# --- 6. resumo -----------------------------------------------------------------
say "Pronto"
echo "  jsonl copiados : $(find "$DEST/claude" -name '*.jsonl' | wc -l)"
echo "  pacotes ai-mem : $(find "$DEST/ai-memory" -name '*.tar.gz' | wc -l)"
echo "  tamanho total  : $(du -sh "$DEST" | cut -f1)"
echo "  destino        : $DEST"
