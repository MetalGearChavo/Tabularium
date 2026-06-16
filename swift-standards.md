# Swift Standards & Best Practices

---

## Folder Structure

```
Tabularium/
├── TabulariumApp.swift               # @main entry point
├── ContentView.swift                 # root navigation shell
│
├── Models/                           # Realm objects — pure data, no logic
│   ├── Account.swift
│   ├── Statement.swift
│   ├── Transaction.swift
│   ├── Category.swift
│   └── Classification.swift
│
├── ViewModels/                       # Business logic, coordinates Models and Services
│   ├── DashboardViewModel.swift
│   ├── ImportViewModel.swift
│   └── ReviewViewModel.swift
│
├── Views/                            # SwiftUI views, one per screen
│   ├── Dashboard/
│   │   └── DashboardView.swift
│   ├── Import/
│   │   └── ImportView.swift
│   ├── Review/
│   │   └── ReviewView.swift
│   ├── Onboarding/
│   │   └── OnboardingView.swift
│   └── Settings/
│       └── SettingsView.swift
│
├── Services/                         # External integrations — no UI, no ViewModels
│   ├── RealmService.swift            # All Realm reads and writes
│   ├── PDFService.swift              # PDFKit text extraction
│   └── OllamaService.swift           # HTTP calls to Ollama API
│
├── Components/                       # Reusable SwiftUI pieces used across views
│   └── TransactionRow.swift
│
└── Extensions/                       # Swift extensions on built-in types
    ├── Date+Formatting.swift
    └── Double+Currency.swift
```

### Layer responsibilities

**Models** are Realm database objects. They define what gets stored and in what shape. No logic, no networking, no formatting — just data and its relationships.

**Services** are the lowest layer. Each service knows how to talk to exactly one external thing:
- `RealmService` — opens the database, reads, writes, deletes
- `PDFService` — takes a file URL, returns raw extracted text using PDFKit
- `OllamaService` — sends HTTP requests to `localhost:11434`, returns categorized results

Services have no knowledge of ViewModels or Views.

**ViewModels** are where all the work happens. They call services to get or save data, run business logic (which transactions need review, what the monthly total is), and expose clean `@Published` state that Views read. A ViewModel never imports SwiftUI — it only knows about data and services.

**Views** are pure UI. They read from a ViewModel via `@StateObject` or `@ObservedObject` and call methods on it when the user taps something. Views never talk to Realm or Ollama directly.

**Components** are small reusable SwiftUI views — things like a single transaction row that appears in multiple screens.

**Extensions** add helper methods to built-in Swift types. `Date+Formatting.swift` adds things like `.monthYearString`. `Double+Currency.swift` formats amounts as "$1,234.56". Named `Type+Functionality.swift` by convention.

### Data flow rule

Data flows **down**: ViewModel → View. Events flow **up**: View calls a method on its ViewModel. A View never modifies data directly — it tells the ViewModel what happened and the ViewModel decides what to do.

---

## Naming Conventions

### Types
- `PascalCase` for all types: classes, structs, enums, protocols, typealiases
- File name must match the type it contains: `Transaction.swift` contains `Transaction`

```swift
struct Transaction { }
class OllamaService { }
enum TransactionState { }
protocol Parseable { }
typealias TransactionID = String
```

### Variables & Functions
- `camelCase` for variables, constants, functions, parameters
- No abbreviations — prefer clarity over brevity

```swift
let transactionAmount: Double
var isReviewed: Bool
func parseTransactions(from url: URL) -> [Transaction]
```

### Constants
- `camelCase`, never `ALL_CAPS`
- Group in enums for namespacing

```swift
enum Constants {
    enum API {
        static let baseURL = "http://localhost:11434"
        static let timeout: TimeInterval = 30
    }
}
```

### Enums
- Type `PascalCase`, cases `camelCase`

```swift
enum AccountType {
    case credit
    case debit
}
```

### Protocols
- Named as capabilities or nouns, `PascalCase`

```swift
protocol Parseable { func parse() -> [Transaction] }
protocol TransactionStore { }
```

---

## Architecture — MVVM

Standard for SwiftUI apps.

- **Model** — data and business rules (Realm objects)
- **View** — UI only, no logic
- **ViewModel** — state management, business logic, coordinates Model → View

