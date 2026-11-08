import Foundation

/// Talks to the LLM backend over its OpenAI-compatible HTTP API (Ollama locally
/// today; swappable to a hosted endpoint later by changing only the base URL).
///
/// This is a **Service** — it only knows how to make the HTTP call and parse the
/// reply; ViewModels decide what to do with the result. (swift-standards.md →
/// "Services".) `class` (not `struct`) because services are shared, stateless-ish
/// objects, per swift-standards' "Value Types vs Reference Types".
class LLMService {
    static let shared = LLMService()
    private init() {}

    // Read per-request from `UserDefaults` so the backend is swappable (local
    // Ollama → hosted EC2/vLLM) without recompiling, per CLAUDE.md → "AI Layer".
    // `??` (nil-coalescing) falls back to the local Ollama defaults when unset.
    private var baseURL: String {
        UserDefaults.standard.string(forKey: "llmBaseURL") ?? "http://localhost:11434/v1"
    }
    private var model: String {
        UserDefaults.standard.string(forKey: "llmModel") ?? "llama3.2"
    }

    /// Sends the extracted statement text to the LLM and returns the parsed,
    /// categorized transactions. `categories` are the user's own category names —
    /// the prompt instructs the AI to only ever pick from this list.
    ///
    /// Takes `[CategoryOption]`, not `[Category]`: this function awaits a network
    /// call, and Realm's live objects are thread-confined and unsafe to touch
    /// after an `await` resumes (possibly on a different thread) — see
    /// `CategoryOption`.
    func parseStatement(text: String, categories: [CategoryOption]) async throws -> [ParsedTransaction] {
        let prompt = try loadPrompt(categories: categories)

        guard let url = URL(string: "\(baseURL)/chat/completions") else {
            throw LLMServiceError.invalidBaseURL
        }

        let body = ChatRequest(
            model: model,
            messages: [
                .init(role: "system", content: prompt),
                .init(role: "user", content: text),
            ],
            temperature: 0.1,   // low = consistent extraction, not creative writing
            responseFormat: .init(type: "json_object"),   // ask Ollama for strict JSON
            // A statement with many charges needs a long reply; without an
            // explicit ceiling, a conservative server default can truncate it
            // mid-JSON. `parse` salvages complete transactions from a truncated
            // reply either way, but more headroom means it happens less often.
            maxTokens: 8192
        )

        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONEncoder().encode(body)
        // Local models can be slow — especially a newly-selected one that Ollama
        // has to load into memory before it can even start generating, on top of
        // producing a long JSON reply for a statement with many charges. Without
        // this, URLSession's default 60s timeout fires while Ollama is still
        // legitimately working, which reads as "unreachable" even though it's not.
        // 360s: a 7B model writing ~50 verbose (unrequested dateRange-wrapped)
        // transaction objects can genuinely take several minutes on-device.
        request.timeoutInterval = 360

        let data: Data
        let response: URLResponse
        do {
            (data, response) = try await URLSession.shared.data(for: request)
        } catch let error as URLError where error.code == .timedOut {
            throw LLMServiceError.timedOut
        } catch {
            throw LLMServiceError.unreachable
        }

        guard let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode) else {
            throw LLMServiceError.requestFailed
        }

        let chat = try JSONDecoder().decode(ChatResponse.self, from: data)
        guard let content = chat.choices.first?.message.content else {
            throw LLMServiceError.emptyResponse
        }

