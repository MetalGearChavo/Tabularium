import SwiftUI
import UniformTypeIdentifiers   // gives us `UTType.pdf` for the drag-and-drop file type

/// The main dashboard screen: a card picker + month navigator on top, a scrolling
/// list of transactions in the middle, and a running total at the bottom.
///
/// The View is "dumb" — all data and logic live in `DashboardViewModel`. The View
/// just reads the VM's published values and forwards user actions back to it.
struct DashboardView: View {
    // `@StateObject` creates and OWNS the view model. It's made once and kept alive
    // for as long as this view exists (unlike `@ObservedObject`, which receives one
    // from a parent). `vm` is short for "view model".
    @StateObject private var vm = DashboardViewModel()

    // View-local UI state (not business data, so it lives here, not in the VM):
    @State private var showingAddTransaction = false                  // is the Add sheet open?
    @State private var editingRow: DashboardViewModel.TransactionRow? // which row is being edited (nil = none)
    @State private var isDragTarget = false                           // is a file hovering over the list?
    // Owns the PDF → LLM pipeline for a dropped statement (extraction, parsing,
    // categorization). See `ImportViewModel`.
    @StateObject private var importVM = ImportViewModel()
    @State private var showingReview = false      // opens ReviewView once parsing succeeds
    @State private var showingImportError = false // drives the failure alert
    @State private var importTask: Task<Void, Never>?  // lets the overlay's Cancel stop an in-flight import
    // Day-group ids that are currently expanded in the list. Empty = all collapsed,
    // which is the default. `Set` gives fast membership checks.
    @State private var expandedDays: Set<String> = []

    // CSV export state. We prepare the document + filename when the button is tapped,
    // then present the system save panel via `.fileExporter`.
    @State private var showingExporter = false
    @State private var exportDocument = CSVDocument(text: "")
    @State private var exportFileName = "export.csv"

