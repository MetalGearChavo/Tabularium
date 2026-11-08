# Tabularium

## Overview
AI-powered personal expense tracker. Mac desktop app, local-first, built for one user before scaling to cloud.

## Living Documents
`CLAUDE.md` and `swift-standards.md` are **living documents** — they must stay in sync with the
code. After any change that affects them (a new/changed model field or schema version, a new
file or folder, a new screen/feature, a renamed service, a changed entitlement, etc.), update the
relevant doc in the same pass. Treat them as out of date until you've reconciled them with reality.

## Standards
See `swift-standards.md` for folder structure, naming conventions, MVVM pattern, Realm conventions, and Swift best practices. Read it before writing any Swift code.

## Development Process
This project follows **spec-driven development / TDD**: for any new logic, write a failing
test first, then write the minimum code to make it pass, then refactor if needed. Same for
bug fixes — write a test that reproduces the bug (red) before fixing it (green).
- Applies to anything with real logic: ViewModel methods, Services (`RealmService`,
  `LLMService`, `PDFService`), Extensions, parsing/formatting/date-math (e.g. `billingPeriod`,
  CSV escaping, category matching).
- Does NOT apply to plain SwiftUI `View` layout/styling — there's no meaningful failing test
  for "this button is on the left." Verify those by running the app, not TDD.
- Test target: `TabulariumTests` (Swift Testing — `import Testing`, `@Test`, `#expect`).
- Services that hit the network or Realm need to be testable in isolation: prefer injecting
  dependencies (e.g. a protocol over `URLSession`, an in-memory Realm configuration) over
  hardcoded singletons, so tests don't require a live Ollama instance or touch the real local
  database. Existing services (`RealmService.shared`, `LLMService.shared`) predate this rule
  and aren't yet structured this way — refactor them for testability as they're touched,
  rather than all at once.

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
- **Categories**: User-defined. Created on first launch, editable at any time (add/remove/rename). AI uses whatever categories the user has defined — no hardcoded list.
- **Transactions**: Each transaction has a date, amount, description, and category.
- **Review**: After AI parsing, user can review and correct transactions before saving.
- **Monthly installments**: If a transaction has been split in months it will be shown as month n of m in the billing cycle.

## MVP Scope (Phase 1)
1. Drag & drop a PDF bank statement ("estado de cuenta") onto the Dashboard — any bank
2. PDFKit extracts raw text (falls back to on-device Vision OCR for scanned/image-only PDFs)
3. Ollama (local LLM) parses transactions + assigns category
4. Review screen — see all transactions, correct any mistakes
5. Save to local Realm database
6. Simple dashboard — totals by category, month summary

## Current Status (implemented)
What actually exists in the code today:
- **Onboarding**: add cards (name, bank, last 4, type, fecha de corte) + create categories.
- **Manual entry**: add / edit / delete transactions, including monthly installments (MSI).
- **Dashboard** (per card):
  - Period selector: **billing cycle (fecha de corte) or calendar month**, with ◀ ▶ nav.
  - **List / Chart** toggle. List groups by day (collapsible); Chart shows a per-category
    breakdown with % + bar, and each category expands to its charges.
  - Running total; tap any charge to edit.
  - **Drag & drop PDF import**: drop a statement onto the transaction list → `PDFService`
    extracts text → `StatementTextFilter` strips non-transaction noise → `StatementChunker`
    splits it into small batches → `LLMService` (Ollama) parses + categorizes each batch →
    `ReviewView` lets the user correct dates/amounts/categories or drop false positives →
    Save All writes a `Statement` + its `Transaction`s to Realm.
