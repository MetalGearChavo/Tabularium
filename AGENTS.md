# Tabularium – Agent Instructions

This project's source of truth lives in two living documents at the repo root. **Read both before doing any work:**

1. [`claude.md`](./claude.md) – overview, stack, core concepts, architecture, AI layer, import-pipeline lessons, design, and notes.
2. [`swift-standards.md`](./swift-standards.md) – folder structure, naming, MVVM, Realm conventions, Swift best practices. Read it before writing any Swift code.

## Key rules (summarized from `claude.md`)

- **Spec-driven / TDD**: for any new logic or bug fix, write a failing test first (Swift Testing: `import Testing`, `@Test`, `#expect`, target `TabulariumTests`), then the minimum code to pass, then refactor. Not required for plain SwiftUI layout.
- **Testability**: prefer injected dependencies (protocol over `URLSession`, in-memory Realm config) over singletons; refactor `RealmService.shared` / `LLMService.shared` as you touch them.
- **Teach-style comments**: the owner is new to Swift. Add `///` doc comments on every type and non-trivial function (mention its MVVM layer) and inline `//` comments explaining Swift/SwiftUI concepts on first use in a file. Explain the *why*. No commented-out code.
- **Realm**: Realm objects must never cross an `await`; use plain snapshots (e.g. `CategoryOption`). Bump `schemaVersion` in `RealmService.swift` on any model change.
- **Living documents**: after any change affecting them (model/schema, new file/folder/screen, renamed service, entitlement change), update `claude.md` / `swift-standards.md` in the same pass.
- **Design**: Phase 1 is a functional, terminal-style UI (dark, SF Mono, minimal chrome). No polish or animations.
- Building requires Xcode; verify UI changes by running the app.
