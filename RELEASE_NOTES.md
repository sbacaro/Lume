# 🚀 Lume v1.4.0 — Modos de verdade, MCP, RAG melhor e IA on-device

A maior atualização desde o lançamento. Os modos **Chat, Cowork e Code** deixaram de ser
só "sidebars diferentes" e passaram a ser experiências distintas; o **MCP** ficou funcional
ponta a ponta; o **RAG** ganhou embeddings contextuais e cache em disco; e a base migrou
para **Swift 6**.

**Data de lançamento:** 2026-06-18
**Versão:** v1.4.0 (build 10)
**Tipo:** Funcionalidades

---

## ✨ Novidades

### Três modos com funções próprias
- O conjunto de ferramentas agora depende do modo: **Chat** só pesquisa na web (conversa
  pura), **Cowork** atua sobre arquivos (ler/escrever, sandbox, MCP) e **Code** tem tudo,
  incluindo Git. O painel direito (inspector) e a faixa de capacidade acima do input
  refletem o modo ativo.
- Limpeza: removidas as áreas decorativas do Code (Terminal/Search/Tests isolados) e o
  terminal interativo do chat — no Code, a saída dos comandos do agente aparece na própria
  conversa.

### MCP funcional (Model Context Protocol)
- Cliente JSON-RPC sobre **stdio e HTTP**: handshake, descoberta (`tools/list`) e execução
  (`tools/call`). As ferramentas dos servidores conectados ficam disponíveis ao agente nos
  dois providers (Anthropic e OpenAI), com gate de aprovação. Status por conector e conexão
  automática no launch.

### RAG mais inteligente e persistente
- Embeddings **contextuais** (NLContextualEmbedding, multilíngue e offline) no lugar da
  média de vetores por palavra, com fallback automático.
- O índice agora é **cacheado em disco**: documentos inalterados não são reprocessados a
  cada abertura do app.

### IA on-device (Apple Foundation Models)
- **Sumarização de contexto** e **roteamento por complexidade** (opcional) rodando no modelo
  local — grátis, offline e privado, economizando tokens da API.

### Histórico de versões de artifacts
- Ao revisar um artifact, as versões anteriores são preservadas; o painel ganhou um
  navegador para voltar e comparar.

## 🔧 Qualidade
- Projeto migrado para o **Swift 6 language mode** com strict concurrency `complete`, e uma
  suíte de **~76 testes** cobrindo roteamento, custo, RAG, MCP, JSON e detecção de artifacts.

---

<details>
<summary>Histórico — versões anteriores</summary>

# ✨ Lume v1.3.4 — Atualização automática (Sparkle)

Esta versão liga a **atualização automática de verdade** via Sparkle: a partir dela, as
próximas versões baixam, instalam e reabrem o app sozinhas — **sem abrir o navegador**.

**Data de lançamento:** 2026-06-16
**Versão:** v1.3.4 (build 9)
**Tipo:** Funcionalidade

---

## ✨ Novidades

### Atualização automática via Sparkle
- Ao detectar uma versão nova, o app **baixa o `.dmg`, instala e reabre sozinho**, pela
  UI padrão do Sparkle — sem passar pelo navegador.
- Segurança por **assinatura EdDSA**: como o app é distribuído sem assinatura da Apple,
  o appcast assinado garante a integridade de cada atualização.

### Setup e release em um comando
- **`setup-sparkle.sh`** configura tudo que é automatizável: resolve o pacote, gera as
  chaves EdDSA e injeta a chave pública no projeto.
- **`release.sh`** passou a **gerar e assinar o appcast** automaticamente e publicar o
  release com o DMG (o `Lume.app` vai **dentro do DMG**).

---

## 🐞 Correções (incluídas da 1.3.3)

- **Menu "Check for Updates…"** verifica dentro do app (não abre mais o navegador).
- **Renderização de chamadas de ferramenta** corrigida (Base64): conteúdos com `]]`, `|`
  ou quebras de linha não vazam mais como texto cru nas mensagens.

---

> Importante: esta é a **primeira** build com Sparkle. Instale-a **manualmente** uma vez
> (a 1.3.2/1.3.3 não têm Sparkle para se auto-atualizar). Da próxima em diante, é automático.

<details>
<summary>Histórico — versões anteriores</summary>

# 🩹 Lume v1.3.3 — "Check for Updates" no menu e correção de renderização

Duas correções: o item **"Check for Updates…"** do menu passa a verificar **dentro do
app** (antes abria o navegador), e o conteúdo de chamadas de ferramenta não vaza mais
como texto cru nas mensagens.

