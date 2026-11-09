import SwiftUI

/// A modal form for editing an existing card: name, bank, last 4, type, and the
/// "fecha de corte" (closing day). Mirrors `EditTransactionSheet` — it loads a
/// record by `cardId`, pre-fills the fields, and updates in place.
struct EditCardSheet: View {
    // Passed in by Settings when a card row is tapped. `let` = never changes here.
    let cardId: String

    // `dismiss` is provided by SwiftUI; calling `dismiss()` closes this sheet.
    @Environment(\.dismiss) private var dismiss

    // The form fields. `@State` because they're temporary UI values owned by this view.
    @State private var name: String = ""
    @State private var bank: String = ""
    @State private var lastFour: String = ""
    @State private var type: String = "credit"
    @State private var closingDay: String = ""      // optional; blank = no corte
    @State private var monthlyBudget: String = ""   // optional; blank or 0 = no budget
    // Guards against re-loading the fields on every re-render (load once, on appear).
    @State private var loaded = false

    // Valid when the required fields are filled and last 4 is exactly four digits.
    // Closing day is optional, so it doesn't affect validity.
    private var isValid: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !bank.trimmingCharacters(in: .whitespaces).isEmpty
            && lastFour.count == 4
            && lastFour.allSatisfy(\.isNumber)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            Text("Edit Card")
                .font(.system(size: 16, weight: .semibold, design: .monospaced))

            VStack(alignment: .leading, spacing: 16) {
                field(label: "NAME") {
                    input("BBVA Platinum", text: $name)
                }

                field(label: "BANK") {
                    input("BBVA", text: $bank)
                }

                field(label: "LAST 4") {
                    input("1234", text: $lastFour)
                        // Keep only digits, at most 4.
                        .onChange(of: lastFour) { _, value in
                            let digits = String(value.filter(\.isNumber).prefix(4))
                            if digits != lastFour { lastFour = digits }
                        }
                }

                field(label: "CLOSING DAY / CORTE (OPTIONAL)") {
                    input("21", text: $closingDay)
                        // Keep only digits, at most 2; 1–31 enforced on save.
                        .onChange(of: closingDay) { _, value in
                            let digits = String(value.filter(\.isNumber).prefix(2))
                            if digits != closingDay { closingDay = digits }
                        }
                }

                field(label: "MONTHLY BUDGET (OPTIONAL)") {
                    input("20000.00", text: $monthlyBudget)
                        .onChange(of: monthlyBudget) { _, value in
                            let filtered = value.amountInputFiltered
                            if filtered != monthlyBudget { monthlyBudget = filtered }
                        }
                }

                field(label: "TYPE") {
                    Picker("", selection: $type) {
                        Text("Credit").tag("credit")
                        Text("Debit").tag("debit")
                    }
                    .pickerStyle(.segmented)
                    .labelsHidden()
                    .frame(width: 160)
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
                    .disabled(!isValid)
                    .opacity(isValid ? 1 : 0.4)
            }
        }
        .padding(28)
        .frame(width: 360)
        .onAppear(perform: loadIfNeeded)
    }

    /// Reusable labeled-field wrapper (same pattern as the transaction sheets).
    @ViewBuilder
    private func field<Content: View>(label: String, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)
            content()
        }
    }

    /// A styled monospaced text input, to avoid repeating the modifiers per field.
    private func input(_ placeholder: String, text: Binding<String>) -> some View {
        TextField(placeholder, text: text)
            .font(.system(size: 14, design: .monospaced))
            .textFieldStyle(.plain)
            .padding(8)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
    }

    /// Loads the card (once) and copies its values into the form fields.
    private func loadIfNeeded() {
        guard !loaded, let card = RealmService.shared.object(Card.self, id: cardId) else { return }
        name = card.name
        bank = card.bank
        lastFour = card.lastFour
        type = card.type
        // Show an empty field rather than "0" when the card has no corte or budget.
        closingDay = card.closingDay >= 1 ? String(card.closingDay) : ""
        monthlyBudget = card.monthlyBudget > 0 ? String(card.monthlyBudget) : ""
        loaded = true
    }

    /// Writes the edited values back onto the same record (by id), then closes.
    private func save() {
        RealmService.shared.update(Card.self, id: cardId) { card in
            card.name = name.trimmingCharacters(in: .whitespaces)
            card.bank = bank.trimmingCharacters(in: .whitespaces)
            card.lastFour = lastFour
            card.type = type
            // A valid 1–31 sets the corte; anything else clears it back to 0 ("none").
            if let day = Int(closingDay), (1...31).contains(day) {
                card.closingDay = day
            } else {
                card.closingDay = 0
            }
            if let budget = Double(monthlyBudget), budget > 0 {
                card.monthlyBudget = budget
            } else {
                card.monthlyBudget = 0
            }
        }
        dismiss()
    }
}