        return try parse(content: content, categories: categories)
    }

    /// A cheap, fast call (no generation) used to drive the sidebar's connection
    /// light — hits the OpenAI-compatible `/models` listing endpoint.
    func checkConnection() async -> Bool {
        guard let url = URL(string: "\(baseURL)/models") else { return false }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        guard let (_, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse else { return false }
        return (200...299).contains(http.statusCode)
    }

    /// The names of models actually installed on the backend (`ollama pull`ed
    /// locally), so Settings can offer a picker instead of a free-text field the
    /// user has to get exactly right. Soft-fails to `[]` — same reasoning as
    /// `checkConnection`: this only drives a UI convenience, never anything the
    /// import pipeline depends on to function.
    func listModels() async -> [String] {
        guard let url = URL(string: "\(baseURL)/models") else { return [] }
        var request = URLRequest(url: url)
        request.timeoutInterval = 3
        guard let (data, response) = try? await URLSession.shared.data(for: request),
              let http = response as? HTTPURLResponse, (200...299).contains(http.statusCode),
              let list = try? JSONDecoder().decode(ModelsResponse.self, from: data) else {
            return []
        }
        return list.data.map(\.id)
    }

    // MARK: - Prompt loading

    /// Loads the bundled system prompt and fills in `{{TODAY}}` / `{{CATEGORIES}}`.
    private func loadPrompt(categories: [CategoryOption]) throws -> String {
        guard let url = Bundle.main.url(forResource: "import_prompt", withExtension: "md"),
              let template = try? String(contentsOf: url, encoding: .utf8) else {
            throw LLMServiceError.missingPrompt
        }

        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyy-MM-dd"
        let today = formatter.string(from: Date())
        let categoryList = categories.map(\.name).joined(separator: "\n")

        return template
            .replacingOccurrences(of: "{{TODAY}}", with: today)
            .replacingOccurrences(of: "{{CATEGORIES}}", with: categoryList)
    }

    // MARK: - Response parsing

    /// Writes the LLM's raw (failed-to-parse) response to a file in the temp
    /// directory and returns a message with a generous preview plus that file's
    /// path. A SwiftUI `.alert` can't comfortably show a multi-thousand-character
    /// response, so this makes the full text inspectable without a debugger —
    /// open the file in TextEdit/Finder to see everything.
    private static func debugDump(_ content: String) -> String {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("tabularium_llm_response.txt")
        try? content.write(to: url, atomically: true, encoding: .utf8)
        return "Full response saved to:\n\(url.path)\n\n\(content.prefix(2000))"
    }

    /// Extracts every syntactically-complete object one level below the top of
    /// `text` — i.e. each `{...}` whose matching close brings the nesting depth
    /// back to 1 — in order, ignoring braces inside string literals.
    ///
    /// Used to salvage transactions from a response that got cut off mid-JSON:
    /// a truncated document is invalid as a whole (unbalanced braces), but the
    /// individual transaction objects before the cutoff are still well-formed.
    /// This also naturally skips the model's occasional extra top-level
    /// "date_range"/"dateRange" summary array — those objects don't have a
    /// "description", so they simply fail to decode as an `Item` and get
    /// dropped by the `compactMap` at the call site.
    private static func extractSecondLevelObjects(from text: String) -> [String] {
        let characters = Array(text)
        var results: [String] = []
        var depth = 0
        var inString = false
        var escapeNext = false
        var startIndex: Int?

        for index in characters.indices {
            let character = characters[index]

            if inString {
                if escapeNext {
                    escapeNext = false
                } else if character == "\\" {
                    escapeNext = true
                } else if character == "\"" {
                    inString = false
                }
                continue
            }

            switch character {
            case "\"":
                inString = true
            case "{":
                depth += 1
                if depth == 2 { startIndex = index }
            case "}":
                if depth == 2, let start = startIndex {
                    results.append(String(characters[start...index]))
                    startIndex = nil
                }
                depth -= 1
            default:
                break
            }
        }
        return results
    }

    /// Turns the model's JSON content string into `[ParsedTransaction]`, matching
    /// each item's category name back to a real `Category.id`.
    ///
    /// Not `private`: `LLMResponseParsingTests` calls this directly with captured
    /// real model output, per CLAUDE.md's spec-driven "Development Process" —
    /// this is the one piece of the AI pipeline that's pure, deterministic logic
    /// and doesn't need a live Ollama instance to test.
    func parse(content: String, categories: [CategoryOption]) throws -> [ParsedTransaction] {
        // Small local models sometimes ignore "no code fences" — strip them
        // defensively rather than failing the whole import over it.
        var cleaned = content
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .replacingOccurrences(of: "```json", with: "")
            .replacingOccurrences(of: "```", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)

        // They also sometimes add a sentence before/after the JSON despite being
        // told not to ("Here's the JSON: {...}") — keep only what's between the
        // outermost brace/bracket, which strips any surrounding prose.
        if let start = cleaned.firstIndex(where: { $0 == "{" || $0 == "[" }),
           let end = cleaned.lastIndex(where: { $0 == "}" || $0 == "]" }),
           start < end {
            cleaned = String(cleaned[start...end])
        }

        // Always dump the raw response, not just on a decode failure — a
        // response that decodes fine but filters down to zero transactions
        // (every date unparseable, every amount non-positive, etc.) is just as
        // undiagnosable without this, and previously left no trace at all.
        _ = Self.debugDump(cleaned)

        guard let data = cleaned.data(using: .utf8) else {
            throw LLMServiceError.invalidJSON(Self.debugDump(cleaned))
        }

        // Accept both the documented `{"transactions": [...]}` shape and a bare
        // `[...]` array, in case the model drops the wrapper object.
        let items: [StatementParseResult.Item]
        if let result = try? JSONDecoder().decode(StatementParseResult.self, from: data) {
            items = result.transactions
        } else if let bare = try? JSONDecoder().decode([StatementParseResult.Item].self, from: data) {
            items = bare
        } else {
            // The whole document failed to decode — most likely truncated
            // mid-response (a long statement's reply hit `maxTokens` before the
            // model finished). That makes the document invalid as a WHOLE, but
            // everything before the cutoff is still individually well-formed
            // JSON, so salvage what we can instead of losing every transaction.
            let salvaged = Self.extractSecondLevelObjects(from: cleaned).compactMap {
                try? JSONDecoder().decode(StatementParseResult.Item.self, from: Data($0.utf8))
            }
            guard !salvaged.isEmpty else {
                throw LLMServiceError.invalidJSON(Self.debugDump(cleaned))
            }
            items = salvaged
        }

        // Case-insensitive lookup so a small casing slip from the model doesn't
        // lose the category it clearly meant.
        let categoryByName = Dictionary(uniqueKeysWithValues: categories.map { ($0.name.lowercased(), $0.id) })

        // `compactMap`, not `map`: an item whose date we can't parse at all gets
        // DROPPED rather than silently defaulting to "today" — a wrong date that
        // looks plausible is worse than a transaction that's simply missing
        // (visible as a gap the user can add manually), since it would corrupt
        // which billing period the charge is filed under.
        return items.compactMap { item in
            guard let date = Self.parseDate(item.date) else { return nil }
            // "amount" is documented as always positive (a real charge); a
            // negative value means the model included something it was told to
            // skip — a payment/credit TO the card — despite the instruction.
            guard item.amount > 0 else { return nil }
            return ParsedTransaction(
                date: date,
                description: item.description,
                amount: item.amount,
                categoryId: categoryByName[item.category.lowercased()] ?? ""
            )
        }
    }

    /// Tries several date shapes in turn, in case the model doesn't follow the
    /// documented ISO format — e.g. `qwen2.5:7b` has been observed echoing the
    /// statement's own "18-jul-2026" format straight through instead of
    /// converting it. Returns `nil` if none match.
    private static func parseDate(_ string: String) -> Date? {
        let formats: [(format: String, localeId: String)] = [
            ("yyyy-MM-dd", "en_US_POSIX"),    // documented shape
            ("dd-MMM-yyyy", "es_MX"),         // "18-jul-2026" (Spanish month)
            ("dd-MMM-yyyy", "en_US_POSIX"),   // "18-Jul-2026" (English month)
            ("dd/MM/yyyy", "en_US_POSIX"),
            ("MM/dd/yyyy", "en_US_POSIX"),
        ]
        for (format, localeId) in formats {
            let formatter = DateFormatter()
            formatter.locale = Locale(identifier: localeId)
            formatter.dateFormat = format
            if let date = formatter.date(from: string) {
                return date
            }
        }
        return nil
    }
}

