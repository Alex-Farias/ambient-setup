#!/usr/bin/env bash
# =============================================================================
# 01-build-image.sh  —  PASSO 1: construir a imagem Docker "claude-box"
# =============================================================================
#
# O QUE ISTO FAZ
#   Cria (uma vez) uma imagem Docker chamada "claude-box" com tudo instalado:
#   ai-jail + ai-memory + Claude Code + bubblewrap + ferramentas básicas.
#   Essa imagem é o "ambiente padrão" reaproveitado por QUALQUER projeto: o
#   código do projeto NÃO entra na imagem, ele é montado na hora de rodar
#   (ver 03-claude-box-function.sh).
#
# ONDE RODAR
#   No terminal do Ubuntu (WSL2), com o Docker Desktop aberto.
#   Exemplo:   bash 01-build-image.sh
#
# QUANTO DEMORA (i5-9400F, 8 GB, conexão comum)
#   Primeira vez: poucos minutos (a maior parte é baixar a base do Ubuntu e
#   rodar os instaladores). Próximas vezes: segundos, por causa do cache.
#
# COMO CONFERIR QUE DEU CERTO
#   docker run --rm claude-box sh -c 'ai-jail --version; ai-memory --version; claude --version'
#   (cada ferramenta deve imprimir uma versão; se alguma disser "not found",
#    o passo correspondente do Dockerfile abaixo falhou ou copiou o binário
#    para o lugar errado)
#
# COMO ATUALIZAR AS FERRAMENTAS DEPOIS
#   Rode o mesmo comando com --no-cache para forçar baixar tudo de novo:
#     docker build --no-cache -t claude-box - <<'EOF' ...
#   Sem --no-cache, o Docker reaproveita as camadas antigas e NÃO pega versões
#   novas (as URLs "latest" só são consultadas quando a camada é refeita).
#
# =============================================================================
# O COMANDO, PEÇA POR PEÇA
# =============================================================================
#
#   docker build -t claude-box - <<'EOF'
#   │      │      │  │         │ │
#   │      │      │  │         │ └─ <<'EOF'  → "here-document": tudo entre esta
#   │      │      │  │         │      linha e a linha "EOF" vira a ENTRADA do
#   │      │      │  │         │      comando. As aspas simples em 'EOF' impedem
#   │      │      │  │         │      o shell de expandir $variáveis e $(...)
#   │      │      │  │         │      dentro do texto; o Dockerfile chega
#   │      │      │  │         │      literalmente como está escrito.
#   │      │      │  │         └─ "-"       → diz ao docker: "o Dockerfile vem da
#   │      │      │  │                         entrada padrão (stdin), não de um
#   │      │      │  │                         arquivo". Consequência: NÃO existe
#   │      │      │  │                         pasta de contexto, então comandos
#   │      │      │  │                         COPY/ADD de arquivos locais não
#   │      │      │  │                         funcionam (aqui não precisamos).
#   │      │      │  └─ claude-box → o nome da imagem.
#   │      │      └─ -t           → "tag": dá nome à imagem. Sem isso ela fica
#   │      │                         só com um ID hexadecimal difícil de usar.
#   │      │                         Exemplo de uso depois: docker run claude-box
#   │      └─ build               → subcomando que constrói imagem.
#   └─ docker                     → o cliente do Docker (Docker Desktop).
#
# =============================================================================

docker build --build-arg INSTALL_OLLAMA="${CLAUDE_BOX_INSTALL_OLLAMA:-0}" -t claude-box - <<'EOF'
# -----------------------------------------------------------------------------
# FROM: a imagem-base. Tudo abaixo é construído em cima dela.
#   ubuntu:26.04 é a imagem OFICIAL do Ubuntu 26.04 LTS ("resolute").
#   Por que esta e não debian/alpine? É a mesma distribuição (e mesma glibc) do
#   seu WSL, então não há surpresas de compatibilidade com os binários.
#   Exemplo de alternativa (não recomendada aqui): FROM debian:stable-slim
# -----------------------------------------------------------------------------
FROM ubuntu:26.04

