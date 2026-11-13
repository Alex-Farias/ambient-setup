# =============================================================================
# 03-claude-box-function.sh  —  PASSO 3: a função "claude-box"  (v3)
# =============================================================================
#
# O QUE É
#   Funções de shell (bash). Este arquivo é carregado pelo ~/.bashrc com a
#   linha:   source ~/claude-box/03-claude-box-function.sh
#   Para atualizar, basta SUBSTITUIR o arquivo e rodar: source ~/.bashrc
#
#   Uso no dia a dia, em qualquer pasta de projeto:
#
#       cd ~/projects/meu-projeto
#       claude-box
#
#   → container → ai-jail (bubblewrap + Landlock + seccomp) → ai-memory run
#     → claude --yolo.  Memória e jail juntos, sempre.
#
# COMANDOS DE MANUTENÇÃO (novos na v3)
#
#   claude-box --config
#       REAJUSTAR as permissões do jail para o projeto atual. Apaga a aprovação
#       salva do ai-jail para esta pasta e inicia normalmente: o ai-jail mostra
#       de novo a tela "Configure claude for this project" para você escolher
#       o acesso. Use quando quiser mudar o preset, remover o GitHub, etc.
#       Qualquer argumento depois de --config segue para o Claude.
#         Exemplo:  claude-box --config --model opus
#
#   claude-box --show-config
#       Só MOSTRA a aprovação salva do projeto atual (arquivo .toml). Não
#       inicia nada.
#
#   claude-box --mcp-setup
#       Registra o servidor MCP do ai-memory no Claude, FORA do jail. É
#       necessário porque, dentro do jail, o ~/.claude.json é um arquivo
#       montado e o ai-memory não consegue trocá-lo (erro "Device or resource
#       busy" do seu último log). Rode uma vez; vale para todos os projetos.
#
#   claude-box --login
#       Faz LOGIN / RENOVA o login do Claude FORA do jail. Use quando aparecer
#       "Please run /login" ou "OAuth access token has expired". Abre o Claude
#       num container descartável SEM seu projeto montado e roda
#       "claude auth login": copie o link, abra no navegador do Windows e cole
#       o código no terminal. O login fica no volume claude-home e vale para
#       todos os projetos.
#
#   claude-box --status
#       Mostra se o Claude está logado (claude auth status), sem abrir o jail.
#
#   CLAUDE_BOX_JAIL_FLAGS="..." claude-box
#       Acrescenta flags do ai-jail só nesta execução, sem editar o arquivo.
#         Exemplo:  CLAUDE_BOX_JAIL_FLAGS="--allow-host exemplo.com" claude-box
#       Flags novas podem gerar uma nova pergunta de aprovação no ai-jail.
#
# PROJETOS SIMULTÂNEOS (comando para guardar)
#   Uso previsto hoje: um projeto por vez. Se precisar de dois, em dois
#   terminais, reduzindo o teto de cada container (o servidor é um só):
#
#       cd ~/projects/projeto-A && CLAUDE_BOX_MEM=1500m CLAUDE_BOX_CPUS=3 claude-box
#       cd ~/projects/projeto-B && CLAUDE_BOX_MEM=1500m CLAUDE_BOX_CPUS=3 claude-box
#
#   Conta de RAM (8 GB no PC; WSL limitado a 5 GB): servidor 1 GB + 2 x 1,5 GB
#   = 4 GB. Com o padrão de 3g cada, dois projetos estouram o limite do WSL.
#
# MEMÓRIA ISOLADA POR PROJETO (.ai-memory.toml)
#   cd ~/projects/websocketTest && claude-box-init      (função no fim do arquivo)
#   Usa a hierarquia de pastas: workspace = pasta-mãe, project = pasta do projeto.
#   Para outro workspace: claude-box-init cliente-a
#
# PRÉ-REQUISITOS
#   Imagem "claude-box" (passo 1, com a correção dos hooks), teste do bwrap OK
#   (passo 2) e login do Claude feito uma vez (volume claude-home).
#
# SOBRE A FORMA DESTE ARQUIVO
#   Em shell, comentário NÃO pode ficar entre linhas terminadas em "\". Por isso
#   as flags ficam em LISTAS (arrays) com um comentário em cada flag. O efeito
#   é idêntico a escrever o comando numa linha só.
#
# =============================================================================


