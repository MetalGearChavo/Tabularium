import SwiftUI

/// View layer: the reimbursement status control inside `TransactionFormContent`
/// (`[ Personal | ⏳ Pending | ✓ Reimbursed ]` + optional `"WHO / NOTE"` field).
///
/// When a transaction is marked `.pending` or `.reimbursed`, it is excluded from
/// the user's personal budget (`$0` personal budget impact) while remaining visible
/// on the card ledger and counted in the total card statement amount to pay.
struct ReimbursementPicker: View {
    @Binding var status: ReimbursementOption.Status
    @Binding var note: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("REIMBURSEMENT")
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.secondary)

            HStack(spacing: 6) {
                statusPill(title: "Personal", target: .personal, tint: .primary)
                statusPill(title: "⏳ Pending", target: .pending, tint: .orange)
                statusPill(title: "✓ Reimbursed", target: .reimbursed, tint: .green)
            }

            if status == .pending || status == .reimbursed {
                HStack(spacing: 8) {
                    Text("WHO / NOTE")
                        .font(.system(size: 9, design: .monospaced))
                        .foregroundStyle(.secondary)

                    TextField("e.g. Viaje, Trabajo, Mamá…", text: $note)
                        .font(.system(size: 12, design: .monospaced))
                        .textFieldStyle(.plain)
                        .padding(.horizontal, 8)
                        .padding(.vertical, 5)
                        .background(Color.primary.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: 5))
                }

                Text(status == .pending
                     ? "Excluded from your personal budget · still counted in card statement total"
                     : "Reimbursed (excluded from your personal budget · counted in card statement total)")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.secondary)
            }
        }
    }

    private func statusPill(title: String, target: ReimbursementOption.Status, tint: Color) -> some View {
        let isSelected = (status == target)

        return Button {
            status = target
        } label: {
            Text(title)
                .font(.system(size: 11, weight: isSelected ? .semibold : .regular, design: .monospaced))
                .foregroundStyle(isSelected ? tint : .secondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 6)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isSelected ? tint.opacity(0.15) : Color.primary.opacity(0.06))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(isSelected ? tint.opacity(0.5) : Color.clear, lineWidth: 1)
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}
