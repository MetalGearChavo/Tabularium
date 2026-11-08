import Foundation
import Combine     // provides `ObservableObject` / the observation system
import SwiftUI

/// The brain behind `DashboardView`. It loads cards and transactions from the
/// database, figures out what to show for the selected card + month, and exposes
/// that as simple `@Published` values the View reads.
///
/// This is a **ViewModel**: it holds logic and state, but never builds UI.
/// (swift-standards.md → "Architecture — MVVM".)
///
/// `@MainActor` guarantees this code runs on the main thread — required because
/// it updates state that the UI reads. `ObservableObject` lets SwiftUI re-render
/// a View automatically whenever a `@Published` property here changes.
@MainActor
class DashboardViewModel: ObservableObject {

    /// A plain, display-ready snapshot of one transaction for the dashboard list.
    ///
    /// We deliberately do NOT hand raw Realm `Transaction` objects to the View.
    /// Instead we flatten exactly what a row needs into this simple `struct`
    /// (a value type — copied, not shared). This keeps the View dumb and avoids
    /// passing live database objects around.
    struct TransactionRow: Identifiable {
        let id: String          // same id as the underlying Transaction (used for editing)
        let emoji: String       // category emoji, or "·" if the category is gone
        let category: String    // category name, shown in the hover tooltip
        let description: String
        let amount: Double      // the amount charged THIS period (a monthly part for MSI)
        let date: Date
        // For a monthly-installment purchase, e.g. "3/12"; `nil` for a normal charge.
        let installmentLabel: String?
    }

    /// How the dashboard groups transactions into a "period".
    /// - `billingCycle`: the card's statement period (fecha de corte → corte).
    /// - `month`: a plain calendar month.
    /// `Hashable` lets us use these as the tags of a SwiftUI `Picker`.
    enum PeriodMode: Hashable {
        case billingCycle
        case month
    }

    /// How the period's data is displayed.
    /// - `list`: the transactions, one per row.
    /// - `chart`: a per-category spend breakdown (% and amount).
    enum ViewMode: Hashable {
        case list
        case chart
    }

    /// All the transactions on one day, plus that day's total — the unit the list
    /// view groups by so long days can be collapsed.
    struct DayGroup: Identifiable {
        let id: String              // stable day key (used for expand/collapse state)
        let date: Date
        let total: Double           // sum of this day's amounts
        let rows: [TransactionRow]
    }

    /// One category's slice of the period's spending, for the chart view.
    struct CategorySlice: Identifiable {
        let id: String          // categoryId (or "uncategorized")
        let emoji: String
        let name: String
        let amount: Double      // total spent in this category this period
        let fraction: Double    // amount ÷ period total, in 0...1 (for the bar width)
        let rows: [TransactionRow]   // the individual charges in this category (for the dropdown)
    }

    // `@Published` = "when this changes, refresh any View watching it".
    @Published var cards: [Card] = []                       // all cards (for the picker)
    @Published var selectedCard: Card?                       // the card being viewed (optional)
    @Published var periodMode: PeriodMode = .month           // billing cycle vs. month
    @Published var viewMode: ViewMode = .list                // list vs. chart
    @Published var breakdown: [CategorySlice] = []           // per-category slices (chart view)
    @Published var dayGroups: [DayGroup] = []                // transactions grouped by day (list view)
    // A date that sits inside the period currently being viewed. We move it back/
    // forward by a month to step between periods, and derive the actual start/end
    // from it plus the selected `periodMode`.
    @Published var anchorDate: Date = Date()
    @Published var rows: [TransactionRow] = []               // the list the View renders
    @Published var total: Double = 0                         // sum of `rows` amounts

    // MARK: - Derived period (start, end, label)

    /// Whether the selected card can be shown by billing cycle (it has a corte set).
    var canUseBillingCycle: Bool {
        (selectedCard?.closingDay ?? 0) >= 1
    }

    /// First instant of the visible period (inclusive).
    var periodStart: Date {
        if periodMode == .billingCycle, canUseBillingCycle {
            return anchorDate.billingPeriod(closingDay: selectedCard!.closingDay).start
        }
        return anchorDate.startOfMonth
    }

    /// One instant past the end of the visible period (exclusive) — used so the
    /// filter `date < periodEnd` includes the whole period.
    var periodEnd: Date {
        if periodMode == .billingCycle, canUseBillingCycle {
            return anchorDate.billingPeriod(closingDay: selectedCard!.closingDay).end
        }
        return anchorDate.endOfMonth
    }

    /// Human label for the navigator, e.g. "June 2026" or "May 21 – Jun 20, 2026".
    var periodLabel: String {
        if periodMode == .billingCycle, canUseBillingCycle {
            // `periodEnd` is exclusive (next cycle's start), so step back one day to
            // show the last day actually inside this period.
            let inclusiveEnd = Calendar.current.date(byAdding: .day, value: -1, to: periodEnd) ?? periodEnd
            return "\(periodStart.shortDateString) – \(inclusiveEnd.shortDateYearString)"
        }
        return anchorDate.monthYearString
    }

