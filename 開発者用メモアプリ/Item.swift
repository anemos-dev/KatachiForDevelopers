import Foundation
import SwiftData

enum IdeaKind: String, CaseIterable, Codable, Identifiable {
    case feature
    case uiux
    case tech
    case bug
    case article
    case note

    var id: String { rawValue }

    var label: String {
        switch self {
        case .feature: return "機能案"
        case .uiux: return "UI改善"
        case .tech: return "技術調査"
        case .bug: return "バグ仮説"
        case .article: return "記事ネタ"
        case .note: return "雑メモ"
        }
    }
}

struct IdeaKindOption: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var label: String
    var isBuiltIn: Bool
}

enum IdeaKindCatalog {
    static let storageKey = "settings.ideaKindOptions"

    static let defaultOptions: [IdeaKindOption] = IdeaKind.allCases.map {
        IdeaKindOption(id: $0.rawValue, label: $0.label, isBuiltIn: true)
    }

    static func options(from data: String) -> [IdeaKindOption] {
        guard let decoded = try? JSONDecoder().decode([IdeaKindOption].self, from: Data(data.utf8)),
              !decoded.isEmpty else {
            return defaultOptions
        }
        return decoded
    }

    static func encode(_ options: [IdeaKindOption]) -> String {
        guard let data = try? JSONEncoder().encode(options),
              let encoded = String(data: data, encoding: .utf8) else {
            return ""
        }
        return encoded
    }

    static func makeCustomOption(label: String) -> IdeaKindOption {
        IdeaKindOption(id: "custom.\(UUID().uuidString)", label: label.trimmed, isBuiltIn: false)
    }

    static func label(for rawValue: String, options: [IdeaKindOption]) -> String {
        if let option = options.first(where: { $0.id == rawValue }) {
            return option.label
        }
        if let builtIn = IdeaKind(rawValue: rawValue) {
            return builtIn.label
        }
        return rawValue.isEmpty ? IdeaKind.feature.label : rawValue
    }
}

struct IdeaGroupOption: Codable, Identifiable, Equatable, Hashable {
    let id: String
    var name: String
    var iconName: String
    var colorName: String

    init(id: String, name: String, iconName: String = "folder", colorName: String = "blue") {
        self.id = id
        self.name = name
        self.iconName = iconName
        self.colorName = colorName
    }

    private enum CodingKeys: String, CodingKey {
        case id
        case name
        case iconName
        case colorName
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(String.self, forKey: .id)
        name = try container.decode(String.self, forKey: .name)
        iconName = try container.decodeIfPresent(String.self, forKey: .iconName) ?? "folder"
        colorName = try container.decodeIfPresent(String.self, forKey: .colorName) ?? "blue"
    }
}

enum IdeaGroupCatalog {
    static let storageKey = "settings.ideaGroupOptions"
    static let defaultName = "Inbox"
    static let defaultOptions = [
        IdeaGroupOption(id: "group.inbox", name: defaultName, iconName: "tray", colorName: "blue"),
        IdeaGroupOption(id: "group.personal", name: "個人開発", iconName: "hammer", colorName: "green"),
        IdeaGroupOption(id: "group.work", name: "仕事", iconName: "briefcase", colorName: "orange"),
        IdeaGroupOption(id: "group.article", name: "記事", iconName: "doc.text", colorName: "pink")
    ]

    static func options(from data: String) -> [IdeaGroupOption] {
        guard let decoded = try? JSONDecoder().decode([IdeaGroupOption].self, from: Data(data.utf8)),
              !decoded.isEmpty else {
            return defaultOptions
        }
        return decoded
    }

    static func encode(_ options: [IdeaGroupOption]) -> String {
        guard let data = try? JSONEncoder().encode(options),
              let encoded = String(data: data, encoding: .utf8) else {
            return ""
        }
        return encoded
    }

    static func makeCustomOption(name: String) -> IdeaGroupOption {
        IdeaGroupOption(id: "group.\(UUID().uuidString)", name: name.trimmed)
    }

    static func displayName(for storedName: String) -> String {
        let trimmed = storedName.trimmed
        return trimmed.isEmpty ? defaultName : trimmed
    }

    static func storedName(from displayName: String) -> String {
        let trimmed = displayName.trimmed
        return trimmed == defaultName ? "" : trimmed
    }
}

enum IdeaStatus: String, CaseIterable, Codable, Identifiable {
    case inbox
    case refining
    case ready
    case done
    case hold

    var id: String { rawValue }

