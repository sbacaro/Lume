# Changelog — Lume

Todas as mudanças notáveis do projeto são documentadas aqui.
Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/).

---

## [Não lançado]

### Alterado

- **RAG com embeddings contextuais**: `TextEmbedder` reescrito como `actor` usando **`NLContextualEmbedding`** (modelo transformer multilíngue, contextual, nativo e offline; script latino cobre PT+EN) com mean-pooling dos vetores de token, e **fallback** para `NLEmbedding` (word2vec) quando os assets do modelo não estão presentes. A dimensão do vetor é fixada na primeira carga. Embeddings de resumo passam a ser **cacheados no `index()`** (antes recomputados a cada busca). +11 testes (`RAGEngineTests`).
- **Swift 6 de verdade**: o projeto migrou para o **Swift 6 language mode** (`SWIFT_VERSION = 6.0`) com **strict concurrency `complete`** em todos os targets. O target de testes (Swift Testing) compartilha a isolação `MainActor` do app; o `LumeUITests` (XCTest) permanece nonisolated.

### Adicionado

- **Cobertura de testes** (Swift Testing): 48 testes cobrindo `LLMRouter` (roteamento/heurísticas), `ModelPricing` (custo/formatação), `ModelCapabilities` (visão), `ArtifactDetector` (detecção em markdown) e `JSONValue` (Codable/acessores/subscripts).

### Corrigido

- **Concorrência sob strict `complete`**: `WKNavigationDelegate.decisionHandler` marcado `@MainActor` em `ArtifactPanelView` (a assinatura antiga "quase casava" e o delegate podia nem ser chamado); `Task.detached` → `Task` em `ProjectDetailView` para não enviar `@Model` não-`Sendable` entre actors; `SpeechDelegateProxy.onEnd` agora é `@Sendable`; `TaskScheduler` pula para o `MainActor` antes de `checkTasks()` no callback do `Timer`.
- **Código morto removido**: `SSEParser` (não referenciado; os providers consomem o SSE direto via `URLSession.bytes`).

---

## [1.3.4] — 2026-06-16

### Adicionado

- **Atualização automática via Sparkle**: ao detectar uma versão nova, o app baixa o `.dmg`, instala e reabre sozinho (UI padrão do Sparkle), **sem abrir o navegador**. Segurança por assinatura **EdDSA** (appcast assinado).
- **`setup-sparkle.sh`**: configura o Sparkle de ponta a ponta no que é automatizável (resolve o pacote, gera as chaves EdDSA e injeta a chave pública no projeto).

### Alterado

- **`release.sh`** agora **gera e assina o appcast** automaticamente quando o Sparkle está instalado, commita o `appcast.xml` e publica o release com o **DMG** (o `Lume.app` vai dentro do DMG). O PKG foi descontinuado.

---

## [1.3.3] — 2026-06-16

### Corrigido

- **Menu "Check for Updates…"** agora faz a verificação **dentro do app** e mostra o status na janela **Sobre**, em vez de abrir a página de releases no navegador.
- **Renderização de chamadas de ferramenta**: conteúdos com `]]`, `|` ou quebras de linha (ex.: um script bash com `if [[ … ]]`) não quebram mais o bloco da ferramenta. O payload passou a ser codificado em **Base64**, então nada vaza como texto cru nem exibe `\n` literais na bolha.

---

## [1.3.2] — 2026-06-16

### Corrigido

- O botão **"Check"** (Verificar atualizações) na tela **Sobre** agora faz a verificação **dentro do app** e mostra o status ali mesmo ("Procurando…", "Nova versão disponível: X" ou "Você está na versão mais recente."), em vez de abrir a página de releases no navegador.

---

## [1.3.1] — 2026-06-16

### Adicionado

