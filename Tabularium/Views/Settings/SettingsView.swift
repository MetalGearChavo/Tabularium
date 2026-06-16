import SwiftUI
import AppKit   // for `NSApp.orderFrontCharacterPalette` — the macOS emoji picker

/// Settings screen: lists the saved cards and categories, plus a debug action to
/// wipe everything and restart onboarding.
struct SettingsView: View {
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    // Loaded from the database in `reload()`. `@State` so the view refreshes when set.
    @State private var cards: [Card] = []
    @State private var categories: [Category] = []

    // The two input fields for creating a new category. `@State` because they're
    // temporary UI values owned by this view; they reset to "" after each add.
    @State private var newCategoryName: String = ""
    @State private var newCategoryEmoji: String = ""

    // `@FocusState` tracks whether the emoji field currently has keyboard focus.
    // We watch it so that focusing the field pops open the macOS emoji picker.
    @FocusState private var emojiFieldFocused: Bool

    // The input fields for creating a new card. Same idea as the category fields:
    // temporary `@State` that resets to its default after each add.
    @State private var newCardName: String = ""
    @State private var newCardBank: String = ""
    @State private var newCardLastFour: String = ""
    @State private var newCardType: String = "credit"   // "credit" or "debit"
    @State private var newCardClosingDay: String = ""   // "fecha de corte" day (1–31), optional

    // Remembers which card the dashboard is showing, so deleting that exact card
    // can clear the stale selection. `@AppStorage` reads the same `UserDefaults`
    // key the dashboard writes.
    @AppStorage("selectedCardId") private var selectedCardId = ""

    // Drives the "are you sure?" alert. The trash button parks the chosen card here
    // and flips the flag; the alert reads the card to show its name and to delete it
    // only if the user confirms.
    @State private var cardToDelete: Card?
    @State private var showingDeleteCardAlert = false

    // The card being edited, if any. Tapping a card row sets this, which opens the
    // edit sheet via `.sheet(item:)`.
    @State private var cardToEdit: Card?

    /// Whether the new-card form is complete enough to save. Mirrors the same rule
    /// onboarding uses: a name, a bank, and exactly 4 digits for the last four.
    private var newCardIsValid: Bool {
        !newCardName.trimmingCharacters(in: .whitespaces).isEmpty
            && !newCardBank.trimmingCharacters(in: .whitespaces).isEmpty
            && newCardLastFour.count == 4
            && newCardLastFour.allSatisfy(\.isNumber)
    }

