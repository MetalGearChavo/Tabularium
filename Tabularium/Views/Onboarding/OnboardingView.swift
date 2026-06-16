import SwiftUI

/// The first-launch setup wizard. It walks through several steps (welcome → card
/// count → card details → categories → done) and saves the results.
///
/// The `OnboardingViewModel` holds the data and the current `step`; this view just
/// shows the right sub-screen for that step and forwards the user's actions.
struct OnboardingView: View {
    @StateObject private var vm = OnboardingViewModel()
    // When set true (on the final step), `ContentView` swaps to the main app.
    @AppStorage("hasCompletedOnboarding") private var hasCompletedOnboarding = false

    var body: some View {
        ZStack {
            // Dark background behind every step.
            Color(red: 0.08, green: 0.08, blue: 0.08)
                .ignoresSafeArea()

            // Show a different sub-view depending on the VM's current step.
            switch vm.step {
            case .welcome:
                // The trailing closure is the step's "next" action — here it just
                // advances the VM to the card-count step.
                WelcomeStep { vm.step = .cardCount }

            case .cardCount:
                // `$vm.cardCount` passes a two-way binding so the stepper can change it.
                CardCountStep(count: $vm.cardCount) {
                    vm.applyCardCount()
                }

            case .cardDetails(let index):
                // `let index` pulls the associated value out of the enum case.
                CardDetailsStep(
                    draft: $vm.cards[index],   // bind to the specific card being edited
                    cardNumber: index + 1,
                    totalCards: vm.cardCount
                ) {
                    vm.nextCardOrCategories(currentIndex: index)
                }

            case .categories:
                CategoriesStep(
                    categories: $vm.categories,
                    onAdd: { vm.addCategory() },
                    onRemove: { vm.removeCategory(at: $0) }   // $0 is the IndexSet to remove
                ) {
                    vm.complete()
                }

            case .complete:
                // An invisible view whose only job is to flip the flag once it appears.
                Color.clear.onAppear { hasCompletedOnboarding = true }
            }
        }
        .frame(minWidth: 520, minHeight: 420)
    }
}

// MARK: - Welcome

private struct WelcomeStep: View {
    // A function passed in by the parent, run when "Get Started" is tapped.
    let onNext: () -> Void

    var body: some View {
        VStack(spacing: 24) {
            Text("TABULARIUM")
                .font(.system(size: 32, weight: .bold, design: .monospaced))
                .foregroundStyle(.white)

            Text("Personal expense tracker")
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(.gray)

            Spacer().frame(height: 8)

            OnboardingButton("Get Started", action: onNext)
        }
        .padding(48)
    }
}

// MARK: - Card Count

/// Lets the user choose how many cards to track with a − / number / + stepper.
private struct CardCountStep: View {
    // `@Binding` is a reference to state owned by the parent. Changing `count`
    // here updates the VM's `cardCount` directly.
    @Binding var count: Int
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 32) {
            StepHeader(title: "Cards", subtitle: "How many cards do you want to track?")

            HStack(spacing: 20) {
                Button {
                    if count > 1 { count -= 1 }   // clamp: never go below 1
                } label: {
                    Text("−")
                        .font(.system(size: 22, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)

                Text("\(count)")
                    .font(.system(size: 36, weight: .bold, design: .monospaced))
                    .foregroundStyle(.white)
                    .frame(minWidth: 40)

                Button {
                    if count < 10 { count += 1 }   // clamp: cap at 10
                } label: {
                    Text("+")
                        .font(.system(size: 22, weight: .medium, design: .monospaced))
                        .foregroundStyle(.white)
                        .frame(width: 36, height: 36)
                        .background(Color.white.opacity(0.1))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                }
                .buttonStyle(.plain)
            }

            Spacer()

            OnboardingButton("Next", action: onNext)
        }
        .padding(48)
    }
}

// MARK: - Card Details

/// Form for one card's details (name, bank, last 4, type).
private struct CardDetailsStep: View {
    @Binding var draft: OnboardingViewModel.CardDraft
    let cardNumber: Int
    let totalCards: Int
    let onNext: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 28) {
            StepHeader(
                title: "Card \(cardNumber) of \(totalCards)",
                subtitle: "Enter details for this card"
            )

            VStack(alignment: .leading, spacing: 16) {
                MonoField(label: "Card name", placeholder: "BBVA Platinum", text: $draft.name)
                MonoField(label: "Bank", placeholder: "BBVA", text: $draft.bank)
                MonoField(label: "Last 4 digits", placeholder: "1234", text: $draft.lastFour)
                    // `.onChange` runs whenever `lastFour` changes. Here it sanitizes
                    // the input: keep only digits, and at most 4 of them.
                    .onChange(of: draft.lastFour) { _, new in
                        draft.lastFour = String(new.filter(\.isNumber).prefix(4))
                    }

                // "Fecha de corte" — statement closing day. Optional, so leave blank
                // for cards without one (e.g. debit). Filtered to at most two digits;
                // the 1–31 range is enforced when the card is saved.
                MonoField(label: "Closing day / corte (optional)", placeholder: "21", text: $draft.closingDay)
                    .onChange(of: draft.closingDay) { _, new in
                        draft.closingDay = String(new.filter(\.isNumber).prefix(2))
                    }

                VStack(alignment: .leading, spacing: 6) {
                    Text("TYPE")
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.gray)

                    // A segmented control (two side-by-side options). The chosen
                    // option's `.tag` becomes the value of `draft.type`.
                    Picker("", selection: $draft.type) {
                        Text("Credit").tag("credit")
                        Text("Debit").tag("debit")
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)
                }
            }

            Spacer()

            OnboardingButton(
                // The button label changes for the last card.
                totalCards == cardNumber ? "Next: Categories" : "Next Card",
                action: onNext
            )
            .disabled(!draft.isValid)              // can't continue until this card is valid
            .opacity(draft.isValid ? 1 : 0.4)
        }
        .padding(48)
    }
}

