# Architecture

This document describes how Lume is organized and how a request flows through the app.
It complements the high-level overview in the [README](../README.md).

Lume is a native macOS SwiftUI application built on Swift 6 with strict concurrency. It has
**one chat engine** that is exposed through **three modes** (Chat, Cowork, Code), each of
which gates a different set of tools and shows a tailored start screen.

## Source layout

The app source lives under `Lume/`, grouped by responsibility. The Xcode project uses
**file-system synchronized groups**, so the folder structure on disk *is* the project
structure — adding or moving a `.swift` file inside `Lume/` is picked up automatically,
with no `.xcodeproj` edits required.

| Folder | Responsibility |
|---|---|
| `App/` | App entry point (`LumeApp`), root navigation shell (`ContentView`), and global configuration (`LumeConfig`). |
| `Models/` | SwiftData `@Model` types (`Project`, `Conversation`, `Message`, `Artifact`, `AIProviderConfig`, `StyleProfile`, `Workflow`, `ScheduledTask`, `MCPConnector`) and shared value types (`JSONValue`, `LumeTypes`, `Transcription`). |
| `AI/Providers/` | Provider adapters (`AnthropicProvider`, `OpenAIProvider`), the streaming/orchestration layer (`AIProviderManager`), the `AIProvider` protocol, the unifying `AIGateway`, and typed errors. |
| `AI/Routing/` | Complexity-based model routing (`LLMRouter`) plus `ModelCapabilities` and `ModelPricing` tables. |
| `AI/Context/` | Context-window budgeting and trimming (`ContextManager`), summarization-based compression (`ContextCompressor`), and the prompt/semantic caches. |
| `AI/OnDevice/` | Apple Foundation Models integrations that run locally and offline: complexity scoring, context summarization, and conversation titling. |
| `RAG/` | File indexing and retrieval (`RAGEngine`) and ingestion of dropped/linked files (`FileIngestionManager`). |
| `MCP/` | Model Context Protocol JSON-RPC client (`MCPClient`, stdio + HTTP) and the persisted connector model wiring (`MCPConnector`). |
| `Agent/` | The tool protocol, registry and per-mode gating (`AgentTool`), execution with approval (`AgentToolExecutor`), and orchestration (`AgentOrchestrator`, `WorkflowEngine`, `ApprovalCoordinator`). `Agent/Tools/` holds the built-in tools. |
| `Services/` | Cross-cutting infrastructure: Keychain, Git, shell, terminal session, project management, theming, speech/dictation, scheduling, agent memory, conversation export, vision OCR, and error logging. |
| `Updates/` | The Sparkle integration (`SparkleUpdater`), the no-Developer-ID in-app `SelfUpdater`, the `UpdateManager` that coordinates them, and the update notification UI. |
| `DesignSystem/` | Brand colors and typography (`LumeBrand`, `LumeTheme`), button styles, and programmatic app-icon rendering/export. |
| `Views/` | All SwiftUI surfaces, sub-grouped into `Chat/`, `Settings/`, `Onboarding/`, `Markdown/`, and reusable `Components/`. Mode dashboards and project sheets sit at the `Views/` root. |

## The three modes

Lume reuses a single chat engine and differentiates behavior by which tools are offered
to the model and which start screen is shown.

- **Chat** — pure conversation. Web search only; no file or shell access.
- **Cowork** — automating work over a project's files. Read/write files, run code in a
  sandbox, use MCP connectors, create documents, and track tasks.
- **Code** — agentic software engineering in a repository. Shell, file editing, and Git
  on top of everything Cowork can do, with command output surfaced in the conversation.

Switching modes returns to that mode's start screen; the inspector and the capability
strip above the input reflect the active mode. Tool gating is enforced centrally in the
`Agent/` layer so a mode can never call a tool it should not have.

## Request flow

A user message flows roughly as follows:

1. **UI** — a `Views/Chat/` surface captures the message and any attachments and hands it
   to the engine.
2. **Routing** — `AI/Routing/LLMRouter` may pick a model based on estimated complexity
   (optionally scored on-device via `AI/OnDevice/`), falling back to the API model.
3. **Context assembly** — `AI/Context/ContextManager` builds the prompt within the model's
   real token budget, pulling RAG citations from `RAG/RAGEngine` when a project is linked
   and compressing/summarizing older turns when needed.
4. **Provider call** — `AI/Providers/AIProviderManager` streams the request through the
   active provider adapter (`AnthropicProvider` / `OpenAIProvider`).
5. **Tool use** — when the model calls a tool, `Agent/AgentToolExecutor` runs it (subject
   to per-mode gating and an approval step), including MCP tools via `MCP/MCPClient`.
6. **Streaming back** — tokens and structured tool blocks stream back to the UI and are
   rendered (Markdown, artifacts, tool-call cards) as they arrive.

## Persistence

State is stored with **SwiftData**. The schema is declared in `App/LumeApp.swift` and
includes `Project`, `Conversation`, `Message`, `Artifact`, `AIProviderConfig`,
`StyleProfile`, `MCPConnector`, `ScheduledTask`, and `Workflow`. Secrets such as API keys
are kept in the **Keychain** (`Services/KeychainManager`), never in the SwiftData store.
The RAG index is cached on disk and invalidated by content hash.

## Concurrency

The project compiles with `SWIFT_STRICT_CONCURRENCY = complete`. UI and SwiftData access
are isolated to the `@MainActor`; work that crosses concurrency boundaries either conforms
to `Sendable` or is funneled through an owning actor. SwiftData model objects are **not**
`Sendable` — a single task owns them and shared state is exchanged through `@MainActor`
objects rather than by passing models across tasks.

## Versioning & updates

`Version.xcconfig` at the repo root is the single source of truth for the marketing
version and the monotonic build number; the app, About screen, and release scripts all
read from it. Releases are produced by `scripts/release.sh`, which builds the app, packages
a DMG, and generates/signs the Sparkle `appcast.xml` (EdDSA). See
[SPARKLE_SETUP.md](SPARKLE_SETUP.md) for the signing setup.

Two independent update paths exist: the standard **Sparkle** updater, and a
**self-updater** that downloads the DMG, verifies an Ed25519 signature, swaps the `.app`,
and clears quarantine — used when shipping without a Developer ID.
