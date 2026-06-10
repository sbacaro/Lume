<p align="center">
  <img src="Lume/Assets.xcassets/AppIcon.appiconset/icon_256x256.png" width="128" alt="Lume">
</p>

<h1 align="center">Lume</h1>

<p align="center">
  Cliente nativo de IA para macOS — chat, projetos, código e agentes em um só lugar.
</p>

<p align="center">
  <img src="https://img.shields.io/badge/macOS-14%2B-blue" alt="macOS 14+">
  <img src="https://img.shields.io/badge/Swift-5.9%2B-orange" alt="Swift 5.9+">
  <img src="https://img.shields.io/badge/license-MIT-green" alt="MIT">
</p>

---

## Funcionalidades

| Categoria | Funcionalidade |
|---|---|
| **Chat** | Streaming em tempo real, múltiplos providers, seletor de modelo |
| **Projetos** | Workspace local, RAG de arquivos, system prompts por projeto |
| **Código** | Syntax highlighting, diff viewer, terminal integrado, Git status |
| **Agentes** | Busca na web, execução de shell, leitura/escrita de arquivos |
| **Voz** | Ditado nativo via SFSpeechRecognizer |
| **Multimodal** | Drag & drop e paste de imagens |
| **Artifacts** | Preview de HTML/React/SVG/Mermaid em split-screen |

## Providers suportados

- **OpenAI** (GPT-4o, GPT-4-turbo, GPT-3.5-turbo)
- **Anthropic** (Claude Opus, Sonnet, Haiku)
- **OpenAI-compatible** (vLLM, TGI, Ollama, LiteLLM, Portkey, qualquer endpoint)

## Instalação

### Download direto

Baixe o `.dmg` mais recente na [página de releases](https://github.com/sbacaro/Lume/releases/latest).

### Build manual

**Pré-requisitos:**
- macOS 14+
- Xcode 15+

```bash
git clone https://github.com/sbacaro/Lume.git
cd Lume
open Lume.xcodeproj
```

Selecione o scheme **Lume** e pressione ⌘R para rodar.

## Como usar

1. Abra o app e vá em **Settings → Providers** para adicionar sua chave de API
2. No modo **Chat**, selecione o provider e modelo desejado e comece a conversar
3. No modo **Cowork**, crie um projeto vinculado a uma pasta local — o Lume indexa os arquivos automaticamente para RAG
4. No modo **Code**, acompanhe o status do Git, veja diffs e execute comandos no terminal integrado
5. Ative agentes para que o Lume possa buscar na web, ler/escrever arquivos e executar shell commands

## Arquitetura

```
Lume/
├── Lume.xcodeproj/
└── Lume/
    ├── AIGateway.swift          # Gateway central de providers
    ├── AgentOrchestrator.swift  # Orquestrador de agentes com grafo de steps
    ├── RAGEngine.swift          # Indexação e busca semântica (NLEmbedding)
    ├── ContextManager.swift     # Compressão e sumarização de contexto
    ├── ModelRouter.swift        # Roteamento automático por complexidade
    ├── WorkflowEngine.swift     # Motor de workflows com condicionais e loops
    └── ...
```

## Roadmap

- [ ] Modo Computer Use (controle de tela via Anthropic API)
- [ ] Planilhas nativas
- [ ] Histórico de versões de artifacts
- [ ] Exportação de projetos
- [ ] Temas de cor customizáveis

## Contribuindo

Pull requests são bem-vindos. Para mudanças grandes, abra uma issue primeiro para discutir o que você quer alterar.

## Licença

[MIT](LICENSE)
