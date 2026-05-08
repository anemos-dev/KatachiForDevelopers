import SwiftUI
import SwiftData
import AuthenticationServices

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var ideas: [Idea]

    @StateObject private var purchaseManager = PurchaseManager()
    @StateObject private var cloudSyncManager = CloudSyncManager()

    @AppStorage("billing.currentPlan") private var currentPlanRaw = AppPlan.free.rawValue
    @AppStorage("billing.extraLocalSlots") private var extraLocalSlots = 0
    @AppStorage("cloudSync.lastSuccessfulSyncAt") private var lastSuccessfulCloudSyncAt = 0.0
    @AppStorage(IdeaKindCatalog.storageKey) private var ideaKindOptionsData = ""
    @AppStorage(IdeaGroupCatalog.storageKey) private var ideaGroupOptionsData = ""

    @State private var searchText = ""
    @State private var selectedKindRaw: String?
    @State private var selectedGroupName: String?
    @State private var selectedStatus: IdeaStatus?
    @State private var favoritesOnly = false
    @State private var sortOption: IdeaSortOption = .updatedDescending

    @State private var selectedTab: KatachiTab = .home
    @State private var isPresentingCreateSheet = false
    @State private var isPresentingBillingSheet = false
    @State private var isPresentingLegalSheet = false
    @State private var quickCaptureText = ""
    @State private var quickCaptureKindRaw = IdeaKind.feature.rawValue
    @State private var quickCaptureGroupName = IdeaGroupCatalog.defaultName
    @State private var quickCaptureSuccessMessage: String?
    @State private var quickCaptureResetID = UUID()
    @State private var homeVisibleCount = IdeaPaging.pageSize
    @State private var searchVisibleCount = IdeaPaging.pageSize
    @State private var groupVisibleCounts: [String: Int] = [:]

    var body: some View {
        NavigationStack {
            selectedTabContent
            .navigationTitle(selectedTab.title)
            .navigationBarTitleDisplayMode(.large)
            .safeAreaInset(edge: .bottom) {
                KatachiTabBar(selectedTab: $selectedTab)
            }
            .sheet(isPresented: $isPresentingCreateSheet) {
                NavigationStack {
                    IdeaEditorView(
                        kindOptionsData: $ideaKindOptionsData,
                        groupOptionsData: $ideaGroupOptionsData
                    )
                }
            }
            .sheet(isPresented: $isPresentingBillingSheet) {
                NavigationStack {
                    BillingView(
                        currentPlan: currentPlan,
                        extraLocalSlots: extraLocalSlots,
                        purchaseManager: purchaseManager,
                        selectFreePlan: selectFreePlan,
                        applyPurchase: applyPurchase,
                        restorePurchases: restorePurchases
                    )
                }
            }
            .sheet(isPresented: $isPresentingLegalSheet) {
                NavigationStack {
                    LegalView()
                }
            }
            .task {
                await purchaseManager.start()
                syncStoredPlanWithEntitlements()
                cloudSyncManager.refresh(for: currentPlan)
            }
            .onChange(of: purchaseManager.purchasedProductIDs) { _, _ in
                syncStoredPlanWithEntitlements()
                cloudSyncManager.refresh(for: currentPlan)
            }
            .onChange(of: currentPlan) { _, newPlan in
                cloudSyncManager.refresh(for: newPlan)
            }
            .onChange(of: searchText) { _, _ in
                searchVisibleCount = IdeaPaging.pageSize
            }
            .onChange(of: selectedKindRaw) { _, _ in
                searchVisibleCount = IdeaPaging.pageSize
            }
            .onChange(of: selectedGroupName) { _, _ in
                searchVisibleCount = IdeaPaging.pageSize
            }
            .onChange(of: selectedStatus) { _, _ in
                searchVisibleCount = IdeaPaging.pageSize
            }
            .onChange(of: favoritesOnly) { _, _ in
                searchVisibleCount = IdeaPaging.pageSize
            }
            .onChange(of: sortOption) { _, _ in
                resetVisibleIdeaPages()
            }
        }
    }

    @ViewBuilder
    private var selectedTabContent: some View {
        switch selectedTab {
        case .home:
            homeContent
        case .groups:
            groupsContent
        case .save:
            saveContent
        case .search:
            searchContent
        case .settings:
            settingsContent
        }
    }

    @ViewBuilder
    private var homeContent: some View {
        if ideas.isEmpty {
            EmptyStateView(
                title: "Katachiにまだカードがありません",
                systemImage: "lightbulb",
                message: "中央の + から、最初のアイデアをすぐ残せます。"
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

                if currentPlan.usesCloudStorage {
                    cloudSyncRow
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                Section {
                    Picker("並び替え", selection: $sortOption) {
                        ForEach(IdeaSortOption.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                }

                ForEach(groupedHomeSections) { section in
                    ideaSection(section)
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

    private var groupsContent: some View {
        List {
            Section {
                ForEach(groupOptions) { group in
                    NavigationLink {
                        groupDetailContent(for: group.name)
                    } label: {
                        GroupListRow(
                            name: group.name,
                            count: countIdeas(in: group.name)
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

    private var saveContent: some View {
        QuickSaveView(
            text: $quickCaptureText,
            kindRaw: $quickCaptureKindRaw,
            groupName: $quickCaptureGroupName,
            resetID: quickCaptureResetID,
            canSave: canSaveQuickCapture,
            statusText: creationAllowance.saveScreenSummary,
            successMessage: quickCaptureSuccessMessage,
            kindOptions: kindOptions,
            groupNames: quickCaptureGroupNames,
            saveAction: saveQuickCapture,
            detailAction: presentCreateFlow,
            planAction: { isPresentingBillingSheet = true }
        )
    }

    private var searchContent: some View {
        List {
            Section {
                TextField("タイトル・内容・タグで検索", text: $searchText)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
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

            if filteredIdeas.isEmpty {
                EmptyResultsRow()
            } else {
                Section("検索結果") {
                    ForEach(pagedFilteredIdeas) { idea in
                        ideaNavigationLink(for: idea)
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
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
    }

    private var settingsContent: some View {
        List {
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

            Section("プランと同期") {
                Button {
                    isPresentingBillingSheet = true
                } label: {
                    Label("プランを管理", systemImage: currentPlan == .free ? "person.crop.circle.badge.plus" : "cloud.fill")
                }

                cloudSyncRow
            }

            Section("情報") {
                Button {
                    isPresentingLegalSheet = true
                } label: {
                    Label("法務・プライバシー", systemImage: "doc.text.magnifyingglass")
                }
            }
        }
        .listStyle(.insetGrouped)
        .scrollContentBackground(.hidden)
        .background(Color(.systemGroupedBackground))
    }

    private var currentPlan: AppPlan {
        if purchaseManager.hasCheckedEntitlements {
            return purchaseManager.entitledPlan ?? .free
        }
        return AppPlan(rawValue: currentPlanRaw) ?? .free
    }

    private var hasActiveFilters: Bool {
        selectedKindRaw != nil || selectedGroupName != nil || selectedStatus != nil || favoritesOnly
    }

    private var kindOptions: [IdeaKindOption] {
        IdeaKindCatalog.options(from: ideaKindOptionsData)
    }

    private var configuredGroupOptions: [IdeaGroupOption] {
        IdeaGroupCatalog.options(from: ideaGroupOptionsData)
    }

    private var groupOptions: [IdeaGroupOption] {
        var options = configuredGroupOptions
        let existingNames = Set(options.map(\.name))
        let discovered = Set(ideas.map(\.displayGroupName))
        for name in discovered.sorted() where !existingNames.contains(name) {
            options.append(IdeaGroupOption(id: "discovered.\(name)", name: name))
        }
        return options
    }

    private var quickCaptureGroupNames: [String] {
        var names = groupOptions.map(\.name)
        if !names.contains(quickCaptureGroupName) {
            names.insert(quickCaptureGroupName, at: 0)
        }
        return names
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

    private var cloudSyncRow: some View {
        CloudSyncStatusRow(
            state: cloudSyncManager.state,
            signInAction: {
                Task {
                    await cloudSyncManager.signInWithGoogle()
                }
            },
            configureAppleSignIn: cloudSyncManager.configureAppleSignInRequest,
            completeAppleSignIn: { result in
                Task {
                    await cloudSyncManager.completeAppleSignIn(result)
                }
            },
            signOutAction: {
                cloudSyncManager.signOut()
            },
            syncAction: {
                Task {
                    let syncCutoff = Date()
                    let changedIdeas = ideasForCloudSync(upTo: syncCutoff)
                    if await cloudSyncManager.sync(ideas: changedIdeas, plan: currentPlan) != nil {
                        lastSuccessfulCloudSyncAt = syncCutoff.timeIntervalSince1970
                    }
                }
            },
            deleteAccountAction: {
                Task {
                    await cloudSyncManager.deleteCloudAccount()
                }
            }
        )
    }

    private var canSaveQuickCapture: Bool {
        !quickCaptureText.trimmed.isEmpty && creationAllowance.allowed
    }

    private var creationAllowance: IdeaCreationAllowance {
        IdeaCreationPolicy.allowance(
            plan: currentPlan,
            ideaCreatedDates: ideas.map(\.createdAt),
            extraSlots: extraLocalSlots
        )
    }

    private var filteredIdeas: [Idea] {
        let result = ideas.filter { idea in
            matchesSearch(idea)
                && matchesKind(idea)
                && matchesGroup(idea)
                && matchesStatus(idea)
                && matchesFavorite(idea)
        }

        return sortedIdeas(result)
    }

    private var pagedFilteredIdeas: [Idea] {
        Array(filteredIdeas.prefix(searchVisibleCount))
    }

    private var groupedHomeSections: [IdeaGroupSection] {
        groupedSections(for: pagedHomeIdeas)
    }

    private var pagedHomeIdeas: [Idea] {
        Array(sortedIdeas(ideas).prefix(homeVisibleCount))
    }

    private var hasMoreHomeIdeas: Bool {
        sortedIdeas(ideas).count > homeVisibleCount
    }

    private var remainingHomeIdeasCount: Int {
        max(sortedIdeas(ideas).count - homeVisibleCount, 0)
    }

    private var hasMoreSearchIdeas: Bool {
        filteredIdeas.count > searchVisibleCount
    }

    private var remainingSearchIdeasCount: Int {
        max(filteredIdeas.count - searchVisibleCount, 0)
    }

    private var lastSuccessfulCloudSyncDate: Date? {
        lastSuccessfulCloudSyncAt > 0 ? Date(timeIntervalSince1970: lastSuccessfulCloudSyncAt) : nil
    }

    private func ideasForCloudSync(upTo cutoff: Date) -> [Idea] {
        guard let lastSuccessfulCloudSyncDate else {
            return ideas.filter { $0.updatedAt <= cutoff }
        }
        return ideas.filter {
            $0.updatedAt > lastSuccessfulCloudSyncDate && $0.updatedAt <= cutoff
        }
    }

    private func groupedSections(for ideas: [Idea]) -> [IdeaGroupSection] {
        let grouped = Dictionary(grouping: ideas, by: \.displayGroupName)
        var orderedNames = groupOptions.map(\.name).filter { grouped[$0] != nil }
        let known = Set(orderedNames)
        orderedNames += grouped.keys.filter { !known.contains($0) }.sorted()
        return orderedNames.map { name in
            IdeaGroupSection(name: name, ideas: grouped[name] ?? [])
        }
    }

    private func sortedIdeas(_ ideas: [Idea]) -> [Idea] {
        var result = ideas
        switch sortOption {
        case .updatedDescending:
            result.sort { lhs, rhs in
                lhs.updatedAt > rhs.updatedAt
            }
        case .createdDescending:
            result.sort { lhs, rhs in
                lhs.createdAt > rhs.createdAt
            }
        case .priorityDescending:
            result.sort { lhs, rhs in
                if lhs.priority == rhs.priority {
                    return lhs.updatedAt > rhs.updatedAt
                }
                return lhs.priority > rhs.priority
            }
        }
        return result
    }

    private func countIdeas(in groupName: String) -> Int {
        ideas.filter { $0.displayGroupName == groupName }.count
    }

    private func ideas(in groupName: String) -> [Idea] {
        sortedIdeas(ideas.filter { $0.displayGroupName == groupName })
    }

    private func visibleCount(forGroup groupName: String) -> Int {
        groupVisibleCounts[groupName] ?? IdeaPaging.pageSize
    }

    private func pagedIdeas(in groupName: String) -> [Idea] {
        Array(ideas(in: groupName).prefix(visibleCount(forGroup: groupName)))
    }

    @ViewBuilder
    private func ideaSection(_ section: IdeaGroupSection) -> some View {
        Section(section.name) {
            ForEach(section.ideas) { idea in
                ideaNavigationLink(for: idea)
            }
        }
    }

    @ViewBuilder
    private func groupDetailContent(for groupName: String) -> some View {
        let groupIdeas = ideas(in: groupName)
        if groupIdeas.isEmpty {
            EmptyStateView(
                title: "\(groupName)にカードがありません",
                systemImage: "tray",
                message: "+保存でグループを選ぶと、ここに集まります。",
                actionTitle: "+保存へ",
                action: {
                    quickCaptureGroupName = groupName
                    selectedTab = .save
                }
            )
            .navigationTitle(groupName)
        } else {
            let visibleIdeas = pagedIdeas(in: groupName)
            List {
                Section {
                    ForEach(visibleIdeas) { idea in
                        ideaNavigationLink(for: idea)
                    }

                    if groupIdeas.count > visibleIdeas.count {
                        LoadMoreIdeasRow(
                            remainingCount: groupIdeas.count - visibleIdeas.count,
                            action: {
                                loadMoreGroupIdeas(groupName)
                            }
                        )
                    }
                } header: {
                    Text("\(visibleIdeas.count)/\(groupIdeas.count)件")
                }
            }
            .listStyle(.insetGrouped)
            .scrollContentBackground(.hidden)
            .background(Color(.systemGroupedBackground))
            .navigationTitle(groupName)
        }
    }

    private func ideaNavigationLink(for idea: Idea) -> some View {
        NavigationLink {
            IdeaDetailView(
                idea: idea,
                kindOptionsData: $ideaKindOptionsData,
                groupOptionsData: $ideaGroupOptionsData
            )
        } label: {
            IdeaCardView(idea: idea, kindOptions: kindOptions)
                .padding(.vertical, 2)
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deleteIdea(idea)
            } label: {
                Label("削除", systemImage: "trash")
            }
        }
        .swipeActions(edge: .leading, allowsFullSwipe: false) {
            Button {
                toggleFavorite(idea)
            } label: {
                Label(
                    idea.isFavorite ? "解除" : "お気に入り",
                    systemImage: idea.isFavorite ? "star.slash" : "star.fill"
                )
            }
            .tint(.yellow)
        }
    }

    private func resetSearchFilters() {
        searchText = ""
        selectedKindRaw = nil
        selectedGroupName = nil
        selectedStatus = nil
        favoritesOnly = false
        searchVisibleCount = IdeaPaging.pageSize
    }

    private func matchesSearch(_ idea: Idea) -> Bool {
        let query = searchText.trimmed
        guard !query.isEmpty else {
            return true
        }
        let lowered = query.lowercased()
        let haystack = [
            idea.displayTitle,
            idea.concept,
            idea.rationale,
            idea.approach,
            idea.nextAction,
            idea.displayGroupName,
            idea.tags.joined(separator: " ")
        ]
        .joined(separator: "\n")
        .lowercased()
        return haystack.contains(lowered)
    }

    private func matchesKind(_ idea: Idea) -> Bool {
        guard let selectedKindRaw else {
            return true
        }
        return idea.kindRaw == selectedKindRaw
    }

    private func matchesGroup(_ idea: Idea) -> Bool {
        guard let selectedGroupName else {
            return true
        }
        return idea.displayGroupName == selectedGroupName
    }

    private func matchesStatus(_ idea: Idea) -> Bool {
        guard let selectedStatus else {
            return true
        }
        return idea.status == selectedStatus
    }

    private func matchesFavorite(_ idea: Idea) -> Bool {
        !favoritesOnly || idea.isFavorite
    }

    private func toggleFavorite(_ idea: Idea) {
        idea.isFavorite.toggle()
        idea.touch()
        saveContext()
    }

    private func deleteIdea(_ idea: Idea) {
        modelContext.delete(idea)
        saveContext()
        resetVisibleIdeaPages()
    }

    private func loadMoreHomeIdeas() {
        homeVisibleCount += IdeaPaging.pageSize
    }

    private func loadMoreSearchIdeas() {
        searchVisibleCount += IdeaPaging.pageSize
    }

    private func loadMoreGroupIdeas(_ groupName: String) {
        groupVisibleCounts[groupName] = visibleCount(forGroup: groupName) + IdeaPaging.pageSize
    }

    private func resetVisibleIdeaPages() {
        homeVisibleCount = IdeaPaging.pageSize
        searchVisibleCount = IdeaPaging.pageSize
        groupVisibleCounts = [:]
    }

    private func presentCreateFlow() {
        if creationAllowance.allowed {
            isPresentingCreateSheet = true
        } else {
            isPresentingBillingSheet = true
        }
    }

    private func saveQuickCapture() {
        let cleanText = quickCaptureText.trimmed
        guard !cleanText.isEmpty, creationAllowance.allowed else {
            if !creationAllowance.allowed {
                isPresentingBillingSheet = true
            }
            return
        }

        let title = cleanText
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? "Untitled Idea"

        let groupName = quickCaptureGroupName.trimmed.isEmpty ? IdeaGroupCatalog.defaultName : quickCaptureGroupName
        let idea = Idea(
            title: title,
            concept: cleanText,
            projectName: IdeaGroupCatalog.storedName(from: groupName)
        )
        idea.kindValue = quickCaptureKindRaw
        modelContext.insert(idea)
        saveContext()
        quickCaptureText = ""
        quickCaptureSuccessMessage = "保存しました。入力欄をリセットしました。"
        quickCaptureResetID = UUID()
    }

    private func saveContext() {
        do {
            try modelContext.save()
        } catch {
            assertionFailure("Failed to save model context: \(error)")
        }
    }

    private func selectFreePlan() {
        currentPlanRaw = AppPlan.free.rawValue
    }

    private func applyPurchase(_ product: BillingProduct) {
        if let plan = product.plan {
            currentPlanRaw = plan.rawValue
        }
        if let pack = product.extraSlotPack {
            extraLocalSlots += pack.slots
        }
        cloudSyncManager.refresh(for: currentPlan)
    }

    private func restorePurchases() async {
        _ = await purchaseManager.restore()
        syncStoredPlanWithEntitlements()
        cloudSyncManager.refresh(for: currentPlan)
    }

    private func syncStoredPlanWithEntitlements() {
        currentPlanRaw = (purchaseManager.entitledPlan ?? .free).rawValue
    }
}

private struct IdeaGroupSection: Identifiable {
    let name: String
    let ideas: [Idea]

    var id: String { name }
}

private enum IdeaPaging {
    static let pageSize = 24
}

private enum KatachiTab: String, CaseIterable, Identifiable {
    case home
    case groups
    case save
    case search
    case settings

    var id: String { rawValue }

    var title: String {
        switch self {
        case .home: return "ホーム"
        case .groups: return "グループ"
        case .save: return "+保存"
        case .search: return "検索"
        case .settings: return "設定"
        }
    }

    var iconName: String {
        switch self {
        case .home: return "house"
        case .groups: return "folder"
        case .save: return "plus"
        case .search: return "magnifyingglass"
        case .settings: return "gearshape"
        }
    }

    var selectedIconName: String {
        switch self {
        case .home: return "house.fill"
        case .groups: return "folder.fill"
        case .save: return "plus"
        case .search: return "magnifyingglass.circle.fill"
        case .settings: return "gearshape.fill"
        }
    }
}

private struct KatachiTabBar: View {
    @Binding var selectedTab: KatachiTab

    var body: some View {
        HStack(alignment: .bottom, spacing: 0) {
            tabButton(.home)
            tabButton(.groups)
            saveButton
            tabButton(.search)
            tabButton(.settings)
        }
        .padding(.horizontal, 14)
        .padding(.top, 8)
        .padding(.bottom, 6)
        .background(.bar)
    }

    private func tabButton(_ tab: KatachiTab) -> some View {
        Button {
            selectedTab = tab
        } label: {
            VStack(spacing: 4) {
                Image(systemName: selectedTab == tab ? tab.selectedIconName : tab.iconName)
                    .font(.system(size: 19, weight: .semibold))
                Text(tab.title)
                    .font(.caption2.weight(.semibold))
            }
            .foregroundStyle(selectedTab == tab ? .blue : .secondary)
            .frame(maxWidth: .infinity)
            .frame(height: 52)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(tab.title)
    }

    private var saveButton: some View {
        Button {
            selectedTab = .save
        } label: {
            Image(systemName: "plus")
                .font(.system(size: 23, weight: .bold))
                .foregroundStyle(.white)
                .frame(width: 50, height: 50)
                .background(selectedTab == .save ? Color.green : Color.blue)
                .clipShape(Circle())
                .shadow(color: .black.opacity(0.14), radius: 8, y: 3)
                .frame(maxWidth: .infinity)
                .frame(height: 58)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(KatachiTab.save.title)
    }
}

private struct EmptyStateView: View {
    let title: String
    let systemImage: String
    let message: String
    let actionTitle: String?
    let action: (() -> Void)?

    init(
        title: String,
        systemImage: String,
        message: String,
        actionTitle: String? = nil,
        action: (() -> Void)? = nil
    ) {
        self.title = title
        self.systemImage = systemImage
        self.message = message
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: systemImage)
                .font(.system(size: 44, weight: .semibold))
                .foregroundStyle(.blue)
            VStack(spacing: 6) {
                Text(title)
                    .font(.headline)
                Text(message)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)
            }

            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.borderedProminent)
            }
        }
        .padding(24)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(Color(.systemGroupedBackground))
    }
}

private struct EmptyResultsRow: View {
    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("条件に合うカードがありません")
                    .font(.subheadline.weight(.semibold))
                Text("検索語や絞り込みを変えると見つかるかもしれません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 8)
    }
}

private struct LoadMoreIdeasRow: View {
    let remainingCount: Int
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack {
                Spacer()
                Label("さらに24件読み込む", systemImage: "chevron.down.circle")
                    .font(.subheadline.weight(.semibold))
                Text("残り\(remainingCount)件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
            }
            .padding(.vertical, 8)
        }
        .buttonStyle(.plain)
        .foregroundStyle(.blue)
        .accessibilityHint("一覧に次の24件を追加表示します")
    }
}

private struct GroupListRow: View {
    let name: String
    let count: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: "folder.fill")
                .foregroundStyle(.blue)
                .frame(width: 28)
            VStack(alignment: .leading, spacing: 3) {
                Text(name)
                    .font(.subheadline.weight(.semibold))
                Text("\(count)件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer()
        }
        .padding(.vertical, 4)
    }
}

private struct QuickSaveView: View {
    @Binding var text: String
    @Binding var kindRaw: String
    @Binding var groupName: String

    let resetID: UUID
    let canSave: Bool
    let statusText: String
    let successMessage: String?
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

private struct QuickCaptureBar: View {
    @Binding var text: String
    let resetID: UUID
    let canSave: Bool
    let statusText: String
    let saveAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(statusText)
                .font(.caption)
                .foregroundStyle(.secondary)

            HStack(alignment: .bottom, spacing: 10) {
                TextField("思いついたことを即保存", text: $text, axis: .vertical)
                    .id(resetID)
                    .textFieldStyle(.roundedBorder)
                    .lineLimit(1...4)
                    .submitLabel(.done)

                Button(action: saveAction) {
                    Image(systemName: "paperplane.fill")
                        .font(.headline)
                        .frame(width: 36, height: 36)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
            }
        }
        .padding(.horizontal, 16)
        .padding(.top, 10)
        .padding(.bottom, 8)
    }
}

private struct StorageStatusRow: View {
    let plan: AppPlan
    let allowance: IdeaCreationAllowance
    let extraLocalSlots: Int

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: plan.usesCloudStorage ? "cloud.fill" : "iphone")
                .foregroundStyle(plan.usesCloudStorage ? .blue : .secondary)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text("\(plan.label)  \(allowance.summary)")
                    .font(.subheadline.weight(.semibold))
                Text(statusDetail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
    }

    private var statusDetail: String {
        if allowance.allowed {
            if plan == .free {
                return "残り\(allowance.remaining)件。追加枠: +\(extraLocalSlots)件"
            }
            return "残り\(allowance.remaining)件。月が変わると新規作成枠がリセットされます。"
        }
        return plan == .free ? "無料枠に達しました。追加枠かPlus/Proを選べます。" : "今月の新規作成枠に達しました。"
    }
}

private struct CloudSyncStatusRow: View {
    let state: CloudSyncState
    let signInAction: () -> Void
    let configureAppleSignIn: (ASAuthorizationAppleIDRequest) -> Void
    let completeAppleSignIn: (Result<ASAuthorization, Error>) -> Void
    let signOutAction: () -> Void
    let syncAction: () -> Void
    let deleteAccountAction: () -> Void

    @State private var isConfirmingDeletion = false

    var body: some View {
        HStack(spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(iconColor)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(state.label)
                    .font(.subheadline.weight(.semibold))
                Text(state.detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            actionControls

            Menu {
                Button("ログアウト", action: signOutAction)
                    .disabled(!canManageCloudAccount)
                Button("クラウドアカウント削除", role: .destructive) {
                    isConfirmingDeletion = true
                }
                .disabled(!canManageCloudAccount)
            } label: {
                Image(systemName: "ellipsis.circle")
            }
            .disabled(!canManageCloudAccount)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .confirmationDialog(
            "クラウドアカウントを削除しますか？",
            isPresented: $isConfirmingDeletion,
            titleVisibility: .visible
        ) {
            Button("クラウドデータとログイン情報を削除", role: .destructive, action: deleteAccountAction)
            Button("キャンセル", role: .cancel) {}
        } message: {
            Text("Firebase上のカードとKatachi用のログイン情報を削除します。Appleの購入履歴はApp Store側で管理されます。")
        }
    }

    @ViewBuilder
    private var actionControls: some View {
        if state == .signedOut {
            VStack(spacing: 6) {
                SignInWithAppleButton(
                    .signIn,
                    onRequest: configureAppleSignIn,
                    onCompletion: completeAppleSignIn
                )
                .signInWithAppleButtonStyle(.black)
                .frame(width: 132, height: 32)

                Button("Google", action: signInAction)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        } else {
            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(disablesAction)
        }
    }

    private var iconName: String {
        switch state {
        case .synced, .ready:
            return "cloud.fill"
        case .syncing:
            return "arrow.triangle.2.circlepath"
        case .failed, .needsConfiguration:
            return "exclamationmark.triangle.fill"
        case .localOnly, .signedOut:
            return "cloud"
        }
    }

    private var iconColor: Color {
        switch state {
        case .synced, .ready:
            return .blue
        case .syncing:
            return .orange
        case .failed, .needsConfiguration:
            return .red
        case .localOnly, .signedOut:
            return .secondary
        }
    }

    private var actionTitle: String {
        switch state {
        case .signedOut:
            return "ログイン"
        case .ready, .failed:
            return "同期"
        case .synced:
            return "再同期"
        case .localOnly, .needsConfiguration, .syncing:
            return "同期"
        }
    }

    private var disablesAction: Bool {
        switch state {
        case .needsConfiguration, .localOnly, .syncing:
            return true
        case .signedOut, .ready, .synced, .failed:
            return false
        }
    }

    private var canManageCloudAccount: Bool {
        switch state {
        case .ready, .synced, .failed:
            return true
        case .localOnly, .needsConfiguration, .signedOut, .syncing:
            return false
        }
    }

    private func action() {
        switch state {
        case .signedOut:
            signInAction()
        case .ready, .synced, .failed:
            syncAction()
        case .localOnly, .needsConfiguration, .syncing:
            break
        }
    }
}

private struct BillingView: View {
    @Environment(\.dismiss) private var dismiss
    @State private var isPresentingLegalSheet = false

    let currentPlan: AppPlan
    let extraLocalSlots: Int
    @ObservedObject var purchaseManager: PurchaseManager
    let selectFreePlan: () -> Void
    let applyPurchase: (BillingProduct) -> Void
    let restorePurchases: () async -> Void

    var body: some View {
        List {
            Section {
                BillingHeroView(
                    currentPlan: currentPlan,
                    extraLocalSlots: extraLocalSlots,
                    purchaseMessage: purchaseManager.state.message,
                    messageColor: messageColor
                )
                .listRowInsets(EdgeInsets(top: 12, leading: 16, bottom: 12, trailing: 16))
            }

            Section {
                ForEach(AppPlan.allCases) { plan in
                    PlanRow(
                        plan: plan,
                        isSelected: plan == currentPlan,
                        purchaseManager: purchaseManager,
                        selectFreePlan: selectFreePlan,
                        purchaseAction: purchase
                    )
                    .listRowInsets(EdgeInsets(top: 10, leading: 16, bottom: 10, trailing: 16))
                }
            } header: {
                Text("おすすめプラン")
            } footer: {
                Text("Plus / Proはクラウド保存を使う自動更新サブスクリプションです。年額は月額より約2か月分お得です。購入はApple IDに請求され、解約や管理はApp Storeのサブスクリプション管理から行えます。")
            }

            Section {
                ForEach(ExtraSlotPack.allCases) { pack in
                    let product = BillingProduct.extraProduct(for: pack)
                    Button {
                        Task {
                            await purchase(product)
                        }
                    } label: {
                        HStack {
                            VStack(alignment: .leading, spacing: 3) {
                                Text("\(pack.label)を追加")
                                    .font(.subheadline.weight(.semibold))
                                    .foregroundStyle(.primary)
                                Text("クラウド同期なし。Freeのまま保存枠だけ増やす")
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Text(purchaseManager.displayPrice(for: product))
                                .foregroundStyle(.secondary)
                        }
                    }
                    .disabled(currentPlan != .free || purchaseManager.product(for: product) == nil || purchaseManager.state == .loading)
                }
            } header: {
                Text("Freeのまま使い続ける")
            } footer: {
                Text("追加枠はローカル保存だけに適用される買い切りです。複数端末同期やクラウド保存が必要になったらPlus / Proを選んでください。")
            }

            Section("Plus / Proで解放されること") {
                BillingFeatureRow(
                    iconName: "cloud.fill",
                    title: "端末を変えてもカードを残せる",
                    detail: "Firebase保存で、機種変更や複数端末利用に備えられます。"
                )
                BillingFeatureRow(
                    iconName: "person.crop.circle",
                    title: "Google / Appleでログイン",
                    detail: "クラウドデータを自分のアカウントに紐づけます。"
                )
                BillingFeatureRow(
                    iconName: "square.grid.2x2",
                    title: "今後の拡張機能を優先提供",
                    detail: "Share Extension、ウィジェット、プロジェクト別ビューをPlus / Pro向けに育てます。"
                )
                BillingFeatureRow(
                    iconName: "arrow.down.doc.fill",
                    title: "振り返りとエクスポートを強化",
                    detail: "週次レビューや一括エクスポートで、溜めたアイデアを実装に戻しやすくします。"
                )
            }

            Section {
                Button {
                    isPresentingLegalSheet = true
                } label: {
                    Label("利用規約とプライバシーポリシー", systemImage: "doc.text.magnifyingglass")
                }

                Button {
                    Task {
                        await restorePurchases()
                    }
                } label: {
                    Label("購入情報を復元", systemImage: "arrow.clockwise")
                }
                .disabled(purchaseManager.state == .loading)
            } footer: {
                Text("購入前に利用規約とプライバシーポリシーをご確認ください。App Store Connectには商品ID katachi.developers.* を登録してください。商品が取得できない場合、購入ボタンは無効になります。")
            }
        }
        .navigationTitle("プラン")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("閉じる") {
                    dismiss()
                }
            }
        }
        .sheet(isPresented: $isPresentingLegalSheet) {
            NavigationStack {
                LegalView()
            }
        }
    }

    private var messageColor: Color {
        switch purchaseManager.state {
        case .failed:
            return .red
        case .purchased, .restored:
            return .green
        case .pending, .cancelled:
            return .orange
        case .idle, .loading:
            return .secondary
        }
    }

    private func purchase(_ product: BillingProduct) async {
        let result = await purchaseManager.purchase(product)
        if case .purchased(let purchasedProduct) = result {
            applyPurchase(purchasedProduct)
        }
    }
}

private struct BillingHeroView: View {
    let currentPlan: AppPlan
    let extraLocalSlots: Int
    let purchaseMessage: String?
    let messageColor: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .center, spacing: 12) {
                Image(systemName: currentPlan.usesCloudStorage ? "cloud.fill" : "iphone")
                    .font(.title2)
                    .foregroundStyle(currentPlan.usesCloudStorage ? .blue : .secondary)
                    .frame(width: 38, height: 38)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("現在のプラン: \(currentPlan.label)")
                        .font(.headline)
                    Text(currentPlan.shortDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                }
            }

            VStack(alignment: .leading, spacing: 7) {
                Label("50件を超えてもアイデアを残したいならPlusへ", systemImage: "tray.and.arrow.down.fill")
                Label("機種変更や複数端末でも使うならクラウド保存へ", systemImage: "arrow.triangle.2.circlepath")
                Label("毎日大量に保存するならProへ", systemImage: "bolt.fill")
            }
            .font(.caption.weight(.semibold))
            .foregroundStyle(.secondary)

            if currentPlan == .free {
                Text("購入済み追加枠: +\(extraLocalSlots)件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if let purchaseMessage {
                Text(purchaseMessage)
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(messageColor)
            }
        }
        .padding(.vertical, 4)
    }
}

private struct BillingFeatureRow: View {
    let iconName: String
    let title: String
    let detail: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: iconName)
                .foregroundStyle(.blue)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(detail)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 3)
    }
}

private struct LegalView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section("Katachi for Developers") {
                Text("Katachiは、開発中の着想をカードとして保存し、あとで実装候補として再利用しやすくするアプリです。")
            }

            Section("プライバシーポリシー") {
                Text("Freeプランでは、カード内容は端末内に保存されます。Plus / Proでクラウド同期を利用する場合、Sign in with AppleまたはGoogleログインの情報とカード内容をFirebaseに保存します。広告目的のトラッキングや第三者広告SDKは使用しません。")
                Text("保存される可能性がある情報: メールアドレスまたはユーザーID、カード本文、タグ、作成/更新日時、購入状態。")
                Text("ユーザーはアプリ内でカードを削除できます。クラウド同期利用時は、同期ステータスのメニューからログアウトとクラウドアカウント削除を行えます。サポート窓口からのデータ削除依頼も受け付けます。")
            }

            Section("利用規約") {
                Text("ユーザーは、自分が権利を持つ内容、または利用許諾を得た内容だけを保存してください。違法な内容、第三者の権利を侵害する内容、秘密保持義務に反する内容の保存は禁止します。")
                Text("Plus / Proは自動更新サブスクリプションです。購入はApple IDに請求され、更新や解約はApp Storeのサブスクリプション管理で行います。")
                Text("Freeの追加保存枠は消耗型アイテムです。購入後、Freeプランのローカル保存上限に加算されます。")
            }

            Section("権利表記") {
                Text("Katachi for Developersのアプリ名、UI、コード、ドキュメントはAnemosが保有または管理します。Apple、App Store、Firebase、Googleは各社の商標です。本アプリはApple、Google、Firebaseの公式アプリではありません。")
            }
        }
        .navigationTitle("法務・プライバシー")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("閉じる") {
                    dismiss()
                }
            }
        }
    }
}

private struct PlanRow: View {
    let plan: AppPlan
    let isSelected: Bool
    @ObservedObject var purchaseManager: PurchaseManager
    let selectFreePlan: () -> Void
    let purchaseAction: (BillingProduct) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .padding(.top, 1)

                VStack(alignment: .leading, spacing: 7) {
                    HStack(alignment: .firstTextBaseline) {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack(spacing: 6) {
                                Text(plan.label)
                                    .font(.headline)
                                    .foregroundStyle(.primary)

                                if let badge = plan.recommendationBadge {
                                    Text(badge)
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.white)
                                        .padding(.horizontal, 7)
                                        .padding(.vertical, 3)
                                        .background(plan == .plus ? Color.blue : Color.green)
                                        .clipShape(Capsule())
                                }
                            }
                            Text(plan.audienceLabel)
                                .font(.caption.weight(.semibold))
                                .foregroundStyle(.secondary)
                        }

                        Spacer(minLength: 8)

                        Text(plan.priceLabel)
                            .font(.subheadline.weight(.semibold))
                            .multilineTextAlignment(.trailing)
                            .foregroundStyle(plan == .free ? .secondary : .primary)
                    }

                    Text(plan.upgradeHeadline)
                        .font(.subheadline.weight(.semibold))
                        .foregroundStyle(plan == .free ? Color.primary : Color.blue)

                    VStack(alignment: .leading, spacing: 5) {
                        ForEach(plan.sellingPoints, id: \.self) { point in
                            Label(point, systemImage: "checkmark")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
            }

            if plan == .free {
                Button("Freeに戻す", action: selectFreePlan)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
                    .disabled(isSelected)
            } else {
                HStack(spacing: 8) {
                    ForEach(BillingProduct.subscriptionProducts(for: plan)) { product in
                        Button {
                            Task {
                                await purchaseAction(product)
                            }
                        } label: {
                            Text(buttonLabel(for: product))
                        }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.small)
                        .disabled(purchaseManager.product(for: product) == nil || purchaseManager.state == .loading)
                    }
                }
            }
        }
        .padding(.vertical, 4)
    }

    private func buttonLabel(for product: BillingProduct) -> String {
        let price = purchaseManager.displayPrice(for: product)
        switch product {
        case .plusYearly, .proYearly:
            return "年額 \(price)で始める"
        case .plusMonthly, .proMonthly:
            return "月額 \(price)"
        case .extra25, .extra100, .extra200:
            return price
        }
    }
}