    var label: String {
        switch self {
        case .inbox: return "Inbox"
        case .refining: return "育成中"
        case .ready: return "実行候補"
        case .done: return "完了"
        case .hold: return "保留"
        }
    }
}

enum IdeaSortOption: String, CaseIterable, Identifiable {
    case updatedDescending
    case createdDescending
    case priorityDescending

    var id: String { rawValue }

    var label: String {
        switch self {
        case .updatedDescending: return "更新日(新しい順)"
        case .createdDescending: return "作成日(新しい順)"
        case .priorityDescending: return "優先度(高い順)"
        }
    }
}

enum AppPlan: String, CaseIterable, Equatable, Identifiable {
    case free
    case plus
    case pro

    var id: String { rawValue }

    var label: String {
        switch self {
        case .free: return "Free"
        case .plus: return "Plus"
        case .pro: return "Pro"
        }
    }

    var priceLabel: String {
        switch self {
        case .free: return "無料"
        case .plus: return "月額460円 / 年額4,600円"
        case .pro: return "月額1,200円 / 年額12,000円"
        }
    }

    var includedMonthlyCreates: Int? {
        switch self {
        case .free: return nil
        case .plus: return 300
        case .pro: return 1_500
        }
    }

    var usesCloudStorage: Bool {
        self != .free
    }

    var shortDescription: String {
        switch self {
        case .free:
            return "まず試す方向け。端末内に50件まで保存できます。"
        case .plus:
            return "個人開発を続ける方向け。クラウド保存と月300件の新規作成枠。"
        case .pro:
            return "毎日たくさん残す方向け。クラウド保存と月1,500件の新規作成枠。"
        }
    }

    var audienceLabel: String {
        switch self {
        case .free:
            return "まず試したい人"
        case .plus:
            return "個人開発を続ける人"
        case .pro:
            return "仕事・複数案件で使う人"
        }
    }

    var upgradeHeadline: String {
        switch self {
        case .free:
            return "50件までローカル保存"
        case .plus:
            return "クラウド保存で、毎月300件まで"
        case .pro:
            return "大容量で、毎月1,500件まで"
        }
    }

    var sellingPoints: [String] {
        switch self {
        case .free:
            return [
                "テンプレートと基本機能",
                "端末内だけに保存",
                "保存枠は買い切りで追加可能"
            ]
        case .plus:
            return [
                "Firebase保存と複数端末同期",
                "Google / Appleログイン",
                "月300件まで新規作成"
            ]
        case .pro:
            return [
                "Plusの全機能",
                "月1,500件まで新規作成",
                "大量メモ・仕事利用向け"
            ]
        }
    }

    var recommendationBadge: String? {
        switch self {
        case .free:
            return nil
        case .plus:
            return "おすすめ"
        case .pro:
            return "大容量"
        }
    }
}

enum ExtraSlotPack: CaseIterable, Identifiable {
    case small
    case medium
    case large

    var id: String { "\(slots)" }

    var priceLabel: String {
        switch self {
        case .small: return "100円"
        case .medium: return "300円"
        case .large: return "500円"
        }
    }

    var slots: Int {
        switch self {
        case .small: return 25
        case .medium: return 100
        case .large: return 200
        }
    }

    var label: String {
        "+\(slots)件"
    }
}

struct IdeaCreationAllowance {
    let allowed: Bool
    let used: Int
    let limit: Int
    let storageLabel: String

    var remaining: Int {
        max(limit - used, 0)
    }

    var summary: String {
        "\(storageLabel): \(used)/\(limit)件"
    }

    var saveScreenSummary: String {
        if allowed {
            return "\(storageLabel)は\(limit)件中\(used)件使用中。あと\(remaining)件保存できます。"
        }
        return "\(storageLabel)の上限\(limit)件に達しました。保存枠を追加するか、Plus / Proに切り替えてください。"
    }
}

enum IdeaCreationPolicy {
    static let freeBaseLimit = 50

    static func allowance(
        plan: AppPlan,
        ideaCreatedDates: [Date],
        extraSlots: Int,
        now: Date = Date(),
        calendar: Calendar = .current
    ) -> IdeaCreationAllowance {
        switch plan {
        case .free:
            let limit = freeBaseLimit + max(extraSlots, 0)
            let used = ideaCreatedDates.count
            return IdeaCreationAllowance(
                allowed: used < limit,
                used: used,
                limit: limit,
                storageLabel: "ローカル保存"
            )
        case .plus, .pro:
            let limit = plan.includedMonthlyCreates ?? 0
            let used = ideaCreatedDates.filter {
                calendar.isDate($0, equalTo: now, toGranularity: .month)
            }.count
            return IdeaCreationAllowance(
                allowed: used < limit,
                used: used,
                limit: limit,
                storageLabel: "今月のクラウド保存"
            )
        }
    }
}

