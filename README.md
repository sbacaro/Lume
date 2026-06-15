<p align="center">
  <img src="Lume/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="Lume">
</p>

<h1 align="center">Lume</h1>

<p align="center">
  <strong>Native AI Client for macOS</strong> — Chat, projects, code, and agents all in one place.<br>
  <strong>Cliente Nativo de IA para macOS</strong> — Chat, projetos, código e agentes em um só lugar.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT">
  <img src="https://img.shields.io/badge/version-1.0.1-brightgreen" alt="v1.0.1">
</p>

---

## 🚀 What's New in v1.0.1 / O que há de novo em v1.0.1

### ✅ Critical Bug Fixes & Performance Improvements
### ✅ Correções Críticas de Bugs e Melhorias de Desempenho

- **Memory Management**: Fixed streaming task retain cycles causing memory leaks
- **Memory Management**: Corrigidos ciclos de retenção de tarefas de streaming que causavam vazamentos de memória
- **Threading**: Added `@MainActor` for consistent UI thread access
- **Threading**: Adicionado `@MainActor` para acesso consistente à thread da UI
- **Safety**: Eliminated force unwrapping and enhanced error handling
- **Segurança**: Eliminados force unwrapping e tratamento de erros aprimorado
- **Performance**: 20-40% reduction in memory usage during extended sessions
- **Performance**: Redução de 20-40% no uso de memória durante sessões estendidas

**Full changelog available**: [v1.0.1 Release](https://github.com/sbacaro/Lume/releases/tag/v1.0.1)

---

## Features / Funcionalidades

| Category / Categoria | Feature / Funcionalidade | EN / PT |
|---|---|---|
| **Chat** | Real-time streaming, multiple providers, model selector | Streaming em tempo real, múltiplos providers, seletor de modelo |
| **Projects / Projetos** | Local workspace, file RAG, project-specific system prompts | Workspace local, RAG de arquivos, system prompts por projeto |
| **Code / Código** | Syntax highlighting, diff viewer, integrated terminal, Git status | Syntax highlighting, diff viewer, terminal integrado, Git status |
| **Agents / Agentes** | Web search, shell execution, file read/write | Busca na web, execução de shell, leitura/escrita de arquivos |
| **Voice / Voz** | Native dictation via SFSpeechRecognizer | Ditado nativo via SFSpeechRecognizer |
| **Multimodal** | Drag & drop and paste of images | Drag & drop e paste de imagens |
| **Artifacts** | Preview of HTML/React/SVG/Mermaid in split-screen | Preview de HTML/React/SVG/Mermaid em split-screen |

## Supported Providers

### English
- **OpenAI** (GPT-4o, GPT-4-turbo, GPT-3.5-turbo)
- **Anthropic** (Claude Opus, Sonnet, Haiku)
- **OpenAI-compatible** (vLLM, TGI, Ollama, LiteLLM, Portkey, any compatible endpoint)

### Português
- **OpenAI** (GPT-4o, GPT-4-turbo, GPT-3.5-turbo)
- **Anthropic** (Claude Opus, Sonnet, Haiku)
- **Compatível com OpenAI** (vLLM, TGI, Ollama, LiteLLM, Portkey, qualquer endpoint compatível)

## Installation / Instalação

### Direct Download / Download Direto

Download the latest `.dmg` from the [releases page](https://github.com/sbacaro/Lume/releases/latest).

Baixe o `.dmg` mais recente na [página de releases](https://github.com/sbacaro/Lume/releases/latest).

### Manual Build / Build Manual

**Prerequisites / Pré-requisitos:**
- macOS 14+
- Xcode 15+

```bash
git clone https://github.com/sbacaro/Lume.git
cd Lume
open Lume.xcodeproj
```

Select the **Lume** scheme and press ⌘R to run.

Selecione o scheme **Lume** e pressione ⌘R para rodar.

## How to Use / Como Usar

1. **English:**
   - Open the app and go to **Settings → Providers** to add your API key
   - In **Chat** mode, select your provider and model and start chatting
   - In **Cowork** mode, create a project linked to a local folder — Lume automatically indexes files for RAG
   - In **Code** mode, track Git status, view diffs, and run commands in the integrated terminal
   - Enable agents to let Lume search the web, read/write files, and execute shell commands

2. **Português:**
   - Abra o app e vá em **Settings → Providers** para adicionar sua chave de API
   - No modo **Chat**, selecione o provider e modelo desejado e comece a conversar
   - No modo **Cowork**, crie um projeto vinculado a uma pasta local — o Lume indexa os arquivos automaticamente para RAG
   - No modo **Code**, acompanhe o status do Git, veja diffs e execute comandos no terminal integrado
   - Ative agentes para que o Lume possa buscar na web, ler/escrever arquivos e executar shell commands

## Architecture / Arquitetura

```
Lume/
├── Lume.xcodeproj/
└── Lume/
    ├── AIGateway.swift          # Central provider gateway / Gateway central de providers
    ├── AgentOrchestrator.swift  # Agent orchestrator with step graph / Orquestrador de agentes com grafo de steps
    ├── RAGEngine.swift          # Semantic indexing and search (NLEmbedding) / Indexação e busca semântica (NLEmbedding)
    ├── ContextManager.swift     # Context compression and summarization / Compressão e sumarização de contexto
    ├── ModelRouter.swift        # Automatic routing by complexity / Roteamento automático por complexidade
    ├── WorkflowEngine.swift     # Workflow engine with conditionals and loops / Motor de workflows com condicionais e loops
    └── ...
```

## Roadmap

- [ ] Computer Use mode (screen control via Anthropic API) / Modo Computer Use (controle de tela via Anthropic API)
- [ ] Native spreadsheets / Planilhas nativas
- [ ] Artifact version history / Histórico de versões de artifacts
- [ ] Project export / Exportação de projetos
- [ ] Custom themes / Temas de cor customizáveis

## Contributing / Contribuindo

Pull requests are welcome. For major changes, please open an issue first to discuss what you would like to change.

Pull requests são bem-vindos. Para mudanças grandes, abra uma issue primeiro para discutir o que você quer alterar.

## License / Licença

[MIT](LICENSE)

---

## 🌟 Legacy Versions / Versões Legadas

### v1.0.0 (June 10, 2026)
Initial release with core features. / Lançamento inicial com funcionalidades principais.

### v1.0.1 (June 15, 2026) - **Current Version / Versão Atual**
Critical bug fixes and performance improvements. / Correções críticas de bugs e melhorias de desempenho.
- Fixed memory leaks in streaming / Corrigidos vazamentos de memória no streaming
- Enhanced thread safety / Segurança de threads aprimorada
- Improved error handling / Tratamento de erros melhorado
- Better overall stability / Melhor estabilidade geral

---

<p align="center">
  <strong>🎉 Thank you for using Lume! / Obrigado por usar Lume!</strong><br>
  <strong>✨ Made with ❤️ for mac</strong>
</p>