private struct ActiveFiltersRow: View {
    let selectedKindRaw: String?
    let selectedGroupName: String?
    let selectedStatus: IdeaStatus?
    let favoritesOnly: Bool
    let kindOptions: [IdeaKindOption]

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let selectedGroupName {
                    IdeaBadge(label: selectedGroupName, tint: .blue)
                }
                if let selectedKindRaw {
                    IdeaBadge(
                        label: IdeaKindCatalog.label(for: selectedKindRaw, options: kindOptions),
                        tint: tintColor(forKindRaw: selectedKindRaw)
                    )
                }
                if let selectedStatus {
                    IdeaBadge(label: selectedStatus.label, tint: selectedStatus.tintColor)
                }
                if favoritesOnly {
                    IdeaBadge(label: "お気に入りのみ", tint: .yellow)
                }
            }
            .padding(.vertical, 4)
        }
    }
}

private struct IdeaCardView: View {
    let idea: Idea
    let kindOptions: [IdeaKindOption]

    private var shownTags: [String] {
        Array(idea.tags.prefix(3))
    }

    private var remainingTagCount: Int {
        max(idea.tags.count - shownTags.count, 0)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 8) {
                Text(idea.displayTitle)
                    .font(.headline)
                    .foregroundStyle(.primary)
                    .lineLimit(2)
                    .multilineTextAlignment(.leading)
                Spacer(minLength: 0)
                if idea.isFavorite {
                    Image(systemName: "star.fill")
                        .foregroundStyle(.yellow)
                }
            }