**Data de lançamento:** 2026-06-16
**Versão:** v1.3.3 (build 8)
**Tipo:** Correções

---

## 🐞 Correções

- **Menu "Check for Updates…"** agora faz a verificação dentro do app e mostra o status
  na janela **Sobre** ("Procurando…", "Nova versão disponível: X" ou "Você está na versão
  mais recente."), em vez de abrir a página de releases do GitHub no navegador.
- **Renderização de chamadas de ferramenta corrigida**: scripts e conteúdos com `]]`, `|`
  ou quebras de linha (ex.: um script bash com `if [[ … ]]`) não quebram mais o bloco da
  ferramenta — o payload passou a ser codificado em Base64, então nada vaza como texto cru
  nem mostra `\n` literais na bolha.

---

<details>
<summary>Histórico — versões anteriores</summary>

# 🩹 Lume v1.3.2 — Correção do "Check" no About

Correção pontual: o botão de **verificar atualizações** na tela Sobre passa a checar
**dentro do app**, em vez de abrir o navegador.

**Data de lançamento:** 2026-06-16
**Versão:** v1.3.2 (build 7)
**Tipo:** Correção

---

## 🐞 Correções

- O botão **"Check"** na tela **Sobre** agora faz a verificação dentro do app e mostra o
  status ali mesmo ("Procurando…", "Nova versão disponível: X" ou "Você está na versão
  mais recente."), em vez de abrir a página de releases do GitHub no navegador.

---

<details>
<summary>Histórico — versões anteriores</summary>

# 🔔 Lume v1.3.1 — Notificação de atualização na sidebar e fonte única de versão

Esta versão traz um **popup de atualização no estilo do Lume** logo acima do nome do
modelo, uma **fonte única para o número da versão** e a consolidação do fluxo de release
em um único script.

**Data de lançamento:** 2026-06-16
**Versão:** v1.3.1 (build 6)
**Tipo:** Melhorias + correção

---

## ✨ Novidades

### Notificação de atualização na sidebar
- Quando há uma versão nova, aparece um **popup no estilo do Lume** (vidro + gradiente da
  marca) **logo acima do nome do modelo**, no rodapé da barra lateral. Toque para atualizar
  (via Sparkle); há um botão para dispensar.

### Fonte única da versão
- O número da versão agora vive só no **`Version.xcconfig`**. O app, o About e todos os
  scripts derivam dele. Use **`set-version.sh`** para bumpar em um comando.

---

## 🔧 Alterações

- **`build-release.sh` virou um único arquivo autocontido**: compila, gera o `.app` e
  produz o `Lume-<versão>.dmg` (fundo no gradiente da marca + atalho do Applications,
  headless). O antigo `build-dmg.sh` foi incorporado.

---

## 🐞 Correções

- Correção de compilação no stub do `SparkleUpdater` (faltava `import Combine`).

---

<details>
<summary>Histórico — versões anteriores</summary>

# 🧭 Lume v1.3.0 — Chat unificado, IA ciente do modo e auto-update

Esta versão **unifica a interface de chat** nos três modos, deixa o **modelo ciente de
onde está** (Chat, Cowork ou Code) e traz a base de **atualização automática (Sparkle)**
além de scripts de release com DMG personalizado.

**Data de lançamento:** 2026-06-16
**Versão:** v1.3.0 (build 5)
**Tipo:** Funcionalidades + correções

---

## ✨ Novidades

### Mesma UI de chat em todos os modos
- O **Cowork** passou a usar o **mesmo composer** (caixa de digitação, menus de modelo e
  aprovação, bolhas) do Chat e do Code. Acabaram as três caixas com aparências diferentes.

### IA ciente do modo
- O modelo recebe um cabeçalho dizendo se está em **Chat**, **Cowork** ou **Code**, com o
  papel, as ferramentas e o comportamento esperados de cada área — respostas mais alinhadas
  ao que cada modo faz.

### Atualização automática (Sparkle)
- **Verificar Atualizações…** (menu) e o botão no About baixam o `.dmg`, instalam e
  reiniciam o app sozinhos. Requer configuração — veja `SETUP_SPARKLE.md`.

### Scripts de release
- `build-release.sh` (compila → `.app` → `Lume-<versão>.dmg`), `build-dmg.sh` (DMG com
  fundo no gradiente da marca + atalho do Applications, headless) e `generate-appcast.sh`.

---

## 🔧 Alterações

- Verificador de atualizações mais robusto: fallback para a lista de releases, header
  `User-Agent` e mensagens de erro localizadas.

---

## 🐞 Correções

- O contexto do workspace de **Code** não vaza mais para conversas do **Chat**.
- Porcentagem do progresso de tarefas formatada via `FormatStyle` (corrige aviso do Xcode).
- Textos remanescentes em português agora localizáveis e chaves órfãs do catálogo removidas.

---

<details>
<summary>Histórico — versões anteriores</summary>

# 🌍 Lume v1.2.0 — Suporte a idiomas, botões em pílula e correções

Esta versão traz **internacionalização completa** (inglês + português do Brasil) com um
**seletor de idioma dentro do app**, a padronização de **todos os botões no formato pílula**
e a correção de um bug em que a chave de IA cadastrada no onboarding não aparecia em Configurações.

**Data de lançamento:** 2026-06-16
**Versão:** v1.2.0 (build 4)
**Tipo:** Funcionalidades + correções

---

## ✨ Novidades

### Dois idiomas, do seu jeito
- Interface disponível em **inglês** e **português (Brasil)**, cobrindo toda a aplicação
- Novo **seletor de idioma** em **Configurações → Avançado → Idioma do App**: escolha **Sistema**, **English** ou **Português (Brasil)**; o app reinicia para aplicar
- Por padrão, o Lume agora **segue o idioma do macOS** (antes ficava preso em português)

### Interface mais consistente
- **Todos os botões em formato pílula (cápsula)** — o seletor Chat/Cowork/Code, o botão "Add" e as ações de diálogos agora têm a mesma forma

---

## 🔧 Alterações

- Base de código migrada para **inglês como idioma de origem**; as traduções em português passam pelo catálogo de strings, e não mais por textos fixos no código

---

## 🐞 Correções

- **Chave de IA do onboarding** (e do "Setup assistant") não se refletia em Configurações, exigindo novo cadastro — corrigido ao injetar o contexto de dados correto nos sheets
- Diversos textos antes fixos em português agora são corretamente localizáveis

---

<details>
<summary>Histórico — v1.1.0 (2026-06-15)</summary>

# 🎉 Lume v1.1.0 — Tela "Sobre", interface consistente e correções

Esta versão traz uma nova tela **Sobre o Lume**, um sistema unificado de botões nas
Configurações, correções de consistência no tema escuro e a eliminação de avisos de
concorrência do Swift 6.

**Data de lançamento:** 2026-06-15
**Versão:** v1.1.0 (build 3)
**Tipo:** Funcionalidades + correções

---

## ✨ Novidades

### Tela "Sobre o Lume"
- Nova janela acessível pelo menu **Lume → Sobre o Lume**, no padrão de um app nativo do macOS
- Mostra o ícone do app, **versão e número de build**, descrição e requisitos técnicos
- Atalhos diretos para **Repositório no GitHub**, **Notas de versão**, **Reportar problema** e **Licença MIT**
- Botão **Verificar atualizações** com status ao vivo, integrado ao sistema de releases

### Interface mais consistente
- **Sistema único de botões** nas Configurações: estilos primário, secundário e destrutivo com a mesma forma, tamanho e comportamento em todas as abas e sheets — fim da mistura de cantos redondos/quadrados e tamanhos diferentes

---

## 🔧 Alterações

- A opção de **cor de acento** foi removida das Configurações; o app mantém apenas a escolha de **aparência** (Claro/Escuro/Sistema)

---

## 🐛 Correções

- **Tema escuro consistente:** a tela inicial do modo **Chat** herdava um fundo diferente do das telas **Cowork** e **Code**. Agora as três usam a mesma cor de fundo
- **Concorrência (Swift 6):** eliminados os avisos de mutação de variáveis capturadas em `ShellFunctions`, encapsulando o estado mutável num tipo de referência protegido por lock
- Removidos `await` redundantes em chamadas não-assíncronas (`AIProviderManager`, `AnthropicProvider`)

---

## 📦 Instalação

### Atualização automática
O app verifica novas versões pelo GitHub Releases. Quando houver atualização, basta
clicar em **Atualizar** na notificação (ou em **Verificar** na tela Sobre).

### Atualização manual
1. Baixe a versão mais recente em **GitHub Releases**
2. Arraste **Lume.app** para a pasta Aplicativos
3. Abra e aproveite

---

## 🖥️ Compatibilidade

- **macOS 14+** — binário universal (Intel / Apple Silicon)
- Totalmente retrocompatível com dados e configurações da v1.0.1

---

**Changelog completo:** veja [`CHANGELOG.md`](CHANGELOG.md) · [v1.1.0](https://github.com/sbacaro/Lume/releases/tag/v1.1.0)

</details>


</details>


</details>


</details>


</details>


</details>


</details>
