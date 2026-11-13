#!/usr/bin/env bash
# =============================================================================
# 04-dry-run.sh  —  PASSO 4: ver o que o ai-jail faria, SEM executar  (v2)
# =============================================================================
#
# O QUE FAZ
#   Mostra o "plano" do ai-jail (pastas montadas, variáveis, rede) sem iniciar o
#   Claude nem o ai-memory. Use depois de mudar qualquer flag do jail.
#
# COMO RODAR (dentro da pasta de um projeto)
#   bash 04-dry-run.sh
#
# O QUE O SEU PRIMEIRO DRY-RUN JÁ MOSTROU (resumo)
#   - bubblewrap + Landlock + seccomp + limites de recursos, HOME privado.
#   - Rede isolada (--unshare-net / --no-network) com saída filtrada: só
#     api.anthropic.com, registros de pacotes e github.com.
#   - O ambiente é LIMPO (--clearenv): só PATH, HOME, TERM, proxies etc.
#
# O QUE CONFERIR NA v2
#   1) Aparece a porta 49374 sendo encaminhada para o loopback do jail
#      (efeito do --forward-port). Se o ai-jail rejeitar a flag, a mensagem de
#      erro aparece aqui, sem risco.
#   2) A variável AI_MEMORY_AUTH_TOKEN é listada pelo NOME (o valor não deve
#      aparecer).
#   3) ~/.claude montado (agent-state). Para isso o volume claude-home precisa
#      estar montado, como nesta versão.
#   4) A pasta do projeto montada no caminho real, gravável.
#
# SOBRE A FORMA DESTE ARQUIVO
#   Comentário não pode ficar entre linhas terminadas em "\"; as flags ficam em
#   listas (arrays) comentadas. O efeito é idêntico a uma linha só.
#
# =============================================================================

flags=(
  # --rm   remove o container ao terminar.
  --rm

  # -it    terminal interativo.
  -it

  # --user 1000:1000   mesmo usuário do dia a dia (dev).
  --user 1000:1000

  # As três liberações necessárias ao bubblewrap dentro do Docker (detalhes em
  # 02-test-bwrap.sh): filtro de syscalls, AppArmor e máscaras do /proc.
  --security-opt seccomp=unconfined
  --security-opt apparmor=unconfined
  --security-opt systempaths=unconfined

  # -e AI_MEMORY_AUTH_TOKEN=valor-de-teste
  #        O dry-run só precisa que a variável EXISTA no ambiente do ai-jail
  #        para listar o --env pelo nome. O valor aqui é falso de propósito.
  -e AI_MEMORY_AUTH_TOKEN=valor-de-teste

  # -v claude-home:/home/dev
  #        Monta o HOME persistente para o dry-run enxergar o ~/.claude já
  #        logado (o ai-jail só monta caminhos que existem).
  -v claude-home:/home/dev

  # -v "$PWD":"$PWD"  e  -w "$PWD"
  #        O projeto atual no seu caminho real, como na função do passo 3.
  -v "$PWD":"$PWD"
  -w "$PWD"
)

# -----------------------------------------------------------------------------
# O comando:
#   docker run FLAGS claude-box ai-jail --dry-run --forward-port 49374 \
#       --env AI_MEMORY_AUTH_TOKEN --allow-host platform.claude.com \
#       ai-memory run --yolo claude
#
#   --dry-run          imprime o plano e termina; não executa nada e não grava o
#                      .ai-jail.
#   --forward-port 49374   expõe a porta do servidor de memória no loopback do jail.
#   --env AI_MEMORY_AUTH_TOKEN   repassa o token pelo nome.
#   --allow-host platform.claude.com   libera a renovação do login do Claude (igual ao 03).
#   ai-memory run --yolo claude  o comando que SERIA executado dentro do jail.
# -----------------------------------------------------------------------------
docker run "${flags[@]}" \
  claude-box ai-jail --dry-run --forward-port 49374 --env AI_MEMORY_AUTH_TOKEN --allow-host platform.claude.com ai-memory run --yolo claude