    /// Called when the dashboard appears. Loads cards and picks a default one.
    func load() {
        cards = RealmService.shared.objects(Card.self)
        // Only choose a default the first time (when nothing is selected yet),
        // so we don't override the user's choice on every reload.
        if selectedCard == nil {
            selectedCard = cards.first   // `.first` is nil-safe: nil if there are no cards
            if let card = selectedCard {
                // Remember the choice so other screens can read it later.
                UserDefaults.standard.set(card.id, forKey: "selectedCardId")
                applyDefaultPeriodMode()
            }
        }
        reload()
    }

    /// The user picked a different card from the menu.
    func select(card: Card) {
        selectedCard = card
        UserDefaults.standard.set(card.id, forKey: "selectedCardId")
        // A different card may have a different corte (or none), so reset the period
        // mode to that card's natural default and jump back to today.
        anchorDate = Date()
        applyDefaultPeriodMode()
        reload()
    }

    /// The user flipped the Cycle/Month toggle.
    func setPeriodMode(_ mode: PeriodMode) {
        periodMode = mode
        reload()
    }

    /// The user flipped the List/Chart toggle. No reload needed — both views read
    /// from values `reload()` already computed (`rows` and `breakdown`).
    func setViewMode(_ mode: ViewMode) {
        viewMode = mode
    }

    /// Picks the right default view for the selected card: billing cycle when the
    /// card has a corte, otherwise calendar month. Cards with a corte are typically
    /// credit cards, where the statement period is the meaningful unit.
    private func applyDefaultPeriodMode() {
        periodMode = canUseBillingCycle ? .billingCycle : .month
    }

    /// Step the visible period one back / forward, then refresh. The anchor moves by
    /// a whole month either way — billing cycles are month-spaced, so this lands in
    /// the adjacent cycle just as it lands in the adjacent month.
    func previousPeriod() {
        // `date(byAdding:)` does calendar-correct math (handles year rollover, etc).
        // `?? anchorDate` keeps the old value if the math ever fails.
        anchorDate = Calendar.current.date(byAdding: .month, value: -1, to: anchorDate) ?? anchorDate
        reload()
    }

    func nextPeriod() {
        anchorDate = Calendar.current.date(byAdding: .month, value: 1, to: anchorDate) ?? anchorDate
        reload()
    }

