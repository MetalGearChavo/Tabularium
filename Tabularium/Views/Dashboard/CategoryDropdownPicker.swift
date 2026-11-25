import SwiftUI
import AppKit   // for `NSApp.orderFrontCharacterPalette` — the native macOS emoji picker

/// View layer: a terminal-styled category dropdown menu that lets the user either
/// pick an existing category, delete an unused one via a hover trash icon, OR
/// create a new category inline right inside the open dropdown list using the
/// native macOS Emoji & Symbols picker (`NSApp.orderFrontCharacterPalette`).
struct CategoryDropdownPicker: View {
    // `@Binding` is a two-way connection to the parent form's `selectedCategoryId`.
    @Binding var selectedCategoryId: String

    let categories: [Category]
    /// Called when the user submits a new inline category (`(emoji, name)`).
    let onAddCategory: (String, String) -> Void
    /// Called when the user clicks the hover trash icon on a category row (`categoryId`).
    var onDeleteCategory: ((String) -> Void)? = nil

    // `@State` holds temporary UI state owned by this view:
    @State private var isMenuOpen = false
    @State private var isAddingInline = false
    @State private var draft = InlineCategoryDraft()
    @State private var hoveredRowId: String?

    // `@FocusState` tracks whether the emoji field or name field has keyboard focus.
    @FocusState private var emojiFieldFocused: Bool
    @FocusState private var nameFieldFocused: Bool

    /// Label shown on the closed dropdown button (matches the selected category,
    /// or `"None"` when `selectedCategoryId` is empty or no longer exists).
    private var selectedLabel: String {
        guard !selectedCategoryId.isEmpty,
              let match = categories.first(where: { $0.id == selectedCategoryId }) else {
            return "None"
        }
        return InlineCategoryDraft.displayLabel(emoji: match.emoji, name: match.name)
    }

    var body: some View {
        Button {
            if isMenuOpen {
                closeMenu()
            } else {
                isMenuOpen = true
            }
        } label: {
            HStack(spacing: 8) {
                Text(selectedLabel)
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.primary)
                    .lineLimit(1)

                Spacer()

                Image(systemName: "chevron.up.chevron.down")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.primary.opacity(0.06))
            .clipShape(RoundedRectangle(cornerRadius: 6))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        // Anchor the floating dropdown to `.bottomLeading` so it fits cleanly inside
        // the modal without being clipped at the bottom edge of the sheet, while
        // living in the sheet's own window so macOS anchors the native Emoji &
        // Symbols palette (`orderFrontCharacterPalette`) with its arrow ("piquito")
        // pointing directly at the `🛒` field.
        .overlay(alignment: .bottomLeading) {
            if isMenuOpen {
                ZStack(alignment: .bottomLeading) {
                    // Full-sheet invisible backdrop: clicking any other section
                    // outside the dropdown hits this backdrop and closes the menu,
                    // while clicks inside `dropdownMenu` never trigger it.
                    Color.black.opacity(0.001)
                        .frame(width: 1400, height: 1000)
                        .offset(x: -500, y: 300)
                        .onTapGesture {
                            closeMenu()
                        }

                    dropdownMenu
                        .offset(y: 44)
                }
            }
        }
        .zIndex(100)
    }

