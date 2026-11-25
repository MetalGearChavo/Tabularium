import SwiftUI

/// View layer: a modal form for manually adding a new transaction to the selected card.
/// Close it with Save, keep it open with Add Another, or leave without saving via ✕ / Esc.
/// Uses the shared `TransactionFormContent` (calendar + form fields) so adding and editing
/// a transaction share the exact same UI.
struct AddTransactionSheet: View {
    // Explicit card ID passed by `DashboardView` (falls back to `@AppStorage` or
    // the first saved card in Realm so a saved charge is never orphaned with `""`).
    var cardId: String? = nil

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
    @State private var reimbursementStatus: ReimbursementOption.Status = .personal
    @State private var reimbursementNote: String = ""

    // How many transactions we've saved so far without closing the sheet, so we can
    // show a "N added" hint during a bulk entry session. `@State` because it's UI-only.
    @State private var savedCount: Int = 0

    // Which text field currently has the keyboard. `@FocusState` is SwiftUI's way to
    // read AND control focus: after "Save & Add Another" we set this back to `.amount`
    // so the user can immediately type the next charge without reaching for the mouse.
    @FocusState private var focusedField: TransactionFormContent.Field?

    // Categories loaded from Realm into `@State` so adding a new category inline
    // inside the dropdown immediately refreshes the picker list.
    @State private var categories: [Category] = []
    // Form is valid only if amount is a real number and description isn't blank.
    private var isValid: Bool { !amountText.isEmpty && Double(amountText) != nil && !description.isEmpty }

    /// The parsed MSI plan from `monthsText` (supports `"6"` → `1/6` or `"3/6"` → `3/6`).
    private var plan: InstallmentPlan {
        InstallmentPlan.parse(monthsText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
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
                reimbursementStatus: $reimbursementStatus,
                reimbursementNote: $reimbursementNote,
                categories: categories,
                onAddCategory: addCategory,
                onDeleteCategory: deleteCategory,
                focusedField: $focusedField
            )
            // Keep the form (and its floating CATEGORY dropdown overlay) layered
            // above the footer buttons (`Cancel`, `Add Another`, `Save`).
            .zIndex(10)

            HStack(spacing: 12) {
                // Cancel button on the left so the user has an obvious way out
                // alongside the ✕ in the top corner.
                Button {
                    dismiss()
                } label: {
                    Text("Cancel")
                        .font(.system(size: 13, design: .monospaced))
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)

                Spacer()

                // Saves the current entry but KEEPS the sheet open with the same date,
                // so you can enter a whole day's charges without re-picking the date.
                Button {
                    save(keepOpen: true)
                } label: {
                    Text("Add Another")
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                        .padding(.horizontal, 12)
                        .padding(.vertical, 7)
                        .background(Color.primary.opacity(0.08))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isValid)
                .opacity(isValid ? 1 : 0.4)

                // Saves the current entry and closes the sheet — the primary action
                // when adding a single transaction. `.contentShape(Rectangle())`
                // guarantees the entire padded button area registers the click even
                // while a TextField has active keyboard focus.
                Button {
                    save(keepOpen: false)
                } label: {
                    Text("Save")
                        .font(.system(size: 14, weight: .semibold, design: .monospaced))
                        .foregroundStyle(Color(nsColor: .windowBackgroundColor))
                        .padding(.horizontal, 16)
                        .padding(.vertical, 7)
                        .background(Color.primary)
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .disabled(!isValid)
                .opacity(isValid ? 1 : 0.4)
            }
        }
        .padding(22)
        .frame(width: TransactionFormContent.sheetWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(WindowDragEnablingView())
        // When the sheet appears, load categories and default to the first one.
        .onAppear {
            categories = RealmService.shared.objects(Category.self)
            selectedCategoryId = categories.first?.id ?? ""
            focusedField = .amount   // start with the cursor on AMOUNT, ready to type
        }
    }

    /// Saves a newly created category to Realm, reloads the category list, and
    /// immediately selects it for the current transaction.
    private func addCategory(emoji: String, name: String) {
        let category = Category()
        category.emoji = emoji
        category.name = name
        RealmService.shared.save(category)
        categories = RealmService.shared.objects(Category.self)
        selectedCategoryId = category.id
    }

    /// Deletes a category directly from the dropdown's hover trash button, reloads
    /// the category list, and falls back to the first remaining category (or `""`)
    /// if the deleted category was currently selected.
    private func deleteCategory(id: String) {
        RealmService.shared.delete(Category.self, id: id)
        categories = RealmService.shared.objects(Category.self)
        if selectedCategoryId == id {
            selectedCategoryId = categories.first?.id ?? ""
        }
    }

    /// Builds a `Transaction` from the form and saves it.
    ///
    /// - Parameter keepOpen: when `true` (the "Save & Add Another" button), the sheet
    ///   stays open and only the amount/description are cleared — the date, category,
    ///   and MSI count carry over so a run of same-day charges is fast to enter. When
    ///   `false` (the "Save" button), the sheet closes as before.
    private func save(keepOpen: Bool) {
        // Parse the entered amount safely (trimming any accidental spaces).
        let cleanAmount = amountText.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let amount = Double(cleanAmount) else { return }

        // Resolve the target card: explicit `cardId` from DashboardView → `@AppStorage`
        // `selectedCardId` → first card in Realm. This prevents saving a charge with
        // an empty `cardId` that wouldn't appear in the dashboard filter.
        let resolvedCardId: String = {
            if let explicit = cardId, !explicit.isEmpty { return explicit }
            if !selectedCardId.isEmpty { return selectedCardId }
            return RealmService.shared.objects(Card.self).first?.id ?? ""
        }()

        let transaction = Transaction()
        transaction.cardId = resolvedCardId
        // If the user entered a mid-stream MSI (e.g. 3/6 on Nov 7 with $500), shift the
        // stored purchase date back by -(current - 1) months (Sep 7) and multiply the
        // monthly payment ($500 × 6 = $3,000) so every period shows $500 / mes.
        transaction.date = plan.effectivePurchaseDate(from: date)
        transaction.amount = plan.storedTotalAmount(fromEnteredAmount: amount)
        transaction.transactionDescription = description
        transaction.categoryId = selectedCategoryId
        transaction.reviewed = true   // manually added → already "reviewed"
        transaction.installments = plan.total   // 1 = single charge; 2+ = MSI (amount is the total)
        transaction.reimbursementStatus = reimbursementStatus.rawValue
        transaction.reimbursementNote = reimbursementStatus == .personal
            ? ""
            : reimbursementNote.trimmingCharacters(in: .whitespacesAndNewlines)
        RealmService.shared.save(transaction)
        savedCount += 1

        if keepOpen {
            // Clear only the per-charge fields; keep date/category for the next one.
            amountText = ""
            description = ""
            monthsText = "1"
            reimbursementStatus = .personal
            reimbursementNote = ""
            focusedField = .amount   // put the cursor back on AMOUNT to type the next charge
        } else {
            dismiss()
        }
    }
}
