import SwiftUI

/// View layer: a modal form for manually adding a new transaction to the selected card.
/// Close it with Save, keep it open with Add Another, or leave without saving via ✕ / Esc.
/// Uses the shared `TransactionFormContent` (calendar + form fields) so adding and editing
/// a transaction share the exact same UI.
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
    @State private var monthsText: String = "1"       // smart MSI field: "1", "6" (1/6), or "3/6"

    // How many transactions we've saved so far without closing the sheet, so we can
    // show a "N added" hint during a bulk entry session. `@State` because it's UI-only.
    @State private var savedCount: Int = 0

    // Which text field currently has the keyboard. `@FocusState` is SwiftUI's way to
    // read AND control focus: after "Save & Add Another" we set this back to `.amount`
    // so the user can immediately type the next charge without reaching for the mouse.
    @FocusState private var focusedField: TransactionFormContent.Field?

    // Computed properties (recalculated each time they're read):
    private var categories: [Category] { RealmService.shared.objects(Category.self) }
    // Form is valid only if amount is a real number and description isn't blank.
    private var isValid: Bool { !amountText.isEmpty && Double(amountText) != nil && !description.isEmpty }

    /// The parsed MSI plan from `monthsText` (supports `"6"` → `1/6` or `"3/6"` → `3/6`).
    private var plan: InstallmentPlan {
        InstallmentPlan.parse(monthsText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            HStack {
                Text("Add Transaction")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))

                Spacer()

                // During a bulk session, remind the user how many they've saved so far.
                // Only appears once at least one has been added.
                if savedCount > 0 {
                    Text("\(savedCount) added")
                        .font(.system(size: 11, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                // Closes the sheet WITHOUT saving whatever is currently in the form.
                // Anything already saved via "Add Another" stays saved — it's in Realm.
                Button {
                    dismiss()
                } label: {
                    // `Image(systemName:)` draws an SF Symbol, Apple's built-in icon set.
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                // `.keyboardShortcut(.cancelAction)` binds this button to the Esc key.
                // On macOS a sheet has no built-in close control and ignores clicks
                // outside it, so without this there'd be no keyboard way out at all.
                .keyboardShortcut(.cancelAction)
                // `.help` is the hover tooltip on macOS.
                .help("Close without saving (Esc)")
            }

            TransactionFormContent(
                date: $date,
                amountText: $amountText,
                description: $description,
                selectedCategoryId: $selectedCategoryId,
                monthsText: $monthsText,
                categories: categories,
                focusedField: $focusedField
            )

            Spacer()

            HStack {
                // Saves the current entry and closes the sheet — the normal "I'm done"
                // action. A blank form keeps it disabled; to leave without saving, use
                // the ✕ in the header (or Esc).
                Button("Save") { save(keepOpen: false) }
                    .buttonStyle(.plain)
                    .foregroundStyle(.secondary)
                    .disabled(!isValid)
                    .opacity(isValid ? 1 : 0.4)

                Spacer()

                // Saves the current entry but KEEPS the sheet open with the same date,
                // so you can enter a whole day's charges without re-picking the date.
                Button("Add Another") { save(keepOpen: true) }
                    .buttonStyle(.plain)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .disabled(!isValid)              // grey out until the form is valid
                    .opacity(isValid ? 1 : 0.4)      // and visually dim it
            }
        }
        .padding(28)
        .frame(width: TransactionFormContent.sheetWidth)
        // When the sheet appears, default the category picker to the first category.
        .onAppear {
            selectedCategoryId = categories.first?.id ?? ""
            focusedField = .amount   // start with the cursor on AMOUNT, ready to type
        }
    }

    /// Builds a `Transaction` from the form and saves it.
    ///
    /// - Parameter keepOpen: when `true` (the "Save & Add Another" button), the sheet
    ///   stays open and only the amount/description are cleared — the date, category,
    ///   and MSI count carry over so a run of same-day charges is fast to enter. When
    ///   `false` (the "Save" button), the sheet closes as before.
    private func save(keepOpen: Bool) {
        // `Double(amountText)` returns an optional (nil if the text isn't a number).
        // `guard` bails out safely if parsing fails.
        guard let amount = Double(amountText) else { return }
        let transaction = Transaction()
        transaction.cardId = selectedCardId
        // If the user entered a mid-stream MSI (e.g. 3/6 on Nov 7 with $500), shift the
        // stored purchase date back by -(current - 1) months (Sep 7) and multiply the
        // monthly payment ($500 × 6 = $3,000) so every period shows $500 / mes.
        transaction.date = plan.effectivePurchaseDate(from: date)
        transaction.amount = plan.storedTotalAmount(fromEnteredAmount: amount)
        transaction.transactionDescription = description
        transaction.categoryId = selectedCategoryId
        transaction.reviewed = true   // manually added → already "reviewed"
        transaction.installments = plan.total   // 1 = single charge; 2+ = MSI (amount is the total)
        RealmService.shared.save(transaction)
        savedCount += 1

        if keepOpen {
            // Clear only the per-charge fields; keep date/category for the next one.
            amountText = ""
            description = ""
            monthsText = "1"
            focusedField = .amount   // put the cursor back on AMOUNT to type the next charge
        } else {
            dismiss()
        }
    }
}
