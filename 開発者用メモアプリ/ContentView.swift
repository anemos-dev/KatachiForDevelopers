import SwiftUI
import SwiftData

struct ContentView: View {
    @Environment(\.modelContext) private var modelContext
    @Query private var ideas: [Idea]

    @StateObject private var purchaseManager = PurchaseManager()
    @StateObject private var cloudSyncManager = CloudSyncManager()

    @AppStorage("billing.currentPlan") private var currentPlanRaw = AppPlan.free.rawValue
    @AppStorage("billing.extraLocalSlots") private var extraLocalSlots = 0

    @State private var searchText = ""
    @State private var selectedKind: IdeaKind?
    @State private var selectedStatus: IdeaStatus?
    @State private var favoritesOnly = false
    @State private var sortOption: IdeaSortOption = .updatedDescending

    @State private var isPresentingCreateSheet = false
    @State private var isPresentingFilterSheet = false
    @State private var isPresentingBillingSheet = false
    @State private var quickCaptureText = ""

    var body: some View {
        NavigationStack {
            Group {
                if filteredIdeas.isEmpty {
                    ContentUnavailableView(
                        "Katachiにまだカードがありません",
                        systemImage: "lightbulb",
                        description: Text("下の入力欄から、最初のアイデアをすぐ保存できます。")
                    )
                } else {
                    List {
                        if hasActiveFilters {
                            ActiveFiltersRow(
                                selectedKind: selectedKind,
                                selectedStatus: selectedStatus,
                                favoritesOnly: favoritesOnly
                            )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }

                        StorageStatusRow(
                            plan: currentPlan,
                            allowance: creationAllowance,
                            extraLocalSlots: extraLocalSlots,
                            upgradeAction: { isPresentingBillingSheet = true }
                        )
                        .listRowSeparator(.hidden)
                        .listRowBackground(Color.clear)

                        if currentPlan.usesCloudStorage {
                            CloudSyncStatusRow(
                                state: cloudSyncManager.state,
                                signInAction: {
                                    Task {
                                        await cloudSyncManager.signInWithGoogle()
                                    }
                                },
                                syncAction: {
                                    Task {
                                        await cloudSyncManager.sync(ideas: ideas, plan: currentPlan)
                                    }
                                }
                            )
                            .listRowSeparator(.hidden)
                            .listRowBackground(Color.clear)
                        }

                        ForEach(filteredIdeas) { idea in
                            NavigationLink {
                                IdeaDetailView(idea: idea)
                            } label: {
                                IdeaCardView(idea: idea)
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
                    }
                    .listStyle(.plain)
                }
            }
            .toolbar {
                ToolbarItem(placement: .topBarLeading) {
                    Button {
                        isPresentingFilterSheet = true
                    } label: {
                        Image(systemName: hasActiveFilters ? "line.3.horizontal.decrease.circle.fill" : "line.3.horizontal.decrease.circle")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Menu {
                        Picker("並び替え", selection: $sortOption) {
                            ForEach(IdeaSortOption.allCases) { option in
                                Text(option.label).tag(option)
                            }
                        }
                    } label: {
                        Image(systemName: "arrow.up.arrow.down.circle")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        presentCreateFlow()
                    } label: {
                        Image(systemName: "plus")
                    }
                }

                ToolbarItem(placement: .topBarTrailing) {
                    Button {
                        isPresentingBillingSheet = true
                    } label: {
                        Image(systemName: currentPlan == .free ? "person.crop.circle.badge.plus" : "cloud.fill")
                    }
                }
            }
            .navigationTitle("Katachi")
            .searchable(text: $searchText, prompt: "タイトル・内容・タグで検索")
            .safeAreaInset(edge: .bottom) {
                QuickCaptureBar(
                    text: $quickCaptureText,
                    canSave: canSaveQuickCapture,
                    statusText: creationAllowance.summary,
                    saveAction: saveQuickCapture
                )
                .background(.bar)
            }
            .sheet(isPresented: $isPresentingCreateSheet) {
                NavigationStack {
                    IdeaEditorView()
                }
            }
            .sheet(isPresented: $isPresentingFilterSheet) {
                NavigationStack {
                    IdeaFilterView(
                        selectedKind: $selectedKind,
                        selectedStatus: $selectedStatus,
                        favoritesOnly: $favoritesOnly
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
        }
    }

    private var currentPlan: AppPlan {
        if purchaseManager.hasCheckedEntitlements {
            return purchaseManager.entitledPlan ?? .free
        }
        return AppPlan(rawValue: currentPlanRaw) ?? .free
    }

    private var hasActiveFilters: Bool {
        selectedKind != nil || selectedStatus != nil || favoritesOnly
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
        var result = ideas.filter { idea in
            matchesSearch(idea)
                && matchesKind(idea)
                && matchesStatus(idea)
                && matchesFavorite(idea)
        }

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
            idea.projectName,
            idea.tags.joined(separator: " ")
        ]
        .joined(separator: "\n")
        .lowercased()
        return haystack.contains(lowered)
    }

    private func matchesKind(_ idea: Idea) -> Bool {
        guard let selectedKind else {
            return true
        }
        return idea.kind == selectedKind
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

        let idea = Idea(title: title, concept: cleanText)
        modelContext.insert(idea)
        quickCaptureText = ""
        saveContext()
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

private struct QuickCaptureBar: View {
    @Binding var text: String
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
    let upgradeAction: () -> Void

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

            Button(plan == .free ? "追加" : "管理", action: upgradeAction)
                .buttonStyle(.bordered)
                .controlSize(.small)
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
    let syncAction: () -> Void

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

            Button(actionTitle, action: action)
                .buttonStyle(.bordered)
                .controlSize(.small)
                .disabled(disablesAction)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        .background(
            RoundedRectangle(cornerRadius: 8, style: .continuous)
                .fill(Color(.secondarySystemBackground))
        )
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

    let currentPlan: AppPlan
    let extraLocalSlots: Int
    @ObservedObject var purchaseManager: PurchaseManager
    let selectFreePlan: () -> Void
    let applyPurchase: (BillingProduct) -> Void
    let restorePurchases: () async -> Void

    var body: some View {
        List {
            Section {
                VStack(alignment: .leading, spacing: 8) {
                    Text("現在のプラン: \(currentPlan.label)")
                        .font(.headline)
                    Text(currentPlan.shortDescription)
                        .font(.subheadline)
                        .foregroundStyle(.secondary)
                    if currentPlan == .free {
                        Text("購入済み追加枠: +\(extraLocalSlots)件")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    if let message = purchaseManager.state.message {
                        Text(message)
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(messageColor)
                    }
                }
                .padding(.vertical, 4)
            }

            Section("プラン") {
                ForEach(AppPlan.allCases) { plan in
                    PlanRow(
                        plan: plan,
                        isSelected: plan == currentPlan,
                        purchaseManager: purchaseManager,
                        selectFreePlan: selectFreePlan,
                        purchaseAction: purchase
                    )
                }
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
                                Text(pack.label)
                                    .foregroundStyle(.primary)
                                Text("サブスクなしでローカル保存枠を追加")
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
                Text("無料版の追加枠")
            } footer: {
                Text("追加枠は無料版のローカル保存に適用されます。Plus / Proでは毎月の新規作成枠が使われます。")
            }

            Section("Plus / Proで使える機能") {
                Label("Firebase保存と複数端末同期", systemImage: "cloud")
                Label("Googleログイン + Sign in with Apple想定", systemImage: "person.crop.circle")
                Label("Share Extension / ウィジェット / プロジェクト別ビュー", systemImage: "square.grid.2x2")
                Label("週次レビューと一括エクスポート", systemImage: "calendar")
            }

            Section {
                Button {
                    Task {
                        await restorePurchases()
                    }
                } label: {
                    Label("購入情報を復元", systemImage: "arrow.clockwise")
                }
                .disabled(purchaseManager.state == .loading)
            } footer: {
                Text("App Store Connectには商品ID katachi.developers.* を登録してください。商品が取得できない場合、購入ボタンは無効になります。")
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

private struct PlanRow: View {
    let plan: AppPlan
    let isSelected: Bool
    @ObservedObject var purchaseManager: PurchaseManager
    let selectFreePlan: () -> Void
    let purchaseAction: (BillingProduct) async -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(alignment: .top, spacing: 12) {
                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .foregroundStyle(isSelected ? .blue : .secondary)
                    .padding(.top, 2)

                VStack(alignment: .leading, spacing: 4) {
                    HStack {
                        Text(plan.label)
                            .font(.headline)
                            .foregroundStyle(.primary)
                        Spacer()
                        Text(plan.priceLabel)
                            .font(.subheadline)
                            .foregroundStyle(.secondary)
                    }

                    Text(plan.shortDescription)
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    if let monthly = plan.includedMonthlyCreates {
                        Text("月\(monthly)件まで新規作成")
                            .font(.caption.weight(.semibold))
                            .foregroundStyle(.blue)
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
                            Text("\(product.billingCycleLabel) \(purchaseManager.displayPrice(for: product))")
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
}

private struct ActiveFiltersRow: View {
    let selectedKind: IdeaKind?
    let selectedStatus: IdeaStatus?
    let favoritesOnly: Bool

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                if let selectedKind {
                    IdeaBadge(label: selectedKind.label, tint: selectedKind.tintColor)
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
                IdeaBadge(label: idea.kind.label, tint: idea.kind.tintColor)
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
    @State private var isPresentingEditor = false

    var body: some View {
        List {
            Section("概要") {
                LabelValueRow(label: "タイトル", value: idea.displayTitle)
                LabelValueRow(label: "種類", value: idea.kind.label)
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

            if !idea.projectName.isEmpty {
                Section("関連プロジェクト") {
                    Text(idea.projectName)
                }
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
                IdeaEditorView(idea: idea)
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

    @Binding var selectedKind: IdeaKind?
    @Binding var selectedStatus: IdeaStatus?
    @Binding var favoritesOnly: Bool

    private var kindSelection: Binding<String> {
        Binding(
            get: { selectedKind?.rawValue ?? "all" },
            set: { selectedKind = IdeaKind(rawValue: $0) }
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
            Section("種類") {
                Picker("種類", selection: kindSelection) {
                    Text("すべて").tag("all")
                    ForEach(IdeaKind.allCases) { kind in
                        Text(kind.label).tag(kind.rawValue)
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
                    selectedKind = nil
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

private struct IdeaEditorView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var modelContext

    private let editingIdea: Idea?

    @State private var title: String
    @State private var kind: IdeaKind
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

    init(idea: Idea? = nil) {
        self.editingIdea = idea
        _title = State(initialValue: idea?.title ?? "")
        _kind = State(initialValue: idea?.kind ?? .feature)
        _status = State(initialValue: idea?.status ?? .inbox)
        _concept = State(initialValue: idea?.concept ?? "")
        _rationale = State(initialValue: idea?.rationale ?? "")
        _approach = State(initialValue: idea?.approach ?? "")
        _nextAction = State(initialValue: idea?.nextAction ?? "")
        _projectName = State(initialValue: idea?.projectName ?? "")
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

                Picker("種類", selection: $kind) {
                    ForEach(IdeaKind.allCases) { kind in
                        Text(kind.label).tag(kind)
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

                    TextField("関連プロジェクト名", text: $projectName)
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

    private var saveErrorIsPresented: Binding<Bool> {
        Binding(
            get: { saveErrorMessage != nil },
            set: { if !$0 { saveErrorMessage = nil } }
        )
    }

    private func applyTemplate(_ template: IdeaTemplate) {
        kind = template.kind
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
        let cleanProjectName = projectName.trimmed
        let cleanTags = Idea.normalizeTags(from: tagsText)
        let cleanPriority = Idea.normalizePriority(priority)

        if let editingIdea {
            editingIdea.title = resolvedTitle
            editingIdea.kind = kind
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
                kind: kind,
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

private extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

#Preview {
    ContentView()
        .modelContainer(for: Idea.self, inMemory: true)
}
