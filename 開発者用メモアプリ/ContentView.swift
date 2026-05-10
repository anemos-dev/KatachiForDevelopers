import SwiftUI
import SwiftData
import AuthenticationServices

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var ideas: [Idea]

    @AppStorage("legal.acceptedTermsVersion") private var acceptedTermsVersion = ""
    @AppStorage("onboarding.didInsertSampleIdeas") private var didInsertSampleIdeas = false
    @StateObject private var purchaseManager = PurchaseManager()
    @StateObject private var cloudSyncManager = CloudSyncManager()

    @AppStorage("billing.currentPlan") private var currentPlanRaw = AppPlan.free.rawValue
    @AppStorage("billing.promotionPlan") private var promotionPlanRaw = ""
    @AppStorage("billing.extraLocalSlots") private var extraLocalSlots = 0
    @AppStorage("billing.redeemedPromotionCodes") private var redeemedPromotionCodesData = ""
    @AppStorage("cloudSync.lastSuccessfulSyncAt") private var lastSuccessfulCloudSyncAt = 0.0
    @AppStorage(IdeaKindCatalog.storageKey) private var ideaKindOptionsData = ""
    @AppStorage(IdeaGroupCatalog.storageKey) private var ideaGroupOptionsData = ""
    @AppStorage("quickCapture.lastKindRaw") private var quickCaptureKindRaw = IdeaKind.feature.rawValue
    @AppStorage("quickCapture.lastGroupName") private var quickCaptureGroupName = IdeaGroupCatalog.defaultName
    @AppStorage("search.recentQueries") private var recentSearchQueriesData = ""
    @AppStorage("campaign.referralBonusApplied") private var referralBonusApplied = false

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
    @State private var quickCaptureSuccessMessage: String?
    @State private var quickCaptureResetID = UUID()
    @State private var promotionCodeInput = ""
    @State private var promotionCodeMessage: String?
    @State private var promotionCodeMessageColor: Color = .secondary
    @State private var referralCodeInput = ""
    @State private var referralCodeMessage: String?
    @State private var deletionCandidate: Idea?
    @State private var selectedIdea: Idea?
    @State private var homeVisibleCount = IdeaPaging.pageSize
    @State private var searchVisibleCount = IdeaPaging.pageSize
    @State private var groupVisibleCounts: [String: Int] = [:]

    var body: some View {
        Group {
            if hasAcceptedCurrentTerms {
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
                    .confirmationDialog(
                        "このカードを削除しますか？",
                        isPresented: deletionConfirmationBinding,
                        titleVisibility: .visible
                    ) {
                        Button("削除", role: .destructive) {
                            if let deletionCandidate {
                                deleteIdea(deletionCandidate)
                            }
                        }
                        Button("キャンセル", role: .cancel) {}
                    } message: {
                        Text("クラウド同期中の場合、Firebase上の同じカードも削除されます。")
                    }
                    .navigationDestination(item: $selectedIdea) { idea in
                        IdeaDetailView(
                            idea: idea,
                            kindOptionsData: $ideaKindOptionsData,
                            groupOptionsData: $ideaGroupOptionsData
                        )
                    }
                }
            } else {
                NavigationStack {
                    TermsAcceptanceView(
                        acceptAction: {
                            acceptedTermsVersion = LegalCopy.termsVersion
                            insertSampleIdeasIfNeeded()
                        }
                    )
                }
            }
        }
    }

    private var hasAcceptedCurrentTerms: Bool {
        acceptedTermsVersion == LegalCopy.termsVersion
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
                message: "思いついたことを、まず1枚だけ保存してみましょう。",
                actionTitle: "保存する",
                action: {
                    selectedTab = .save
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
                            isPresentingBillingSheet = true
                        }
                    )
                    .listRowSeparator(.hidden)
                    .listRowBackground(Color.clear)
                }

                if currentPlan.usesCloudStorage {
                    cloudSyncRow
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)
                }

                Section("最近のカード") {
                    ForEach(pagedHomeIdeas) { idea in
                        ideaNavigationLink(for: idea)
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
            showsUpgradeNudge: shouldShowUpgradeNudge,
            upgradeTitle: upgradeNudgeTitle,
            upgradeMessage: upgradeNudgeMessage,
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
                    .submitLabel(.search)
                    .onSubmit(recordCurrentSearchQuery)

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
                    recentSearchQueriesData = ""
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
            Section("アカウント") {
                cloudSyncRow
            }

            Section {
                PlanSummaryCard(
                    plan: currentPlan,
                    allowance: creationAllowance,
                    extraLocalSlots: extraLocalSlots,
                    action: {
                        isPresentingBillingSheet = true
                    }
                )

                Button {
                    isPresentingBillingSheet = true
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
        let purchasedPlan = purchaseManager.hasCheckedEntitlements ? purchaseManager.entitledPlan : nil
        let storedPlan = AppPlan(rawValue: currentPlanRaw) ?? .free
        let promotionPlan = AppPlan(rawValue: promotionPlanRaw)
        return [purchasedPlan, promotionPlan, storedPlan]
            .compactMap { $0 }
            .max(by: { $0.rank < $1.rank }) ?? .free
    }

    private var redeemedPromotionCodes: Set<String> {
        PromotionCodeStore.decode(redeemedPromotionCodesData)
    }

    private var recentSearchQueries: [String] {
        RecentSearchStore.decode(recentSearchQueriesData)
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
            options.append(IdeaGroupOption(id: "discovered.\(name)", name: name, iconName: "folder", colorName: "gray"))
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

    private var deletionConfirmationBinding: Binding<Bool> {
        Binding(
            get: { deletionCandidate != nil },
            set: { isPresented in
                if !isPresented {
                    deletionCandidate = nil
                }
            }
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
                    await performCloudSync()
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
        Array(homeSortedIdeas.prefix(homeVisibleCount))
    }

    private var homeSortedIdeas: [Idea] {
        ideas.sorted { lhs, rhs in
            lhs.updatedAt > rhs.updatedAt
        }
    }

    private var hasMoreHomeIdeas: Bool {
        homeSortedIdeas.count > homeVisibleCount
    }

    private var remainingHomeIdeasCount: Int {
        max(homeSortedIdeas.count - homeVisibleCount, 0)
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

    private var shouldShowUpgradeNudge: Bool {
        guard creationAllowance.allowed else {
            return true
        }
        let warningThreshold = max(5, Int(Double(creationAllowance.limit) * 0.1))
        return creationAllowance.remaining <= warningThreshold
    }

    private var upgradeNudgeTitle: String {
        creationAllowance.allowed ? "保存枠が少なくなっています" : "保存枠の上限に達しました"
    }

    private var upgradeNudgeMessage: String {
        if currentPlan == .free {
            return "あと\(creationAllowance.remaining)件保存できます。追加枠の購入かPlusでクラウド保存に切り替えられます。"
        }
        return "今月の残りは\(creationAllowance.remaining)件です。より多く保存するならProを検討できます。"
    }

    private func ideasForCloudSync(upTo cutoff: Date) -> [Idea] {
        guard let lastSuccessfulCloudSyncDate else {
            return ideas.filter { $0.updatedAt <= cutoff }
        }
        return ideas.filter {
            $0.updatedAt > lastSuccessfulCloudSyncDate && $0.updatedAt <= cutoff
        }
    }

    private func performCloudSync() async {
        let syncCutoff = Date()
        let changedIdeas = ideasForCloudSync(upTo: syncCutoff)

        guard let cloudRecords = await cloudSyncManager.fetchCloudIdeas(plan: currentPlan) else {
            return
        }

        let mergeSummary = mergeCloudRecords(cloudRecords)
        if mergeSummary.hasChanges {
            saveContext()
            resetVisibleIdeaPages()
        }

        if await cloudSyncManager.sync(ideas: changedIdeas, plan: currentPlan) != nil {
            lastSuccessfulCloudSyncAt = syncCutoff.timeIntervalSince1970
        }
    }

    private func mergeCloudRecords(_ records: [IdeaCloudRecord]) -> CloudMergeSummary {
        var existingIdeas = Dictionary(uniqueKeysWithValues: ideas.map { ($0.id.uuidString, $0) })
        var summary = CloudMergeSummary()

        for record in records {
            guard let ideaID = UUID(uuidString: record.id) else {
                summary.skipped += 1
                continue
            }

            if let existingIdea = existingIdeas[record.id] {
                if record.updatedAt > existingIdea.updatedAt {
                    apply(record, to: existingIdea)
                    summary.updated += 1
                } else {
                    summary.skipped += 1
                }
            } else {
                let idea = Idea(record: record, id: ideaID)
                modelContext.insert(idea)
                existingIdeas[record.id] = idea
                summary.inserted += 1
            }
        }

        return summary
    }

    private func apply(_ record: IdeaCloudRecord, to idea: Idea) {
        idea.title = record.title.trimmed
        idea.kindValue = record.kind
        idea.status = IdeaStatus(rawValue: record.status) ?? .inbox
        idea.concept = record.concept.trimmed
        idea.rationale = record.rationale.trimmed
        idea.approach = record.approach.trimmed
        idea.nextAction = record.nextAction.trimmed
        idea.projectName = record.projectName.trimmed
        idea.tags = Idea.normalizeTags(record.tags)
        idea.priority = Idea.normalizePriority(record.priority)
        idea.isFavorite = record.isFavorite
        idea.dueAt = record.dueAt
        idea.createdAt = record.createdAt
        idea.updatedAt = record.updatedAt
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

    private func ideaNavigationLink(for idea: Idea, prominence: IdeaCardProminence = .regular) -> some View {
        ZStack(alignment: .topTrailing) {
            Button {
                selectedIdea = idea
            } label: {
                IdeaCardView(idea: idea, kindOptions: kindOptions, prominence: prominence)
                    .padding(.vertical, 2)
            }
            .buttonStyle(.plain)

            Button {
                toggleFavorite(idea)
            } label: {
                Image(systemName: idea.isFavorite ? "star.fill" : "star")
                    .foregroundStyle(idea.isFavorite ? .yellow : .secondary)
                    .imageScale(.medium)
                    .frame(width: 34, height: 34)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(idea.isFavorite ? "お気に入りを解除" : "お気に入りに追加")
            .padding(.top, 12)
            .padding(.trailing, 10)
        }
        .listRowSeparator(.hidden)
        .listRowInsets(EdgeInsets(top: 8, leading: 16, bottom: 8, trailing: 16))
        .swipeActions(edge: .trailing, allowsFullSwipe: true) {
            Button(role: .destructive) {
                deletionCandidate = idea
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

    private func recordCurrentSearchQuery() {
        recordSearchQuery(searchText)
    }

    private func recordSearchQuery(_ query: String) {
        let cleaned = query.trimmed
        guard cleaned.count >= 2 else {
            return
        }
        recentSearchQueriesData = RecentSearchStore.encodeAdding(cleaned, to: recentSearchQueries)
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
        let deletedIdeaID = idea.id
        modelContext.delete(idea)
        saveContext()
        resetVisibleIdeaPages()

        if currentPlan.usesCloudStorage {
            Task {
                await cloudSyncManager.deleteCloudIdea(id: deletedIdeaID, plan: currentPlan)
            }
        }
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

    private func insertSampleIdeasIfNeeded() {
        guard !didInsertSampleIdeas, ideas.isEmpty else {
            return
        }
        IdeaSampleFactory.makeSamples().forEach(modelContext.insert)
        saveContext()
        didInsertSampleIdeas = true
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
        promotionPlanRaw = ""
        promotionCodeMessage = "特典コードで有効化したプランを解除しました。"
        promotionCodeMessageColor = .secondary
        cloudSyncManager.refresh(for: currentPlan)
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

    private func redeemPromotionCode() {
        let normalizedCode = PromotionCode.normalized(promotionCodeInput)
        guard !normalizedCode.isEmpty else {
            promotionCodeMessage = "特典コードを入力してください。"
            promotionCodeMessageColor = .red
            return
        }
        guard let promotionCode = PromotionCode.find(normalizedCode) else {
            promotionCodeMessage = "この特典コードは使えません。"
            promotionCodeMessageColor = .red
            return
        }
        guard promotionCode.isCurrentlyValid else {
            promotionCodeMessage = "この特典コードは有効期限が切れています。"
            promotionCodeMessageColor = .red
            return
        }
        if promotionCode.localRedemptionLimit != nil,
           redeemedPromotionCodes.contains(promotionCode.id) {
            promotionCodeMessage = "この特典コードはすでに適用済みです。"
            promotionCodeMessageColor = .secondary
            return
        }

        switch promotionCode.effect {
        case .plan(let plan):
            promotionPlanRaw = plan.rawValue
            currentPlanRaw = plan.rawValue
            cloudSyncManager.refresh(for: currentPlan)
        case .extraSlots(let slots):
            extraLocalSlots += slots
        }

        if promotionCode.localRedemptionLimit != nil {
            var redeemedCodes = redeemedPromotionCodes
            redeemedCodes.insert(promotionCode.id)
            redeemedPromotionCodesData = PromotionCodeStore.encode(redeemedCodes)
        }

        promotionCodeInput = ""
        promotionCodeMessage = "\(promotionCode.effect.message) \(promotionCode.note)"
        promotionCodeMessageColor = .green
    }

    private func applyReferralCode() {
        let normalizedCode = ReferralCode.normalized(referralCodeInput)
        guard !normalizedCode.isEmpty else {
            referralCodeMessage = "紹介コードを入力してください。"
            return
        }
        guard ReferralCode.isValid(normalizedCode) else {
            referralCodeMessage = "この紹介コードは使えません。"
            return
        }
        guard !referralBonusApplied else {
            referralCodeMessage = "紹介特典はこの端末では適用済みです。"
            return
        }
        extraLocalSlots += ReferralCode.bonusSlots
        referralBonusApplied = true
        referralCodeInput = ""
        referralCodeMessage = "紹介特典として保存枠を+\(ReferralCode.bonusSlots)件追加しました。"
    }
}

private struct IdeaGroupSection: Identifiable {
    let name: String
    let ideas: [Idea]

    var id: String { name }
}

private struct CloudMergeSummary {
    var inserted = 0
    var updated = 0
    var skipped = 0

    var hasChanges: Bool {
        inserted > 0 || updated > 0
    }
}

private enum PromotionCodeStore {
    static func decode(_ data: String) -> Set<String> {
        guard let jsonData = data.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: jsonData) else {
            return []
        }
        return Set(decoded)
    }

    static func encode(_ codes: Set<String>) -> String {
        guard let data = try? JSONEncoder().encode(codes.sorted()),
              let encoded = String(data: data, encoding: .utf8) else {
            return ""
        }
        return encoded
    }
}

private enum RecentSearchStore {
    static let maxCount = 8

    static func decode(_ data: String) -> [String] {
        guard let jsonData = data.data(using: .utf8),
              let decoded = try? JSONDecoder().decode([String].self, from: jsonData) else {
            return []
        }
        return decoded
    }

    static func encodeAdding(_ query: String, to existing: [String]) -> String {
        var values = existing.filter { $0.caseInsensitiveCompare(query) != .orderedSame }
        values.insert(query, at: 0)
        values = Array(values.prefix(maxCount))
        guard let data = try? JSONEncoder().encode(values),
              let encoded = String(data: data, encoding: .utf8) else {
            return ""
        }
        return encoded
    }
}

private enum ReferralCode {
    static let bonusSlots = 10
    private static let validCodes = [
        "KATACHI-FRIEND-10",
        "KFD-INVITE-10"
    ]

    static func normalized(_ rawValue: String) -> String {
        PromotionCode.normalized(rawValue)
    }

    static func isValid(_ rawValue: String) -> Bool {
        validCodes.contains(normalized(rawValue))
    }
}

private enum IdeaSampleFactory {
    static func makeSamples(now: Date = Date()) -> [Idea] {
        [
            Idea(
                title: "保存タブの入力欄をもっと速くする",
                kind: .uiux,
                status: .ready,
                concept: "保存タブを開いた瞬間に入力欄へ集中できるようにして、思いついたことをすぐ残せる体験にする。",
                rationale: "このアプリの中心価値は、開発中の違和感やアイデアを逃さないこと。",
                approach: "入力欄、種類、グループ、保存ボタンの視線移動を減らす。",
                nextAction: "実機で保存までのタップ数を確認する",
                projectName: "",
                tags: ["UI", "保存"],
                priority: 4,
                isFavorite: true,
                dueAt: Calendar.current.date(byAdding: .day, value: 7, to: now),
                createdAt: now,
                updatedAt: now
            ),
            Idea(
                title: "クラウド復元の確認",
                kind: .tech,
                status: .refining,
                concept: "再インストール後にGoogleログインして、Firestoreからカードを復元できるか確認する。",
                rationale: "機種変更やサ終リスクの説明にも関わる重要な品質項目。",
                approach: "テスト端末で削除、再インストール、ログイン、同期の順に確認する。",
                nextAction: "別端末またはシミュレータで復元テストをする",
                projectName: IdeaGroupCatalog.storedName(from: "仕事"),
                tags: ["Firebase", "QA"],
                priority: 5,
                dueAt: Calendar.current.date(byAdding: .day, value: 3, to: now),
                createdAt: now.addingTimeInterval(-3600),
                updatedAt: now.addingTimeInterval(-1800)
            ),
            Idea(
                title: "リリース記念の特典コード運用",
                kind: .feature,
                status: .inbox,
                concept: "初期ユーザー向けに保存枠を追加できる特典コードを配布する。",
                rationale: "無料版のまま試してもらいやすくし、Plus/Proへの導線も自然に作れる。",
                approach: "端末内コードから始め、必要になったらFirebase台帳へ移行する。",
                nextAction: "配布するコード名と有効期限を決める",
                projectName: IdeaGroupCatalog.storedName(from: "個人開発"),
                tags: ["キャンペーン"],
                priority: 3,
                createdAt: now.addingTimeInterval(-7200),
                updatedAt: now.addingTimeInterval(-3600)
            )
        ]
    }
}

private extension AppPlan {
    var rank: Int {
        switch self {
        case .free: return 0
        case .plus: return 1
        case .pro: return 2
        }
    }
}

private extension Idea {
    convenience init(record: IdeaCloudRecord, id: UUID) {
        self.init(
            id: id,
            title: record.title,
            kind: IdeaKind(rawValue: record.kind) ?? .feature,
            status: IdeaStatus(rawValue: record.status) ?? .inbox,
            concept: record.concept,
            rationale: record.rationale,
            approach: record.approach,
            nextAction: record.nextAction,
            projectName: record.projectName,
            tags: record.tags,
            priority: record.priority,
            isFavorite: record.isFavorite,
            dueAt: record.dueAt,
            createdAt: record.createdAt,
            updatedAt: record.updatedAt
        )
        kindValue = record.kind
    }
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
    let actionTitle: String?
    let action: (() -> Void)?

    init(actionTitle: String? = nil, action: (() -> Void)? = nil) {
        self.actionTitle = actionTitle
        self.action = action
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "line.3.horizontal.decrease.circle")
                .foregroundStyle(.secondary)
            VStack(alignment: .leading, spacing: 3) {
                Text("条件に合うカードがありません")
                    .font(.subheadline.weight(.semibold))
                Text("検索語や絞り込みを変えると見つかるかもしれません。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
            Spacer(minLength: 8)
            if let actionTitle, let action {
                Button(actionTitle, action: action)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
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
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 12) {
                Image(systemName: plan.usesCloudStorage ? "cloud.fill" : "iphone")
                    .foregroundStyle(plan.usesCloudStorage ? .blue : .secondary)
                    .frame(width: 24)

                VStack(alignment: .leading, spacing: 3) {
                    Text("\(plan.label)の保存枠")
                        .font(.subheadline.weight(.semibold))
                    Text(statusDetail)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                Spacer(minLength: 8)
            }

            ProgressView(value: Double(allowance.used), total: Double(max(allowance.limit, 1)))
                .tint(progressColor)

            VStack(alignment: .leading, spacing: 3) {
                Text("使用中: \(allowance.used) / \(allowance.limit)件")
                    .font(.caption)
                    .foregroundStyle(.primary)
                Text(allowance.allowed ? "あと\(allowance.remaining)件保存できます。" : "新しいカードを保存するには保存枠の追加が必要です。")
                    .font(.caption)
                    .foregroundStyle(allowance.allowed ? Color.secondary : Color.orange)
            }
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
                return "ローカル保存。追加枠: +\(extraLocalSlots)件"
            }
            return "クラウド保存。月が変わると新規作成枠がリセットされます。"
        }
        return plan == .free ? "無料枠に達しました。追加枠かPlus/Proを選べます。" : "今月の新規作成枠に達しました。"
    }

    private var progressColor: Color {
        let ratio = Double(allowance.used) / Double(max(allowance.limit, 1))
        if ratio >= 0.9 {
            return .orange
        }
        return plan.usesCloudStorage ? .blue : .green
    }
}

private struct UpgradeNudgeRow: View {
    let title: String
    let message: String
    let action: () -> Void

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            Image(systemName: "tray.and.arrow.down.fill")
                .foregroundStyle(.orange)
                .frame(width: 24)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.subheadline.weight(.semibold))
                Text(message)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer(minLength: 8)

            Button("確認", action: action)
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color.orange.opacity(0.12))
        )
    }
}

private struct PlanSummaryCard: View {
    let plan: AppPlan
    let allowance: IdeaCreationAllowance
    let extraLocalSlots: Int
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: plan.usesCloudStorage ? "cloud.fill" : "iphone")
                    .foregroundStyle(plan.usesCloudStorage ? .blue : .secondary)
                    .frame(width: 28, height: 28)
                    .background(Color(.tertiarySystemFill))
                    .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))

                VStack(alignment: .leading, spacing: 3) {
                    Text("現在: \(plan.label)")
                        .font(.headline)
                    Text(plan.shortDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Spacer(minLength: 8)
            }

            ProgressView(value: Double(allowance.used), total: Double(max(allowance.limit, 1)))
                .tint(plan.usesCloudStorage ? .blue : .green)

            HStack {
                Text("使用中 \(allowance.used) / \(allowance.limit)件")
                    .font(.caption.weight(.semibold))
                Spacer()
                Text("残り \(allowance.remaining)件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            if plan == .free {
                Text("追加済みローカル枠: +\(extraLocalSlots)件")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Button(action: action) {
                Label(plan == .free ? "保存枠とクラウド保存を見る" : "プランを確認", systemImage: "person.crop.circle.badge.plus")
                    .frame(maxWidth: .infinity)
            }
            .buttonStyle(.bordered)
        }
        .padding(.vertical, 4)
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

                Button("Googleでログイン", action: signInAction)
                    .buttonStyle(.bordered)
                    .controlSize(.small)
            }
        } else if state == .syncing {
            Button {} label: {
                HStack(spacing: 6) {
                    ProgressView()
                    Text("同期中")
                }
            }
            .buttonStyle(.bordered)
            .controlSize(.small)
            .disabled(true)
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

private struct PromotionCodeRedeemView: View {
    @Binding var code: String
    let message: String?
    let messageColor: Color
    let redeemAction: () -> Void
    @Binding var referralCode: String
    let referralMessage: String?
    let referralAction: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(spacing: 8) {
                TextField("特典コードを入力", text: $code)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit(redeemAction)

                Button("適用", action: redeemAction)
                    .buttonStyle(.borderedProminent)
                    .disabled(code.trimmed.isEmpty)
            }

            if let message {
                Text(message)
                    .font(.caption)
                    .foregroundStyle(messageColor)
            }

            Divider()

            HStack(spacing: 8) {
                TextField("紹介コードを入力", text: $referralCode)
                    .textInputAutocapitalization(.characters)
                    .autocorrectionDisabled()
                    .textFieldStyle(.roundedBorder)
                    .submitLabel(.done)
                    .onSubmit(referralAction)

                Button("適用", action: referralAction)
                    .buttonStyle(.bordered)
                    .disabled(referralCode.trimmed.isEmpty)
            }

            if let referralMessage {
                Text(referralMessage)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .padding(.vertical, 4)
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

private enum LegalCopy {
    static let appName = "Katachi for Developers"
    static let displayName = "Katachi"
    static let termsVersion = "2026-05-08"
    static let lastUpdated = "2026年5月8日"

    static let serviceSummary = [
        "Katachi for Developersは、開発中の着想、実装メモ、検証メモなどをカードとして保存し、あとで再利用しやすくするための補助ツールです。",
        "本アプリは、保存内容の正確性、完全性、継続保存、特定目的への適合性、第三者権利の非侵害、または将来のOSや端末での動作を保証しません。"
    ]

    static let privacyItems = [
        "Freeプランでは、カード内容は原則として端末内に保存されます。",
        "Plus / Proでクラウド同期を利用する場合、Sign in with AppleまたはGoogleログインの認証情報、カード内容、タグ、作成/更新日時、購入状態などをFirebaseに保存することがあります。",
        "広告目的のトラッキングや第三者広告SDKは使用しません。",
        "ユーザーはアプリ内でカードを削除できます。クラウド同期利用時は、同期ステータスのメニューからログアウトとクラウドアカウント削除を行えます。"
    ]

    static let termsItems = [
        "ユーザーは、自分が権利を持つ内容、または利用許諾を得た内容だけを保存してください。違法な内容、第三者の権利を侵害する内容、秘密保持義務に反する内容の保存は禁止します。",
        "Plus / Proは自動更新サブスクリプションです。購入はApple IDに請求され、更新、解約、返金はApp Storeの規約およびAppleの手続きに従います。",
        "Freeの追加保存枠は消耗型アイテムです。購入後、Freeプランのローカル保存上限に加算されます。",
        "本アプリは、OSの仕様変更、端末の買い替え、古いOSの非対応、App StoreやFirebaseなど外部サービスの変更、通信障害、メンテナンス、開発終了、配信停止、サービス終了により、全部または一部の機能が利用できなくなる場合があります。",
        "ユーザーは重要な情報を自己の責任でバックアップしてください。アプリの不具合、同期失敗、端末故障、誤操作、アカウント削除、サービス終了などによるデータ消失について、法令で認められる最大限の範囲で、開発者は責任を負いません。",
        "本アプリの利用または利用不能により生じた損害、逸失利益、業務上の損失、第三者との紛争について、法令で認められる最大限の範囲で、開発者は責任を負いません。",
        "有料機能の価格、保存枠、提供内容、対応OS、提供地域は、将来変更される場合があります。既に購入済みのサブスクリプションや返金の扱いは、App Storeのルールに従います。",
        "本規約またはプライバシーポリシーを変更する場合があります。重要な変更がある場合、アプリ内表示など合理的な方法で通知し、必要に応じて再同意を求めます。"
    ]

    static let rightsItems = [
        "Katachi for Developersのアプリ名、UI、コード、ドキュメントはAnemosが保有または管理します。",
        "Apple、App Store、Firebase、Googleは各社の商標です。本アプリはApple、Google、Firebaseの公式アプリではありません。"
    ]
}

private struct TermsAcceptanceView: View {
    let acceptAction: () -> Void
    @State private var hasConfirmedAgreement = false

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text(LegalCopy.appName)
                        .font(.title2.weight(.bold))
                    Text("利用規約とプライバシーポリシー")
                        .font(.headline)
                    Text("最終更新: \(LegalCopy.lastUpdated)")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .padding(.vertical, 6)
            }

            LegalCopySection(title: "アプリについて", items: LegalCopy.serviceSummary)
            LegalCopySection(title: "プライバシーポリシー", items: LegalCopy.privacyItems)
            LegalCopySection(title: "利用規約", items: LegalCopy.termsItems)
            LegalCopySection(title: "権利表記", items: LegalCopy.rightsItems)

            Section {
                Toggle("上記の利用規約とプライバシーポリシーに同意します", isOn: $hasConfirmedAgreement)

                Button {
                    acceptAction()
                } label: {
                    Label("同意して開始", systemImage: "checkmark.circle.fill")
                        .frame(maxWidth: .infinity)
                }
                .buttonStyle(.borderedProminent)
                .disabled(!hasConfirmedAgreement)

                Text("同意しない場合、本アプリを利用できません。返金や購入管理はApp Storeの手続きに従ってください。")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        }
        .navigationTitle("利用開始前の確認")
    }
}

private struct LegalCopySection: View {
    let title: String
    let items: [String]

    var body: some View {
        Section(title) {
            ForEach(items, id: \.self) { item in
                Text(item)
                    .font(.subheadline)
            }
        }
    }
}

private struct LegalView: View {
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        List {
            Section(LegalCopy.appName) {
                Text("ホーム画面表示名: \(LegalCopy.displayName)")
                Text("最終更新: \(LegalCopy.lastUpdated)")
            }

            LegalCopySection(title: "アプリについて", items: LegalCopy.serviceSummary)
            LegalCopySection(title: "プライバシーポリシー", items: LegalCopy.privacyItems)
            LegalCopySection(title: "利用規約", items: LegalCopy.termsItems)
            LegalCopySection(title: "権利表記", items: LegalCopy.rightsItems)
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

private enum IdeaCardProminence {
    case regular
    case featured
}

private struct IdeaCardView: View {
    let idea: Idea
    let kindOptions: [IdeaKindOption]
    let prominence: IdeaCardProminence

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
                Color.clear
                    .frame(width: 34, height: 34)
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
                if let dueAt = idea.dueAt {
                    IdeaBadge(label: dueAt.formatted(date: .numeric, time: .omitted), tint: dueAt < Date() ? .red : .orange)
                }
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
        .padding(prominence == .featured ? 14 : 12)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(prominence == .featured ? Color.blue.opacity(0.08) : Color(.secondarySystemBackground))
        )
        .overlay(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .stroke(prominence == .featured ? Color.blue.opacity(0.28) : Color(.separator), lineWidth: 0.5)
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
                LabelValueRow(label: "期限", value: idea.dueDateLabel)
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
        .safeAreaInset(edge: .bottom) {
            Button {
                isPresentingEditor = true
            } label: {
                Label("編集", systemImage: "square.and.pencil")
                    .font(.headline)
                    .frame(maxWidth: .infinity)
                    .frame(height: 46)
            }
            .buttonStyle(.borderedProminent)
            .padding(.horizontal, 16)
            .padding(.top, 8)
            .padding(.bottom, 8)
            .background(.bar)
        }
        .toolbar {
            ToolbarItem(placement: .topBarTrailing) {
                Menu {
                    ShareLink(item: idea.markdownExport) {
                        Label("Markdown詳細", systemImage: "doc.text")
                    }

                    ShareLink(item: idea.githubIssueExport) {
                        Label("GitHub Issue", systemImage: "number")
                    }

                    ShareLink(item: idea.reviewExport) {
                        Label("レビュー用メモ", systemImage: "checklist")
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
    @State private var newGroupIconName = "folder"
    @State private var newGroupColorName = "blue"

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
                    HStack(spacing: 10) {
                        Image(systemName: group.iconName)
                            .foregroundStyle(color(forGroupColorName: group.colorName))
                            .frame(width: 24)
                        Text(group.name)
                        Spacer()
                        Text(group.colorName)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                }
                .onDelete(perform: deleteGroups)

                VStack(alignment: .leading, spacing: 10) {
                    TextField("新しいグループ", text: $newGroupName)
                    Picker("アイコン", selection: $newGroupIconName) {
                        ForEach(GroupAppearance.iconOptions, id: \.self) { iconName in
                            Label(iconName, systemImage: iconName).tag(iconName)
                        }
                    }
                    Picker("色", selection: $newGroupColorName) {
                        ForEach(GroupAppearance.colorOptions, id: \.self) { colorName in
                            Text(colorName).tag(colorName)
                        }
                    }
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
        options.append(IdeaGroupOption(id: "group.\(UUID().uuidString)", name: name, iconName: newGroupIconName, colorName: newGroupColorName))
        groupOptionsData = IdeaGroupCatalog.encode(options)
        newGroupName = ""
        newGroupIconName = "folder"
        newGroupColorName = "blue"
    }

    private func deleteGroups(at offsets: IndexSet) {
        var options = groupOptions
        options.remove(atOffsets: offsets)
        if options.isEmpty {
            options = [IdeaGroupOption(id: "group.inbox", name: IdeaGroupCatalog.defaultName, iconName: "tray", colorName: "blue")]
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
    @State private var hasDueDate: Bool
    @State private var dueAt: Date
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
        _hasDueDate = State(initialValue: idea?.dueAt != nil)
        _dueAt = State(initialValue: idea?.dueAt ?? Date())
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

                    Toggle("期限を設定", isOn: $hasDueDate)
                    if hasDueDate {
                        DatePicker("期限", selection: $dueAt, displayedComponents: .date)
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
        let cleanDueAt = hasDueDate ? dueAt : nil

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
            editingIdea.dueAt = cleanDueAt
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
                isFavorite: isFavorite,
                dueAt: cleanDueAt
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

private enum GroupAppearance {
    static let iconOptions = ["folder", "tray", "hammer", "briefcase", "doc.text", "paintpalette", "lightbulb", "tag"]
    static let colorOptions = ["blue", "green", "orange", "pink", "teal", "indigo", "gray"]
}

private func color(forGroupColorName name: String) -> Color {
    switch name {
    case "green": return .green
    case "orange": return .orange
    case "pink": return .pink
    case "teal": return .teal
    case "indigo": return .indigo
    case "gray": return .gray
    default: return .blue
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