# -----------------------------------------------------------------------------
# RUN #1: instalar pacotes do sistema com apt.
#   apt-get update ................ baixa a lista atual de pacotes (a imagem-base
#                                   vem sem lista, então sem isto o install falha).
#   apt-get install -y ............ instala; "-y" responde "sim" sozinho, pois
#                                   o build não tem teclado para confirmar.
#   --no-install-recommends ....... NÃO instala pacotes "recomendados" (extras
#                                   opcionais). Deixa a imagem bem menor.
#   Pacotes e para que servem:
#     bubblewrap .......... o "bwrap": sandbox de namespaces que o ai-jail usa.
#                           Sem ele o ai-jail não consegue isolar nada.
#     ca-certificates ..... certificados raiz; sem eles o curl/git não validam
#                           HTTPS (erro típico: "SSL certificate problem").
#     curl ................ baixa arquivos/instaladores (usado nos RUN seguintes).
#     git ................. o Claude e você usam para versionar o projeto.
#     ripgrep (rg) ........ busca de texto muito rápida; o Claude Code usa.
#     jq .................. lê/edita JSON no terminal (útil p/ configs e hooks).
#     less ................ paginador (ex.: "git log" usa).
#     procps .............. traz "ps", "top", "free" para inspecionar processos.
#     openssl ............. gerar segredos (ex.: openssl rand -hex 24).
#   rm -rf /var/lib/apt/lists/* ... apaga a lista de pacotes baixada, que só
#                                   serve durante o install. Reduz o tamanho
#                                   da imagem (tudo na MESMA linha RUN, senão
#                                   a lista continuaria numa camada anterior).
#   O "\" no fim da linha apenas continua o comando na linha seguinte.
#   Exemplo de erro se faltar "update": "E: Unable to locate package ripgrep".
# -----------------------------------------------------------------------------
RUN apt-get update && apt-get install -y --no-install-recommends \
    bubblewrap ca-certificates curl git ripgrep jq less procps openssl \
    make postgresql python3 zstd \
    && rm -rf /var/lib/apt/lists/* \
    && for b in initdb pg_ctl postgres psql pg_isready createdb; do \
         ln -sf /usr/lib/postgresql/*/bin/$b /usr/local/bin/$b; done

# -----------------------------------------------------------------------------
# Ferramentas de dev para os projetos (a imagem é o "host" do jail: o que não
# estiver aqui não existe lá dentro).
#   make .......... roda o Makefile do projeto (make test, make db-up...).
#   postgresql .... servidor + cliente PostgreSQL (versão do Ubuntu da imagem).
#                   Ninguém sobe banco aqui: o PROJETO decide (ex.: make db-up
#                   inicia o servidor em 127.0.0.1 DENTRO do jail).
#   ln -sf ... .... os binários do servidor ficam em /usr/lib/postgresql/<versão>/bin,
#                   fora do PATH fixo do jail; os atalhos em /usr/local/bin
#                   resolvem isso. O "*" acha a versão instalada.
#   Go ............ versão estável mais recente como base. A versão de cada
#                   projeto vem do go.mod (toolchain); com GOTOOLCHAIN=auto o Go
#                   baixa a versão pedida pelo proxy.golang.org (liberado no jail).
#                   Para fixar a base: troque a linha do GOV por  GOV=go1.25.4
#   cgo / go test -race: acrescente "gcc libc6-dev" ao apt-get acima.
# -----------------------------------------------------------------------------
RUN GOV=$(curl -fsSL 'https://go.dev/VERSION?m=text' | head -1) \
    && curl -fsSL "https://go.dev/dl/${GOV}.linux-amd64.tar.gz" | tar xz -C /usr/local \
    && ln -s /usr/local/go/bin/go /usr/local/bin/go \
    && ln -s /usr/local/go/bin/gofmt /usr/local/bin/gofmt \
    && go version

# Python: python3 (apt) é a base; o uv cria o .venv de cada projeto e instala os
# pacotes travados no uv.lock pelo PyPI (liberado no jail).
#   UV_INSTALL_DIR=/usr/local/bin ... binário no PATH fixo do jail
#   UV_NO_MODIFY_PATH=1 ............. não mexe no .bashrc do root
#   /etc/uv/uv.toml ................. config em arquivo (o jail limpa o env);
#                                     link-mode=copy evita aviso de hardlink
RUN curl -LsSf https://astral.sh/uv/install.sh | env UV_INSTALL_DIR=/usr/local/bin UV_NO_MODIFY_PATH=1 sh \
    && mkdir -p /etc/uv && printf 'link-mode = "copy"\n' > /etc/uv/uv.toml \
    && uv --version && python3 --version

