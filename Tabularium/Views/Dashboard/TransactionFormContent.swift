import SwiftUI

/// View layer: the shared two-column form body used by both `AddTransactionSheet`
/// and `EditTransactionSheet` — an always-visible month calendar (`DayGridPicker`)
/// on the left, and the `DATE`, `AMOUNT`, `DESCRIPTION`, `CATEGORY`, and smart
/// `MONTHS · MSI` (`"6"` or `"3/6"`) fields on the right.
///
/// Extracting this into one component guarantees that adding and editing a
/// transaction always look and behave identically (DRY — Don't Repeat Yourself).
struct TransactionFormContent: View {
    // `@Binding` connects each field back to the `@State` owned by the parent sheet.
    @Binding var date: Date
    @Binding var amountText: String
    @Binding var description: String
    @Binding var selectedCategoryId: String
    @Binding var monthsText: String

    let categories: [Category]

    // `@FocusState.Binding` lets the parent sheet pass its `@FocusState` down so
    // both the parent (e.g. after "Add Another") and this view (when a calendar day
    // is clicked) can move the keyboard cursor to AMOUNT.
    var focusedField: FocusState<Field?>.Binding

    /// The focusable text fields inside the transaction form.
    enum Field {
        case amount
        case description
    }

    /// Standard width for sheets hosting this two-column form (calendar + gap + fields).
    static let sheetWidth: CGFloat = 640

    /// The parsed MSI plan from `monthsText` (supports `"6"` → `1/6` or `"3/6"` → `3/6`).
    private var plan: InstallmentPlan {
        InstallmentPlan.parse(monthsText)
    }

    /// Live hint for installment plans (`total >= 2`):
    /// - For a new MSI (`"6"`), shows `"= $500.00 / mes"`.
    /// - For a backtracked MSI (`"3/6"`), the entered amount is this month's payment,
    ///   so it shows `"$500.00 / mes (total $3,000.00) · 3/6 now · 1/6 on Sep 7"`.
    private var monthlyPreview: String? {
        guard plan.total >= 2 else { return nil }
        var parts: [String] = []
        if let entered = Double(amountText), entered > 0 {
            let monthly = plan.monthlyAmount(fromEnteredAmount: entered)
            let total = plan.storedTotalAmount(fromEnteredAmount: entered)
            if plan.current >= 2 {
                parts.append("\(monthly.currencyString) / mes (total \(total.currencyString))")
            } else {
                parts.append("= \(monthly.currencyString) / mes")
            }
        }
        if plan.current >= 2 {
            let startDate = plan.effectivePurchaseDate(from: date)
            parts.append("\(plan.current)/\(plan.total) now · 1/\(plan.total) on \(startDate.shortDateString)")
        }
        return parts.isEmpty ? nil : parts.joined(separator: " · ")
    }

    var body: some View {
        // Two columns: the big always-visible calendar on the left, the form fields
        // on the right. Side-by-side keeps the sheet compact vertically.
        HStack(alignment: .top, spacing: 28) {
            // Clicking a day sets `date` and jumps the cursor to AMOUNT.
            DayGridPicker(selection: $date) {
                focusedField.wrappedValue = .amount
            }

            VStack(alignment: .leading, spacing: 16) {
                field(label: "DATE") {
                    Text(date.longDayString)
                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                        .padding(.vertical, 4)
                }

                field(label: "AMOUNT") {
                    TextField("0.00", text: $amountText)
                        .font(.system(size: 14, design: .monospaced))
                        .textFieldStyle(.plain)
                        .padding(8)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .focused(focusedField, equals: .amount)
                        // Strip anything that isn't a digit or the first dot on every keystroke.
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
                        .focused(focusedField, equals: .description)
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

                field(label: "MONTHS · MSI (e.g. 6 or 3/6)") {
                    VStack(alignment: .leading, spacing: 6) {
                        HStack(spacing: 10) {
                            TextField("1", text: $monthsText)
                                .font(.system(size: 14, design: .monospaced))
                                .textFieldStyle(.plain)
                                .padding(8)
                                .background(Color.primary.opacity(0.06))
                                .clipShape(RoundedRectangle(cornerRadius: 6))
                                .frame(width: 84)
                                // Keep only up to two digits, an optional "/", and up to two digits after it.
                                .onChange(of: monthsText) { _, value in
                                    let filtered = InstallmentPlan.filterSmartInput(value)
                                    if filtered != monthsText { monthsText = filtered }
                                }

                            Text(plan.total >= 2 ? "\(plan.current) of \(plan.total) months" : "de contado")
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }

                        if let preview = monthlyPreview {
                            Text(preview)
                                .font(.system(size: 11, design: .monospaced))
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    /// Reusable labeled-field wrapper.
    @ViewBuilder
    private func field<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            content()
        }
    }
}