enum IdeaTemplate: String, CaseIterable, Identifiable {
    case feature
    case bug
    case tech
    case article

    var id: String { rawValue }

    var label: String {
        switch self {
        case .feature: return "機能案"
        case .bug: return "バグ仮説"
        case .tech: return "技術検証"
        case .article: return "記事ネタ"
        }
    }

    var kind: IdeaKind {
        switch self {
        case .feature: return .feature
        case .bug: return .bug
        case .tech: return .tech
        case .article: return .article
        }
    }

    var status: IdeaStatus {
        .inbox
    }

    var conceptPrompt: String {
        switch self {
        case .feature: return "誰のどんな課題を解決する機能かを書く"
        case .bug: return "どんな条件で何が起きそうかを書く"
        case .tech: return "試したい技術、API、設計案を書く"
        case .article: return "読者に伝えたい主題や切り口を書く"
        }
    }

    var rationalePrompt: String {
        switch self {
        case .feature: return "ユーザー価値、差別化、作る理由を書く"
        case .bug: return "怪しい理由、影響範囲、再現しそうな根拠を書く"
        case .tech: return "採用できると何が良くなるかを書く"
        case .article: return "なぜ今書く価値があるかを書く"
        }
    }

    var approachSeed: String {
        switch self {
        case .feature: return "最小実装で試す範囲:\n成功条件:\n懸念点:"
        case .bug: return "再現手順:\n確認ログ:\n切り分け候補:"
        case .tech: return "検証手順:\n比較対象:\n判断基準:"
        case .article: return "構成案:\nコード例:\n公開先:"
        }
    }

    var nextActionSeed: String {
        switch self {
        case .feature: return "最小プロトタイプを作る"
        case .bug: return "最小再現手順を確認する"
        case .tech: return "小さな検証コードを書く"
        case .article: return "見出し案を3つ出す"
        }
    }
}

@Model
final class Idea {
    @Attribute(.unique) var id: UUID
    var title: String
    var kindRaw: String
    var statusRaw: String
    var concept: String
    var rationale: String
    var approach: String
    var nextAction: String
    var projectName: String
    var tags: [String]
    var priority: Int
    var isFavorite: Bool
    var dueAt: Date?
    var createdAt: Date
    var updatedAt: Date

