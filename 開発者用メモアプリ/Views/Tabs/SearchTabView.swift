import SwiftUI

struct SearchTabView: View {
    let recentSearchQueries: [String]
    let groupOptions: [IdeaGroupOption]
    let kindOptions: [IdeaKindOption]
    @Binding var searchText: String
    @Binding var selectedKindRaw: String?
    @Binding var selectedGroupName: String?
    @Binding var selectedStatus: IdeaStatus?
    @Binding var favoritesOnly: Bool
    @Binding var sortOption: IdeaSortOption
    let hasActiveFilters: Bool
    let showSearchResults: () -> Void
    let recordSearchQuery: (String) -> Void
    let resetSearchFilters: () -> Void
    let clearSearchHistory: () -> Void

    var body: some View {
        List {
            Section {
                HStack(spacing: 10) {
                    TextField("タイトル・内容・タグで検索", text: $searchText)
                        .textInputAutocapitalization(.never)
                        .autocorrectionDisabled()
                        .submitLabel(.search)
                        .onSubmit(showSearchResults)

                    Button(action: showSearchResults) {
                        Image(systemName: "magnifyingglass")
                            .font(.headline)
                            .frame(width: 38, height: 38)
                    }
                    .buttonStyle(.borderedProminent)
                    .accessibilityLabel("検索")
                }

                if !recentSearchQueries.isEmpty {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(recentSearchQueries, id: \.self) { query in
                                Button(query) {
                                    searchText = query
                                    recordSearchQuery(query)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                            }
                        }
                        .padding(.vertical, 2)
                    }
                }
            }

            Section("絞り込み") {
                Picker("グループ", selection: groupSelection) {
                    Text("すべて").tag("all")
                    ForEach(groupOptions) { group in
                        Text(group.name).tag(group.name)
                    }
                }

                Picker("種類", selection: kindSelection) {
                    Text("すべて").tag("all")
                    ForEach(kindOptions) { kind in
                        Text(kind.label).tag(kind.id)
                    }
                }

                Picker("ステータス", selection: statusSelection) {
                    Text("すべて").tag("all")
                    ForEach(IdeaStatus.allCases) { status in
                        Text(status.label).tag(status.rawValue)
                    }
                }

                Toggle("お気に入りのみ", isOn: $favoritesOnly)

                Picker("並び替え", selection: $sortOption) {
                    ForEach(IdeaSortOption.allCases) { option in
                        Text(option.label).tag(option)
                    }
                }

                Button("条件をリセット") {
                    resetSearchFilters()
                }
                .disabled(!hasActiveFilters && searchText.trimmed.isEmpty)

                Button("検索履歴を消去") {
                    clearSearchHistory()
                }
                .disabled(recentSearchQueries.isEmpty)
            }

            if hasActiveFilters {
                ActiveFiltersRow(
                    selectedKindRaw: selectedKindRaw,
                    selectedGroupName: selectedGroupName,
                    selectedStatus: selectedStatus,
                    favoritesOnly: favoritesOnly,
                    kindOptions: kindOptions
                )
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
    }

    private var kindSelection: Binding<String> {
        Binding(
            get: { selectedKindRaw ?? "all" },
            set: { selectedKindRaw = $0 == "all" ? nil : $0 }
        )
    }

    private var groupSelection: Binding<String> {
        Binding(
            get: { selectedGroupName ?? "all" },
            set: { selectedGroupName = $0 == "all" ? nil : $0 }
        )
    }

    private var statusSelection: Binding<String> {
        Binding(
            get: { selectedStatus?.rawValue ?? "all" },
            set: { selectedStatus = IdeaStatus(rawValue: $0) }
        )
    }
}

struct SearchResultsView<IdeaRow: View>: View {
    let hasActiveFilters: Bool
    let selectedKindRaw: String?
    let selectedGroupName: String?
    let selectedStatus: IdeaStatus?
    let favoritesOnly: Bool
    let kindOptions: [IdeaKindOption]
    let searchText: String
    let filteredIdeas: [Idea]
    let pagedFilteredIdeas: [Idea]
    let hasMoreSearchIdeas: Bool
    let remainingSearchIdeasCount: Int
    let resetSearchFilters: () -> Void
    let loadMoreSearchIdeas: () -> Void
    @ViewBuilder var ideaRow: (Idea) -> IdeaRow

    var body: some View {
        List {
            if hasActiveFilters {
                ActiveFiltersRow(
                    selectedKindRaw: selectedKindRaw,
                    selectedGroupName: selectedGroupName,
                    selectedStatus: selectedStatus,
                    favoritesOnly: favoritesOnly,
                    kindOptions: kindOptions
                )
            }

            if filteredIdeas.isEmpty {
                EmptyResultsRow(
                    actionTitle: hasActiveFilters || !searchText.trimmed.isEmpty ? "条件をリセット" : nil,
                    action: {
                        resetSearchFilters()
                    }
                )
            } else {
                Section("検索結果 \(filteredIdeas.count)件") {
                    ForEach(pagedFilteredIdeas) { idea in
                        ideaRow(idea)
                    }

                    if hasMoreSearchIdeas {
                        LoadMoreIdeasRow(
                            remainingCount: remainingSearchIdeasCount,
                            action: loadMoreSearchIdeas
                        )
                    }
                }
            }
        }
        .navigationTitle("検索結果")
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
    }
}