- **Notificação de atualização na sidebar**: um popup no estilo do Lume (vidro + gradiente da marca) aparece **logo acima do nome do modelo**, no rodapé da barra lateral. Toque para atualizar (via Sparkle); há um botão para dispensar.
- **Fonte única da versão (`Version.xcconfig`)**: o número da versão passa a viver em um único arquivo, do qual o app, o About e todos os scripts derivam. Inclui `set-version.sh` para bumpar em um comando.

### Alterado

- **`build-release.sh` agora é um único arquivo autocontido**: compila, gera o `.app` e produz o `Lume-<versão>.dmg` (com fundo no gradiente da marca e atalho do Applications, headless) — o antigo `build-dmg.sh` foi incorporado.

### Corrigido

- Correção de compilação no stub do `SparkleUpdater` (faltava `import Combine`), que impedia o build sem o pacote Sparkle adicionado.

---

## [1.3.0] — 2026-06-16

### Adicionado

- **Atualização automática (Sparkle)**: o menu **Verificar Atualizações…** e o botão no About baixam o `.dmg`, instalam e reiniciam o app sozinhos — na próxima abertura já na versão nova. (Requer configuração do pacote e do appcast — ver `SETUP_SPARKLE.md`.)
- **IA ciente do modo**: o modelo agora recebe, no topo do system prompt, um cabeçalho dizendo se está em **Chat**, **Cowork** ou **Code**, com o papel, as ferramentas e o comportamento esperados de cada área.
- **Scripts de release**:
  - `build-release.sh` — pipeline completo: compila, gera o `.app` e entrega o `Lume-<versão>.dmg`.
  - `build-dmg.sh` — DMG custom com **fundo no gradiente da marca**, seta e atalho do **Applications**, de forma headless (sem depender do Finder).
  - `generate-appcast.sh` — gera e assina (EdDSA) o `appcast.xml` do Sparkle.

### Alterado

- **UI do chat unificada**: o **Cowork** agora usa o mesmo composer (caixa de digitação, menus de modelo/aprovação e bolhas) do Chat e do Code — fim das três caixas diferentes.
- **Verificador de atualizações mais robusto**: fallback para a lista de releases quando o "latest" retorna 404, header `User-Agent` e mensagens de erro localizadas.

### Corrigido

- O **contexto do workspace de Code** não vaza mais para conversas do Chat — fica restrito ao modo Code.
- Porcentagem do progresso de tarefas formatada via **FormatStyle** (corrige o aviso de localização do Xcode).
- Textos que ainda apareciam em português agora são localizáveis (ex.: "Verificar" → Check, "Modelo" → Model) e chaves órfãs do catálogo de strings foram removidas.

---

## [1.2.0] — 2026-06-16

### Adicionado

#### Internacionalização (i18n)
- **Suporte completo a dois idiomas**: inglês (base) e **português (Brasil)**, com catálogo de strings (`Localizable.xcstrings`) cobrindo toda a interface
- **Seletor de idioma no app** em Configurações → Avançado → **Idioma do App**: escolha entre **Sistema**, **English** e **Português (Brasil)**, com reinício automático para aplicar
- Por padrão, o app passa a seguir o idioma do macOS (antes ficava preso em português)

### Alterado

- **Botões padronizados em formato pílula (cápsula)** em todo o app — fim da mistura de cantos arredondados e quadrados; o seletor Chat/Cowork/Code e os botões de ação agora compartilham a mesma forma
- Base de código migrada para **inglês como idioma de origem**, com as traduções em português movidas para o catálogo de strings (em vez de textos fixos no código)

### Corrigido

- **Chave de IA cadastrada no onboarding** (e no "Setup assistant") não aparecia em Configurações, exigindo novo cadastro — causado pela falta de injeção do contexto de dados (`modelContext`) nos sheets de onboarding
- Diversos textos que estavam fixos em português e não passavam pela tradução agora são localizáveis

---

## [1.1.0] — 2026-06-15

### Adicionado

#### Sobre o app
- Nova tela **"Sobre o Lume"** profissional, acessível pelo menu (Lume → Sobre o Lume): ícone do app, versão e número de build, descrição, requisitos técnicos e copyright
- Atalhos diretos para **Repositório no GitHub**, **Notas de versão**, **Reportar problema** e **Licença MIT**
- Botão **Verificar atualizações** com status ao vivo, integrado ao sistema de releases

