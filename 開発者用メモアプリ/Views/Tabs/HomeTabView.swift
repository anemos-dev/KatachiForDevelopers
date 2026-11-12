import SwiftUI

struct HomeTabView<CloudRow: View, IdeaRow: View>: View {
    let ideas: [Idea]
    let currentPlan: AppPlan
    let creationAllowance: IdeaCreationAllowance
    let extraLocalSlots: Int
    let shouldShowUpgradeNudge: Bool
    let upgradeNudgeTitle: String
    let upgradeNudgeMessage: String
    let nextActionIdeas: [Idea]
    let dueSoonIdeas: [Idea]
    let uncategorizedIdeas: [Idea]
    let kindOptions: [IdeaKindOption]
    let groupOptions: [IdeaGroupOption]
    let pagedHomeIdeas: [Idea]
    let hasMoreHomeIdeas: Bool
    let remainingHomeIdeasCount: Int
    let createAction: () -> Void
    let planAction: () -> Void
    let selectIdea: (Idea) -> Void
    let loadMoreHomeIdeas: () -> Void
    @ViewBuilder var cloudSyncRow: () -> CloudRow
    @ViewBuilder var ideaRow: (Idea) -> IdeaRow

    var body: some View {
        if ideas.isEmpty {
            EmptyStateView(
                title: "Katachiにまだカードがありません",
                systemImage: "lightbulb",
                message: "思いついたことを、まず1枚だけ保存してみましょう。",
                actionTitle: "保存する",
                action: {
                    createAction()
                }
            )
        } else {
            List {
                StorageStatusRow(
                    plan: currentPlan,
                    allowance: creationAllowance,
                    extraLocalSlots: extraLocalSlots
                )
                .listRowSeparator(.hidden)
                .listRowBackground(Color.clear)

                if shouldShowUpgradeNudge {
                    UpgradeNudgeRow(
                        title: upgradeNudgeTitle,
                        message: upgradeNudgeMessage,
                        action: {
                            planAction()
                        }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                if currentPlan.usesCloudStorage {
                    cloudSyncRow()
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                if !nextActionIdeas.isEmpty || !dueSoonIdeas.isEmpty || !uncategorizedIdeas.isEmpty {
                    Section("今見るカード") {
                        if !nextActionIdeas.isEmpty {
                            SmartIdeaShelfRow(
                                title: "次にやること",
                                subtitle: "\(nextActionIdeas.count)件のアクションがあります",
                                iconName: "checklist",
                                tint: .green,
                                ideas: Array(nextActionIdeas.prefix(3)),
                                kindOptions: kindOptions,
                                groupOptions: groupOptions,
                                selectAction: selectIdea
                            )
                            .listRowSeparator(.hidden)
                        }

                        if !dueSoonIdeas.isEmpty {
                            SmartIdeaShelfRow(
                                title: "期限が近い",
                                subtitle: "\(dueSoonIdeas.count)件を確認できます",
                                iconName: "calendar",
                                tint: .orange,
                                ideas: Array(dueSoonIdeas.prefix(3)),
                                kindOptions: kindOptions,
                                groupOptions: groupOptions,
                                selectAction: selectIdea
                            )
                            .listRowSeparator(.hidden)
                        }

                        if !uncategorizedIdeas.isEmpty {
                            SmartIdeaShelfRow(
                                title: "未分類",
                                subtitle: "Inboxに\(uncategorizedIdeas.count)件あります",
                                iconName: "tray",
                                tint: .blue,
                                ideas: Array(uncategorizedIdeas.prefix(3)),
                                kindOptions: kindOptions,
                                groupOptions: groupOptions,
                                selectAction: selectIdea
                            )
                            .listRowSeparator(.hidden)
                        }
                    }
                }

                Section("最近のカード") {
                    ForEach(pagedHomeIdeas) { idea in
                        ideaRow(idea)
                    }
                }

                if hasMoreHomeIdeas {
                    LoadMoreIdeasRow(
                        remainingCount: remainingHomeIdeasCount,
                        action: loadMoreHomeIdeas
                    )
                    .listRowSeparator(.hidden)
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
        }
    }
}