# -----------------------------------------------------------------------------
# RUN #2: instalar o ai-jail pelo método oficial "binário das GitHub Releases".
#   curl -fsSL URL ...... baixa o arquivo. Flags:
#        -f  falha (código de erro) se o servidor responder 404/500, em vez de
#            salvar a página de erro como se fosse o arquivo;
#        -s  silencioso (sem barra de progresso nos logs do build);
#        -S  mesmo silencioso, MOSTRA mensagens de erro;
#        -L  segue redirecionamentos (o GitHub redireciona "latest/download").
#   .../releases/latest/download/ai-jail-linux-x86_64.tar.gz
#        → sempre o release mais recente para Linux x86_64. Para fixar uma
#          versão específica, troque "latest/download" por "download/vX.Y.Z"
#          (ex.: .../releases/download/v2.6.2/ai-jail-linux-x86_64.tar.gz).
#   | (pipe) ........... entrega o arquivo baixado direto ao próximo comando,
#                         sem gravar em disco.
#   tar xz -C /usr/local/bin
#        x  extrair; z  descomprimir gzip; (sem -f, o tar lê da entrada padrão,
#        isto é, do pipe); -C troca para a pasta destino antes de extrair.
#        /usr/local/bin é uma pasta que já está no PATH de todo usuário.
#   && chmod 755 ....... garante permissão de execução para todos (rwxr-xr-x),
#                        para o usuário "dev" (criado mais abaixo) conseguir
#                        rodar o binário.
#   Alternativas oficiais (não usadas aqui): "cargo install --locked ai-jail"
#   (compila do código-fonte; lento e pesado em 8 GB), Homebrew, mise.
# -----------------------------------------------------------------------------
RUN curl -fsSL https://github.com/akitaonrails/ai-jail/releases/latest/download/ai-jail-linux-x86_64.tar.gz | tar xz -C /usr/local/bin \
    && chmod 755 /usr/local/bin/ai-jail

# -----------------------------------------------------------------------------
# RUN #3: instalar o ai-memory pelo instalador oficial e COPIAR o binário.
#   curl ... install.sh | sh
#        Baixa o script instalador oficial e o executa. Segundo a documentação
#        do ai-memory, ele baixa o release certo para o seu SO/CPU, confere o
#        SHA-256 e cria um link em ~/.local/bin/ai-memory. Como o build roda
#        como root, o HOME é /root, então o link vai para
#        /root/.local/bin/ai-memory.
#   readlink -f /root/.local/bin/ai-memory
#        Resolve o link até o arquivo REAL (ex.: um caminho dentro de
#        /root/.local/share/...). "install" não deve copiar o link, e sim o
#        binário de verdade.
#   install -m755 -D ORIGEM DESTINO
#        Copia ORIGEM para DESTINO já com permissão 755 (-m755) e cria as
#        pastas que faltarem (-D). Resultado: /usr/local/bin/ai-memory.
#   POR QUE COPIAR PARA /usr/local/bin?
#        Na hora de rodar, montamos um volume (claude-home) em /home/dev. Um
#        volume montado ESCONDE o que a imagem tinha naquela pasta. Binário
#        em ~/.local/bin sumiria; em /usr/local/bin fica seguro.
#   SE FALHAR: o erro mais provável é o instalador ter colocado o binário em
#        outro caminho que não /root/.local/bin/ai-memory. O build para aqui
#        com uma mensagem tipo "readlink: ... No such file". Mande a mensagem.
# -----------------------------------------------------------------------------
RUN curl -fsSL https://github.com/akitaonrails/ai-memory/releases/latest/download/install.sh | sh \
    && install -m755 -D "$(readlink -f /root/.local/bin/ai-memory)" /usr/local/bin/ai-memory

# -----------------------------------------------------------------------------
# RUN #3b: copiar o PACOTE DE HOOKS do ai-memory (correção do seu teste).
#   O QUE ACONTECEU: no primeiro claude-box o ai-memory avisou "could not locate
#   hooks directory" e listou onde procurou (/usr/local/share/ai-memory/hooks/
#   claude-code, /usr/share/ai-memory/hooks/claude-code, ...). O instalador tinha
#   posto os hooks em /root/.local/lib/ai-memory/hooks/claude-code (confirmado
#   pelo seu comando find), um lugar que o usuário "dev" não enxerga e que não
#   está na lista de busca. Sem hooks, nada do que acontece na sessão é capturado.
#   O QUE FAZ:
#     mkdir -p /usr/local/share/ai-memory
#         cria a pasta, que É um dos caminhos pesquisados pelo ai-memory.
#     cp -a /root/.local/lib/ai-memory/. /usr/local/share/ai-memory/
#         copia TODO o conteúdo de lib/ai-memory (o "/." no fim copia o conteúdo,
#         não a pasta). -a preserva permissões (os scripts de hook precisam
#         continuar executáveis) e a estrutura de subpastas. Resultado:
#         /usr/local/share/ai-memory/hooks/claude-code
#     Copiamos a pasta inteira, e não só "claude-code", porque os hooks podem
#     usar arquivos auxiliares ao lado.
#   COMO CONFERIR depois do build:
#     docker run --rm claude-box ls /usr/local/share/ai-memory/hooks/claude-code
# -----------------------------------------------------------------------------
RUN mkdir -p /usr/local/share/ai-memory \
    && cp -a /root/.local/lib/ai-memory/. /usr/local/share/ai-memory/