// MARK: - Wire types (OpenAI-compatible chat completions)

/// The shape of the OpenAI-compatible `/models` listing endpoint.
private struct ModelsResponse: Decodable {
    struct Model: Decodable { let id: String }
    let data: [Model]
}

/// `Encodable`/`Decodable` request/response shapes for the chat completions API.
/// `private` — nothing outside this file needs to know the wire format.
private struct ChatRequest: Encodable {
    struct Message: Encodable { let role: String; let content: String }
    struct ResponseFormat: Encodable { let type: String }

    let model: String
    let messages: [Message]
    let temperature: Double
    let responseFormat: ResponseFormat
    let maxTokens: Int

    // The API expects snake_case keys; `CodingKeys` maps our camelCase Swift
    // property to the JSON key it should encode as.
    enum CodingKeys: String, CodingKey {
        case model, messages, temperature
        case responseFormat = "response_format"
        case maxTokens = "max_tokens"
    }
}

private struct ChatResponse: Decodable {
    struct Choice: Decodable { let message: Message }
    struct Message: Decodable { let content: String }
    let choices: [Choice]
}

/// The shape of the LLM's JSON reply, as defined in `import_prompt.md`.
private struct StatementParseResult: Decodable {
    struct Item: Decodable {
        // `date` stays a raw String here (parsed later by `LLMService.parseDate`,
        // which tries several formats) — this type's job is just pulling one
        // date string out of whatever shape the model actually sent.
        let date: String
        let description: String
        let amount: Double
        let category: String

