#!/usr/bin/env bash
# =============================================================================
# 02-test-bwrap.sh  —  PASSO 2: o bubblewrap funciona DENTRO do container?
# =============================================================================
#
# POR QUE ESTE TESTE EXISTE
#   Sua exigência: rodar o ai-jail mesmo dentro do container. O ai-jail usa o
#   bubblewrap (bwrap) para criar um sandbox. Mas um container Docker comum
#   BLOQUEIA o que o bwrap precisa (criar namespaces e montar um /proc novo).
#   Este teste descobre, em 2 segundos e sem risco, se as liberações abaixo
#   são suficientes na SUA máquina. Rode ANTES de qualquer outra coisa.
#   (Eu não testei esta combinação no seu PC: é exatamente para isso que ele serve.)
#
# COMO RODAR
#   bash 02-test-bwrap.sh
#
# COMO LER O RESULTADO
#   BWRAP_OK ....................... funciona → siga para o passo 3.
#   "No permissions to create new namespace"
#                                     o kernel/seccomp barrou namespaces.
#                                     Mande o erro completo.
#   "Can't mount proc ... Operation not permitted"
#                                     o /proc do container segue mascarado.
#                                     Confira se systempaths=unconfined está
#                                     presente (está, na lista abaixo).
#   "loopback: Failed RTM_NEWADDR"    falta capacidade de rede. Tente acrescentar
#                                     "--cap-add NET_ADMIN" à lista; se não
#                                     resolver, "--cap-add SYS_ADMIN"
#                                     (SYS_ADMIN é bem mais permissivo; use só
#                                     se necessário).
#
# SOBRE A FORMA DESTE ARQUIVO
#   Em shell, um comentário NÃO pode ficar entre linhas terminadas em "\" (isso
#   quebra o comando). Por isso as flags estão numa LISTA (array) com um
#   comentário em cada linha, e o comando é "docker run "${flags[@]}" ...".
#   O resultado é IDÊNTICO ao comando original de uma linha só.
#
# =============================================================================

flags=(
  # --rm
  #   Remove o container assim que o comando termina. Sem isso, cada teste
  #   deixaria um container parado ocupando espaço (veja com: docker ps -a).
  --rm

  # -it  (= -i + -t)
  #   -i mantém a entrada (stdin) aberta; -t aloca um terminal (TTY). Juntos
  #   deixam a saída e eventuais prompts aparecerem normalmente no seu terminal.
  -it

  # --user 1000:1000
  #   Roda como uid 1000 / gid 1000 (o usuário "dev" da imagem), NÃO como root.
  #   O teste precisa ser feito como não-root, porque é assim que o dia a dia
  #   vai rodar (o Claude --yolo recusa root). Exemplo: dentro do container,
  #   "id" mostraria uid=1000(dev).
  --user 1000:1000

  # --security-opt seccomp=unconfined
  #   O Docker aplica por padrão um filtro de chamadas de sistema (seccomp) que
  #   bloqueia, entre outras, a criação de namespaces de usuário sem privilégio
  #   — exatamente o que o bwrap faz. "unconfined" remove esse filtro.
  #   Custo: o container fica menos blindado contra chamadas perigosas.
  --security-opt seccomp=unconfined

  # --security-opt apparmor=unconfined
  #   Desliga o perfil AppArmor padrão do Docker. Em alguns hosts o AppArmor
  #   também impede criar namespaces. No Docker Desktop (VM do WSL2) o AppArmor
  #   pode nem estar ativo; nesse caso a flag é inofensiva.
  --security-opt apparmor=unconfined

  # --security-opt systempaths=unconfined
  #   Por padrão o Docker "mascara" partes do /proc e do /sys (esconde ou deixa
  #   somente leitura). O bwrap monta um /proc NOVO e o kernel recusa isso se
  #   o /proc de origem estiver mascarado ("Can't mount proc"). Esta opção
  #   remove as máscaras. É a flag que mais costuma faltar quando se tenta
  #   rodar bwrap/podman dentro de Docker.
  --security-opt systempaths=unconfined
)

# -----------------------------------------------------------------------------
# O comando em si:
#
#   docker run "${flags[@]}" claude-box bwrap ... true && echo BWRAP_OK
#
#   claude-box
#       Nome da imagem criada no passo 1. O que vem DEPOIS do nome da imagem é
#       o comando a executar dentro do container.
#
#   bwrap --unshare-all --ro-bind / / --proc /proc --dev /dev true
#       Roda o bubblewrap com:
#         --unshare-all     cria TODOS os namespaces novos possíveis (usuário,
#                           processos, rede, IPC, hostname...). É o isolamento
#                           máximo; se funciona, o ai-jail também consegue.
#         --ro-bind / /     monta a raiz "/" do container dentro do sandbox em
#                           SOMENTE LEITURA ("ro" = read-only). Formato:
#                           --ro-bind ORIGEM DESTINO.
#         --proc /proc      monta um /proc novo, próprio do sandbox (a parte que
#                           falha sem systempaths=unconfined).
#         --dev /dev        monta um /dev mínimo e novo (null, zero, tty...).
#         true              o programa a rodar dentro do sandbox: "true" não faz
#                           nada e termina com sucesso (código 0). Serve só
#                           para provar que o sandbox ABRIU e FECHOU sem erro.
#
#   && echo BWRAP_OK
#       "&&" só executa o que vem depois SE o comando anterior terminou com
#       sucesso. Portanto BWRAP_OK só aparece se o bwrap funcionou. Se o bwrap
#       falhar, você vê a mensagem de erro dele e NÃO vê BWRAP_OK.
# -----------------------------------------------------------------------------
docker run "${flags[@]}" \
  claude-box bwrap --unshare-all --ro-bind / / --proc /proc --dev /dev true && echo BWRAP_OK