    var body: some View {
        // `VStack` stacks children top-to-bottom. `spacing: 0` removes gaps.
        VStack(spacing: 0) {
            HeaderBar(vm: vm)

            // `content` is the area below the header (defined further down). We attach
            // the drag-and-drop behavior to it so ONLY this region reacts — not the
            // header or sidebar.
            content
                // `.onDrop` fires when a PDF is dragged in. `isTargeted:` flips
                // `isDragTarget` true/false as the file enters/leaves, which drives
                // the glowing border below.
                .onDrop(of: [UTType.pdf], isTargeted: $isDragTarget) { providers in
                    guard let provider = providers.first else { return false }
                    // Reading the file is asynchronous (it finishes later), so we get
                    // a callback closure. `url, _` ignores the second argument (an error).
                    provider.loadFileRepresentation(forTypeIdentifier: UTType.pdf.identifier) { url, _ in
                        guard let url else { return }
                        // The URL the system hands us is only guaranteed to exist for
                        // the length of this closure, but we need it after an `await`
                        // (inside the Task below) — so copy the bytes into our own temp
                        // file first, then work from that stable copy.
                        let tempURL = FileManager.default.temporaryDirectory
                            .appendingPathComponent(UUID().uuidString)
                            .appendingPathExtension("pdf")
                        guard (try? FileManager.default.copyItem(at: url, to: tempURL)) != nil else { return }

                        // UI updates must run on the main thread; this callback may not,
                        // so we hop back onto it.
                        DispatchQueue.main.async {
                            startImport(from: tempURL)
                        }
                    }
                    return true   // tell the system we accepted the drop
                }
                // `.overlay` draws on top of `content`. Here: a glowing accent border
                // while a file hovers, signalling "you can drop here".
                .overlay {
                    if isDragTarget {
                        RoundedRectangle(cornerRadius: 10)
                            .strokeBorder(Color.accentColor, lineWidth: 3)
                            .shadow(color: Color.accentColor.opacity(0.6), radius: 8)
                            .padding(2)
                            .allowsHitTesting(false)   // let clicks pass through the border
                    }
                }
        }
        // Modifiers below apply to the whole VStack:
        .font(.system(.body, design: .monospaced))   // terminal-style font everywhere
        .toolbar {
            // Export the current view to CSV. Prepares the document + filename, then
            // opens the save panel. Disabled when there's nothing to export.
            ToolbarItem(placement: .primaryAction) {
                Button {
                    exportDocument = CSVDocument(text: vm.exportCSVText())
                    exportFileName = vm.exportFileName
                    showingExporter = true
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
                .disabled(vm.rows.isEmpty)
                .help("Export this period to CSV")
            }

            // The "+ Add" button in the window toolbar that opens the Add sheet.
            ToolbarItem(placement: .primaryAction) {
                Button {
                    showingAddTransaction = true
                } label: {
                    // `Label` pairs text with an SF Symbol icon. Toolbars show only the
                    // icon by default — which is what made the old "+" so small to hit —
                    // so `.labelStyle(.titleAndIcon)` forces both the "+" AND "Add" text.
                    Label("Add", systemImage: "plus")
                        .labelStyle(.titleAndIcon)
                }
                // `.borderedProminent` fills the button with the accent color: a wider,
                // obvious click target that reads as the screen's main action.
                .buttonStyle(.borderedProminent)
                .help("Add a transaction")   // hover tooltip
            }
        }
        // The system save panel for the CSV export.
        .fileExporter(
            isPresented: $showingExporter,
            document: exportDocument,
            contentType: .commaSeparatedText,
            defaultFilename: exportFileName
        ) { _ in
            // Nothing to do on completion; the system handles success/cancel.
        }
        // A "sheet" is a modal panel that slides up. This one shows the Add form.
        // The first closure runs on dismiss (reload so the new transaction appears);
        // `content:` builds the sheet's contents.
        .sheet(isPresented: $showingAddTransaction) {
            vm.load()
        } content: {
            AddTransactionSheet()
        }
        // `.sheet(item:)` opens whenever `editingRow` becomes non-nil (i.e. a row was
        // tapped) and passes that row in. We reload on dismiss to reflect any edits.
        .sheet(item: $editingRow, onDismiss: { vm.load() }) { row in
            EditTransactionSheet(transactionId: row.id)
        }
        .overlay {
            if importVM.isProcessing {
                ProcessingOverlay(fileName: importVM.sourceFileName, progressLabel: importVM.progressLabel) {
                    importTask?.cancel()
                    importVM.isProcessing = false
                }
            }
        }
        // Opens once `startImport` finds transactions to review. On dismiss
        // (Save or Cancel) we reset the import state and reload the dashboard,
        // so any newly-saved transactions show up right away.
        .sheet(isPresented: $showingReview, onDismiss: {
            importVM.reset()
            vm.load()
        }) {
            ReviewView(
                parsed: importVM.parsedTransactions,
                categories: RealmService.shared.objects(Category.self),
                cards: vm.cards,
                defaultCardId: vm.selectedCard?.id ?? "",
                sourceFileName: importVM.sourceFileName
            )
        }
        .alert("Import Failed", isPresented: $showingImportError) {
            Button("OK") { importVM.errorMessage = nil }
        } message: {
            Text(importVM.errorMessage ?? "")
        }
        // `.onAppear` runs when the view first shows — load the data then.
        .onAppear { vm.load() }
    }

    /// Kicks off the PDF → LLM pipeline for a dropped statement, then routes to
    /// the review screen on success or an alert on failure.
    private func startImport(from fileURL: URL) {
        // Snapshot categories into plain `CategoryOption` values here, on the
        // main thread, BEFORE starting any async work. Realm's managed
        // `Category` objects are thread-confined and must never cross an
        // `await` suspension point — the LLM's network call inside
        // `ImportViewModel.process` can resume on a different thread than it
        // started on, and touching a live Realm object from the wrong thread
        // crashes.
        let categories = RealmService.shared.objects(Category.self).map(CategoryOption.init)
        importTask = Task {
            await importVM.process(fileURL: fileURL, categories: categories)
            if !importVM.parsedTransactions.isEmpty {
                showingReview = true
            } else if importVM.errorMessage != nil {
                showingImportError = true
            }
        }
    }

    /// Expand a collapsed day or collapse an expanded one.
    private func toggleDay(_ id: String) {
        if expandedDays.contains(id) {
            expandedDays.remove(id)
        } else {
            expandedDays.insert(id)
        }
    }

    // Everything below the header bar, pulled into its own property to keep `body`
    // readable. `@ViewBuilder` lets it contain `if/else` and multiple views.
    @ViewBuilder
    private var content: some View {
        VStack(spacing: 0) {
            Divider()

            if vm.rows.isEmpty {
                // `{ ... }` right after the type name is "trailing closure" syntax: the
                // last closure argument (`onAdd`) written outside the parentheses.
                EmptyDashboard { showingAddTransaction = true }
            } else {
                // Swap the middle area between the transaction list and the chart.
                switch vm.viewMode {
                case .list:
                    // `ScrollView` makes its contents scrollable when they overflow.
                    ScrollView {
                        VStack(spacing: 0) {
                            // One collapsible section per day. Tapping a day header
                            // toggles whether its transactions are shown.
                            ForEach(vm.dayGroups) { group in
                                DayHeaderRow(
                                    group: group,
                                    isExpanded: expandedDays.contains(group.id)
                                ) {
                                    toggleDay(group.id)
                                }

                                // Only render the day's rows when it's expanded.
                                if expandedDays.contains(group.id) {
                                    ForEach(group.rows) { row in
                                        CategoryRowView(row: row)
                                            .contentShape(Rectangle())
                                            .onTapGesture { editingRow = row }
                                        Divider().opacity(0.3)
                                    }
                                }
                            }
                        }
                    }
                case .chart:
                    DistributionView(slices: vm.breakdown) { row in
                        editingRow = row
                    }
                }

                Divider()

                TotalRow(total: vm.total)
            }
        }
        // Fill all available space so the drop target/border covers the whole lower
        // area even when the list is empty.
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .contentShape(Rectangle())
    }
}

// MARK: - Processing Overlay

/// Full-screen dimmed overlay shown while a dropped PDF is being extracted and
/// parsed by the LLM (see `ImportViewModel.process`).
private struct ProcessingOverlay: View {
    let fileName: String
    // "Parsing 3 of 6…" while a long statement is split into chunks (see
    // `StatementChunker`/`ImportViewModel`); empty for a single-chunk import.
    let progressLabel: String
    let onCancel: () -> Void   // a function passed in from the parent, called on Cancel