            if !idea.concept.isEmpty {
                Text(idea.concept)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
                    .lineLimit(2)
            }

            HStack(spacing: 8) {
                IdeaBadge(label: idea.status.label, tint: idea.status.tintColor)
                IdeaBadge(
                    label: IdeaKindCatalog.label(for: idea.kindRaw, options: kindOptions),
                    tint: tintColor(forKindRaw: idea.kindRaw)
                )
                IdeaBadge(label: idea.displayGroupName, tint: .blue)
            }

            if !shownTags.isEmpty {
                HStack(spacing: 6) {
                    ForEach(shownTags, id: \.self) { tag in
                        Text("#\(tag)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                            .padding(.horizontal, 8)
                            .padding(.vertical, 4)
                            .background(Color(.tertiarySystemFill))
                            .clipShape(Capsule())
                    }
                    if remainingTagCount > 0 {
                        Text("+\(remainingTagCount)")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
            }

            HStack(alignment: .firstTextBaseline, spacing: 8) {
                if !idea.nextAction.isEmpty {
                    Text("次: \(idea.nextAction)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer()
                Text(idea.updatedAt, style: .relative)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(14)
        .background(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .stroke(Color(.separator), lineWidth: 0.5)
        )
    }
}

private struct IdeaBadge: View {
    let label: String
    let tint: Color

    var body: some View {
        Text(label)
            .font(.caption.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 10)
            .padding(.vertical, 4)
            .background(tint.opacity(0.18))
            .clipShape(Capsule())
    }
}

private struct IdeaDetailView: View {
    @Environment(\.modelContext) private var modelContext
    @Bindable var idea: Idea
    @Binding var kindOptionsData: String
    @Binding var groupOptionsData: String
    @State private var isPresentingEditor = false

    private var kindOptions: [IdeaKindOption] {
        IdeaKindCatalog.options(from: kindOptionsData)
    }

    var body: some View {
        List {
            Section("概要") {
                LabelValueRow(label: "タイトル", value: idea.displayTitle)
                LabelValueRow(label: "種類", value: IdeaKindCatalog.label(for: idea.kindRaw, options: kindOptions))
                LabelValueRow(label: "グループ", value: idea.displayGroupName)
                LabelValueRow(label: "ステータス", value: idea.status.label)
                LabelValueRow(label: "優先度", value: "\(idea.priority)")
                LabelValueRow(label: "更新日時", value: idea.updatedAt.formatted(date: .abbreviated, time: .shortened))
            }

            Section("何を思いついたか") {
                TextOrPlaceholder(value: idea.concept)
            }

            Section("なぜ良さそうか") {
                TextOrPlaceholder(value: idea.rationale)
            }

            Section("どう作るか / どう試すか") {
                TextOrPlaceholder(value: idea.approach)
            }

            Section("次にやること") {
                TextOrPlaceholder(value: idea.nextAction)
            }

            if !idea.tags.isEmpty {
                Section("タグ") {
                    ScrollView(.horizontal, showsIndicators: false) {
                        HStack(spacing: 8) {
                            ForEach(idea.tags, id: \.self) { tag in
                                Text("#\(tag)")
                                    .font(.subheadline)
                                    .padding(.horizontal, 10)
                                    .padding(.vertical, 6)
                                    .background(Color(.tertiarySystemFill))
                                    .clipShape(Capsule())
                            }
                        }
                        .padding(.vertical, 4)
                    }
                }
            }
        }
        .navigationTitle("アイデア詳細")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: idea.markdownExport) {
                        Label("Markdown", systemImage: "doc.text")
                    }

                    ShareLink(item: idea.githubIssueExport) {
                        Label("GitHub Issue", systemImage: "number")
                    }
                } label: {
                    Image(systemName: "square.and.arrow.up")
                }
            }

            ToolbarItem(placement: .topBarTrailing) {
                Button {
                    idea.isFavorite.toggle()
                    idea.touch()
                    try? modelContext.save()
                } label: {
                    Image(systemName: idea.isFavorite ? "star.fill" : "star")
                        .foregroundStyle(idea.isFavorite ? .yellow : .secondary)
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("編集") {
                    isPresentingEditor = true
                }
            }
        }
        .sheet(isPresented: $isPresentingEditor) {
            NavigationStack {
                IdeaEditorView(
                    idea: idea,
                    kindOptionsData: $kindOptionsData,
                    groupOptionsData: $groupOptionsData
                )
            }
        }
    }
}

private struct LabelValueRow: View {
    let label: String
    let value: String

    var body: some View {
        HStack {
            Text(label)
                .foregroundStyle(.secondary)
            Spacer()
            Text(value)
                .multilineTextAlignment(.trailing)
        }
    }
}

private struct TextOrPlaceholder: View {
    let value: String

    var body: some View {
        if value.trimmed.isEmpty {
            Text("未入力")
                .foregroundStyle(.secondary)
        } else {
            Text(value)
        }
    }
}

private struct IdeaFilterView: View {
    @Environment(\.dismiss) private var dismiss

    @Binding var selectedKindRaw: String?
    @Binding var selectedGroupName: String?
    @Binding var selectedStatus: IdeaStatus?
    @Binding var favoritesOnly: Bool
    let kindOptions: [IdeaKindOption]
    let groupOptions: [IdeaGroupOption]

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

    var body: some View {
        Form {
            Section("グループ") {
                Picker("グループ", selection: groupSelection) {
                    Text("すべて").tag("all")
                    ForEach(groupOptions) { group in
                        Text(group.name).tag(group.name)
                    }
                }
            }

            Section("種類") {
                Picker("種類", selection: kindSelection) {
                    Text("すべて").tag("all")
                    ForEach(kindOptions) { kind in
                        Text(kind.label).tag(kind.id)
                    }
                }
            }

            Section("ステータス") {
                Picker("ステータス", selection: statusSelection) {
                    Text("すべて").tag("all")
                    ForEach(IdeaStatus.allCases) { status in
                        Text(status.label).tag(status.rawValue)
                    }
                }
            }

            Section {
                Toggle("お気に入りのみ", isOn: $favoritesOnly)
            }
        }
        .navigationTitle("絞り込み")
        .toolbar {
            ToolbarItem(placement: .topBarLeading) {
                Button("リセット") {
                    selectedKindRaw = nil
                    selectedGroupName = nil
                    selectedStatus = nil
                    favoritesOnly = false
                }
            }
            ToolbarItem(placement: .topBarTrailing) {
                Button("適用") {
                    dismiss()
                }
            }
        }
    }
}

private struct LibrarySettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var kindOptionsData: String
    @Binding var groupOptionsData: String

    @State private var newKindLabel = ""
    @State private var newGroupName = ""

    private var kindOptions: [IdeaKindOption] {
        IdeaKindCatalog.options(from: kindOptionsData)
    }

    private var groupOptions: [IdeaGroupOption] {
        IdeaGroupCatalog.options(from: groupOptionsData)
    }

    var body: some View {
        Form {
            Section("グループ") {
                ForEach(groupOptions) { group in
                    Text(group.name)
                }
                .onDelete(perform: deleteGroups)

                HStack {
                    TextField("新しいグループ", text: $newGroupName)
                    Button("追加", action: addGroup)
                        .disabled(newGroupName.trimmed.isEmpty)
                }
            }

            Section("種類") {
                ForEach(kindOptions) { kind in
                    HStack {
                        Text(kind.label)
                        Spacer()
                        if kind.isBuiltIn {
                            Text("標準")
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                    }
                }
                .onDelete(perform: deleteKinds)

                HStack {
                    TextField("新しい種類", text: $newKindLabel)
                    Button("追加", action: addKind)
                        .disabled(newKindLabel.trimmed.isEmpty)
                }
            }
        }
        .navigationTitle("設定")
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Button("閉じる") {
                    dismiss()
                }
            }
        }
    }

