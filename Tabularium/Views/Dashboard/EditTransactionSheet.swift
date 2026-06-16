import SwiftUI

/// A modal form for editing (or deleting) an existing transaction.
///
/// Almost identical to `AddTransactionSheet`, but it loads an existing record by
/// `transactionId`, pre-fills the fields, and updates in place instead of inserting.
struct EditTransactionSheet: View {
    // Passed in by the dashboard when a row is tapped. `let` = it never changes here.
    let transactionId: String

    @Environment(\.dismiss) private var dismiss

    @State private var date: Date = Date()
    @State private var amountText: String = ""
    @State private var description: String = ""
    @State private var selectedCategoryId: String = ""
    @State private var monthsText: String = "1"       // installments (MSI); 1 = single charge
    // Guards against re-loading the fields every time the view re-renders
    // (we only want to fill them from the database once, on first appearance).
    @State private var loaded = false

    private var categories: [Category] { RealmService.shared.objects(Category.self) }
    private var isValid: Bool { !amountText.isEmpty && Double(amountText) != nil && !description.isEmpty }

    // Number of installments, at least 1. `amountText` is the FULL price.
    private var months: Int { max(1, Int(monthsText) ?? 1) }
    // A "= $X / mes" hint shown only for a real installment plan (2+ months).
    private var monthlyPreview: String? {
        guard months >= 2, let total = Double(amountText), total > 0 else { return nil }
        return "= \((total / Double(months)).currencyString) / mes"
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Edit Transaction")
                .font(.system(size: 16, weight: .semibold, design: .monospaced))

            VStack(alignment: .leading, spacing: 16) {
                field(label: "DATE") {
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                }

                field(label: "AMOUNT") {
                    TextField("0.00", text: $amountText)
                        .font(.system(size: 14, design: .monospaced))
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        // Keep only digits and a single dot (same rule as Add).
                        .onChange(of: amountText) { _, value in
                            let filtered = value.amountInputFiltered
                            if filtered != amountText {
                                amountText = filtered
                            }
                        }
                }

                field(label: "DESCRIPTION") {
                    TextField("Walmart", text: $description)
                        .font(.system(size: 14, design: .monospaced))
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }

                field(label: "CATEGORY") {
                    Picker("", selection: $selectedCategoryId) {
                        Text("None").tag("")
                        ForEach(categories) { cat in
                            Text("\(cat.emoji) \(cat.name)").tag(cat.id)
                        }
                    }
                    .labelsHidden()
                }

                field(label: "MONTHS · MSI (1 = de contado)") {
                    HStack(spacing: 10) {
                        TextField("1", text: $monthsText)
                            .font(.system(size: 14, design: .monospaced))
                            .textFieldStyle(.plain)
                            .padding(8)
                            .background(Color.primary.opacity(0.06))
                            .clipShape(RoundedRectangle(cornerRadius: 6))
                            .frame(width: 70)
                            .onChange(of: monthsText) { _, value in
                                let digits = String(value.filter(\.isNumber).prefix(2))
                                if digits != monthsText { monthsText = digits }
                            }

                        if let preview = monthlyPreview {
                            Text(preview)
                                .font(.system(size: 12, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            Spacer()

            HStack {
                Button("Delete") { delete() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.red)

                Spacer()

                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                Button("Save") { save() }
                    .buttonStyle(.plain)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .disabled(!isValid)
                    .opacity(isValid ? 1 : 0.4)
                    .padding(.leading, 16)
            }
        }
        .padding(28)
        .frame(width: 340)
        // `perform:` runs this function when the view appears. (Same as `.onAppear { loadIfNeeded() }`.)
        .onAppear(perform: loadIfNeeded)
    }

    @ViewBuilder
    private func field<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            content()
        }
    }

    /// Fetches the transaction from the database (once) and copies its values into
    /// the form fields so the user sees the current data.
    private func loadIfNeeded() {
        // `guard` chains two conditions: only proceed if we haven't loaded yet AND
        // the transaction actually exists. `tx` is the found record.
        guard !loaded, let tx = RealmService.shared.object(Transaction.self, id: transactionId) else { return }
        date = tx.date
        amountText = String(tx.amount)   // number → text for the TextField (the FULL price)
        description = tx.transactionDescription
        selectedCategoryId = tx.categoryId
        // Show the installment count, or "1" for a normal one-time charge.
        monthsText = tx.installments >= 2 ? String(tx.installments) : "1"
        loaded = true
    }

    /// Writes the edited values back onto the same record (by id), then closes.
    private func save() {
        guard let amount = Double(amountText) else { return }
        // The closure receives the live database object (`tx`); whatever we change
        // on it inside `update` is saved.
        RealmService.shared.update(Transaction.self, id: transactionId) { tx in
            tx.date = date
            tx.amount = amount
            tx.transactionDescription = description
            tx.categoryId = selectedCategoryId
            tx.reviewed = true
            tx.installments = months   // 1 = single charge; 2+ = MSI (amount is the total)
        }
        dismiss()
    }

    /// Permanently removes this transaction, then closes.
    private func delete() {
        RealmService.shared.delete(Transaction.self, id: transactionId)
        dismiss()
    }
}
