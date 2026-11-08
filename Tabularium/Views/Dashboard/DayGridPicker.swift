import SwiftUI

/// View layer: an always-visible month calendar with large day buttons, so a date
/// can be picked with a single click — built to replace the tiny stepper-style
/// `DatePicker` when entering a run of past transactions.
///
/// It doesn't own the date: the parent form passes it in as a `@Binding`, and the
/// grid writes back to it when a day is clicked.
struct DayGridPicker: View {
    // `@Binding` = a two-way link to state owned by the parent (here the Add sheet's
    // `date`). Writing to `selection` updates the parent's value directly.
    @Binding var selection: Date

    /// Called right after a day is clicked — the Add sheet uses it to move the
    /// cursor to AMOUNT so the user can type immediately.
    var onPick: () -> Void

    /// Which month the grid is showing (the 1st of that month). Separate from
    /// `selection` so you can browse ◀ ▶ without changing the chosen date.
    @State private var displayedMonth: Date

    private let calendar = Calendar.current

    // Named sizes (no magic numbers): 7 × 36pt cells + 6 × 4pt gaps = 276pt wide.
    private static let cellSize: CGFloat = 36
    private static let cellSpacing: CGFloat = 4
    private static let gridWidth: CGFloat = cellSize * 7 + cellSpacing * 6

    /// A custom `init` because `@State` must be *seeded* from the incoming binding:
    /// the underscore names (`_selection`, `_displayedMonth`) are the property
    /// wrappers themselves, which is how you initialise them by hand.
    init(selection: Binding<Date>, onPick: @escaping () -> Void = {}) {
        _selection = selection
        self.onPick = onPick
        _displayedMonth = State(initialValue: selection.wrappedValue.startOfMonth)
    }

    /// Seven fixed-width columns. `GridItem` describes ONE column of a `LazyVGrid`;
    /// repeating it 7 times gives a week per row.
    private var columns: [GridItem] {
        Array(repeating: GridItem(.fixed(Self.cellSize), spacing: Self.cellSpacing), count: 7)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            monthHeader

            // `LazyVGrid` lays its children out row by row into the columns above.
            LazyVGrid(columns: columns, spacing: Self.cellSpacing) {
                // Header row: "Su Mo Tu …", ordered to match the user's first weekday.
                // `id: \.self` identifies each symbol by its own value.
                ForEach(calendar.orderedWeekdaySymbols, id: \.self) { symbol in
                    Text(symbol)
                        .font(.system(size: 10, design: .monospaced))
                        .foregroundStyle(.secondary)
                }

                // Day cells. `enumerated()` pairs each cell with its position, which
                // gives the blank (`nil`) cells a stable id too.
                ForEach(Array(displayedMonth.monthGridDays(calendar: calendar).enumerated()), id: \.offset) { _, day in
                    if let day {
                        dayCell(day)
                    } else {
                        Color.clear.frame(width: Self.cellSize, height: Self.cellSize)
                    }
                }
            }

            quickPresetRow
        }
        .frame(width: Self.gridWidth)
        // When the date changes from OUTSIDE the grid, follow it so the selected
        // day stays visible.
        .onChange(of: selection) { _, newValue in
            if !calendar.isDate(newValue, equalTo: displayedMonth, toGranularity: .month) {
                displayedMonth = newValue.startOfMonth
            }
        }
    }

    /// "◀  OCTOBER 2026  ▶" — month browsing above the calendar grid.
    private var monthHeader: some View {
        HStack(spacing: 4) {
            monthButton(systemImage: "chevron.left", offset: -1, help: "Previous month")

            Text(displayedMonth.monthYearString.uppercased())
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .frame(maxWidth: .infinity)

            monthButton(systemImage: "chevron.right", offset: 1, help: "Next month")
        }
    }

    /// Row of one-click relative date chips ("Today", "Yesterday", "Last Week",
    /// "Last Month") beneath the calendar grid. Active chip highlights when
    /// `selection` matches that preset's resolved day.
    private var quickPresetRow: some View {
        HStack(spacing: 4) {
            ForEach(QuickDatePreset.allCases) { preset in
                let target = preset.resolve(calendar: calendar)
                let isSelected = calendar.isDate(selection, inSameDayAs: target)

                Button(preset.rawValue) {
                    pick(target)
                }
                .buttonStyle(.plain)
                .font(.system(size: 10, weight: isSelected ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(isSelected ? Color.white : Color.secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 5)
                .background(
                    isSelected ? Color.accentColor : Color.primary.opacity(0.06),
                    in: RoundedRectangle(cornerRadius: 5)
                )
                .contentShape(RoundedRectangle(cornerRadius: 5))
            }
        }
        .padding(.top, 2)
    }

    /// A ◀ / ▶ button with a generous 28pt square hit area (not just the glyph).
    private func monthButton(systemImage: String, offset: Int, help: String) -> some View {
        Button {
            displayedMonth = calendar.date(byAdding: .month, value: offset, to: displayedMonth) ?? displayedMonth
        } label: {
            Image(systemName: systemImage)
                .frame(width: 28, height: 28)
                // `.contentShape` makes the whole 28pt square clickable, not only
                // the thin chevron strokes.
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(help)
    }

    /// One clickable day square: accent-filled when selected, accent-outlined when
    /// it's today, dimmed when it's in the future (still clickable).
    private func dayCell(_ day: Date) -> some View {
        let isSelected = calendar.isDate(day, inSameDayAs: selection)
        let isToday = calendar.isDateInToday(day)
        let isFuture = day > calendar.startOfDay(for: Date())
        let shape = RoundedRectangle(cornerRadius: 6)

        return Button { pick(day) } label: {
            Text("\(calendar.component(.day, from: day))")
                .font(.system(size: 13, weight: isSelected ? .bold : .regular, design: .monospaced))
                .foregroundStyle(isSelected ? Color.white : (isFuture ? Color.secondary : Color.primary))
                .frame(width: Self.cellSize, height: Self.cellSize)
                .background(isSelected ? Color.accentColor : Color.primary.opacity(0.05), in: shape)
                .overlay {
                    if isToday && !isSelected {
                        shape.strokeBorder(Color.accentColor, lineWidth: 1.5)
                    }
                }
                .contentShape(shape)   // the full square is the click target
        }
        .buttonStyle(.plain)
    }

    /// Selects `day`, makes sure its month is showing, and notifies the parent.
    private func pick(_ day: Date) {
        selection = day
        displayedMonth = day.startOfMonth
        onPick()
    }
}

#Preview {
    // `.constant(...)` is a read-only binding — handy for previews.
    DayGridPicker(selection: .constant(Date()))
        .padding()
}
