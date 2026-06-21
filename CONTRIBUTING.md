# Contributing to Lume

Thank you for your interest in contributing to Lume! We want to make it easy and rewarding to contribute.

---

## Code of Conduct

By participating in this project, you agree to abide by our [Code of Conduct](CODE_OF_CONDUCT.md). Please report any unacceptable behavior to the project maintainers.

---

## Development Setup

### Requirements
* **macOS 15.0+**
* **Xcode 16.0+** (with Swift 6.0 compiler support)
* **Cocoapods / SPM** (Dependencies are managed directly via Swift Package Manager inside the Xcode project)

### Getting the Code
1. Fork the repository on GitHub.
2. Clone your fork locally:
   ```bash
   git clone https://github.com/<your-username>/Lume.git
   cd Lume
   ```
3. Open `Lume.xcodeproj` in Xcode.

---

## Project structure

App source lives under `Lume/`, grouped by responsibility (`App/`, `Models/`, `AI/`,
`RAG/`, `MCP/`, `Agent/`, `Services/`, `Updates/`, `DesignSystem/`, `Views/`). The Xcode
project uses **file-system synchronized groups**, so a new `.swift` file placed in the
right folder is compiled automatically — there's no need to edit the `.xcodeproj`. Please
add new files to the folder that matches their responsibility.

Build/release tooling lives in `scripts/`, and longer-form docs live in `docs/` (start with
[docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)).

---

## Code Style & Standards

Lume is a modern macOS application built entirely on Swift 6. We enforce strict programming guidelines to maintain safety, scalability, and performance:

* **Swift 6 Strict Concurrency:** The project compiles with `SWIFT_STRICT_CONCURRENCY = complete` in all targets. Any code crossing concurrency boundaries must conform to `Sendable` or be correctly isolated using actors or the `@MainActor` attribute.
* **No Unchecked Force Unwraps:** Do not use `!` on optionals unless it is a static resource or preview that is guaranteed never to fail. For system directories, Keychain lookups, or user settings, always use safe optionals or structured fallbacks (e.g., using `temporaryDirectory` if Application Support is unavailable).
* **Property Wrappers in SwiftUI:** Avoid using `@State` for sharing ObservableObject classes. Use `@ObservedObject` or modern observation (`@Observable` class instances passed via standard parameters or `@State` if initialized inside the view itself).
* **Maintain Comments:** Do not delete existing comments unless they are obsolete. Document any non-obvious architecture decisions or tricky workarounds (like the Rosetta warning fixes or custom Sparkle signatures).

---

## Testing

Lume contains a robust suite of unit tests verifying LLM routing decisions, cost estimations, RAG engines, and MCP integration.

* **Swift Testing Framework:** All unit tests are built using Swift's native `import Testing` framework.
* **Running Tests:**
  * In Xcode: Select the **Lume** scheme and press `⌘U`.
  * In the Terminal:
    ```bash
    xcodebuild test -scheme Lume -destination 'platform=macOS'
    ```
* **Adding Tests:** When adding new features or fixing critical bugs, ensure you add corresponding unit tests in the `LumeTests/` directory.

---

## Contribution Workflow

1. **Create a branch:** Use descriptive names like `feature/mcp-connector` or `fix/crash-keychain`.
2. **Implement changes:** Keep changes focused on a single issue or feature.
3. **Validate:** Build the project cleanly (without warnings) and verify all unit tests pass.
4. **Commit:** Write clear, concise commit messages.
5. **Open a Pull Request:** Submit your PR against the `main` branch of the upstream repository. Fill out the PR template completely.