// MARK: - Categories

/// Lets the user add/remove their spending categories.
private struct CategoriesStep: View {
    @Binding var categories: [OnboardingViewModel.CategoryDraft]
    let onAdd: () -> Void
    let onRemove: (IndexSet) -> Void
    let onFinish: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 24) {
            StepHeader(title: "Categories", subtitle: "Define your spending categories — shared across all cards")

            ScrollView {
                VStack(spacing: 10) {
                    // We loop over indices (not the items) because we need to bind to
                    // each element by position (`$categories[i]`). `id: \.self` tells
                    // SwiftUI to identify rows by the index value itself.
                    ForEach(categories.indices, id: \.self) { i in
                        HStack(spacing: 12) {
                            EmojiPickerField(emoji: $categories[i].emoji)
                            MonoField(label: nil, placeholder: "Groceries", text: $categories[i].name)

                            Button {
                                if categories.count > 1 {   // always keep at least one
                                    categories.remove(at: i)
                                }
                            } label: {
                                Image(systemName: "minus.circle")
                                    .foregroundStyle(.gray)
                            }
                            .buttonStyle(.plain)
                        }
                    }
                }
            }
            .frame(maxHeight: 200)

            Button {
                onAdd()
            } label: {
                Label("Add category", systemImage: "plus")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.gray)
            }
            .buttonStyle(.plain)

            Spacer()

            OnboardingButton("Finish Setup", action: onFinish)
                // Disabled only if EVERY category is invalid (none filled in).
                .disabled(categories.allSatisfy { !$0.isValid })
                .opacity(categories.allSatisfy { !$0.isValid } ? 0.4 : 1)
        }
        .padding(48)
    }
}

// MARK: - Shared Components

/// A tappable box that opens the macOS emoji palette and captures one emoji.
private struct EmojiPickerField: View {
    @Binding var emoji: String
    // `@FocusState` tracks whether a hidden text field has keyboard focus, which
    // is the trick used to receive the emoji the user picks.
    @FocusState private var isFocused: Bool

    var body: some View {
        Button {
            isFocused = true
            // Wait a beat for focus to land, then pop the system emoji picker.
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                NSApp.orderFrontCharacterPalette(nil)
            }
        } label: {
            Text(emoji.isEmpty ? "·" : emoji)
                .font(.system(size: 18))
                .frame(width: 44, height: 36)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        // An invisible text field laid over the button. It actually receives the
        // typed/picked character; we keep only the first one.
        .overlay(
            TextField("", text: $emoji)
                .focused($isFocused)
                .opacity(0.01)               // effectively invisible
                .allowsHitTesting(false)     // but clicks still hit the button beneath
                .onChange(of: emoji) { _, new in
                    if new.count > 1 { emoji = String(new.prefix(1)) }
                }
        )
    }
}

/// A small uppercase label over a subtitle — the heading at the top of each step.
private struct StepHeader: View {
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(title.uppercased())
                .font(.system(size: 11, design: .monospaced))
                .foregroundStyle(.gray)
            Text(subtitle)
                .font(.system(size: 18, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white)
        }
    }
}

/// A reusable monospaced text input with an optional label above it.
private struct MonoField: View {
    let label: String?   // optional — `nil` means "no label"
    let placeholder: String
    @Binding var text: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            // `if let label` only shows the label when one was provided.
            if let label {
                Text(label.uppercased())
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.gray)
            }
            TextField(placeholder, text: $text)
                .font(.system(size: 14, design: .monospaced))
                .foregroundStyle(.white)
                .textFieldStyle(.plain)
                .padding(8)
                .background(Color.white.opacity(0.07))
                .clipShape(RoundedRectangle(cornerRadius: 6))
        }
    }
}

/// The big white primary button used at the bottom of every step.
private struct OnboardingButton: View {
    let title: String
    let action: () -> Void

    // A custom initializer so callers can write `OnboardingButton("Next") { ... }`
    // with the title as the first unlabeled argument. `@escaping` means the action
    // closure is stored and called later, not immediately.
    init(_ title: String, action: @escaping () -> Void) {
        self.title = title
        self.action = action
    }

    var body: some View {
        Button(action: action) {
            Text(title)
                .font(.system(size: 14, weight: .semibold, design: .monospaced))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(Color.white)
                .clipShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
    }
}

#Preview {
    OnboardingView()
}
