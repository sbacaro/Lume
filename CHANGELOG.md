# Changelog — Lume

Todas as mudanças notáveis do projeto são documentadas aqui.
Formato baseado em [Keep a Changelog](https://keepachangelog.com/pt-BR/1.0.0/).

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
- [ ] Temas de cor customizáveis
