import SwiftUI

struct GroupsTabView<GroupDestination: View>: View {
    let groupOptions: [IdeaGroupOption]
    let countIdeas: (String) -> Int
    @Binding var ideaKindOptionsData: String
    @Binding var ideaGroupOptionsData: String
    @ViewBuilder var groupDestination: (String) -> GroupDestination

    var body: some View {
        List {
            Section {
                ForEach(groupOptions) { group in
                    NavigationLink {
                        groupDestination(group.name)
                    } label: {
                        GroupListRow(
                            group: group,
                            count: countIdeas(group.name)
                        )
                    }
                }
            } header: {
                Text("グループ")
            } footer: {
                Text("グループを選ぶと、その中のカードだけを確認できます。")
            }

            Section {
                NavigationLink {
                    LibrarySettingsView(
                        kindOptionsData: $ideaKindOptionsData,
                        groupOptionsData: $ideaGroupOptionsData
                    )
                } label: {
                    Label("グループと種類を管理", systemImage: "slider.horizontal.3")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
    }
}
