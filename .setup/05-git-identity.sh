#!/usr/bin/env bash
# 05-git-identity.sh: grava user.name/user.email do git no volume claude-home,
# para o git dentro do jail conseguir fazer commits (push continua no host).
# Lê git-identity.env (só as 2 chaves, sem 'source') ou o git config do host.
set -euo pipefail
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FILE="$DIR/git-identity.env"

read_key() {
  grep -E "^$1=" "$FILE" 2>/dev/null | head -1 | cut -d= -f2- \
    | sed -e 's/^"//' -e 's/"$//' || true
}

NAME=""; EMAIL=""
if [ -f "$FILE" ]; then
  NAME="$(read_key GIT_USER_NAME)"
  EMAIL="$(read_key GIT_USER_EMAIL)"
fi
[ -n "$NAME" ]  || NAME="$(git config --global user.name 2>/dev/null || true)"
[ -n "$EMAIL" ] || EMAIL="$(git config --global user.email 2>/dev/null || true)"

if [ -z "$NAME" ] || [ -z "$EMAIL" ]; then
  echo "ERRO: sem nome/e-mail. Crie git-identity.env (veja o .example) ou rode git config --global." >&2
  exit 1
fi
if printf '%s%s' "$NAME" "$EMAIL" | grep -q '[[:cntrl:]]'; then
  echo "ERRO: caracteres de controle no nome/e-mail." >&2; exit 1
fi
if ! printf '%s' "$EMAIL" | grep -Eq '^[^@ ]+@[^@ ]+$'; then
  echo "ERRO: e-mail inválido: $EMAIL" >&2; exit 1
fi
docker image inspect claude-box >/dev/null 2>&1 || { echo "ERRO: imagem claude-box não existe (rode o passo 1)." >&2; exit 1; }

docker run --rm -u 1000 -v claude-home:/home/dev -e HOME=/home/dev \
  -e GN="$NAME" -e GE="$EMAIL" claude-box \
  sh -c 'git config --global user.name "$GN" && git config --global user.email "$GE" && git config --global --list'
echo "OK: identidade gravada no volume claude-home."