        // Two different real responses used two different casings for the same
        // invented structure ("date_range" and "dateRange") — both are tried.
        private enum CodingKeys: String, CodingKey {
            case date, description, amount, category
            case dateRangeSnakeCase = "date_range"
            case dateRangeCamelCase = "dateRange"
        }

        // Despite the prompt explicitly forbidding it, `qwen2.5:7b` kept
        // inventing this shape for rows with two printed dates (purchase +
        // posting date) instead of picking one. We take the first/earliest one.
        // Same casing story as above: both key spellings are tried.
        private struct DateRange: Decodable {
            let startDate: String
            private enum CodingKeys: String, CodingKey {
                case startDateSnakeCase = "start_date"
                case startDateCamelCase = "startDate"
            }
            init(from decoder: Decoder) throws {
                let container = try decoder.container(keyedBy: CodingKeys.self)
                if let value = try? container.decode(String.self, forKey: .startDateSnakeCase) {
                    startDate = value
                } else {
                    startDate = try container.decode(String.self, forKey: .startDateCamelCase)
                }
            }
        }

        /// Tries to read `key` as either a single `DateRange` object or an array
        /// of them, returning the first `startDate` found either way.
        private static func dateFromRange(_ container: KeyedDecodingContainer<CodingKeys>, key: CodingKeys) -> String? {
            if let range = try? container.decode(DateRange.self, forKey: key) {
                return range.startDate
            }
            if let ranges = try? container.decode([DateRange].self, forKey: key), let first = ranges.first {
                return first.startDate
            }
            return nil
        }

        // A custom `init` instead of the free synthesized one: small local
        // models deviate from the documented shape in specific, observed ways —
        // quoting the amount as a string, dropping "category" for their own
        // "type" field, or nesting the date in a "date_range" object. Each `try?`
        // below absorbs one such deviation instead of failing the whole import.
        init(from decoder: Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            description = try container.decode(String.self, forKey: .description)
            // Missing entirely (e.g. replaced with the model's own "type" field)
            // → uncategorized, same as an unmatched name; the user fixes it in
            // Review rather than the whole import failing.
            category = (try? container.decode(String.self, forKey: .category)) ?? ""

            if let value = try? container.decode(String.self, forKey: .date) {
                date = value
            } else if let value = Self.dateFromRange(container, key: .dateRangeSnakeCase)
                ?? Self.dateFromRange(container, key: .dateRangeCamelCase) {
                date = value
            } else {
                // No parseable date anywhere — `LLMService.parseDate` will fail
                // on this too, and the item gets dropped rather than guessed.
                date = ""
            }

            if let value = try? container.decode(Double.self, forKey: .amount) {
                amount = value
            } else {
                let raw = (try? container.decode(String.self, forKey: .amount)) ?? ""
                let digitsAndDot = raw.filter { $0.isNumber || $0 == "." }
                amount = Double(digitsAndDot) ?? 0
            }
        }
    }
    let transactions: [Item]
}

enum LLMServiceError: LocalizedError {
    case invalidBaseURL
    case unreachable
    // Distinct from `.unreachable`: the connection was fine, but generation took
    // longer than our timeout — e.g. a newly-selected model still loading into
    // memory, or a big model working through a long statement. Not the same fix
    // as "start Ollama".
    case timedOut
    case requestFailed
    case emptyResponse
    // Carries a snippet of what the model actually returned, so a bad response
    // is self-diagnosing from the alert alone — no Xcode console needed.
    case invalidJSON(String)
    case missingPrompt

    var errorDescription: String? {
        switch self {
        case .invalidBaseURL: return "The LLM connection URL is invalid."
        case .unreachable:    return "Could not reach the LLM. Is Ollama running?"
        case .timedOut:
            return "The LLM took over 6 minutes to respond and gave up. A local model "
                + "generating a long, detailed reply can genuinely take a while — "
                + "try again, or a smaller/faster model."
        case .requestFailed:  return "The LLM request failed."
        case .emptyResponse:  return "The LLM returned an empty response."
        case .invalidJSON(let snippet):
            return "Could not understand the LLM's response:\n\n\(snippet)"
        case .missingPrompt:  return "Missing import_prompt.md in the app bundle."
        }
    }
}