# -----------------------------------------------------------------------------
# RUN #4: instalar o Claude Code pelo instalador oficial e COPIAR o binário.
#   Mesma lógica do passo anterior:
#     - o instalador nativo (claude.ai/install.sh) coloca um link em
#       ~/.local/bin/claude apontando para o binário real em ~/.local/share/...
#     - readlink -f acha o arquivo real; install copia para /usr/local/bin/claude.
#   Detalhe: o Claude Code tem autoatualização. Numa CÓPIA do binário em pasta
#   protegida isso não funciona bem, por isso o ENV DISABLE_AUTOUPDATER=1 mais
#   abaixo. Para atualizar o Claude, reconstrua a imagem (--no-cache).
# -----------------------------------------------------------------------------
RUN curl -fsSL https://claude.ai/install.sh | bash \
    && install -m755 -D "$(readlink -f /root/.local/bin/claude)" /usr/local/bin/claude

# -----------------------------------------------------------------------------
# RUN #5: criar o usuário comum "dev" e a pasta de trabalho.
#   userdel -r ubuntu 2>/dev/null
#        Imagens recentes do Ubuntu já trazem um usuário "ubuntu" com uid 1000.
#        Removemos (-r apaga a home dele) para liberar o uid 1000 para o "dev".
#        2>/dev/null esconde o erro caso o usuário não exista; o ";" (e não
#        "&&") faz o comando seguinte rodar de qualquer jeito.
#   useradd -m -u 1000 -s /bin/bash dev
#        Cria o usuário: -m cria /home/dev; -u 1000 fixa o uid; -s define o shell.
#        POR QUE uid 1000? É o mesmo uid do seu usuário no WSL. Arquivos criados
#        no projeto (montado do WSL) ficam com o dono certo, sem "permission
#        denied" nem arquivos de root espalhados.
#   mkdir -p /workspace && chown dev:dev /workspace
#        Cria /workspace (onde o projeto é montado) e entrega ao "dev".
#   POR QUE NÃO ROOT? O Claude Code recusa o modo --dangerously-skip-permissions
#        (o "--yolo") rodando como root. Precisa ser usuário comum.
# -----------------------------------------------------------------------------
RUN userdel -r ubuntu 2>/dev/null; useradd -m -u 1000 -s /bin/bash dev && mkdir -p /workspace && chown dev:dev /workspace

# -----------------------------------------------------------------------------
# RUN #5b: Ollama OPCIONAL (só para "claude-box --local"). Padrão: NÃO instala.
#   ARG INSTALL_OLLAMA=0 ... 1 instala; 0 deixa a imagem sem Ollama. Vem do
#                            setup.sh (--local-yes / --local-no) ou do
#                            "claude-box --install-local" pela variável
#                            CLAUDE_BOX_INSTALL_OLLAMA no docker build.
#   zstd ................... o instalador baixa um pacote .tar.zst (já vem no apt principal, ~1 MB).
#   curl ... | sh .......... instalador oficial do Ollama. Dentro do container não
#                            há systemd: o aviso de que o serviço não foi criado
#                            é esperado.
#   /ollama-models ......... pasta dos modelos. Existe na imagem com dono "dev"
#                            para o volume nomeado "ollama-models" herdar esse dono.
#   command -v ollama ...... faz o build falhar se o binário não foi instalado.
#   Com INSTALL_OLLAMA=0 o RUN não faz nada (camada vazia, quase instantânea).
# -----------------------------------------------------------------------------
ARG INSTALL_OLLAMA=0
RUN if [ "$INSTALL_OLLAMA" = "1" ]; then \
      curl -fsSL https://ollama.com/install.sh | sh \
      && command -v ollama \
      && mkdir -p /ollama-models && chown dev:dev /ollama-models; \
    fi

# -----------------------------------------------------------------------------
# USER dev: a partir daqui (e quando o container rodar) o usuário padrão é
#   "dev", não root. Tudo que ficou antes dessa linha rodou como root.
# -----------------------------------------------------------------------------
USER dev

# -----------------------------------------------------------------------------
# ENV: variáveis de ambiente fixas dentro da imagem.
#   HOME=/home/dev ............ garante que programas gravem config/login em
#                               /home/dev (a pasta que vira o volume claude-home).
#   DISABLE_AUTOUPDATER=1 ..... desliga a autoatualização do Claude Code (ver RUN #4).
# -----------------------------------------------------------------------------
ENV HOME=/home/dev DISABLE_AUTOUPDATER=1

# -----------------------------------------------------------------------------
# WORKDIR: a pasta onde o container começa. Exemplo: ao rodar um shell dentro
#   dele, "pwd" mostra /workspace, onde o seu projeto aparece montado.
# -----------------------------------------------------------------------------
WORKDIR /workspace
EOF
