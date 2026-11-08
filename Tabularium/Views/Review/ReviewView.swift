import SwiftUI
import RealmSwift   // for `Statement.transactions`, a Realm `List<Transaction>`

/// The post-import review screen: every transaction the AI parsed from a dropped
/// PDF statement, editable before anything touches the database. The user can
/// fix a wrong date/amount/category, delete a false positive, and pick which
/// card the charges belong to, then save them all at once.
///
/// This is a **View** — it reads/edits a local working copy and, on save, calls
/// `RealmService` directly (small enough not to warrant its own ViewModel; the
/// real logic — extraction + AI parsing — already lives in `ImportViewModel`).
struct ReviewView: View {
    let categories: [Category]
    let cards: [Card]
    let sourceFileName: String

    @Environment(\.dismiss) private var dismiss

    // A local, editable working copy — nothing touches Realm until "Save All".
    // `@State` because this view owns and mutates its own draft data.
    @State private var rows: [ParsedTransaction]
    @State private var selectedCardId: String

    /// `parsed`/`defaultCardId` seed the local `@State` once, at init — after
    /// that, edits only affect this view's own copy, not the caller's.
    init(parsed: [ParsedTransaction], categories: [Category], cards: [Card], defaultCardId: String, sourceFileName: String) {
        self.categories = categories
        self.cards = cards
        self.sourceFileName = sourceFileName
        _rows = State(initialValue: parsed)
        _selectedCardId = State(initialValue: defaultCardId)
    }

    private var total: Double { rows.reduce(0) { $0 + $1.amount } }

    var body: some View {
        VStack(spacing: 0) {
            header
            Divider()

            if rows.isEmpty {
                Text("No transactions to review")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                // `$rows` gives `ForEach` a binding to each element, so
                // `ReviewRowView` can edit a row in place via `@Binding`.
                List {
                    ForEach($rows) { $row in
                        ReviewRowView(row: $row, categories: categories) {
                            rows.removeAll { $0.id == row.id }
                        }
                    }
                }
                .listStyle(.plain)
            }

            Divider()
            footer
        }
        .font(.system(.body, design: .monospaced))
        .frame(width: 620, height: 520)
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Text("Review Import")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))
                Spacer()
                Text("\(rows.count) transactions")
                    .font(.system(size: 11, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
            Text(sourceFileName)
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.secondary)

            if !cards.isEmpty {
                Picker("Card", selection: $selectedCardId) {
                    ForEach(cards) { card in
                        Text("\(card.name) •••• \(card.lastFour)").tag(card.id)
                    }
                }
            }
        }
        .padding(20)
    }

    private var footer: some View {
        HStack {
            Button("Cancel") { dismiss() }
                .buttonStyle(.plain)
                .foregroundStyle(.secondary)

            Spacer()

            Text(total.currencyString)
                .font(.system(size: 13, weight: .semibold, design: .monospaced))

            Button("Save All") { saveAll() }
                .buttonStyle(.plain)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .disabled(rows.isEmpty || selectedCardId.isEmpty)
                .opacity(rows.isEmpty || selectedCardId.isEmpty ? 0.4 : 1)
                .padding(.leading, 16)
        }
        .padding(20)
    }

    /// Writes a new `Statement` plus one `Transaction` per reviewed row, all
    /// inside a single Realm write (via `RealmService.save`'s cascade — see
    /// `Statement.transactions`), then closes the sheet.
    private func saveAll() {
        let statement = Statement()
        statement.cardId = selectedCardId
        statement.periodStart = rows.map(\.date).min() ?? Date()
        statement.periodEnd = rows.map(\.date).max() ?? Date()
        statement.importedAt = Date()

        for row in rows {
            let transaction = Transaction()
            transaction.statementId = statement.id
            transaction.cardId = selectedCardId
            transaction.date = row.date
            transaction.amount = row.amount
            transaction.transactionDescription = row.description
            transaction.categoryId = row.categoryId
            transaction.reviewed = true   // the user just confirmed it here
            statement.transactions.append(transaction)
        }

        // `statement` is still unmanaged at this point, so appending to its
        // `List<Transaction>` above didn't need a write transaction. `save`
        // wraps the whole thing in one, and Realm cascades to insert every
        // transaction reachable from `statement.transactions` along with it.
        RealmService.shared.save(statement)
        dismiss()
    }
}

// MARK: - Row

/// One editable row: date, description, amount, category — plus a delete
/// control for false positives the AI picked up. Bound directly to its
/// `ParsedTransaction` via `@Binding`, so edits here update the parent's array.
private struct ReviewRowView: View {
    @Binding var row: ParsedTransaction
    let categories: [Category]
    let onDelete: () -> Void

    var body: some View {
        HStack(spacing: 10) {
            DatePicker("", selection: $row.date, displayedComponents: .date)
                .labelsHidden()
                .frame(width: 110)

            TextField("Description", text: $row.description)
                .textFieldStyle(.plain)

            // `TextField(value:format:)` binds straight to a numeric type (here
            // `Double`) through a `FormatStyle`, converting to/from the text the
            // user sees — no manual string parsing needed, unlike the free-text
            // amount fields in Add/EditTransactionSheet.
            TextField("0.00", value: $row.amount, format: .number.precision(.fractionLength(2)))
                .textFieldStyle(.plain)
                .frame(width: 80)

            Picker("", selection: $row.categoryId) {
                Text("None").tag("")
                ForEach(categories) { cat in
                    Text("\(cat.emoji) \(cat.name)").tag(cat.id)
                }
            }
            .labelsHidden()
            .frame(width: 150)

            Button(action: onDelete) {
                Image(systemName: "trash")
                    .foregroundStyle(.red)
            }
            .buttonStyle(.plain)
        }
        .font(.system(size: 12, design: .monospaced))
        .padding(.vertical, 4)
    }
}

#Preview {
    ReviewView(
        parsed: [
            ParsedTransaction(date: Date(), description: "OXXO Gasolina Sur", amount: 850.00, categoryId: ""),
            ParsedTransaction(date: Date(), description: "Uber Eats", amount: 210.50, categoryId: ""),
        ],
        categories: [],
        cards: [],
        defaultCardId: "",
        sourceFileName: "estado_bbva.pdf"
    )
}