    /// The contents of the open dropdown menu: `"None"`, every saved category
    /// (with hover trash button), a divider, and the bottom row that transforms
    /// from `"+ Add category"` into `[ 🛒 ] [ New category name ] [ + ]` in place.
    private var dropdownMenu: some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 1) {
                optionRow(id: "", label: "None", canDelete: false)

                ForEach(categories) { category in
                    optionRow(
                        id: category.id,
                        label: InlineCategoryDraft.displayLabel(
                            emoji: category.emoji,
                            name: category.name
                        ),
                        canDelete: true
                    )
                }
            }

            Divider()
                .padding(.vertical, 3)

            if isAddingInline {
                inlineAddEditorRow
            } else {
                addTriggerRow
            }
        }
        .padding(.horizontal, 6)
        .padding(.vertical, 4)
        .frame(width: 270)
        .background(
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(nsColor: .windowBackgroundColor))
                .shadow(color: Color.black.opacity(0.5), radius: 14, x: 0, y: 6)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(Color.primary.opacity(0.2), lineWidth: 1)
        )
    }

    /// A single selectable row inside the dropdown list, with a checkmark on the
    /// active category, a subtle highlight on hover, and a red trash button that
    /// appears on hover for user-saved categories (`canDelete == true`).
    private func optionRow(id: String, label: String, canDelete: Bool) -> some View {
        let isSelected = (selectedCategoryId == id)
        let isHovered = (hoveredRowId == id)

        return HStack(spacing: 6) {
            Button {
                selectedCategoryId = id
                closeMenu()
            } label: {
                HStack(spacing: 8) {
                    Image(systemName: "checkmark")
                        .font(.system(size: 11, weight: .semibold))
                        .opacity(isSelected ? 1 : 0)

                    Text(label)
                        .font(.system(size: 13, design: .monospaced))
                        .lineLimit(1)

                    Spacer()
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)

            if canDelete && isHovered, let onDeleteCategory {
                Button {
                    onDeleteCategory(id)
                } label: {
                    Image(systemName: "trash")
                        .font(.system(size: 11))
                        .foregroundStyle(.red.opacity(0.85))
                        .padding(.horizontal, 4)
                        .padding(.vertical, 2)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .help("Delete category")
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
        .background(
            RoundedRectangle(cornerRadius: 5)
                .fill(isHovered ? Color.primary.opacity(0.1) : Color.clear)
        )
        .contentShape(Rectangle())
        .onHover { hovering in
            hoveredRowId = hovering ? id : nil
        }
    }

    /// The bottom row before it's clicked: shows `+ Add category` aligned with the
    /// options above. Clicking it flips `isAddingInline` to `true` and puts the
    /// cursor into the name field.
    private var addTriggerRow: some View {
        let isHovered = (hoveredRowId == "__add__")

        return Button {
            isAddingInline = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) {
                nameFieldFocused = true
            }
        } label: {
            HStack(spacing: 8) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.secondary)

                Text("Add category")
                    .font(.system(size: 13, design: .monospaced))
                    .foregroundStyle(.secondary)

                Spacer()
            }
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(
                RoundedRectangle(cornerRadius: 5)
                    .fill(isHovered ? Color.primary.opacity(0.1) : Color.clear)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering in
            hoveredRowId = hovering ? "__add__" : nil
        }
    }

    /// The bottom row *after* clicking `+ Add category`:
    /// `[ 🛒 ] [ New category name ] [ + ]`.
    /// Clicking `🛒` opens the native macOS Emoji Picker with its arrow ("piquito")
    /// pointing directly at `🛒` and no visible text cursor. As soon as an emoji is
    /// selected, the Emoji Picker closes and focus jumps straight to `"New category name"`.
    private var inlineAddEditorRow: some View {
        HStack(spacing: 8) {
            TextField("🛒", text: $draft.emoji)
                .font(.system(.body, design: .monospaced))
                .multilineTextAlignment(.center)
                .frame(width: 38)
                .focused($emojiFieldFocused)
                .onChange(of: emojiFieldFocused) { _, focused in
                    if focused {
                        setFieldEditorCaretVisible(false)
                        NSApp.orderFrontCharacterPalette(nil)
                    } else {
                        setFieldEditorCaretVisible(true)
                    }
                }
                .onChange(of: draft.emoji) { oldValue, value in
                    let single = InlineCategoryDraft.sanitizeEmoji(value)
                    if single != draft.emoji {
                        draft.emoji = single
                        return
                    }
                    // As soon as a single emoji is chosen (whether `emojiFieldFocused`
                    // is still true or macOS temporarily resigned it while clicking
                    // the palette), close the Emoji Picker and move the cursor
                    // straight into `"New category name"`.
                    if !single.isEmpty && single != oldValue {
                        emojiFieldFocused = false
                        closeCharacterPalette()
                        DispatchQueue.main.asyncAfter(deadline: .now() + 0.03) {
                            nameFieldFocused = true
                            setFieldEditorCaretVisible(true)
                        }
                    }
                }

            TextField("New category name", text: $draft.name)
                .font(.system(.body, design: .monospaced))
                .focused($nameFieldFocused)
                .onChange(of: nameFieldFocused) { _, focused in
                    if focused {
                        setFieldEditorCaretVisible(true)
                    }
                }
                .onSubmit(commitNewCategory)

            Button(action: commitNewCategory) {
                Image(systemName: "plus.circle.fill")
            }
            .buttonStyle(.plain)
            .disabled(!draft.isValid)
            .opacity(draft.isValid ? 1 : 0.35)
        }
        .padding(.horizontal, 4)
        .padding(.vertical, 2)
    }

    /// Shows or hides the blinking text cursor (`insertionPointColor`) on the window's
    /// shared AppKit field editor (`NSTextView`) so the emoji box never displays a
    /// blinking text cursor while the category name field keeps its normal cursor.
    private func setFieldEditorCaretVisible(_ visible: Bool) {
        DispatchQueue.main.async {
            for window in NSApp.windows {
                if let textView = window.firstResponder as? NSTextView {
                    textView.insertionPointColor = visible ? .labelColor : .clear
                }
            }
        }
    }

    /// Dismisses the native macOS Emoji & Symbols palette (`CharacterPalette`) as
    /// soon as a single emoji is selected so it doesn't stay open over the form.
    private func closeCharacterPalette() {
        for window in NSApp.windows {
            let className = String(describing: type(of: window))
            if className.contains("CharacterPalette")
                || className.contains("Emoji")
                || className.contains("Popover")
                || window.title.localizedCaseInsensitiveContains("Emoji")
                || window.title.localizedCaseInsensitiveContains("Character")
                || (window is NSPanel && window != NSApp.keyWindow && window.sheetParent == nil) {
                window.orderOut(nil)
                window.close()
            }
        }
        // Resigning the window's firstResponder (`makeFirstResponder(nil)`) detaches
        // the out-of-process macOS CharacterViewer popover from the emoji field editor,
        // causing macOS to dismiss the emoji popover immediately before we focus the
        // category name field.
        NSApp.keyWindow?.makeFirstResponder(nil)
    }

    /// Validates the draft, hands `(emoji, name)` to the parent callback to save
    /// and select it, and closes the dropdown.
    private func commitNewCategory() {
        guard draft.isValid else { return }
        onAddCategory(draft.trimmedEmoji, draft.trimmedName)
        closeMenu()
    }

    /// Closes the dropdown and resets any temporary inline draft.
    private func closeMenu() {
        closeCharacterPalette()
        setFieldEditorCaretVisible(true)
        isMenuOpen = false
        isAddingInline = false
        draft = InlineCategoryDraft()
        emojiFieldFocused = false
        nameFieldFocused = false
    }
}