    private func addGroup() {
        let name = newGroupName.trimmed
        guard !name.isEmpty else {
            return
        }
        var options = groupOptions
        guard !options.contains(where: { $0.name.caseInsensitiveCompare(name) == .orderedSame }) else {
            newGroupName = ""
            return
        }
        options.append(IdeaGroupCatalog.makeCustomOption(name: name))
        groupOptionsData = IdeaGroupCatalog.encode(options)
        newGroupName = ""
    }

    private func deleteGroups(at offsets: IndexSet) {
        var options = groupOptions
        options.remove(atOffsets: offsets)
        if options.isEmpty {
            options = [IdeaGroupOption(id: "group.inbox", name: IdeaGroupCatalog.defaultName)]
        }
        groupOptionsData = IdeaGroupCatalog.encode(options)
    }

    private func addKind() {
        let label = newKindLabel.trimmed
        guard !label.isEmpty else {
            return
        }
        var options = kindOptions
        guard !options.contains(where: { $0.label.caseInsensitiveCompare(label) == .orderedSame }) else {
            newKindLabel = ""
            return
        }
        options.append(IdeaKindCatalog.makeCustomOption(label: label))
        kindOptionsData = IdeaKindCatalog.encode(options)
        newKindLabel = ""
    }

    private func deleteKinds(at offsets: IndexSet) {
        var options = kindOptions
        options.remove(atOffsets: offsets)
        if options.isEmpty {
            options = [IdeaKindOption(id: IdeaKind.note.rawValue, label: IdeaKind.note.label, isBuiltIn: true)]
        }
        kindOptionsData = IdeaKindCatalog.encode(options)
    }
}