    var body: some View {
        // `ZStack` layers children front-to-back (here: dim background, then content).
        ZStack {
            Color.black.opacity(0.7).ignoresSafeArea()
            VStack(spacing: 16) {
                ProgressView()           // the spinning indicator
                    .scaleEffect(1.2)
                    .tint(.white)
                Text("Reading \(fileName)")
                    .font(.system(size: 14, design: .monospaced))
                    .foregroundStyle(.white)
                if !progressLabel.isEmpty {
                    Text(progressLabel)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.7))
                }
                Text("Extracting text and asking the LLM to categorize charges — a local")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                Text("model can take several minutes on a long statement")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
                Button("Cancel") { onCancel() }
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.6))
                    .padding(.top, 8)
            }
        }
    }
}

// MARK: - Header

/// The top bar: card picker on the left, month navigator on the right.
private struct HeaderBar: View {
    // `@ObservedObject` receives the VM from the parent (it doesn't own it).
    @ObservedObject var vm: DashboardViewModel

    var body: some View {
        // `HStack` lays children out left-to-right.
        HStack(spacing: 16) {
            CardPicker(vm: vm)
            Spacer()        // flexible gap that pushes the two sides apart
            // The Cycle/Month switch only makes sense for cards that have a corte.
            if vm.canUseBillingCycle {
                PeriodModeToggle(vm: vm)
            }
            ViewModeToggle(vm: vm)
            MonthNav(vm: vm)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

/// A dropdown menu to choose which card the dashboard shows.
private struct CardPicker: View {
    @ObservedObject var vm: DashboardViewModel

    var body: some View {
        // `Menu` shows a popup of buttons when its label is clicked.
        Menu {
            ForEach(vm.cards) { card in
                Button("\(card.name) ••••\(card.lastFour)") {
                    vm.select(card: card)
                }
            }
        } label: {
            HStack(spacing: 6) {
                // `if let` unwraps the optional: show the card name only if one is selected.
                if let card = vm.selectedCard {
                    Text("\(card.name) ••••\(card.lastFour)")
                        .font(.system(.body, design: .monospaced))
                } else {
                    Text("No card selected")
                        .foregroundStyle(.secondary)
                }
                Image(systemName: "chevron.down")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .buttonStyle(.plain)   // remove default button chrome for a clean look
    }
}

/// Left/right arrows around the current period label. The label is either a month
/// ("June 2026") or a billing cycle ("May 21 – Jun 20, 2026"), depending on the
/// view model's `periodMode`.
private struct MonthNav: View {
    @ObservedObject var vm: DashboardViewModel

    var body: some View {
        HStack(spacing: 12) {
            Button { vm.previousPeriod() } label: {
                Image(systemName: "chevron.left")
                    .font(.caption)
            }
            .buttonStyle(.plain)

            Text(vm.periodLabel)
                .font(.system(.body, design: .monospaced))
                // Wider than before to fit the longer billing-cycle label.
                .frame(minWidth: 180, alignment: .center)

            Button { vm.nextPeriod() } label: {
                Image(systemName: "chevron.right")
                    .font(.caption)
            }
            .buttonStyle(.plain)
        }
    }
}

/// A small Cycle/Month switch, shown only when the selected card has a corte.
/// Billing cycle is the default for those cards; this lets the user drop to plain
/// calendar months when they want.
private struct PeriodModeToggle: View {
    @ObservedObject var vm: DashboardViewModel

    var body: some View {
        // The picker's selection is wired straight to the VM: reading gives the
        // current mode, setting routes through `setPeriodMode` so it also reloads.
        Picker("", selection: Binding(
            get: { vm.periodMode },
            set: { vm.setPeriodMode($0) }
        )) {
            Text("Cycle").tag(DashboardViewModel.PeriodMode.billingCycle)
            Text("Month").tag(DashboardViewModel.PeriodMode.month)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 150)
    }
}

/// A List/Chart switch that flips the content area between the transaction list and
/// the per-category spend breakdown for the current period.
private struct ViewModeToggle: View {
    @ObservedObject var vm: DashboardViewModel

    var body: some View {
        Picker("", selection: Binding(
            get: { vm.viewMode },
            set: { vm.setViewMode($0) }
        )) {
            Text("List").tag(DashboardViewModel.ViewMode.list)
            Text("Chart").tag(DashboardViewModel.ViewMode.chart)
        }
        .pickerStyle(.segmented)
        .labelsHidden()
        .frame(width: 130)
    }
}

// MARK: - Transaction Row

/// One row in the list: description · category emoji · date · amount.
private struct CategoryRowView: View {
    let row: DashboardViewModel.TransactionRow
    // Tracks whether the mouse is over the emoji, to show the category tooltip.
    @State private var hovering = false

    var body: some View {
        HStack(spacing: 12) {
            HStack(spacing: 6) {
                Text(row.description)
                    .lineLimit(1)                                  // never wrap to a 2nd line
                // For an installment purchase, a small "3/12" pill next to the name.
                if let label = row.installmentLabel {
                    Text(label)
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .padding(.horizontal, 5)
                        .padding(.vertical, 1)
                        .background(Color.accentColor.opacity(0.18))
                        .clipShape(Capsule())
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)       // takes the leftover width

            Text(row.emoji)
                .frame(width: 24)
                .contentShape(Rectangle())     // make the whole 24pt box hoverable
                .onHover { hovering = $0 }      // $0 is true when entering, false when leaving
                .overlay(alignment: .top) {
                    if hovering {
                        // A small bubble showing the category name. Placed BELOW the emoji
                        // (offset down) so the first row's tooltip isn't clipped by the
                        // scroll view's top edge.
                        CategoryTooltip(name: row.category)
                            .fixedSize()             // don't shrink the bubble to fit
                            .offset(y: 26)
                            .transition(.opacity)    // fade in/out
                    }
                }

            Text(row.date.shortDateString)   // "Jun 1"
                .foregroundStyle(.secondary)
                .frame(width: 60, alignment: .trailing)

            Text(row.amount.currencyString)  // "$1,234.50"
                .frame(width: 90, alignment: .trailing)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 10)
        // Raise the hovered row above its neighbors so its tooltip draws on top.
        .zIndex(hovering ? 1 : 0)
        .animation(.easeInOut(duration: 0.1), value: hovering)
    }
}

/// The little floating label showing a category's name on hover.
private struct CategoryTooltip: View {
    let name: String

    var body: some View {
        Text(name)
            .font(.system(size: 11, design: .monospaced))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            // `.ultraThinMaterial` is a translucent, blurred system background.
            .background(.ultraThinMaterial, in: RoundedRectangle(cornerRadius: 6))
            .overlay(
                RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Color.secondary.opacity(0.3))
            )
            .shadow(color: .black.opacity(0.2), radius: 4, y: 2)
    }
}

// MARK: - Total Row

/// The bold "TOTAL ........ $X" row pinned under the list.
private struct TotalRow: View {
    let total: Double

    var body: some View {
        HStack {
            Text("TOTAL")
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
            Spacer()
            Text(total.currencyString)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 12)
    }
}

// MARK: - Day Header (collapsible)

/// A tappable day header in the list view: chevron + date + transaction count on
/// the left, the day's total on the right. Tapping toggles the day open/closed.
private struct DayHeaderRow: View {
    let group: DashboardViewModel.DayGroup
    let isExpanded: Bool
    let onTap: () -> Void   // called when the header is tapped

    var body: some View {
        HStack(spacing: 10) {
            // The chevron points right when collapsed, down when expanded.
            Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                .font(.caption2)
                .foregroundStyle(.secondary)
                .frame(width: 10)

            Text(group.date.dayHeaderString)
                .font(.system(.body, design: .monospaced))

            // Number of transactions that day, e.g. "(4)".
            Text("(\(group.rows.count))")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)

            Spacer()

            // The day's total, shown even when collapsed so the summary is useful.
            Text(group.total.currencyString)
                .font(.system(.body, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 20)
        .padding(.vertical, 8)
        .background(Color.primary.opacity(0.04))   // subtle shading to read as a header
        .contentShape(Rectangle())                 // whole bar is tappable
        .onTapGesture { onTap() }
    }
}

// MARK: - Distribution (Chart)

/// The chart view: one row per category, sorted by spend, each with a proportional
/// bar, its share of the period total, and the amount. Tapping a category expands it
/// to reveal its individual charges.
private struct DistributionView: View {
    let slices: [DashboardViewModel.CategorySlice]
    // Called when a charge inside an expanded category is tapped (to open the editor).
    let onSelectCharge: (DashboardViewModel.TransactionRow) -> Void

    // Category ids currently expanded. Local to the chart; resets when you leave it.
    @State private var expanded: Set<String> = []

    var body: some View {
        ScrollView {
            VStack(spacing: 16) {
                ForEach(slices) { slice in
                    DistributionRow(
                        slice: slice,
                        isExpanded: expanded.contains(slice.id),
                        onToggle: { toggle(slice.id) },
                        onSelectCharge: onSelectCharge
                    )
                }
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 16)
        }
    }

    private func toggle(_ id: String) {
        if expanded.contains(id) {
            expanded.remove(id)
        } else {
            expanded.insert(id)
        }
    }
}

/// A single category's row in the chart: a tappable header (chevron + label + %/
/// amount) over a proportional bar. When expanded, it lists the category's charges.
private struct DistributionRow: View {
    let slice: DashboardViewModel.CategorySlice
    let isExpanded: Bool
    let onToggle: () -> Void
    let onSelectCharge: (DashboardViewModel.TransactionRow) -> Void

    var body: some View {
        VStack(spacing: 6) {
            // Header — tap anywhere on it to open/close the category.
            HStack(spacing: 8) {
                Image(systemName: isExpanded ? "chevron.down" : "chevron.right")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .frame(width: 10)
                Text("\(slice.emoji) \(slice.name)")
                    .font(.system(.body, design: .monospaced))
                Spacer()
                // `(fraction * 100).rounded()` → whole-percent label, e.g. "42%".
                Text("\(Int((slice.fraction * 100).rounded()))%")
                    .font(.system(.body, design: .monospaced))
                    .foregroundStyle(.secondary)
                    .frame(width: 48, alignment: .trailing)
                Text(slice.amount.currencyString)
                    .font(.system(.body, design: .monospaced))
                    .frame(width: 110, alignment: .trailing)
            }
            .contentShape(Rectangle())   // whole header is tappable
            .onTapGesture { onToggle() }

            // The proportional bar. `GeometryReader` gives us the available width so
            // we can size the fill to `width * fraction`.
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    Capsule().fill(Color.primary.opacity(0.08))   // track
                    Capsule()
                        .fill(Color.accentColor)
                        .frame(width: max(0, geo.size.width * slice.fraction))   // fill
                }
            }
            .frame(height: 6)

            // The dropdown: this category's individual charges. Tapping one edits it.
            if isExpanded {
                VStack(spacing: 0) {
                    ForEach(slice.rows) { row in
                        ChargeLine(row: row)
                            .contentShape(Rectangle())
                            .onTapGesture { onSelectCharge(row) }
                        Divider().opacity(0.2)
                    }
                }
                .padding(.top, 4)
            }
        }
    }
}

/// A compact line for one charge inside an expanded category: description (+ optional
/// installment pill) on the left, date and amount on the right.
private struct ChargeLine: View {
    let row: DashboardViewModel.TransactionRow

    var body: some View {
        HStack(spacing: 8) {
            Text(row.description)
                .lineLimit(1)
            if let label = row.installmentLabel {
                Text(label)
                    .font(.system(size: 9, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 5)
                    .padding(.vertical, 1)
                    .background(Color.accentColor.opacity(0.18))
                    .clipShape(Capsule())
            }
            Spacer()
            Text(row.date.shortDateString)
                .foregroundStyle(.secondary)
                .frame(width: 56, alignment: .trailing)
            Text(row.amount.currencyString)
                .frame(width: 90, alignment: .trailing)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.vertical, 5)
        .padding(.leading, 18)   // indent so it reads as nested under the category
    }
}

// MARK: - Empty State

/// Shown when the selected card + period has no transactions. Offers the two ways
/// to fill it: a big "Add Transaction" button, or dropping a PDF statement here.
private struct EmptyDashboard: View {
    let onAdd: () -> Void   // called when the button is clicked; the parent opens the sheet

    var body: some View {
        VStack(spacing: 12) {
            Text("No transactions")
                .font(.system(.body, design: .monospaced))

            Button(action: onAdd) {
                Label("Add Transaction", systemImage: "plus")
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 4)
            }
            .buttonStyle(.borderedProminent)
            // `.controlSize(.large)` asks macOS for its biggest standard button size.
            .controlSize(.large)

            Text("or drop a PDF statement here")
                .font(.system(.caption, design: .monospaced))
                .foregroundStyle(.secondary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

#Preview {
    DashboardView()
        .frame(width: 600, height: 400)
}
