import SwiftUI

/// A modal form for manually adding a new transaction to the selected card.
struct AddTransactionSheet: View {
    // Reads which card is currently selected (saved by the dashboard).
    @AppStorage("selectedCardId") private var selectedCardId = ""

    // `dismiss` is provided by SwiftUI; calling `dismiss()` closes this sheet.
    @Environment(\.dismiss) private var dismiss

    // The form fields. `@State` because they're temporary UI values owned by this view.
    @State private var date: Date = Date()
    @State private var amountText: String = ""        // kept as text; parsed to a number on save
    @State private var description: String = ""
    @State private var selectedCategoryId: String = ""
    @State private var monthsText: String = "1"       // installments (MSI); 1 = single charge

    // Computed properties (recalculated each time they're read):
    private var categories: [Category] { RealmService.shared.objects(Category.self) }
    // Form is valid only if amount is a real number and description isn't blank.
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
            Text("Add Transaction")
                .font(.system(size: 16, weight: .semibold, design: .monospaced))

            VStack(alignment: .leading, spacing: 16) {
                // `field(label:)` is a small helper (defined below) that wraps each
                // input with a label, so we don't repeat the styling four times.
                field(label: "DATE") {
                    DatePicker("", selection: $date, displayedComponents: .date)
                        .labelsHidden()
                }

                field(label: "AMOUNT") {
                    TextField("0.00", text: $amountText)   // `$amountText` = two-way binding
                        .font(.system(size: 14, design: .monospaced))
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        // Strip anything that isn't a digit or the first dot, on every
                        // keystroke. The guard avoids an endless write loop.
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
                    // A dropdown bound to `selectedCategoryId`. Each option's `.tag`
                    // is the value stored when that option is chosen.
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
                            // Keep only digits, at most 2 (so up to 99 months).
                            .onChange(of: monthsText) { _, value in
                                let digits = String(value.filter(\.isNumber).prefix(2))
                                if digits != monthsText { monthsText = digits }
                            }

                        // Live "= $X / mes" hint for installment plans.
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
                Button("Cancel") { dismiss() }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)

                Spacer()

                Button("Save") { save() }
                    .buttonStyle(.plain)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .disabled(!isValid)              // grey out until the form is valid
                    .opacity(isValid ? 1 : 0.4)      // and visually dim it
            }
        }
        .padding(28)
        .frame(width: 340)
        // When the sheet appears, default the category picker to the first category.
        .onAppear {
            selectedCategoryId = categories.first?.id ?? ""
        }
    }

    /// Reusable labeled-field wrapper. The `@ViewBuilder content` parameter lets a
    /// caller pass in any view (the actual input control) to sit under the label.
    /// `<Content: View>` is a generic so it accepts any kind of view.
    @ViewBuilder
    private func field<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            content()
        }
    }

    /// Builds a `Transaction` from the form and saves it, then closes the sheet.
    private func save() {
        // `Double(amountText)` returns an optional (nil if the text isn't a number).
        // `guard` bails out safely if parsing fails.
        guard let amount = Double(amountText) else { return }
        let transaction = Transaction()
        transaction.cardId = selectedCardId
        transaction.date = date
        transaction.amount = amount
        transaction.transactionDescription = description
        transaction.categoryId = selectedCategoryId
        transaction.reviewed = true   // manually added → already "reviewed"
        transaction.installments = months   // 1 = single charge; 2+ = MSI (amount is the total)
        RealmService.shared.save(transaction)
        dismiss()
    }
}