# -----------------------------------------------------------------------------
# _claude_box_token  —  devolve o token do servidor de memória (cria se faltar)
# -----------------------------------------------------------------------------
#   [ -f ARQUIVO ] || openssl rand -hex 24 > ARQUIVO
#     [ -f ... ]  testa "o arquivo existe?".   ||  executa o lado direito só
#     se o esquerdo for falso. openssl rand -hex 24 → 48 caracteres hex
#     aleatórios (ex.: 9f2c41b07a...).  Resultado: o token nasce na primeira
#     execução e é reaproveitado depois.
#   cat ARQUIVO  imprime o token (quem chama captura com $(...)).
#   TROCAR O TOKEN: apagar só o arquivo NÃO basta, o servidor já nasceu com o
#   antigo. Faça: docker rm -f ai-memory-server && rm ~/.claude-box-token
#   (os dados ficam no volume ai-memory-data, nada se perde).
_claude_box_token() {
  [ -f ~/.claude-box-token ] || openssl rand -hex 24 > ~/.claude-box-token
  cat ~/.claude-box-token
}


# -----------------------------------------------------------------------------
# _claude_box_server_up  —  garante o container do servidor criado e ligado
# -----------------------------------------------------------------------------
_claude_box_server_up() {
  local TOKEN; TOKEN=$(_claude_box_token)

  local -a server_flags=(
    # -d  roda em segundo plano e devolve o terminal.
    -d

    # --name ai-memory-server
    #     Nome fixo: é por ele que os containers de projeto entram na rede do
    #     servidor e que você o controla (docker stop/start/logs).
    --name ai-memory-server

    # --restart unless-stopped
    #     Religa sozinho quando o Docker Desktop abre, a menos que você o tenha
    #     parado de propósito.
    --restart unless-stopped

    # --memory 1g   teto de 1 GB de RAM (protege seus 8 GB).
    --memory 1g

    # -p 127.0.0.1:49374:49374
    #     Publica a porta SÓ no loopback do seu PC (IP:PORTA_HOST:PORTA_CONTAINER).
    #     Serve para abrir http://127.0.0.1:49374/web no navegador. Os containers
    #     de projeto NÃO dependem desta publicação.
    -p 127.0.0.1:49374:49374

    # -v ai-memory-data:/data
    #     Volume nomeado com banco, wiki e modelos. Sobrevive a recriar o container.
    -v ai-memory-data:/data

    # -e AI_MEMORY_AUTH_TOKEN="$TOKEN"
    #     Token exigido pelo servidor (no Docker ele escuta em 0.0.0.0 e, fora do
    #     loopback, se recusa a subir sem token; o log mostrou "auth=true").
    -e AI_MEMORY_AUTH_TOKEN="$TOKEN"
  )

  # docker inspect NOME >/dev/null 2>&1 || docker run ...
  #   inspect sai com sucesso se o container existe; >/dev/null 2>&1 esconde a
  #   saída; || cria o servidor SÓ se ele não existir.
  docker inspect ai-memory-server >/dev/null 2>&1 || docker run "${server_flags[@]}" akitaonrails/ai-memory:latest

  # docker start: garante o servidor ligado; repetir é seguro.
  docker start ai-memory-server >/dev/null
}


# -----------------------------------------------------------------------------
# _claude_box_policy_reset  —  apaga a aprovação salva do ai-jail desta pasta
# -----------------------------------------------------------------------------
#   Onde fica a aprovação: no volume claude-home, em
#     /home/dev/.config/ai-jail/projects/<nome-da-pasta>-<hash>.toml
#   (o seu log mostrou, por exemplo, websocketTest-43a36e7a792fe8522246.toml).
#   Sem esse arquivo o ai-jail considera o projeto novo e refaz a tela de
#   configuração (você já viu isso funcionar quando apagou o workspace-*.toml).
#
#   docker run --rm --user 1000:1000 -v claude-home:/home/dev claude-box sh -c '...' _ "$name"
#     Container descartável que só monta o volume do HOME e roda um pequeno
#     script. O "_" é o $0 do script; "$name" vira o $1 dentro dele.
#   "$1"-*.toml
#     Aspas protegem o nome da pasta; o "-*.toml" é expandido pelo shell.
#     Se existirem duas pastas com o MESMO nome em caminhos diferentes, as duas
#     aprovações são apagadas (elas só serão perguntadas de novo; nada se perde).
_claude_box_policy_reset() {
  local name; name=$(basename "$PWD")
  echo "claude-box: resetando as permissões do ai-jail para '$name' (a tela de configuração vai aparecer de novo)."
  docker run --rm --user 1000:1000 -v claude-home:/home/dev claude-box sh -c '
    found=0
    for f in /home/dev/.config/ai-jail/projects/"$1"-*.toml; do
      if [ -e "$f" ]; then rm -f "$f"; echo "removido: $f"; found=1; fi
    done
    [ "$found" = 1 ] || echo "(nenhuma aprovação salva para este projeto; a configuração será pedida de qualquer forma)"
  ' _ "$name"
}