private struct IdeaEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let editingIdea: Idea?
    @Binding private var kindOptionsData: String
    @Binding private var groupOptionsData: String

    @State private var title: String
    @State private var kindRaw: String
    @State private var status: IdeaStatus
    @State private var concept: String
    @State private var rationale: String
    @State private var approach: String
    @State private var nextAction: String
    @State private var projectName: String
    @State private var tagsText: String
    @State private var priority: Int
    @State private var isFavorite: Bool
    @State private var isDetailExpanded: Bool
    @State private var saveErrorMessage: String?

    init(
        idea: Idea? = nil,
        kindOptionsData: Binding<String>,
        groupOptionsData: Binding<String>
    ) {
        self.editingIdea = idea
        _kindOptionsData = kindOptionsData
        _groupOptionsData = groupOptionsData
        _title = State(initialValue: idea?.title ?? "")
        _kindRaw = State(initialValue: idea?.kindRaw ?? IdeaKind.feature.rawValue)
        _status = State(initialValue: idea?.status ?? .inbox)
        _concept = State(initialValue: idea?.concept ?? "")
        _rationale = State(initialValue: idea?.rationale ?? "")
        _approach = State(initialValue: idea?.approach ?? "")
        _nextAction = State(initialValue: idea?.nextAction ?? "")
        _projectName = State(initialValue: idea?.displayGroupName ?? IdeaGroupCatalog.defaultName)
        _tagsText = State(initialValue: idea?.tags.joined(separator: ", ") ?? "")
        _priority = State(initialValue: idea?.priority ?? 3)
        _isFavorite = State(initialValue: idea?.isFavorite ?? false)
        _isDetailExpanded = State(initialValue: idea != nil)
    }

    var body: some View {
        Form {
            Section("テンプレート") {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(IdeaTemplate.allCases) { template in
                            Button {
                                applyTemplate(template)
                            } label: {
                                Text(template.label)
                                    .font(.subheadline.weight(.semibold))
                                    .padding(.horizontal, 12)
                                    .padding(.vertical, 8)
                            }
                            .buttonStyle(.bordered)
                        }
                    }
                    .padding(.vertical, 2)
                }
            }

            Section("基本") {
                TextField("タイトル", text: $title)

                Picker("グループ", selection: $projectName) {
                    ForEach(editorGroupNames, id: \.self) { name in
                        Text(name).tag(name)
                    }
                }

                Picker("種類", selection: $kindRaw) {
                    ForEach(editorKindOptions) { kind in
                        Text(kind.label).tag(kind.id)
                    }
                }

                PromptedTextEditor(
                    label: "何を思いついたか",
                    prompt: "何を作るか、何を変えるかをそのまま書く",
                    text: $concept,
                    minHeight: 90
                )

                PromptedTextEditor(
                    label: "なぜ良さそうか",
                    prompt: "課題、価値、改善理由などを書く",
                    text: $rationale,
                    minHeight: 90
                )
            }

            Section {
                DisclosureGroup("詳細項目", isExpanded: $isDetailExpanded) {
                    PromptedTextEditor(
                        label: "どう作るか / どう試すか",
                        prompt: "実装方針、検証手順、懸念点などを書く",
                        text: $approach,
                        minHeight: 90
                    )

                    TextField("次にやること", text: $nextAction, axis: .vertical)
                        .lineLimit(2...4)

                    TextField("タグ (カンマ区切り)", text: $tagsText, axis: .vertical)
                        .lineLimit(1...3)

                    Picker("ステータス", selection: $status) {
                        ForEach(IdeaStatus.allCases) { status in
                            Text(status.label).tag(status)
                        }
                    }

                    Stepper(value: $priority, in: 1...5) {
                        Text("優先度: \(priority)")
                    }

                    Toggle("お気に入り", isOn: $isFavorite)
                }
            }
        }
        .navigationTitle(editingIdea == nil ? "新規アイデア" : "アイデア編集")
        .toolbar {
            ToolbarItem(placement: .cancellationAction) {
                Button("Cancel") {
                    dismiss()
                }
            }
            ToolbarItem(placement: .confirmationAction) {
                Button("Save") {
                    saveIdea()
                }
                .disabled(!canSave)
            }
        }
        .alert("保存できませんでした", isPresented: saveErrorIsPresented) {
            Button("OK", role: .cancel) {
                saveErrorMessage = nil
            }
        } message: {
            Text(saveErrorMessage ?? "不明なエラー")
        }
    }

    private var canSave: Bool {
        !title.trimmed.isEmpty || !concept.trimmed.isEmpty
    }

    private var editorKindOptions: [IdeaKindOption] {
        var options = IdeaKindCatalog.options(from: kindOptionsData)
        if !options.contains(where: { $0.id == kindRaw }) {
            options.append(IdeaKindOption(
                id: kindRaw,
                label: IdeaKindCatalog.label(for: kindRaw, options: options),
                isBuiltIn: IdeaKind(rawValue: kindRaw) != nil
            ))
        }
        return options
    }

    private var editorGroupNames: [String] {
        var names = IdeaGroupCatalog.options(from: groupOptionsData).map(\.name)
        if !names.contains(projectName) {
            names.insert(projectName, at: 0)
        }
        return names
    }

    private var saveErrorIsPresented: Binding<Bool> {
        Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )
    }

    private func applyTemplate(_ template: IdeaTemplate) {
        kindRaw = template.kind.rawValue
        status = template.status

        if concept.trimmed.isEmpty {
            concept = template.conceptPrompt
        }
        if rationale.trimmed.isEmpty {
            rationale = template.rationalePrompt
        }
        if approach.trimmed.isEmpty {
            approach = template.approachSeed
        }
        if nextAction.trimmed.isEmpty {
            nextAction = template.nextActionSeed
        }
        isDetailExpanded = true
    }

    private func saveIdea() {
        let resolvedTitle: String = {
            if !title.trimmed.isEmpty {
                return title.trimmed
            }
            if let firstLine = concept
                .split(whereSeparator: \.isNewline)
                .first?
                .trimmingCharacters(in: .whitespacesAndNewlines),
               !firstLine.isEmpty {
                return firstLine
            }
            return "Untitled Idea"
        }()

        let cleanConcept = concept.trimmed
        let cleanRationale = rationale.trimmed
        let cleanApproach = approach.trimmed
        let cleanNextAction = nextAction.trimmed
        let cleanProjectName = IdeaGroupCatalog.storedName(from: projectName)
        let cleanTags = Idea.normalizeTags(from: tagsText)
        let cleanPriority = Idea.normalizePriority(priority)

        if let editingIdea {
            editingIdea.title = resolvedTitle
            editingIdea.kindValue = kindRaw
            editingIdea.status = status
            editingIdea.concept = cleanConcept
            editingIdea.rationale = cleanRationale
            editingIdea.approach = cleanApproach
            editingIdea.nextAction = cleanNextAction
            editingIdea.projectName = cleanProjectName
            editingIdea.tags = cleanTags
            editingIdea.priority = cleanPriority
            editingIdea.isFavorite = isFavorite
            editingIdea.touch()
        } else {
            let newIdea = Idea(
                title: resolvedTitle,
                kind: IdeaKind(rawValue: kindRaw) ?? .feature,
                status: status,
                concept: cleanConcept,
                rationale: cleanRationale,
                approach: cleanApproach,
                nextAction: cleanNextAction,
                projectName: cleanProjectName,
                tags: cleanTags,
                priority: cleanPriority,
                isFavorite: isFavorite
            )
            newIdea.kindValue = kindRaw
            modelContext.insert(newIdea)
        }

        do {
            try modelContext.save()
            dismiss()
        } catch {
            saveErrorMessage = error.localizedDescription
        }
    }
}