    /// Recomputes `rows` and `total` for the selected card + current month.
    /// `private` because only this class should call it.
    private func reload() {
        // No card selected → show nothing and stop early.
        guard let card = selectedCard else {
            rows = []; total = 0; breakdown = []; dayGroups = []
            return
        }

        let start = periodStart
        let end = periodEnd
        let calendar = Calendar.current

        // The visible period's cycle ordinal, used to measure how many cycles a
        // purchase is from "now" (which installment to show).
        let visibleIndex = cycleIndex(of: start, closingDay: card.closingDay, mode: periodMode)

        // Build a quick lookup: categoryId → Category. A dictionary makes each
        // emoji/name lookup instant instead of re-searching the list every row.
        let categories = RealmService.shared.objects(Category.self)
        let categoryMap = Dictionary(uniqueKeysWithValues: categories.map { ($0.id, $0) })

        // Build the rows for this period. Normal charges are included when their date
        // falls inside the period; installment (MSI) purchases contribute the single
        // monthly part that lands in this period — even if the purchase itself was
        // months ago or is months ahead. We also tally each category as we go.
        var built: [TransactionRow] = []
        var categorySums: [String: Double] = [:]
        // Rows grouped by categoryId, so the chart can expand each category to show
        // its individual charges.
        var categoryRows: [String: [TransactionRow]] = [:]

        for tx in RealmService.shared.objects(Transaction.self) where tx.cardId == card.id {
            let emoji = categoryMap[tx.categoryId]?.emoji ?? "·"
            let categoryName = categoryMap[tx.categoryId]?.name ?? "Uncategorized"

            // Decide this transaction's contribution to the period (a monthly part for
            // an MSI purchase, or the full amount for a one-time charge), then build a
            // single row we file into all three buckets below.
            let row: TransactionRow
            if tx.installments >= 2 {
                // Which installment, if any, falls in the visible period? `offset` 0 is
                // the purchase cycle (1/N), 1 is the next cycle (2/N), and so on.
                let purchaseIndex = cycleIndex(of: tx.date, closingDay: card.closingDay, mode: periodMode)
                let offset = visibleIndex - purchaseIndex
                guard offset >= 0 && offset < tx.installments else { continue }

                let monthly = tx.amount / Double(tx.installments)
                // Show it on the purchase's day-of-month shifted into this period's
                // month, so it sorts and day-groups naturally within the period.
                let shownDate = calendar.date(byAdding: .month, value: offset, to: tx.date) ?? tx.date

                row = TransactionRow(
                    id: tx.id,
                    emoji: emoji,
                    category: categoryName,
                    description: tx.transactionDescription,
                    amount: monthly,
                    date: shownDate,
                    installmentLabel: "\(offset + 1)/\(tx.installments)"
                )
            } else {
                // Normal one-time charge: include only if it falls inside the period.
                guard tx.date >= start && tx.date < end else { continue }
                row = TransactionRow(
                    id: tx.id,
                    emoji: emoji,
                    category: categoryName,
                    description: tx.transactionDescription,
                    amount: tx.amount,
                    date: tx.date,
                    installmentLabel: nil
                )
            }

            built.append(row)
            categorySums[tx.categoryId, default: 0] += row.amount
            categoryRows[tx.categoryId, default: []].append(row)
        }

        rows = built.sorted { $0.date < $1.date }   // oldest first (earliest on top)
        total = rows.reduce(0) { $0 + $1.amount }

        // Group the rows by calendar day for the collapsible list. `Dictionary(grouping:)`
        // buckets the rows by the key we return — here the start of each row's day.
        let byDay = Dictionary(grouping: rows) { calendar.startOfDay(for: $0.date) }
        dayGroups = byDay.map { day, dayRows in
            DayGroup(
                // A stable string key for this day, so the View can remember which
                // days are expanded across reloads.
                id: String(day.timeIntervalSinceReferenceDate),
                date: day,
                total: dayRows.reduce(0) { $0 + $1.amount },
                rows: dayRows.sorted { $0.date < $1.date }
            )
        }
        .sorted { $0.date < $1.date }   // oldest day first, matching the flat list

        // Turn the per-category tallies into chart slices with a fraction of the total.
        breakdown = categorySums.map { categoryId, amount in
            let category = categoryMap[categoryId]
            return CategorySlice(
                id: categoryId.isEmpty ? "uncategorized" : categoryId,
                emoji: category?.emoji ?? "·",
                name: category?.name ?? "Uncategorized",
                amount: amount,
                fraction: total != 0 ? amount / total : 0,
                rows: (categoryRows[categoryId] ?? []).sorted { $0.date < $1.date }
            )
        }
        .sorted { $0.amount > $1.amount }   // biggest spend first
    }

    // MARK: - CSV export

    /// Builds a CSV of the rows currently shown (the selected card + visible period,
    /// installments included exactly as displayed). No AI — a plain dump of what's on
    /// screen, for spreadsheets or accounting.
    func exportCSVText() -> String {
        let dateFormatter = DateFormatter()
        dateFormatter.locale = Locale(identifier: "en_US_POSIX")
        dateFormatter.dateFormat = "yyyy-MM-dd"

        var lines = ["Date,Description,Category,Installment,Amount"]
        for row in rows {
            let fields = [
                dateFormatter.string(from: row.date),
                row.description,
                row.category,
                row.installmentLabel ?? "",
                // Plain dot-decimal number (no symbol/grouping) for spreadsheets.
                String(format: "%.2f", row.amount),
            ]
            lines.append(fields.map(Self.csvEscape).joined(separator: ","))
        }
        return lines.joined(separator: "\n")
    }

    /// A suggested file name like "BBVA Platinum — June 2026.csv", with characters
    /// that aren't safe in file names stripped out.
    var exportFileName: String {
        let cardName = selectedCard?.name ?? "Tabularium"
        let raw = "\(cardName) — \(periodLabel)"
        let cleaned = raw.components(separatedBy: CharacterSet(charactersIn: "/\\:*?\"<>|"))
            .joined(separator: " ")
        return cleaned + ".csv"
    }

    /// Wraps a field in quotes (and doubles internal quotes) when it contains a comma,
    /// quote, or newline — the standard CSV escaping rules.
    private static func csvEscape(_ field: String) -> String {
        guard field.contains(",") || field.contains("\"") || field.contains("\n") else { return field }
        return "\"" + field.replacingOccurrences(of: "\"", with: "\"\"") + "\""
    }

    /// Maps a date to a monotonic "cycle ordinal" (a `year*12 + month` integer) for
    /// the current period mode, so the difference between two ordinals is exactly how
    /// many cycles apart they are — which is how we pick the installment to show.
    private func cycleIndex(of date: Date, closingDay: Int, mode: PeriodMode) -> Int {
        let cal = Calendar.current
        let cycleStart: Date = (mode == .billingCycle && closingDay >= 1)
            ? date.billingPeriod(closingDay: closingDay).start
            : date.startOfMonth
        let comps = cal.dateComponents([.year, .month], from: cycleStart)
        return (comps.year ?? 0) * 12 + (comps.month ?? 0)
    }
}
