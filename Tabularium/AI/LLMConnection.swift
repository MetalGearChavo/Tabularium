import SwiftUI
import Combine     // provides `ObservableObject` / the observation system

/// Describes the app's connection to the LLM backend that powers import/analysis.
enum LLMConnection {
    case online(type: String)   // `type` is a human label, e.g. "Local · Ollama"
    case offline

    var isOnline: Bool {
        // `if case` checks which enum case this is without caring about the payload.
        if case .online = self { return true }
        return false
    }

    /// Green when connected, red when not — drives the status dot.
    var color: Color { isOnline ? .green : .red }

    /// Short label next to the dot, e.g. "LLM online".
    var label: String { isOnline ? "LLM online" : "LLM offline" }

    /// Connection detail shown in Settings, e.g. "Local · Ollama" / "Not connected".
    var detail: String {
        switch self {
        case .online(let type): return type
        case .offline:          return "Not connected"
        }
    }
}

/// Pings the LLM backend and publishes the result so any view can show a live
/// status light. This is a small **ViewModel**-shaped helper (state + a service
/// call, no UI) shared by the sidebar badge and Settings, so both stay in sync.
///
/// `@MainActor` + `ObservableObject`: same reasoning as `DashboardViewModel` — it
/// mutates `@Published` state that SwiftUI reads, so it must run on the main
/// thread. It's a singleton (`shared`) since there's only ever one LLM connection
/// for the whole app to track.
@MainActor
class LLMConnectionMonitor: ObservableObject {
    static let shared = LLMConnectionMonitor()
    private init() {}

    @Published var connection: LLMConnection = .offline
    // Model names actually installed on the backend, for Settings' model picker.
    // Empty while offline/unknown — Settings falls back to a free-text field then.
    @Published var availableModels: [String] = []

    /// Pings the backend's `/models` endpoint. Cheap and fast (no generation), so
    /// it's safe to call whenever a view showing the status appears.
    func refresh() async {
        let reachable = await LLMService.shared.checkConnection()
        connection = reachable ? .online(type: "Local · Ollama") : .offline
        availableModels = reachable ? await LLMService.shared.listModels() : []
    }
}

/// The small LLM connection light. Used in the sidebar footer (and reusable elsewhere).
struct LLMStatusBadge: View {
    // `@ObservedObject` because this view doesn't own the monitor's lifecycle —
    // it's a shared singleton, not created fresh here (swift-standards.md →
    // "Property Wrappers").
    @ObservedObject private var monitor = LLMConnectionMonitor.shared

    var body: some View {
        HStack(spacing: 8) {
            Circle()
                .fill(monitor.connection.color)
                .frame(width: 8, height: 8)
            Text(monitor.connection.label)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)
            Spacer()
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 10)
        .background(.bar)   // subtle footer shading so it reads as a status bar
        // `.task` runs async work tied to this view's lifetime — perfect for a
        // one-shot check when the badge first appears.
        .task { await monitor.refresh() }
    }
}