#### Renderização de mensagens
- **Tabelas** markdown com cabeçalho, alinhamento por coluna (`:--`, `--:`, `:-:`), zebra e scroll horizontal
- **Blockquotes** (`>`) com barra de acento
- **Checkboxes** de task list (`- [ ]` / `- [x]`) com texto riscado quando concluído
- **Listas aninhadas** com indentação e marcadores por nível (•/◦/▪)
- **Tamanho de fonte ajustável** das mensagens (Pequeno/Padrão/Grande/Extra) em Configurações → Avançado, com pré-visualização ao vivo

#### Inteligência e contexto
- **Memória persistente** entre conversas: fatos do usuário injetados no system prompt, com aba de gestão (categorias, ativar/desativar, editar) e captura rápida a partir de qualquer mensagem
- **Contexto temporal**: data e hora atuais do macOS enviadas a cada mensagem, ancorando a IA no presente
- **Títulos de conversa on-device** via Apple Foundation Models (privado, gratuito, com fallback)
- **RAG híbrido**: busca vetorial (cosine) combinada com lexical (BM25-lite)
- **Citações RAG clicáveis**: seção "Fontes" nas respostas, com popover do trecho, documento e relevância
- **Vision OCR**: texto de imagens anexadas extraído localmente (pt-BR/en) e incluído no contexto — útil até para modelos sem visão
- **Badge de modelo e custo**: modelo escolhido pelo roteamento automático + tokens e custo estimado por conversa

#### Interface e UX
- **Paleta de comandos (⌘K)** com busca global por título *e* conteúdo das mensagens, e ações rápidas
- **Atalhos de teclado**: ⌘N (nova conversa), ⌘F (busca), ⌘1/2/3 (alternar Chat/Cowork/Code)
- **Auto-scroll inteligente**: só acompanha o fim se o usuário já estava lá, com botão flutuante "ir ao fim"
- **Toast de erro** transitório (substitui mensagens de erro no histórico)
- **Velocidade de geração** (tok/s) ao vivo no header durante o streaming
- **Timestamp** também nas respostas do assistente
- **Thumbnails** das imagens anexadas, com remoção individual
- **Histórico de versões (branching)**: editar/reiniciar não destrói mais o trecho anterior — ele é arquivado e pode ser restaurado de forma reversível

#### Tema
- **Aparência** Claro/Escuro/Sistema, aplicada em todo o app

#### Voz
- **Leitura em voz alta (TTS)** das respostas via `AVSpeechSynthesizer`, com limpeza de markdown
- Abstração de transcrição (`TranscriptionProvider`) preparada para motor local Whisper (WhisperKit)

#### Exportação
- Export de conversa como **Markdown** (arquivo) e **PDF** paginado, além de copiar para a área de transferência

### Alterado
- **Botões das Configurações padronizados** num único sistema de estilos (primário, secundário e destrutivo) com forma, tamanho e estados consistentes em todas as abas e sheets
- Blocos de código agora **auto-expandem** quando curtos (≤40 linhas); longos continuam colapsados
- Largura de leitura das respostas limitada (~760pt) para legibilidade em janelas largas
- `RAGEngine` passou de busca puramente vetorial para **recuperação híbrida** com fontes rastreáveis
- Títulos automáticos deixaram de usar as primeiras palavras do texto, passando a usar modelo on-device

### Removido
- **Cor de acento customizável**: a opção foi removida das Configurações; o app mantém apenas a escolha de aparência (Claro/Escuro/Sistema)

### Corrigido
- **Tema escuro consistente**: a tela inicial do modo Chat herdava um fundo diferente do das telas Cowork e Code; agora todas usam a mesma cor de fundo
- **Concorrência (Swift 6)**: eliminados os avisos de mutação de variáveis capturadas em `ShellFunctions`, encapsulando o estado mutável num tipo de referência protegido por lock
- Removidos `await` redundantes em chamadas não-assíncronas (`AIProviderManager`, `AnthropicProvider`)

