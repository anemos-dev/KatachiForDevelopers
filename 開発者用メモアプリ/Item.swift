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
            return "ローカル保存50件まで。テンプレートと基本機能を無料で使えます。"
        case .plus:
            return "個人開発向け。クラウド保存と月300件の新規作成枠。"
        case .pro:
            return "ヘビー利用向け。クラウド保存と月1,500件の新規作成枠。"
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
        self.createdAt = createdAt
        self.updatedAt = updatedAt
    }
}

extension Idea {
    var kind: IdeaKind {
        get { IdeaKind(rawValue: kindRaw) ?? .feature }
        set { kindRaw = newValue.rawValue }
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

        return sections.joined(separator: "\n\n")
    }

    var githubIssueExport: String {
        var sections: [String] = []

        appendSection("概要", concept, to: &sections)
        appendSection("背景 / 良さそうな理由", rationale, to: &sections)
        appendSection("実装・検証方針", approach, to: &sections)
        appendSection("次のアクション", nextAction, to: &sections)

        let labels = ([kind.label, status.label] + tags.map { "tag: \($0)" }).joined(separator: ", ")
        sections.append(
            """
            ## メタ情報
            - 種類: \(kind.label)
            - ステータス: \(status.label)
            - 優先度: \(priority)
            - プロジェクト: \(projectName.isEmpty ? "未設定" : projectName)
            - ラベル候補: \(labels)
            """
        )

        return sections.joined(separator: "\n\n")
    }

    private var metadataMarkdown: String {
        var lines = [
            "- 種類: \(kind.label)",
            "- ステータス: \(status.label)",
            "- 優先度: \(priority)"
        ]

        if !projectName.isEmpty {
            lines.append("- 関連プロジェクト: \(projectName)")
        }

        if !tags.isEmpty {
            lines.append("- タグ: \(tags.map { "#\($0)" }.joined(separator: " "))")
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