# -----------------------------------------------------------------------------
# _claude_box_policy_show  —  mostra a aprovação salva do projeto atual
# -----------------------------------------------------------------------------
_claude_box_policy_show() {
  docker run --rm --user 1000:1000 -v claude-home:/home/dev claude-box sh -c '
    found=0
    for f in /home/dev/.config/ai-jail/projects/"$1"-*.toml; do
      if [ -e "$f" ]; then echo "# $f"; cat "$f"; echo; found=1; fi
    done
    [ "$found" = 1 ] || echo "(nenhuma aprovação salva para este projeto)"
  ' _ "$(basename "$PWD")"
}


# -----------------------------------------------------------------------------
# _claude_box_mcp_setup  —  registra o MCP do ai-memory no Claude, FORA do jail
# -----------------------------------------------------------------------------
#   Por que fora do jail: dentro dele o ~/.claude.json é montado como arquivo
#   (agent-state) e o ai-memory o atualiza criando um arquivo temporário e
#   renomeando; renomear sobre um arquivo montado dá "Device or resource busy".
#   Aqui o HOME é o volume normal, sem montagem de arquivo, e a escrita funciona.
#
#   --network container:ai-memory-server   mesma rede do servidor (127.0.0.1:49374).
#   -e AI_MEMORY_AUTH_TOKEN                token do servidor para o install-mcp.
#   -v claude-home:/home/dev               o MESMO HOME usado nas sessões.
#   ai-memory install-mcp --client claude-code --apply
#                                          comando indicado pelo próprio ai-memory
#                                          no seu log ("Wire it manually with ...").
_claude_box_mcp_setup() {
  local TOKEN; TOKEN=$(_claude_box_token)
  _claude_box_server_up
  docker run --rm --user 1000:1000 \
    --network container:ai-memory-server \
    -e AI_MEMORY_AUTH_TOKEN="$TOKEN" \
    -v claude-home:/home/dev \
    claude-box ai-memory install-mcp --client claude-code --apply
}


# -----------------------------------------------------------------------------
# _claude_box_login  —  login do Claude FORA do jail
# -----------------------------------------------------------------------------
#   Por que fora do jail: o jail só deixa o tráfego passar para uma lista de
#   hosts, e a tela de login precisa falar com o serviço de autenticação.
#   Aqui o container tem rede normal, mas NÃO monta o seu projeto e não usa
#   --yolo: só serve para autenticar.
#
#   -v claude-home:/home/dev   o MESMO HOME das sessões: o login gravado aqui
#                              (~/.claude e ~/.claude.json) é o que o jail usa.
#   -w /home/dev               pasta de trabalho neutra (não usa /workspace).
#   claude auth login          fluxo de login por linha de comando: imprime o
#                              link e espera o código colado no terminal.
_claude_box_login() {
  echo "claude-box: login do Claude fora do jail (claude auth login)."
  echo "  1) copie o link e abra no navegador do Windows   2) cole o código aqui quando pedir"
  docker run --rm -it --user 1000:1000 -w /home/dev -v claude-home:/home/dev claude-box claude auth login
}

# _claude_box_status  —  mostra o estado do login (saída 0 = logado, 1 = não)
_claude_box_status() {
  docker run --rm --user 1000:1000 -w /home/dev -v claude-home:/home/dev claude-box claude auth status --text
}


