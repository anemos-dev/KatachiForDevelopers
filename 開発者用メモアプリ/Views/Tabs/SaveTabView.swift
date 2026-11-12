import SwiftUI

struct SaveTabView: View {
    @Binding var text: String
    @Binding var kindRaw: String
    @Binding var groupName: String

    let resetID: UUID
    let canSave: Bool
    let statusText: String
    let successMessage: String?
    let showsUpgradeNudge: Bool
    let upgradeTitle: String
    let upgradeMessage: String
    let kindOptions: [IdeaKindOption]
    let groupNames: [String]
    let saveAction: () -> Void
    let detailAction: () -> Void
    let planAction: () -> Void

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                Label(statusText, systemImage: canSave ? "tray.full" : "exclamationmark.triangle.fill")
                    .font(.subheadline.weight(.semibold))
                    .foregroundStyle(canSave ? Color.secondary : Color.orange)
                    .padding(12)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color(.secondarySystemBackground))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                if showsUpgradeNudge {
                    UpgradeNudgeRow(
                        title: upgradeTitle,
                        message: upgradeMessage,
                        action: planAction
                    )
                }

                VStack(alignment: .leading, spacing: 8) {
                    Text("入力欄")
                        .font(.caption.weight(.bold))
                        .foregroundStyle(.secondary)
                    TextField("作りたい機能、直したい違和感、あとで試したいこと", text: $text, axis: .vertical)
                        .id(resetID)
                        .font(.body)
                        .lineLimit(5...10)
                        .padding(12)
                        .background(Color(.systemBackground))
                        .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: 8, style: .continuous)
                                .stroke(Color.blue.opacity(0.35), lineWidth: 1.5)
                        )
                }
                .padding(14)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 14) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("種類")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Picker("種類", selection: $kindRaw) {
                            ForEach(kindOptions) { kind in
                                Text(kind.label).tag(kind.id)
                            }
                        }
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("グループ")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(.secondary)
                        Picker("グループ", selection: $groupName) {
                            ForEach(groupNames, id: \.self) { name in
                                Text(name).tag(name)
                            }
                        }
                    }
                }
                .padding(14)
                .background(Color(.secondarySystemBackground))
                .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                Button(action: saveAction) {
                    Label("保存", systemImage: "tray.and.arrow.down.fill")
                        .font(.headline)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)

                Button(action: detailAction) {
                    Label("詳細入力で作成", systemImage: "square.and.pencil")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.bordered)

                Button(action: planAction) {
                    Label("プランと保存枠を確認", systemImage: "person.crop.circle.badge.plus")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderless)

                if let successMessage {
                    Label(successMessage, systemImage: "checkmark.circle.fill")
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(.green)
                        .padding(.top, 2)
                }
            }
            .padding(20)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Color(.systemGroupedBackground))
    }
}