private struct PromptedTextEditor: View {
    let label: String
    let prompt: String
    @Binding var text: String
    var minHeight: CGFloat = 80

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text(label)
                .font(.subheadline.weight(.semibold))
                .foregroundStyle(.secondary)

            ZStack(alignment: .topLeading) {
                if text.trimmed.isEmpty {
                    Text(prompt)
                        .foregroundStyle(.tertiary)
                        .padding(.horizontal, 4)
                        .padding(.vertical, 8)
                }
                TextEditor(text: $text)
                    .frame(minHeight: minHeight)
            }
        }
        .padding(.vertical, 2)
    }
}

private extension IdeaStatus {
    var tintColor: Color {
        switch self {
        case .inbox: return .gray
        case .refining: return .teal
        case .ready: return .orange
        case .done: return .green
        case .hold: return .indigo
        }
    }
}

private extension IdeaKind {
    var tintColor: Color {
        switch self {
        case .feature: return .blue
        case .uiux: return .pink
        case .tech: return .purple
        case .bug: return .red
        case .article: return .mint
        case .note: return .brown
        }
    }
}

private func tintColor(forKindRaw rawValue: String) -> Color {
    if let builtIn = IdeaKind(rawValue: rawValue) {
        return builtIn.tintColor
    }

    let palette: [Color] = [.cyan, .indigo, .green, .orange, .purple, .pink, .mint]
    let total = rawValue.unicodeScalars.reduce(0) { $0 + Int($1.value) }
    return palette[abs(total) % palette.count]
}

#Preview {
    ContentView()
        .modelContainer(for: Idea.self, inMemory: true)
}