    var body: some View {
        // `List` with `Section`s renders the standard grouped settings layout.
        List {
            Section("Cards") {
                if cards.isEmpty {
                    Text("No cards saved")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(cards) { card in
                        HStack {
                            VStack(alignment: .leading, spacing: 2) {
                                Text("\(card.name) •••• \(card.lastFour)")
                                    .font(.system(.body, design: .monospaced))
                                // Append the corte only when the card has one.
                                Text(card.closingDay >= 1
                                     ? "\(card.bank) · \(card.type) · corte \(card.closingDay)"
                                     : "\(card.bank) · \(card.type)")
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                            }
                            // Make the whole text block tappable (not just the letters)
                            // and open the edit sheet for this card.
                            .contentShape(Rectangle())
                            .onTapGesture { cardToEdit = card }

                            Spacer()   // pushes the trash button to the right edge

                            // Per-row delete control (no swipe-to-delete on macOS).
                            // Doesn't delete immediately — it asks for confirmation
                            // first, because deleting a card also wipes its transactions.
                            Button {
                                cardToDelete = card
                                showingDeleteCardAlert = true
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }

                // The "add new card" form, shown at the bottom of the section.
                VStack(alignment: .leading, spacing: 8) {
                    TextField("Card name (e.g. BBVA Platinum)", text: $newCardName)
                        .font(.system(.body, design: .monospaced))

                    HStack(spacing: 8) {
                        TextField("Bank", text: $newCardBank)
                            .font(.system(.body, design: .monospaced))

                        TextField("Last 4", text: $newCardLastFour)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 70)
                            // Keep only digits and never more than 4. Runs on every
                            // keystroke; the guard avoids an endless write loop.
                            .onChange(of: newCardLastFour) { _, value in
                                let digits = String(value.filter(\.isNumber).prefix(4))
                                if digits != newCardLastFour {
                                    newCardLastFour = digits
                                }
                            }

                        // "Fecha de corte" — the statement closing day. Optional;
                        // leave blank for cards without one (e.g. debit). Filtered to
                        // at most two digits; the 1–31 range is enforced on save.
                        TextField("Corte", text: $newCardClosingDay)
                            .font(.system(.body, design: .monospaced))
                            .frame(width: 60)
                            .onChange(of: newCardClosingDay) { _, value in
                                let digits = String(value.filter(\.isNumber).prefix(2))
                                if digits != newCardClosingDay {
                                    newCardClosingDay = digits
                                }
                            }
                    }

                    HStack {
                        // A segmented control to pick credit vs debit. Each option's
                        // `.tag` is the string stored on the card.
                        Picker("", selection: $newCardType) {
                            Text("Credit").tag("credit")
                            Text("Debit").tag("debit")
                        }
                        .pickerStyle(.segmented)
                        .labelsHidden()
                        .frame(width: 160)

                        Spacer()

                        Button("Add Card", action: addCard)
                            .font(.system(.body, design: .monospaced))
                            .disabled(!newCardIsValid)   // greyed out until valid
                    }
                }
                .padding(.vertical, 4)
            }

            Section("Categories") {
                if categories.isEmpty {
                    Text("No categories saved")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(categories) { category in
                        HStack {
                            Text("\(category.emoji) \(category.name)")
                                .font(.system(.body, design: .monospaced))

                            Spacer()   // pushes the trash button to the right edge

                            // macOS has no swipe-to-delete in a `List`, so each row
                            // carries its own delete control instead.
                            Button {
                                deleteCategory(category)
                            } label: {
                                Image(systemName: "trash")
                                    .foregroundStyle(.red)
                            }
                            .buttonStyle(.plain)   // no default button chrome, just the icon
                        }
                    }
                }

                // The "add new category" row, always visible at the bottom of the
                // section so the user can create one at any time.
                HStack(spacing: 8) {
                    // Emoji field — kept narrow since it holds a single symbol.
                    // `$newCategoryEmoji` is a two-way binding: typing updates the state.
                    TextField("🛒", text: $newCategoryEmoji)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 44)
                        // Track focus so we can open the picker when the user clicks in.
                        .focused($emojiFieldFocused)
                        // When the field gains focus, pop the native macOS emoji &
                        // symbols picker. The new `onChange` hands us (old, new) values;
                        // we only act when focus flips from false → true.
                        .onChange(of: emojiFieldFocused) { _, focused in
                            if focused {
                                NSApp.orderFrontCharacterPalette(nil)
                            }
                        }
                        // Reject anything that isn't an emoji and keep only one. After
                        // any change we strip non-emoji characters; if several remain we
                        // keep the last one picked, so the field holds a single emoji.
                        .onChange(of: newCategoryEmoji) { _, value in
                            let emojisOnly = value.filter { $0.isEmoji }
                            // `.last.map(String.init)` turns the last emoji `Character`
                            // into a `String`, or gives "" when there are none.
                            let single = emojisOnly.last.map(String.init) ?? ""
                            // Guard prevents an infinite loop: only write back when the
                            // cleaned value actually differs from what's already there.
                            if single != newCategoryEmoji {
                                newCategoryEmoji = single
                            }
                        }

                    TextField("New category name", text: $newCategoryName)
                        .font(.system(.body, design: .monospaced))
                        // Pressing Return in the name field also adds the category.
                        .onSubmit(addCategory)

                    Button(action: addCategory) {
                        Image(systemName: "plus.circle.fill")
                    }
                    .buttonStyle(.plain)
                    // Disable until there's a non-blank name. `trimmingCharacters`
                    // ignores entries that are only spaces.
                    .disabled(newCategoryName.trimmingCharacters(in: .whitespaces).isEmpty)
                }
            }

            Section("Debug") {
                // Wipes the database and flips the onboarding flag back to false.
                // Because `ContentView` watches that flag, the app immediately
                // returns to the onboarding wizard.
                Button("Reset Onboarding") {
                    RealmService.shared.deleteAll()
                    UserDefaults.standard.removeObject(forKey: "selectedCardId")
                    hasCompletedOnboarding = false
                }
                .foregroundStyle(.red)
            }
        }
        .onAppear { reload() }   // load fresh data whenever the screen shows
        // Confirmation before a destructive card delete. `presenting:` hands the
        // pending card into both closures so we can name it and delete the right one.
        .alert("Delete card?", isPresented: $showingDeleteCardAlert, presenting: cardToDelete) { card in
            Button("Delete", role: .destructive) { deleteCard(card) }
            Button("Cancel", role: .cancel) { }
        } message: { card in
            Text("Are you sure you want to do this? Deleting \"\(card.name)\" will also permanently delete all of its transactions.")
        }
        // Edit sheet: opens whenever a card row is tapped. We reload on dismiss so
        // any changes (e.g. a new corte) show immediately in the list.
        .sheet(item: $cardToEdit, onDismiss: { reload() }) { card in
            EditCardSheet(cardId: card.id)
        }
    }

    /// Pulls the latest cards and categories from the database into local state.
    private func reload() {
        cards = RealmService.shared.objects(Card.self)
        categories = RealmService.shared.objects(Category.self)
    }

    /// Creates a new card from the input fields and saves it to the database.
    private func addCard() {
        guard newCardIsValid else { return }

        let card = Card()
        card.name = newCardName.trimmingCharacters(in: .whitespaces)
        card.bank = newCardBank.trimmingCharacters(in: .whitespaces)
        card.lastFour = newCardLastFour
        card.type = newCardType
        // Only store a closing day if it's a valid 1–31; otherwise leave it 0 ("none").
        if let day = Int(newCardClosingDay), (1...31).contains(day) {
            card.closingDay = day
        }
        RealmService.shared.save(card)

        // Reset the form for the next entry, then refresh the list.
        newCardName = ""
        newCardBank = ""
        newCardLastFour = ""
        newCardType = "credit"
        newCardClosingDay = ""
        reload()
    }

    /// Deletes a card and everything tied to it (a "cascade" delete), after the
    /// user confirms in the alert.
    ///
    /// We read `card.id` into `deletedId` up front: once the card object is deleted
    /// from Realm, touching its properties would crash, so we grab the id first.
    private func deleteCard(_ card: Card) {
        let deletedId = card.id

        // Wipe this card's transactions and any statements that reference it, so no
        // orphaned rows are left pointing at a card that no longer exists.
        let transactions = RealmService.shared.objects(Transaction.self).filter { $0.cardId == deletedId }
        RealmService.shared.delete(transactions)

        let statements = RealmService.shared.objects(Statement.self).filter { $0.cardId == deletedId }
        RealmService.shared.delete(statements)

        RealmService.shared.delete(Card.self, id: deletedId)

        // If the dashboard was showing this card, forget the selection so it doesn't
        // try to reopen a card that's gone.
        if selectedCardId == deletedId {
            selectedCardId = ""
        }
        reload()
    }

    /// Creates a new category from the input fields and saves it to the database.
    private func addCategory() {
        // Drop surrounding spaces, then bail out if nothing meaningful was typed.
        let name = newCategoryName.trimmingCharacters(in: .whitespaces)
        guard !name.isEmpty else { return }

        let category = Category()           // a fresh empty Realm object
        category.name = name
        category.emoji = newCategoryEmoji.trimmingCharacters(in: .whitespaces)
        RealmService.shared.save(category)

        // Clear the inputs so the row is ready for the next entry, then refresh.
        newCategoryName = ""
        newCategoryEmoji = ""
        reload()
    }

    /// Deletes a single category (triggered by its trash button).
    ///
    /// NOTE: this removes the category itself, not the transactions that point at
    /// it. Those transactions keep their old `categoryId`, which no longer matches
    /// anything, so the dashboard shows them as "·" / "Uncategorized".
    private func deleteCategory(_ category: Category) {
        RealmService.shared.delete(Category.self, id: category.id)
        reload()
    }
}

#Preview {
    SettingsView()
}
