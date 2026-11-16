# Arquitetura de Skills do agente — Monorepo com SDD + TDD

> **Para o agente:** este documento descreve como você deve trabalhar neste repositório e
> como montar as skills que tornam isso automático. Se as skills ainda não existem, execute a
> seção **[10. Bootstrap](#10-bootstrap-instruções-para-o-agente)**. Se já existem, siga o
> **[3. Fluxo de trabalho](#3-fluxo-de-trabalho)**.
>
> **Para humanos:** para iniciar, abra o agente na raiz e peça:
> `Leia SKILLS-ARCHITECTURE.md e execute o Bootstrap.`

---

## Sumário

1. [Objetivo e princípios](#1-objetivo-e-princípios)
2. [Estrutura de diretórios](#2-estrutura-de-diretórios)
3. [Fluxo de trabalho](#3-fluxo-de-trabalho)
4. [Como o Claude Code carrega skills e CLAUDE.md](#4-como-o-claude-code-carrega-skills-e-claudemd)
5. [Rastreabilidade: spec → tarefa → teste](#5-rastreabilidade-spec--tarefa--teste)
6. [Skills de processo (raiz)](#6-skills-de-processo-raiz)
7. [Templates de specs](#7-templates-de-specs)
8. [Skills de domínio (por pacote)](#8-skills-de-domínio-por-pacote)
9. [CLAUDE.md da raiz e dos pacotes](#9-claudemd-da-raiz-e-dos-pacotes)
10. [Bootstrap (instruções para o agente)](#10-bootstrap-instruções-para-o-agente)
11. [Quando NÃO usar o fluxo completo](#11-quando-não-usar-o-fluxo-completo)
12. [Reforço opcional com hooks](#12-reforço-opcional-com-hooks)
13. [Manutenção](#13-manutenção)
14. [Fontes](#14-fontes)

---

## 1. Objetivo e princípios

Fazer o agente trabalhar de forma previsível num monorepo, combinando:

- **SDD (Spec-Driven Development):** o *quê* é decidido e escrito antes do código, em arquivos
  versionados no repositório.
- **TDD (Test-Driven Development):** o *como* é guiado por testes que falham antes do código
  existir.

Princípios:

| # | Princípio | Consequência prática |
|---|---|---|
| P1 | **Processo na raiz, domínio no pacote** | Skills de fluxo ficam em `/.claude/skills/`; convenções de cada pacote ficam em `packages/<pkg>/.claude/skills/`. |
| P2 | **Spec é a fonte do *quê*, teste é a prova** | Todo critério de aceite vira pelo menos um teste com o mesmo ID. |
| P3 | **Spec ancorada, não spec como código** | Specs curtas, mantidas atualizadas quando o código muda. Não geramos código a partir delas sem revisão. |
| P4 | **Contexto é caro** | `CLAUDE.md` curtos; skills com corpo enxuto (alvo < 500 linhas) e detalhes em arquivos de referência. |
| P5 | **Verificação objetiva** | Nenhuma tarefa é dada como pronta sem rodar os comandos de teste do pacote. |

---

## 2. Estrutura de diretórios

```
<raiz>/
├── CLAUDE.md                          # curto: mapa do repo, regras gerais, aponta para este doc
├── SKILLS-ARCHITECTURE.md             # este documento
├── .claude/
│   └── skills/                        # PROCESSO — valem para o repo inteiro
│       ├── sdd-specify/
│       │   ├── SKILL.md
│       │   └── template.md            # template de spec.md
│       ├── sdd-plan/
│       │   ├── SKILL.md
│       │   └── template.md            # template de plan.md
│       ├── sdd-tasks/
│       │   ├── SKILL.md
│       │   └── template.md            # template de tasks.md
│       ├── tdd/
│       │   └── SKILL.md
│       └── verify/
│           └── SKILL.md
├── specs/
│   ├── constitution.md                # princípios do projeto (stack, qualidade, testes)
│   └── 001-<slug-da-feature>/
│       ├── spec.md
│       ├── plan.md
│       └── tasks.md
└── packages/                          # ou apps/, services/ — o que o repo usar
    ├── <pacote-a>/
    │   ├── CLAUDE.md                  # comandos de teste/lint/build deste pacote
    │   └── .claude/skills/
    │       └── <pacote-a>-conventions/
    │           └── SKILL.md           # DOMÍNIO
    └── <pacote-b>/
        ├── CLAUDE.md
        └── .claude/skills/
            └── <pacote-b>-conventions/
                └── SKILL.md
```

Numeração das specs: `NNN-slug`, sequencial (`001-login`, `002-notificacoes`).

---

## 3. Fluxo de trabalho

```
Pedido do usuário
   │
   ├─ é pequeno? (ver seção 11) ──sim──► tdd ──► verify
   │
   └─ não
      ▼
 sdd-specify ──► spec.md      (o quê e critérios de aceite; o usuário revisa)
      ▼
 sdd-plan    ──► plan.md      (como; pacotes afetados; estratégia de teste; o usuário revisa)
      ▼
 sdd-tasks   ──► tasks.md     (tarefas pequenas, ordenadas, cada uma testável)
      ▼
 para cada tarefa:
      tdd    ──► RED → GREEN → REFACTOR
      verify ──► testes do pacote + rastreabilidade + marca a tarefa como feita
      ▼
 verify final (todos os pacotes afetados) ──► relatório ao usuário
```

Pontos de parada obrigatórios (o agente para e espera o usuário):

1. Depois de `spec.md` — o usuário aprova os critérios de aceite.
2. Depois de `plan.md` — o usuário aprova as decisões técnicas.
3. Quando um teste existente precisaria mudar de comportamento esperado (ver skill `tdd`).

---

## 4. Como o Claude Code carrega skills e CLAUDE.md

Saber isso explica as decisões de estrutura:

- **Skills:** cada skill é uma pasta com um `SKILL.md`. No início da sessão só o `name` e a
  `description` de cada skill entram no contexto; o corpo é lido quando o agente decide que a
  skill é relevante, e os arquivos anexos (templates, referências) só quando são abertos.
- **Skills aninhadas (monorepo):** além de `/.claude/skills/`, o Claude Code descobre pastas
  `.claude/skills/` dentro de subdiretórios quando o agente lê ou edita arquivos ali. As skills
  de um pacote só aparecem quando o agente trabalha naquele pacote, mesmo que a sessão tenha
  começado na raiz.
- **CLAUDE.md:** o da raiz é carregado no início; os de subdiretórios entram quando o agente
  trabalha naquela pasta. Por isso o `CLAUDE.md` de cada pacote é o lugar dos comandos de teste
  daquele pacote.
- **A `description` é o gatilho.** O agente tende a acionar skills de menos, não de mais. Escreva
  descrições explícitas, dizendo *o que* a skill faz e *quando* usar.
- **O `name`** vira também um comando de barra (`/sdd-specify`, `/tdd`...), útil para acionar a
  skill manualmente.

---

## 5. Rastreabilidade: spec → tarefa → teste

O elo entre SDD e TDD é um ID:

| Artefato | Formato do ID | Exemplo |
|---|---|---|
| Critério de aceite (`spec.md`) | `CA-NN` | `CA-03: usuário com senha errada recebe erro 401` |
| Tarefa (`tasks.md`) | `T-NN` + lista de CAs | `T-04 [backend] (CA-03, CA-04) validar credenciais` |
| Teste | ID do CA no nome do teste | `it("CA-03: retorna 401 para senha errada", ...)` |

Regras:

- Todo `CA` tem pelo menos um teste com o seu ID no nome.
- Toda tarefa referencia pelo menos um `CA` (exceto tarefas de infraestrutura, marcadas `infra`).
- A skill `verify` confere isso com uma busca (`grep -rn "CA-03"`).

---

## 6. Skills de processo (raiz)

Crie cada arquivo exatamente no caminho indicado.

### 6.1 `.claude/skills/sdd-specify/SKILL.md`

````markdown
---
name: sdd-specify
description: Cria a especificação (spec.md) de uma nova feature a partir do pedido do usuário, com critérios de aceite numerados. Use ANTES de planejar ou escrever código para qualquer feature que exija mais de uma tarefa, ou quando o usuário pedir uma spec.
---

# SDD — Especificar

Objetivo: registrar O QUÊ deve ser construído e POR QUÊ, sem decisões técnicas.

## Passos

1. Leia `specs/constitution.md` e liste as specs existentes em `specs/` para não duplicar.
2. Defina o próximo número `NNN` e um slug curto; crie `specs/NNN-slug/spec.md` a partir de
   `template.md` (nesta pasta).
3. Preencha: contexto, objetivo, fora de escopo, histórias de usuário e critérios de aceite.
4. Cada critério de aceite recebe um ID `CA-NN` e é escrito de forma verificável
   (Dado / Quando / Então). Um critério que não pode virar teste deve ser reescrito.
5. Tudo que for ambíguo vira um item em "Perguntas em aberto" marcado `[ESCLARECER]`.
   Não invente respostas.
6. NÃO escreva decisões técnicas (bibliotecas, tabelas, endpoints). Isso é do plano.
7. PARE. Mostre ao usuário o resumo dos critérios e as perguntas em aberto e aguarde aprovação.

## Pronto quando

- Nenhum `[ESCLARECER]` restante (ou o usuário aceitou deixá-los).
- O usuário aprovou os critérios de aceite.
````

### 6.2 `.claude/skills/sdd-plan/SKILL.md`

````markdown
---
name: sdd-plan
description: Transforma uma spec aprovada (specs/NNN-*/spec.md) em plano técnico (plan.md) indicando pacotes afetados, contratos entre pacotes e estratégia de teste por critério de aceite. Use depois que a spec for aprovada e antes de quebrar em tarefas.
---

# SDD — Planejar

Objetivo: decidir COMO implementar a spec neste monorepo.

## Passos

1. Leia `spec.md`, `specs/constitution.md` e o `CLAUDE.md` de cada pacote que pode ser afetado.
2. Explore o código existente dos pacotes afetados antes de decidir (padrões, utilitários já
   existentes). Prefira reutilizar a criar.
3. Crie `plan.md` a partir de `template.md` (nesta pasta), cobrindo:
   - pacotes afetados e o papel de cada um;
   - contratos entre pacotes (tipos, APIs, eventos) — defina-os ANTES das implementações;
   - ordem de mudança: pacotes compartilhados primeiro, consumidores depois;
   - estratégia de teste: para cada `CA-NN`, o nível (unitário, integração, e2e) e o pacote;
   - riscos e alternativas descartadas (uma linha cada).
4. Se a decisão contrariar `constitution.md`, aponte e pergunte.
5. PARE. Mostre o resumo ao usuário e aguarde aprovação.

## Pronto quando

- Todo `CA-NN` da spec tem estratégia de teste no plano.
- O usuário aprovou o plano.
````

### 6.3 `.claude/skills/sdd-tasks/SKILL.md`

````markdown
---
name: sdd-tasks
description: Quebra um plano aprovado (plan.md) numa lista ordenada de tarefas pequenas e testáveis (tasks.md), cada uma ligada a critérios de aceite. Use depois que o plano for aprovado e antes de implementar.
---

# SDD — Tarefas

## Passos

1. Leia `spec.md` e `plan.md` da feature.
2. Crie `tasks.md` a partir de `template.md` (nesta pasta).
3. Regras para cada tarefa:
   - ID `T-NN`, pacote entre colchetes, CAs entre parênteses:
     `- [ ] T-03 [backend] (CA-02) criar endpoint de login`
   - cabe em um ciclo TDD curto (idealmente um pacote e poucos arquivos);
   - informa o comando de teste que a valida (do CLAUDE.md do pacote);
   - lista dependências (`depende de: T-01`).
4. Ordem: contratos/tipos compartilhados → implementações → integração entre pacotes.
5. Confira que todo `CA-NN` aparece em pelo menos uma tarefa.
6. Mostre a lista ao usuário. Comece a implementação só se o usuário pedir.
````

### 6.4 `.claude/skills/tdd/SKILL.md`

````markdown
---
name: tdd
description: Implementa código pelo ciclo red-green-refactor, escrevendo e rodando um teste que falha antes de qualquer código de produção. Use SEMPRE ao implementar uma tarefa, feature ou correção de bug, antes de escrever código de implementação.
---

# TDD — Red, Green, Refactor

## Regras invioláveis

1. Nenhum código de produção sem um teste falhando que o exija.
2. Você precisa VER o teste falhar, e pelo motivo certo (asserção, não erro de import/sintaxe).
3. Nunca altere um teste existente para fazê-lo passar. Se o comportamento esperado mudou,
   PARE e pergunte ao usuário.
4. Não use mocks para o próprio código sob teste nem implementações falsas que só satisfazem
   o teste (retornar valor fixo, ramificar por nome de teste).
5. Correção de bug começa com um teste que reproduz o bug.

## Ciclo (repita por comportamento)

1. **RED** — Escreva UM teste mínimo para o próximo comportamento. Se houver critério de
   aceite, coloque o ID no nome do teste (`CA-03: ...`). Rode só esse teste. Confirme a falha
   e o motivo.
2. **GREEN** — Escreva o MENOR código que faz o teste passar. Rode o teste. Rode também os
   testes do pacote para garantir que nada quebrou.
3. **REFACTOR** — Melhore nomes, remova duplicação, ajuste à skill de convenções do pacote.
   Rode os testes de novo: devem continuar verdes.
4. Próximo comportamento.

## Comandos

Use os comandos de teste do `CLAUDE.md` do pacote. Se não existirem, descubra-os
(package.json, Makefile, pom.xml, pyproject...) e informe o usuário.

## Commits

Só faça commits se o `CLAUDE.md` da raiz permitir. Nesse caso: um commit com os testes (RED)
e outro com a implementação (GREEN + REFACTOR).

## Ao terminar a tarefa

Acione a skill `verify`.
````

### 6.5 `.claude/skills/verify/SKILL.md`

````markdown
---
name: verify
description: Verifica se uma tarefa ou feature está realmente pronta - roda testes, lint e checagem de tipos dos pacotes afetados e confere a rastreabilidade entre critérios de aceite e testes. Use ao final de cada tarefa e antes de dizer ao usuário que algo está concluído.
---

# Verify

## Passos

1. Identifique os pacotes alterados (`git status` / `git diff --name-only`).
2. Para cada pacote, rode os comandos de teste, lint e tipos do seu `CLAUDE.md`.
3. Se a tarefa pertence a uma spec:
   - para cada `CA-NN` da tarefa, confirme que existe teste com o ID (`grep -rn "CA-NN"`);
   - marque a tarefa como feita em `tasks.md` (`- [x]`).
4. Se o código mudou algo que a spec ou o plano descrevem diferente, atualize o documento
   (spec ancorada) ou aponte a divergência ao usuário.
5. Relatório curto: comandos rodados e resultado, CAs cobertos, pendências.

## Nunca

- Dizer que está pronto sem ter rodado os testes.
- Esconder testes falhando ou pulados; reporte-os.
````

---

## 7. Templates de specs

### 7.1 `specs/constitution.md`

```markdown
# Constituição do projeto

## Stack
- <linguagens, frameworks e versões por pacote>

## Qualidade
- Todo código novo nasce por TDD.
- <cobertura mínima, se houver>
- <padrões de lint/format>

## Arquitetura
- <regras de dependência entre pacotes: quem pode importar quem>
- <onde ficam tipos e contratos compartilhados>

## Segurança
- Segredos nunca no código nem nas specs.
- <outras regras>

## Proibido
- <ex.: novas dependências sem aprovação>
```

### 7.2 `.claude/skills/sdd-specify/template.md`

```markdown
# Spec NNN — <título>

Status: rascunho | aprovada | implementada
Data: <AAAA-MM-DD>

## Contexto
<problema e por que importa>

## Objetivo
<resultado esperado em 1-3 frases>

## Fora de escopo
- <item>

## Histórias de usuário
- Como <papel>, quero <ação>, para <benefício>.

## Critérios de aceite
- **CA-01:** Dado <contexto>, quando <ação>, então <resultado verificável>.
- **CA-02:** ...

## Perguntas em aberto
- [ESCLARECER] <pergunta>
```

### 7.3 `.claude/skills/sdd-plan/template.md`

```markdown
# Plano — Spec NNN <título>

## Pacotes afetados
| Pacote | Papel nesta feature |
|---|---|

## Contratos entre pacotes
<tipos, endpoints, eventos — definidos antes das implementações>

## Ordem de mudança
1. <pacote compartilhado>
2. <consumidores>

## Estratégia de teste
| CA | Nível | Pacote | Observação |
|---|---|---|---|
| CA-01 | unitário | | |

## Decisões
- <decisão> — <motivo>

## Riscos e alternativas descartadas
- <risco/alternativa> — <motivo>
```

### 7.4 `.claude/skills/sdd-tasks/template.md`

```markdown
# Tarefas — Spec NNN <título>

- [ ] T-01 [<pacote>] (CA-01) <descrição>
  - teste: `<comando>`
- [ ] T-02 [<pacote>] (CA-02, CA-03) <descrição>
  - depende de: T-01
  - teste: `<comando>`
- [ ] T-03 [<pacote>] (infra) <descrição>
```

---

## 8. Skills de domínio (por pacote)

Uma skill de convenções por pacote, em `packages/<pkg>/.claude/skills/<pkg>-conventions/SKILL.md`.
Conteúdo: só o que é específico do pacote e que o agente não adivinharia.

````markdown
---
name: <pkg>-conventions
description: Convenções do pacote <pkg> (<tecnologia>) - estrutura de pastas, padrões de código e de testes. Use ao criar ou alterar qualquer arquivo em packages/<pkg>/.
---

# Convenções — <pkg>

## Estrutura
- <onde ficam módulos, testes, fixtures>

## Padrões de código
- <ex.: injeção de dependência, tratamento de erros, nomes>

## Padrões de teste
- Framework: <jest | vitest | junit | pytest...>
- Local dos testes: <ao lado do arquivo | pasta tests/>
- Dados de teste: <factories, fixtures>
- O que NÃO mockar: <ex.: banco em testes de integração usa container>

## Armadilhas conhecidas
- <coisas que já deram errado>
````

Se o pacote tiver muito conteúdo, mantenha o `SKILL.md` curto e mova detalhes para arquivos na
mesma pasta (`testing.md`, `api.md`), referenciados a partir do `SKILL.md` com uma linha cada.

---

## 9. CLAUDE.md da raiz e dos pacotes

### 9.1 `CLAUDE.md` (raiz) — curto

```markdown
# <nome do projeto>

Monorepo. Pacotes: <lista curta com uma linha cada>.

## Como trabalhamos
- Features com mais de uma tarefa seguem SDD: skills sdd-specify → sdd-plan → sdd-tasks.
- Todo código segue TDD (skill tdd) e só é dado como pronto após a skill verify.
- Specs ficam em specs/; princípios em specs/constitution.md.
- Arquitetura completa das skills: SKILLS-ARCHITECTURE.md.

## Regras
- Commits: <permitidos por etapa | não fazer commits>.
- Não adicionar dependências sem perguntar.
- Comandos de cada pacote estão no CLAUDE.md do próprio pacote.
```

### 9.2 `packages/<pkg>/CLAUDE.md`

```markdown
# <pkg>

<uma linha sobre o papel do pacote>

## Comandos (rodar dentro de packages/<pkg>)
- Testes (todos): `<comando>`
- Teste único: `<comando> <arquivo>`
- Lint: `<comando>`
- Tipos: `<comando>`
- Build: `<comando>`
```

---

## 10. Bootstrap (instruções para o agente)

Execute em ordem. **Não sobrescreva arquivos existentes**: se um arquivo já existir, mostre a
diferença e pergunte.

1. **Mapear o repositório**
   - Liste os pacotes (procure `packages/`, `apps/`, `services/` e arquivos de workspace:
     `pnpm-workspace.yaml`, `package.json` com `workspaces`, `turbo.json`, `nx.json`,
     `settings.gradle`, `pom.xml` com módulos, `go.work`, `Cargo.toml` com `[workspace]`).
   - Para cada pacote, descubra linguagem, framework de teste e comandos de teste/lint/tipos/build.
   - Mostre o mapa ao usuário e confirme antes de criar arquivos.
2. **Skills de processo:** crie os cinco `SKILL.md` e os três `template.md` da seção 6 e 7,
   exatamente como estão.
3. **Constituição:** crie `specs/constitution.md` (seção 7.1) preenchendo o que conseguir
   inferir do repo; marque o resto com `[PREENCHER]`.
4. **CLAUDE.md por pacote:** crie (seção 9.2) com os comandos descobertos. Se um comando não foi
   encontrado, marque `[PREENCHER]` em vez de inventar.
5. **Skills de domínio:** crie uma `<pkg>-conventions` por pacote (seção 8) a partir do código
   existente: leia alguns arquivos e testes representativos e registre só padrões observados.
6. **CLAUDE.md da raiz:** crie ou complete (seção 9.1). Se já existir, proponha só as linhas
   novas.
7. **Validar:** confirme que cada `SKILL.md` tem frontmatter com `name` igual ao nome da pasta e
   uma `description` explícita; rode os comandos de teste de cada pacote uma vez e anote se
   passam.
8. **Relatório final:** arquivos criados, itens `[PREENCHER]` e o que o usuário precisa revisar.

Depois do bootstrap, o usuário pode precisar reiniciar o agente para que pastas `.claude/skills/`
recém-criadas sejam observadas.

---

## 11. Quando NÃO usar o fluxo completo

Use só `tdd` + `verify` (sem spec) para:

- correção de bug localizada (começa com teste que reproduz o bug);
- refatoração sem mudança de comportamento (os testes existentes são a rede de segurança);
- ajustes de texto, configuração ou dependência.

Use o fluxo SDD completo quando a mudança tiver mais de uma tarefa, envolver mais de um pacote ou
mudar comportamento visível ao usuário.

Em caso de dúvida, o agente pergunta.

---

## 12. Reforço opcional com hooks

Skills são instruções: o agente pode pular etapas. Para regras que não podem falhar, o Claude Code
permite hooks (comandos executados antes/depois de ferramentas, configurados em
`.claude/settings.json`). Ideias:

- antes de editar um arquivo de código, checar se existe o arquivo de teste correspondente;
- depois de editar, rodar o teste do arquivo alterado.

Consulte a documentação oficial de hooks antes de configurar; o formato e a lógica dependem do
stack de cada pacote.

---

## 13. Manutenção

- **Skill não aciona:** reescreva a `description` com palavras que aparecem nos pedidos reais.
- **Skill cresceu demais:** mantenha o corpo < 500 linhas; mova detalhes para arquivos de
  referência na mesma pasta (um nível de profundidade).
- **Spec desatualizada:** atualize-a no mesmo trabalho que mudou o comportamento; spec errada é
  pior que spec ausente.
- **Erro repetido do agente:** registre em "Armadilhas conhecidas" da skill de convenções do
  pacote, não no CLAUDE.md da raiz.

---

## 14. Fontes

Oficiais:

- Claude Code — Skills (inclui descoberta em diretórios aninhados): https://code.claude.com/docs/en/skills
- Anthropic — Skill authoring best practices: https://platform.claude.com/docs/en/agents-and-tools/agent-skills/best-practices
- Anthropic — Claude Code: best practices for agentic coding (fluxo de TDD): https://www.anthropic.com/engineering/claude-code-best-practices
- Claude Code — Best practices: https://code.claude.com/docs/en/best-practices
- GitHub Spec Kit: https://github.github.com/spec-kit/
- GitHub Blog — Spec-driven development with AI: https://github.blog/ai-and-ml/generative-ai/spec-driven-development-with-ai-get-started-with-a-new-open-source-toolkit/

Análise crítica de SDD:

- Birgitta Böckeler — Understanding Spec-Driven-Development: Kiro, spec-kit, and Tessl: https://www.martinfowler.com/articles/exploring-gen-ai/sdd-3-tools.html
- InfoWorld — 4 cutting-edge tools for spec-driven development: https://infoworld.com/article/4171332/four-cutting-edge-tools-for-spec-driven-development.html

Skills de referência:

- obra/superpowers — test-driven-development: https://www.skills.sh/obra/superpowers/test-driven-development
- addyosmani/agent-skills — test-driven-development: https://claudemarketplaces.com/skills/addyosmani/agent-skills/test-driven-development
