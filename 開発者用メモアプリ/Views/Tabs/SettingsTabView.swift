import SwiftUI

struct SettingsTabView<CloudRow: View>: View {
    let currentPlan: AppPlan
    let creationAllowance: IdeaCreationAllowance
    let extraLocalSlots: Int
    @Binding var ideaKindOptionsData: String
    @Binding var ideaGroupOptionsData: String
    @Binding var promotionCodeInput: String
    let promotionCodeMessage: String?
    let promotionCodeMessageColor: Color
    @Binding var referralCodeInput: String
    let referralCodeMessage: String?
    let redeemPromotionCode: () -> Void
    let applyReferralCode: () -> Void
    let planAction: () -> Void
    let legalAction: () -> Void
    let mdExportURL: () -> URL
    let csvExportURL: () -> URL
    let jsonExportURL: () -> URL
    @ViewBuilder var cloudSyncRow: () -> CloudRow

    var body: some View {
        List {
            Section("アカウント") {
                cloudSyncRow()
            }

            Section {
                PlanSummaryCard(
                    plan: currentPlan,
                    allowance: creationAllowance,
                    extraLocalSlots: extraLocalSlots,
                    action: {
                        planAction()
                    }
                )

                Button {
                    planAction()
                } label: {
                    Label("プランを管理", systemImage: currentPlan == .free ? "person.crop.circle.badge.plus" : "cloud.fill")
                }
            } header: {
                Text("プラン")
            } footer: {
                Text("保存枠が少なくなったら、Freeの追加枠またはPlus / Proを選べます。クラウド保存はPlus / Proで使えます。")
            }

            Section("ライブラリ") {
                NavigationLink {
                    LibrarySettingsView(
                        kindOptionsData: $ideaKindOptionsData,
                        groupOptionsData: $ideaGroupOptionsData
                    )
                } label: {
                    Label("種類・グループの管理", systemImage: "slider.horizontal.3")
                }
            }

            Section {
                DeferredExportShareButton(
                    urlProvider: mdExportURL
                ) {
                    Label("Markdownで書き出す", systemImage: "doc.text")
                }
                DeferredExportShareButton(
                    urlProvider: csvExportURL
                ) {
                    Label("CSVで書き出す", systemImage: "tablecells")
                }
                DeferredExportShareButton(
                    urlProvider: jsonExportURL
                ) {
                    Label("JSONで書き出す", systemImage: "curlybraces")
                }
            } header: {
                Text("バックアップ")
            } footer: {
                Text("端末内のカードをまとめて共有・保存できます。重要な内容は定期的に外部へ退避してください。")
            }

            Section {
                PromotionCodeRedeemView(
                    code: $promotionCodeInput,
                    message: promotionCodeMessage,
                    messageColor: promotionCodeMessageColor,
                    redeemAction: redeemPromotionCode,
                    referralCode: $referralCodeInput,
                    referralMessage: referralCodeMessage,
                    referralAction: applyReferralCode
                )
            } header: {
                Text("特典コード")
            } footer: {
                Text("特典コードを引き換えると、プランの有効化や保存枠の追加ができます。App Storeの購入履歴とは別管理です。")
            }

            Section("情報") {
                Button {
                    legalAction()
                } label: {
                    Label("法務・プライバシー", systemImage: "doc.text.magnifyingglass")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
    }
}
