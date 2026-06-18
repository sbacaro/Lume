# Plano de Execução — Testes + Swift 6

Branch: `swift6-and-tests`

## Objetivo

Estabelecer uma rede de testes nas partes críticas de lógica pura e, em cima dela,
migrar o projeto para o Swift 6 language mode com strict concurrency `complete` —
sem regressões visíveis ao usuário.

## Estado atual (verificado)

- `SWIFT_VERSION = 5.0` em todos os targets (o README anuncia Swift 6, mas a config não reflete isso).
- `SWIFT_STRICT_CONCURRENCY = minimal`.
- Já configurado (favorável): `SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` e `SWIFT_APPROACHABLE_CONCURRENCY = YES` no target app.
- Testes: framework Swift Testing (`import Testing`), mas só um teste de exemplo vazio (~97 linhas no total entre unit e UI).
- `LumeTests/` e `LumeUITests/` são grupos sincronizados (`PBXFileSystemSynchronizedRootGroup`): arquivos `.swift` novos nessas pastas entram no target automaticamente, sem editar o `.xcodeproj`.

## Restrição de ambiente

O assistente não compila Swift (sandbox Linux, sem Xcode). O ciclo de migração é:
assistente edita config/código → **você builda no Xcode** → reporta erros → assistente corrige.
Os testes são escritos contra assinaturas reais já lidas no código.

## Fases

### Fase 0 — Baseline ✅
- Branch `swift6-and-tests` criada a partir de `main` (limpo).
- Este documento.

### Fase 1 — Testes primeiro (rede de segurança)
Cobrir unidades determinísticas e sem dependência de rede/UI/SwiftData de escrita:

| Arquivo de teste | Cobre | Por quê |
|---|---|---|
| `LLMRouterTests.swift` | route, analyzeComplexity, isCodeRelated, containsMath, estimateTokens, bareModelName, inferProvider, costTier, multimodalModel, maxContextWindow | Núcleo do roteamento — alto risco de regressão |
| `ModelPricingTests.swift` | price (exato/prefixo/heurística), estimatedCost, formatCost, formatTokens | Cálculo de custo exibido na UI |
| `ModelCapabilitiesTests.swift` | supportsVision (com/sem visão, desconhecido) | Decide envio de imagem vs OCR local |
| `ArtifactDetectorTests.swift` | detect, hasArtifact, extração de título | Detecção de artifacts no markdown |
| `JSONValueTests.swift` | round-trip Codable, acessores, subscripts | Base de tool-calling/JSON |

Critério de saída: suite compila e passa verde no Xcode (⌘U).

### Fase 2 — Strict concurrency incremental
1. `SWIFT_STRICT_CONCURRENCY = minimal → targeted`. Build. Corrigir.
2. `targeted → complete`. Build. Corrigir.

Focos prováveis de erro (a confirmar no build):
- Tipos cruzando fronteiras de concorrência sem `Sendable` (modelos, callbacks de provider).
- `SSEParser` (callbacks `((SSEEvent) -> Void)?` + delegate URLSession) — provável `@unchecked Sendable` ou isolamento explícito.
- Singletons `static let shared` (`MCPManager`, etc.) — exigem `Sendable`/isolamento.
- `nonisolated(unsafe)` já usado em `RAGEngine` (auditar se ainda é necessário).

### Fase 3 — Swift 6 language mode
3. `SWIFT_VERSION = 5.0 → 6.0` em todos os targets (app, LumeTests, LumeUITests). Build.
4. Corrigir erros remanescentes (em modo Swift 6 os warnings de concorrência viram erros).

Critério de saída: build verde em todos os targets + suite de testes passando + smoke test manual (Chat streaming, Cowork/RAG, Code).

### Fase 4 — Acabamento
- Deletar `ModelRouter.swift` (marcado como obsoleto no próprio arquivo).
- Atualizar README/CHANGELOG para refletir Swift 6 real.

## Como rodar os testes
No Xcode: selecione o scheme **Lume** e ⌘U. Ou via terminal:
```bash
xcodebuild test -scheme Lume -destination 'platform=macOS'
```