```swift
// Model
class Transaction: Object {
    @Persisted(primaryKey: true) var id: String = UUID().uuidString
    @Persisted var amount: Double = 0.0
}

// ViewModel
@MainActor
class TransactionViewModel: ObservableObject {
    @Published var transactions: [Transaction] = []
    @Published var isLoading: Bool = false

    func load() async {
        isLoading = true
        // fetch from Realm
        isLoading = false
    }
}

// View
struct TransactionListView: View {
    @StateObject private var viewModel = TransactionViewModel()

    var body: some View {
        List(viewModel.transactions) { transaction in
            TransactionRowView(transaction: transaction)
        }
        .task { await viewModel.load() }
    }
}
```

---

## Property Wrappers

| Wrapper | Use |
|---|---|
| `@State` | Local view state |
| `@StateObject` | Owns a ViewModel, created once |
| `@ObservedObject` | Receives a ViewModel from parent |
| `@EnvironmentObject` | App-wide shared state |
| `@Binding` | Two-way data flow from parent |
| `@Published` | Observable property inside ViewModel |
| `@Persisted` | Realm model property |

---

## Access Control

- `private` — within the same declaration
- `fileprivate` — within the same file
- `internal` — within the module (default, omit the keyword)
- `public` / `open` — across modules (rarely needed in app targets)

**Rule of thumb:** start with `private`, loosen only when needed.

```swift
class OllamaService {
    private let baseURL: String
    private var session: URLSession

    func categorize(description: String) async throws -> String { }
}
```

---

## Value Types vs Reference Types

- `struct` — value type, copied on assignment. Use for models, data containers.
- `class` — reference type, shared. Use for services, ViewModels.
- Prefer `struct` by default.

```swift
// Prefer struct for data
struct ParsedTransaction {
    let date: Date
    let amount: Double
    let description: String
}

// Class for services and ViewModels
class OllamaService { }
```

---

## Optionals

Never force unwrap (`!`) outside of tests or previews.

```swift
// Preferred
if let value = optionalValue {
    use(value)
}

// Preferred for early exits
guard let url = URL(string: rawString) else { return }

// Nil coalescing for defaults
let name = optionalName ?? "Unknown"
```

---

## Error Handling

```swift
enum AppError: LocalizedError {
    case pdfParsingFailed
    case ollamaUnavailable
    case databaseWriteFailed(String)

    var errorDescription: String? {
        switch self {
        case .pdfParsingFailed: return "Could not parse the PDF."
        case .ollamaUnavailable: return "Ollama is not running."
        case .databaseWriteFailed(let msg): return "Database error: \(msg)"
        }
    }
}

func parse(url: URL) throws -> Statement {
    guard let text = extractText(from: url) else {
        throw AppError.pdfParsingFailed
    }
    return Statement(raw: text)
}
```

---

## Async/Await

Prefer `async/await` over callbacks or Combine for new code.

```swift
func categorize(transactions: [ParsedTransaction]) async throws -> [Transaction] {
    try await withThrowingTaskGroup(of: Transaction.self) { group in
        for parsed in transactions {
            group.addTask {
                try await self.ollamaService.categorize(parsed)
            }
        }
        return try await group.reduce(into: []) { $0.append($1) }
    }
}
```

---

## Realm Conventions

```swift
import RealmSwift

class Transaction: Object, Identifiable {
    @Persisted(primaryKey: true) var id: String = UUID().uuidString
    @Persisted var date: Date = Date()
    @Persisted var amount: Double = 0.0
    @Persisted var transactionDescription: String = ""  // avoid 'description' — shadows Object.description
    @Persisted var reviewed: Bool = false
    @Persisted var categoryId: String = ""
    @Persisted var classificationId: String = ""

    // Back-link to parent
    @Persisted(originProperty: "transactions") var statement: LinkingObjects<Statement>
}
```

- Never name a property `description` — it shadows `CustomStringConvertible`
- Always define a `primaryKey`
- Open Realm on the main thread for UI reads, background thread for heavy writes

---

## General Best Practices

- One type per file
- Keep Views under ~100 lines — extract subviews aggressively
- `guard` for preconditions and early exits
- Use `let` by default, `var` only when mutation is required
- No magic numbers — use named constants
- No commented-out code — use git history
- Extensions go in `Extensions/` and are named `Type+Functionality.swift`

---

## Resources
- Swift API Design Guidelines — https://www.swift.org/documentation/api-design-guidelines/
- Swift by Sundell — https://www.swiftbysundell.com
- Hacking with Swift — https://www.hackingwithswift.com
- Point-Free — https://www.pointfree.co (advanced, functional Swift)
- Realm Swift SDK — https://www.mongodb.com/docs/realm/sdk/swift/