---

## [1.0.0] — 2025-06-26

### Adicionado

#### Interface
- Sidebar com três modos: **Chat**, **Cowork** e **Code**
- Área de chat com streaming de tokens em tempo real
- Syntax highlighting estilo Xcode Dark para Swift, Python, JS/TS, Bash, JSON, HTML, CSS, SQL e Rust
- Numeração de linhas nos blocos de código
- Diff viewer com cores para arquivos de patch
- Blocos de código colapsados por padrão, expansíveis ao clicar
- Mensagens do usuário com ações no hover: hora de envio, reiniciar, editar, copiar
- Mensagens da IA com ações no hover: copiar, continuar a partir daqui
- Seleção de texto cruzando múltiplas mensagens
- Notificação de atualização disponível (card animado no canto inferior direito)
- Indicador de modelo ativo na barra inferior da sidebar

#### Chat
- Suporte a múltiplos providers: **OpenAI**, **Anthropic**, providers customizados (OpenAI-compatible)
- Seletor de modelo por provider com modelos dinâmicos via API
- Streaming de tokens via Server-Sent Events (SSE)
- Cache semântico com persistência em disco (TTL de 24h)
- Compressão de contexto usando NLEmbedding nativo do macOS
- Sumarização automática de histórico longo
- Roteamento automático de modelo por complexidade da query (inspirado em RouteLLM)

#### Projetos (Cowork)
- Criação de projetos do zero com pasta local em `~/Lume/`
- Importação de conversas existentes como projetos
- Importação de pastas existentes
- System prompt por projeto
- Indexação de arquivos para RAG (PDF, imagens, texto, código)
- Painel direito com instruções, contexto e arquivos do projeto

#### Ferramentas do Agente
- Busca na web via DuckDuckGo (sem chave de API)
- Fetch de páginas web com extração de texto
- Execução de shell commands
- Leitura e escrita de arquivos
- Listagem e criação de diretórios
- Integração com Git (status de branch, arquivos staged/modified)

#### Infraestrutura de IA
- Gateway compatível com LiteLLM, Portkey, Langfuse, vLLM, TGI e Ollama
- Prompt caching nativo (Anthropic `cache_control`, OpenAI seed)
- RAG Engine com NLEmbedding, chunking hierárquico e busca por similaridade
- Orquestrador de agentes com grafo de steps, condicionais e loops
- Execução paralela de subagentes

#### Voice
- Ditado por voz usando `SFSpeechRecognizer` nativo do macOS
- Reconhecimento em português brasileiro com fallback para inglês
- Indicador visual de gravação no header do chat
- Envio automático após parar de gravar

#### Multimodal
- Arraste e solte imagens diretamente no campo de entrada
- Cole imagens do clipboard (⌘V)
- Envio de imagens como base64 para modelos compatíveis (GPT-4o, Claude)

#### Artifacts
- Detecção automática de HTML, SVG, JavaScript, CSS, React, Mermaid e Markdown
- Preview interativo ao lado do chat
- O inspector fecha automaticamente ao abrir um artifact

#### Atualizações
- Verificação automática de atualizações via GitHub Releases (a cada 6 horas)
- Card de notificação animado com release notes expansíveis
- Versões dispensadas são lembradas entre sessões

---

## Pendente / Roadmap

- [ ] Modo Computer Use (controle de tela via Anthropic API)
- [ ] Planilhas nativas
- [ ] Histórico de versões de artifacts
- [ ] Exportação de projetos
- [ ] Ditado local com Whisper (WhisperKit) — abstração pronta, falta adicionar o pacote no Xcode
- [x] Modos de aparência (Claro/Escuro/Sistema)
- [x] Memória persistente entre conversas
- [x] Histórico de versões de conversas (branching)
