# Tabularium

## Overview
AI-powered personal expense tracker. Mac desktop app, local-first, built for one user before scaling to cloud.

## Standards
See `swift-standards.md` for folder structure, naming conventions, MVVM pattern, Realm conventions, and Swift best practices. Read it before writing any Swift code.

## Code Documentation
The owner is new to Swift. Whenever you write or edit code, comment it to teach, not just to label:
- Add a `///` doc comment on every type and non-trivial function explaining what it is and why it exists (including its MVVM layer when relevant: Model / Service / ViewModel / View).
- Add inline `//` comments explaining Swift/SwiftUI concepts as they appear the first time in a file — e.g. optionals (`?`, `if let`, `guard let`, `??`), property wrappers (`@State`, `@StateObject`, `@ObservedObject`, `@Binding`, `@Published`, `@AppStorage`, `@Persisted`), generics, closures, `$` bindings, `map`/`filter`/`reduce`, view modifiers.
- Explain the *why* behind non-obvious choices, not just the *what*. Skip narrating self-evident lines.
- Keep this style consistent with the existing files (see `DashboardView.swift`, `DashboardViewModel.swift`, `RealmService.swift` as references).
- This complements `swift-standards.md` ("No commented-out code" still applies — use git history; these are explanatory comments, not dead code).

## Stack
- **UI**: SwiftUI (native Mac)
- **Database**: Realm (local NoSQL, document-based)
- **PDF Parsing**: PDFKit (Apple built-in)
- **AI**: Ollama (local, OpenAI-compatible API)
- **Language**: Swift

## Core Concepts
- **Accounts**: User-defined. Any number of credit cards (or debit cards in the future). Each account has a name, last 4 digits, and type (credit/debit).
- **Classifications**: User-defined groups for splitting expenses (e.g. Conjunto, Individual — but the user decides the labels and how many). Not hardcoded.
- **Categories**: User-defined. Created on first launch, editable at any time (add/remove/rename). AI uses whatever categories the user has defined — no hardcoded list.

## MVP Scope (Phase 1)
1. Import a BBVA PDF bank statement
2. PDFKit extracts raw text
3. Claude API parses transactions + assigns category + Conjunto/Individual
4. Review screen — see all transactions, correct any mistakes
5. Save to local Realm database
6. Simple dashboard — totals by category, month summary

## Data Models

### Card
- id: String (UUID)
- name: String (e.g. "BBVA Platinum")
- lastFour: String
- type: String (credit | debit)
- bank: String

### Statement
- id: String (UUID)
- cardId: String
- periodStart: Date
- periodEnd: Date
- importedAt: Date
- transactions: List<Transaction>

### Transaction
- id: String (UUID)
- statementId: String
- date: Date
- amount: Double
- description: String
- categoryId: String
- reviewed: Bool

### Category
- id: String (UUID)
- name: String
- emoji: String


## App Screens (MVP)
1. **Onboarding** — first launch only: add cards, create categories
2. **Dashboard** — per-card dashboard, monthly summary, breakdown by category
3. **Import** — drag & drop PDF, Ollama parses, review transactions inline before saving
4. **Settings** — debug dump, reset onboarding, manage categories and cards

## AI Layer
- **Beta (local)**: Ollama running on Mac — `qwen2.5:3b` or `llama3.2:3b`
- **Production**: Ollama or vLLM on EC2 — swap base URL only, code stays the same
- API is OpenAI-compatible: `http://localhost:11434/v1` locally → EC2 URL in prod
- Categorization is a simple task, 3B models are more than enough

## Phase 2 (after beta)
- Budget alerts
- Multi-bank support
- Google Sheets sync
- iCloud backup
- AWS / cloud sync via Realm Atlas Device Sync
- Swap Ollama local → EC2 hosted model

## Design
- Functional terminal-looking UI for now — this is a personal tool, aesthetics come later
- Dark background, SF Mono font, minimal chrome
- No fancy animations or polish in Phase 1
- Design system and visual refinement deferred to Phase 2

## Notes
- Current Google Sheet: `10XeOhFNaydh7KUwoyBKrM48WSFw9NttgHMoj-_V_y0o` (reference for category structure)
- BBVA Platinum is the primary card being tracked
- Xcode required — install from App Store before building