    init(
        id: UUID = UUID(),
        title: String,
        kind: IdeaKind = .feature,
        status: IdeaStatus = .inbox,
        concept: String = "",
        rationale: String = "",
        approach: String = "",
        nextAction: String = "",
        projectName: String = "",
        tags: [String] = [],
        priority: Int = 3,
        isFavorite: Bool = false,
        dueAt: Date? = nil,
        createdAt: Date = Date(),
        updatedAt: Date = Date()
    ) {
        self.id = id
        self.title = title.trimmingCharacters(in: .whitespacesAndNewlines)
        self.kindRaw = kind.rawValue
        self.statusRaw = status.rawValue
        self.concept = concept.trimmingCharacters(in: .whitespacesAndNewlines)
        self.rationale = rationale.trimmingCharacters(in: .whitespacesAndNewlines)
        self.approach = approach.trimmingCharacters(in: .whitespacesAndNewlines)
        self.nextAction = nextAction.trimmingCharacters(in: .whitespacesAndNewlines)
        self.projectName = projectName.trimmingCharacters(in: .whitespacesAndNewlines)
        self.tags = Self.normalizeTags(tags)
        self.priority = Self.normalizePriority(priority)
        self.isFavorite = isFavorite
        self.dueAt = dueAt
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Idea {
    var kind: IdeaKind {
        get { IdeaKind(rawValue: kindRaw) ?? .feature }
        set { kindRaw = newValue.rawValue }
    }

    var kindValue: String {
        get { kindRaw }
        set { kindRaw = newValue.trimmed.isEmpty ? IdeaKind.feature.rawValue : newValue }
    }

    var status: IdeaStatus {
        get { IdeaStatus(rawValue: statusRaw) ?? .inbox }
        set { statusRaw = newValue.rawValue }
    }

    var displayTitle: String {
        let trimmedTitle = title.trimmingCharacters(in: .whitespacesAndNewlines)
        if !trimmedTitle.isEmpty {
            return trimmedTitle
        }
        let firstLine = concept
            .split(whereSeparator: \.isNewline)
            .first
            .map(String.init)?
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if !firstLine.isEmpty {
            return firstLine
        }
        return "Untitled Idea"
    }

    var displayGroupName: String {
        IdeaGroupCatalog.displayName(for: projectName)
    }

    static func normalizeTags(_ tags: [String]) -> [String] {
        var seen = Set<String>()
        var normalized: [String] = []
        for tag in tags {
            let cleaned = tag.trimmingCharacters(in: .whitespacesAndNewlines)
            if cleaned.isEmpty {
                continue
            }
            let key = cleaned.lowercased()
            if seen.contains(key) {
                continue
            }
            seen.insert(key)
            normalized.append(cleaned)
        }
        return normalized
    }

    static func normalizeTags(from text: String) -> [String] {
        let chunks = text
            .split(whereSeparator: { $0 == "," || $0 == "\n" || $0 == "、" })
            .map(String.init)
        return normalizeTags(chunks)
    }

    static func normalizePriority(_ value: Int) -> Int {
        min(max(value, 1), 5)
    }

    func touch() {
        updatedAt = Date()
    }

    var markdownExport: String {
        var sections: [String] = ["# \(displayTitle)"]

        sections.append(metadataMarkdown)
        appendSection("何を思いついたか", concept, to: &sections)
        appendSection("なぜ良さそうか", rationale, to: &sections)
        appendSection("どう作るか / どう試すか", approach, to: &sections)
        appendSection("次にやること", nextAction, to: &sections)
        appendSection("チェックリスト", checklistMarkdown, to: &sections)

        return sections.joined(separator: "\n\n")
    }

    var githubIssueExport: String {
        var sections: [String] = []

        appendSection("概要", concept, to: &sections)
        appendSection("背景 / 良さそうな理由", rationale, to: &sections)
        appendSection("実装・検証方針", approach, to: &sections)
        appendSection("次のアクション", nextAction, to: &sections)
        appendSection("チェックリスト", checklistMarkdown, to: &sections)

        let labels = ([kind.label, status.label] + tags.map { "tag: \($0)" }).joined(separator: ", ")
        sections.append(
            """
            ## メタ情報
            - 種類: \(kind.label)
            - ステータス: \(status.label)
            - 優先度: \(priority)
            - グループ: \(displayGroupName)
            - 期限: \(dueDateLabel)
            - ラベル候補: \(labels)
            """
        )

        return sections.joined(separator: "\n\n")
    }

    var reviewExport: String {
        """
        # \(displayTitle)

        ## 次にやること
        \(nextAction.trimmed.isEmpty ? "- [ ] 未設定" : "- [ ] \(nextAction.trimmed)")

        ## 判断メモ
        - 種類: \(kind.label)
        - ステータス: \(status.label)
        - 優先度: \(priority)
        - グループ: \(displayGroupName)
        - 期限: \(dueDateLabel)

        ## 内容
        \(concept.trimmed.isEmpty ? "未入力" : concept.trimmed)
        """
    }

    private var metadataMarkdown: String {
        var lines = [
            "- 種類: \(kind.label)",
            "- ステータス: \(status.label)",
            "- 優先度: \(priority)",
            "- グループ: \(displayGroupName)",
            "- 期限: \(dueDateLabel)"
        ]

        if !tags.isEmpty {
            lines.append("- タグ: \(tags.map { "#\($0)" }.joined(separator: " "))")
        }

        return lines.joined(separator: "\n")
    }

    var dueDateLabel: String {
        guard let dueAt else {
            return "未設定"
        }
        return dueAt.formatted(date: .abbreviated, time: .omitted)
    }

    private var checklistMarkdown: String {
        var lines: [String] = []
        if !nextAction.trimmed.isEmpty {
            lines.append("- [ ] \(nextAction.trimmed)")
        }
        if !approach.trimmed.isEmpty {
            lines.append("- [ ] 実装・検証方針を確認する")
        }
        return lines.joined(separator: "\n")
    }

    private func appendSection(_ title: String, _ value: String, to sections: inout [String]) {
        let cleaned = value.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !cleaned.isEmpty else {
            return
        }
        sections.append(
            """
            ## \(title)
            \(cleaned)
            """
        )
    }
}

extension String {
    var trimmed: String {
        trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
