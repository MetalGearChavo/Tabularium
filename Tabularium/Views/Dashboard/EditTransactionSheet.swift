import SwiftUI

/// View layer: a modal form for editing (or deleting) an existing transaction.
///
/// Shares `TransactionFormContent` (`DayGridPicker` + form fields, including the
/// smart `"6"` / `"3/6"` MSI box) with `AddTransactionSheet`, loading the existing
/// record by `transactionId` on appear and updating it in place on Save.
struct EditTransactionSheet: View {
    // Passed in by the dashboard when a row is tapped. `let` = it never changes here.
    let transactionId: String
    // The date and installment label ("5/12") shown on the dashboard row the user
    // clicked, so editing a mid-stream MSI anchors on the visible period's date
    // instead of double-backdating the stored purchase date.
    var displayedRowDate: Date? = nil
    var installmentLabel: String? = nil

    @Environment(\.dismiss) private var dismiss

    @State private var date: Date = Date()
    @State private var amountText: String = ""
    @State private var description: String = ""
    @State private var selectedCategoryId: String = ""
    @State private var monthsText: String = "1"       // smart MSI field: "1", "6" (1/6), or "3/6"
    @State private var reimbursementStatus: ReimbursementOption.Status = .personal
    @State private var reimbursementNote: String = ""
    // Guards against re-loading the fields every time the view re-renders
    // (we only want to fill them from the database once, on first appearance).
    @State private var loaded = false

    @FocusState private var focusedField: TransactionFormContent.Field?

    // Categories loaded into `@State` so adding a new category inline inside the
    // dropdown immediately updates the available options.
    @State private var categories: [Category] = []
    private var isValid: Bool { !amountText.isEmpty && Double(amountText) != nil && !description.isEmpty }

    /// The parsed MSI plan from `monthsText` (supports `"6"` → `1/6` or `"3/6"` → `3/6`).
    private var plan: InstallmentPlan {
        InstallmentPlan.parse(monthsText)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            HStack {
                Text("Edit Transaction")
                    .font(.system(size: 16, weight: .semibold, design: .monospaced))

                Spacer()

                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
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
            // above the footer buttons (`Delete`, `Cancel`, `Save`).
            .zIndex(10)

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
        .padding(22)
        .frame(width: TransactionFormContent.sheetWidth)
        .fixedSize(horizontal: false, vertical: true)
        .background(WindowDragEnablingView())
        // `perform:` runs this function when the view appears. (Same as `.onAppear { loadIfNeeded() }`.)
        .onAppear(perform: loadIfNeeded)
    }

    /// Fetches the transaction from the database (once) and copies its values into
    /// the form fields so the user sees the current data.
    private func loadIfNeeded() {
        categories = RealmService.shared.objects(Category.self)
        // `guard` chains two conditions: only proceed if we haven't loaded yet AND
        // the transaction actually exists. `tx` is the found record.
        guard !loaded, let tx = RealmService.shared.object(Transaction.self, id: transactionId) else { return }
        let seed = InstallmentPlan.editFormSeed(
            storedTotalAmount: tx.amount,
            totalInstallments: tx.installments,
            storedPurchaseDate: tx.date,
            displayedRowDate: displayedRowDate,
            installmentLabel: installmentLabel
        )
        date = seed.date
        amountText = seed.amountText
        description = tx.transactionDescription
        selectedCategoryId = tx.categoryId
        monthsText = seed.monthsText
        let opt = ReimbursementOption(rawStatus: tx.reimbursementStatus, note: tx.reimbursementNote)
        reimbursementStatus = opt.status
        reimbursementNote = opt.note
        loaded = true
    }

    /// Saves a newly created category to Realm, reloads the category list, and
    /// immediately selects it for the transaction being edited.
    private func addCategory(emoji: String, name: String) {
        let category = Category()
        category.emoji = emoji
        category.name = name
        RealmService.shared.save(category)
        categories = RealmService.shared.objects(Category.self)
        selectedCategoryId = category.id
    }

    /// Deletes a category directly from the dropdown's hover trash button, reloads
    /// the category list, and clears or updates the selection if it was active.
    private func deleteCategory(id: String) {
        RealmService.shared.delete(Category.self, id: id)
        categories = RealmService.shared.objects(Category.self)
        if selectedCategoryId == id {
            selectedCategoryId = categories.first?.id ?? ""
        }
    }

    /// Writes the edited values back onto the same record (by id), then closes.
    private func save() {
        guard let amount = Double(amountText) else { return }
        // The closure receives the live database object (`tx`); whatever we change
        // on it inside `update` is saved.
        RealmService.shared.update(Transaction.self, id: transactionId) { tx in
            tx.date = plan.effectivePurchaseDate(from: date)
            tx.amount = plan.storedTotalAmount(fromEnteredAmount: amount)
            tx.transactionDescription = description
            tx.categoryId = selectedCategoryId
            tx.reviewed = true
            tx.installments = plan.total   // 1 = single charge; 2+ = MSI (amount is the total)
            tx.reimbursementStatus = reimbursementStatus.rawValue
            tx.reimbursementNote = reimbursementStatus == .personal
                ? ""
                : reimbursementNote.trimmingCharacters(in: .whitespacesAndNewlines)
            tx.personalShareAmount = 0
        }
        dismiss()
    }

    /// Permanently removes this transaction, then closes.
    private func delete() {
        RealmService.shared.delete(Transaction.self, id: transactionId)
        dismiss()
    }
}