# -----------------------------------------------------------------------------
# claude-box  —  a função principal
# -----------------------------------------------------------------------------
claude-box() {

  # ---------------------------------------------------------------------------
  # Comandos de manutenção: olham só o PRIMEIRO argumento.
  #   case "${1:-}" in ... esac   compara o primeiro argumento (vazio se não houver).
  #   --config      shift remove "--config" da lista de argumentos; depois do reset
  #                 a função CONTINUA e inicia o Claude (o ai-jail pergunta o acesso).
  #                 "|| return $?" aborta se o reset falhar.
  #   --show-config e --mcp-setup terminam sem iniciar o Claude (return).
  # ---------------------------------------------------------------------------
  case "${1:-}" in
    --config)      shift; _claude_box_policy_reset || return $? ;;
    --show-config) _claude_box_policy_show; return $? ;;
    --mcp-setup)   _claude_box_mcp_setup;   return $? ;;
    --login)       _claude_box_login;       return $? ;;
    --status)      _claude_box_status;      return $? ;;
  esac

  local TOKEN; TOKEN=$(_claude_box_token)
  _claude_box_server_up

  # ---------------------------------------------------------------------------
  # LISTA run_flags: flags do container do PROJETO (descartável).
  # ---------------------------------------------------------------------------
  local -a run_flags=(
    # --rm  remove o container ao sair. Persistem os volumes e a sua pasta.
    --rm

    # -it   terminal interativo (stdin + TTY) para conversar com o Claude.
    -it

    # --user 1000:1000
    #       Usuário "dev" (uid 1000), não root: obrigatório para o --yolo do
    #       Claude Code e mantém o dono certo dos arquivos do projeto.
    --user 1000:1000

    # --network container:ai-memory-server
    #       Entra na rede do servidor: o "127.0.0.1:49374" do container chega no
    #       servidor. Dentro do jail o loopback é outro; quem resolve é o
    #       --forward-port mais abaixo.
    --network container:ai-memory-server

    # --memory "${CLAUDE_BOX_MEM:-3g}"
    #       Teto de RAM. "${VAR:-3g}" usa CLAUDE_BOX_MEM se existir, senão 3g.
    #       Exemplo: CLAUDE_BOX_MEM=1500m claude-box.  Com 16 GB de RAM: 6g.
    --memory "${CLAUDE_BOX_MEM:-3g}"

    # --cpus "${CLAUDE_BOX_CPUS:-4}"
    #       Teto de núcleos (de 6 no i5-9400F). Padrão 4; use 3 para dois projetos.
    --cpus "${CLAUDE_BOX_CPUS:-4}"

    # --cap-drop ALL
    #       Remove todos os poderes especiais de root do container.
    --cap-drop ALL

    # --security-opt no-new-privileges
    #       Impede ganhar mais privilégios (ex.: via setuid).
    --security-opt no-new-privileges

    # --security-opt seccomp=unconfined
    #       Remove o filtro de chamadas de sistema do Docker. NECESSÁRIO para o
    #       bubblewrap criar namespaces dentro do container (seu teste BWRAP_OK).
    --security-opt seccomp=unconfined

    # --security-opt apparmor=unconfined
    #       Desliga o perfil AppArmor padrão (pode nem existir no Docker Desktop).
    --security-opt apparmor=unconfined

    # --security-opt systempaths=unconfined
    #       Tira as máscaras do /proc e /sys para o bwrap montar um /proc próprio.
    --security-opt systempaths=unconfined

    # -e AI_MEMORY_AUTH_TOKEN="$TOKEN"
    #       Entrega o token ao processo ai-jail (que o repassa ao jail pelo --env
    #       abaixo). Sem esta linha o --env não teria o que copiar.
    -e AI_MEMORY_AUTH_TOKEN="$TOKEN"

    # -v "$PWD":"$PWD"
    #       Monta a pasta atual NO MESMO CAMINHO dentro do container (ex.:
    #       /home/alex-nabo/projects/loja). Cada projeto tem caminho único:
    #       aprovações do ai-jail, histórico do Claude e escopo do ai-memory não
    #       se misturam. As aspas protegem espaços. É a ÚNICA parte do seu disco
    #       visível ao agente.
    -v "$PWD":"$PWD"

    # -w "$PWD"   começa dentro do projeto.
    -w "$PWD"

    # -v claude-home:/home/dev
    #       Volume do HOME do dev: login do Claude, aprovações do ai-jail
    #       (/home/dev/.config/ai-jail) e estado do ai-memory persistem entre
    #       execuções e projetos. Zerar tudo: docker volume rm claude-home.
    -v claude-home:/home/dev
  )

  # ---------------------------------------------------------------------------
  # LISTA jail_flags: opções do PRÓPRIO ai-jail (vêm antes de "ai-memory run").
  # ---------------------------------------------------------------------------
  local -a jail_flags=(
    # --forward-port 49374
    #       Expõe a porta do servidor de memória no loopback isolado do jail
    #       (efeito confirmado no seu log: forward_ports = [49374] e eventos
    #       salvos no servidor). O "host" aqui é o container, que compartilha a
    #       rede do servidor. Sem rede aberta.
    --forward-port 49374

    # --env AI_MEMORY_AUTH_TOKEN
    #       Repassa ao jail o token PELO NOME (o --help recomenda esta forma:
    #       "--env NOME=VALOR" deixaria o segredo visível na linha de comando).
    #       O agente dentro do jail passa a ter o token do servidor de memória.
    --env AI_MEMORY_AUTH_TOKEN

    # --allow-host platform.claude.com
    #       O Claude renova sozinho o token de login (ele vence depois de
    #       algumas horas) falando com este host. Sem liberá-lo, o proxy do jail
    #       bloqueia (erro ERR_PROXY_TUNNEL do seu log) e o login "expira" de
    #       tempos em tempos. Só este host é acrescentado à lista padrão do
    #       ai-jail (api.anthropic.com, registries, github...). O ai-jail pode
    #       pedir uma nova aprovação na primeira vez que ver esta flag.
    --allow-host platform.claude.com
  )

  # ---------------------------------------------------------------------------
  # LISTA extra_jail: flags opcionais do ai-jail vindas da variável
  #   CLAUDE_BOX_JAIL_FLAGS. Sem aspas de propósito em ${...}: o shell separa
  #   a variável em palavras (cada flag vira um argumento).
  #   Exemplo: CLAUDE_BOX_JAIL_FLAGS="--allow-host exemplo.com --allow-host b.com"
  # ---------------------------------------------------------------------------
  local -a extra_jail=( ${CLAUDE_BOX_JAIL_FLAGS:-} )

  # ---------------------------------------------------------------------------
  # LINHA FINAL:
  #   docker run RUN_FLAGS claude-box ai-jail JAIL_FLAGS EXTRA ai-memory run --yolo claude "$@"
  #
  #   ai-jail ... ai-memory run --yolo claude
  #       De fora para dentro: o ai-jail abre o sandbox e roda dentro dele o
  #       "ai-memory run" (workstream, hooks, memória), que inicia o "claude" em
  #       modo --yolo (sem pedir confirmação).
  #   "$@"
  #       Argumentos extras depois de claude-box vão para o fim.
  #       Exemplo: claude-box --model opus.
  #
  #   Ao sair do Claude, o ai-memory mostra "r) run claude again / q) quit
  #   (default)": Enter ou q encerra; r reinicia o Claude no mesmo jail.
  # ---------------------------------------------------------------------------
  docker run "${run_flags[@]}" claude-box ai-jail "${jail_flags[@]}" "${extra_jail[@]}" ai-memory run --yolo claude "$@"
}