- **CSV export** of the current period (no AI).
- **Settings**: cards CRUD (delete cascades the card's transactions, with confirmation),
  categories CRUD, LLM connection status (live, with a manual recheck), reset onboarding.
- **LLM connection light** in the sidebar footer and Settings — pings the backend's
  `/models` endpoint on appear (`LLMConnectionMonitor`).

## Data Models

### Card
- id: String (UUID)
- name: String (e.g. "BBVA Platinum")
- lastFour: String
- type: String (credit | debit)
- bank: String
- closingDay: Int — statement closing day / fecha de corte (1–31; 0 = none, e.g. debit)

### Statement
- id: String (UUID)
- cardId: String
- periodStart: Date
- periodEnd: Date
- importedAt: Date
- transactions: List<Transaction>
- (model exists but isn't created yet — statements come with the import flow)

### Transaction
- id: String (UUID)
- statementId: String
- cardId: String
- date: Date
- amount: Double — the FULL price (for an MSI purchase, the monthly part is amount ÷ installments)
- transactionDescription: String — named this way to avoid shadowing Realm's `Object.description`
- categoryId: String
- reviewed: Bool
- installments: Int — 1 = single charge; N ≥ 2 = monthly installments (MSI)

### Category
- id: String (UUID)
- name: String
- emoji: String

### MerchantAlias
- id: String (UUID)
- pattern: String — matched case-insensitively as a substring of a raw transaction
  description (e.g. "UBER" matches "DLO*UBER RIDES ; Tarjeta Digital ***9171")
- displayName: String — clean name shown instead (e.g. "Uber")
- categoryId: String — default category to apply; "" = rewrite the name only,
  leave whatever category the AI assigned alone
- User-managed in Settings → "Merchant Names"; applied automatically to every
  import by `MerchantAliasMatcher`, after the LLM parses but before Review opens.


## App Screens
1. **Onboarding** — first launch only: add cards (incl. fecha de corte), create categories
2. **Dashboard** — per-card; billing-cycle/month selector, List/Chart toggle, breakdown by
   category, collapsible day groups, CSV export, add/edit/delete transactions (incl. MSI),
   drag & drop PDF import → review → save
3. **Review** — shown as a sheet after a successful import; edit/delete parsed rows, pick
   the target card, Save All
4. **Settings** — cards & categories CRUD, merchant name rules CRUD (pattern → clean
   name + default category, applied automatically on import), LLM connection status +
   editable base URL/model (`llmBaseURL`/`llmModel`, takes effect on the next import —
   no restart), reset onboarding
- The sidebar nav (`ContentView`) lists Dashboard + Settings, with an LLM connection light
  pinned to its footer. Import has no separate nav item — it's triggered by dropping a PDF
  directly onto the Dashboard. `Views/Import/ImportView.swift` is an unused placeholder.

## AI Layer
- **Beta (local)**: Ollama running on Mac. Real-world testing (see "Import pipeline lessons"
  below) showed 3B models (`llama3.2`) can't reliably do full statement extraction — `qwen2.5:7b`
  is the current working default. Switchable in Settings → LLM without recompiling.
- **Production**: Ollama or vLLM on EC2 — swap base URL only, code stays the same.
- API is OpenAI-compatible: `http://localhost:11434/v1` locally → EC2 URL in prod.
- Base URL + model are read from `UserDefaults` keys `llmBaseURL` / `llmModel`, defaulting to
  the local Ollama setup in `LLMService`, so the backend is swappable without recompiling —
  editable directly in Settings → LLM (takes effect on the next import).
- The LLM's instructions ("its CLAUDE.md") live in `Tabularium/AI/import_prompt.md`, a bundled
  resource loaded at runtime with `{{TODAY}}` and `{{CATEGORIES}}` injected per request. The
  prompt is bank-agnostic: it works from raw extracted text, not a fixed column layout, so it
  handles any bank's statement without per-bank code.
- `Tabularium/AI/LLMConnection.swift` models the connection status; `LLMConnectionMonitor`
  (same file) pings `LLMService.checkConnection()` and publishes it for the sidebar badge and
  Settings.
- `Tabularium/Services/PDFService.swift` extracts statement text: `PDFKit` reads the text
  layer directly (the common case — nearly all bank e-statements are digitally generated);
  if a page has no usable text layer (a scanned/photographed statement), it falls back to
  on-device OCR via Apple's **Vision** framework (`VNRecognizeTextRequest`) — a classical,
  local, free text-recognition engine, NOT an LLM/vision model. No model download needed.
- `Tabularium/AI/StatementTextFilter.swift` keeps only lines with a currency symbol before
  the LLM ever sees the text — strips marketing copy, legal notes, a loyalty-points ledger,
  and (for BBVA) a CFDI tax-invoice annex, all of which a small model can mistake for the
  data to extract.
- `Tabularium/AI/StatementChunker.swift` splits the filtered text into ~12-line batches, one
  LLM call per batch — see "Import pipeline lessons" below for why.
- `Tabularium/AI/CategoryOption.swift` is a plain, thread-safe snapshot of `Category` (see
  swift-standards.md → "Realm Conventions" for why this exists).
- `Tabularium/AI/MerchantAliasMatcher.swift` rewrites a parsed transaction's description
  (and optionally its category) using `MerchantAlias` rules the user has taught in Settings —
  runs after the LLM parses each chunk, before Review opens, so recurring merchants ("DLO*UBER
  RIDES ; Tarjeta Digital ***9171" → "Uber") don't need re-fixing on every import.

### Import pipeline lessons (from real debugging, not speculation)
Real-world testing against an actual BBVA statement surfaced failure modes worth knowing
before touching this code again:
- **A local model asked to extract from a long, noisy document will latch onto whatever
  "clean-looking" structured data it can find** — it mirrored a loyalty-points table, then a
  CFDI annex, before `StatementTextFilter` removed both. Assume any noise left in the input
  is a candidate for this, not just prose.
- **A model will invent its own JSON shape despite explicit schema instructions** — it kept
  wrapping two-date rows (purchase + posting date) in a `date_range`/`dateRange` object
  instead of picking one `date` string, in multiple casings, across many prompt rewrites.
  `LLMService`'s `Item` decoder tolerates this instead of continuing to fight it in the prompt.
  Prompt engineering has a real ceiling here — don't expect one more rewrite to fix a
  structural quirk like this.
- **A model's reply can be complete, valid JSON, and still silently incomplete** — given
  ~50 transactions in one call, it produced perfectly-shaped JSON covering only the first ~25
  before stopping (with a repeated entry right before it gave up — a tell that it lost its
  place). This is why `StatementChunker` exists: smaller batches are a track-fewer-items task
  the model can actually complete reliably, not a shape problem `LLMService` can absorb.
- **Realm objects must never cross an `await`** — see swift-standards.md → "Realm Conventions".
  This caused a real Realm thread-verification crash the first time the import pipeline ran.
- Debugging a bad LLM response: `LLMService.debugDump` always writes the raw response to
  `tabularium_llm_response.txt` in the app's sandbox temp directory (path included in any
  `.invalidJSON` error message) — read it directly rather than guessing from a truncated alert.

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
- BBVA Platinum is the primary card being tracked, but the import prompt is bank-agnostic
  by design (see AI Layer) — other banks' statements should parse without code changes
- Xcode required — install from App Store before building
- **Realm schema versions** (`RealmService.swift`, bump `schemaVersion` on any model change):
  - v1 — added `Card.closingDay`
  - v2 — added `Transaction.installments`
- **Sandbox entitlements** (`Tabularium.entitlements`): app-sandbox, user-selected file
  read-write (CSV export / future import), and network client (for the local LLM).
- Billing-cycle rule: installment/period math treats the **fecha de corte as the FIRST day**
  of the cycle (corte 21 → period 21st through 20th of next month). See `Date.billingPeriod`.
