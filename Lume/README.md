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
  <img src="https://img.shields.io/badge/license-GPLv3-green" alt="GPLv3">
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
Baixe o `.dmg` mais recente na [página de releases](../../releases/latest).

### Build manual

**Pré-requisitos:**
- macOS 14+
- Xcode 15+

```bash
git clone https://github.com/samuelbacaro/Lume.git
cd Lume
open Lume.xcodeproj