# =============================================================================
# claude-box-init  —  cria o marcador .ai-memory.toml do projeto atual
# =============================================================================
#   Uso:
#       cd ~/projects/websocketTest
#       claude-box-init              # workspace = "projects", project = "websocketTest"
#       claude-box-init cliente-a    # workspace = "cliente-a", project = "websocketTest"
#
#   Roda no WSL (fora do container); só escreve um arquivo de texto na pasta
#   atual. Não sobrescreve um marcador que já exista. Evite aspas dentro de
#   nomes de pasta (o nome vai literalmente para dentro do arquivo TOML).
claude-box-init() {
  # ${1:-...}: se você passou um argumento, ele é o workspace; senão usa o nome
  # da pasta-mãe. dirname "$PWD" = pasta-mãe; basename = só o último nome.
  local ws="${1:-$(basename "$(dirname "$PWD")")}"
  local proj; proj=$(basename "$PWD")

  # Se já existe, não mexe: mostra o conteúdo atual e sai (return 0 = sem erro).
  if [ -e .ai-memory.toml ]; then
    echo ".ai-memory.toml já existe; nada foi alterado:"
    cat .ai-memory.toml
    return 0
  fi

  # printf escreve as duas linhas do TOML; o \n separa as linhas.
  printf 'workspace = "%s"\nproject = "%s"\n' "$ws" "$proj" > .ai-memory.toml
  echo "criado .ai-memory.toml  (workspace=$ws, project=$proj)"
}
