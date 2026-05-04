import Testing
import Foundation
@testable import Katachi

@MainActor
struct KatachiTests {

    @Test func titleFallsBackToConcept() async throws {
        let idea = Idea(title: "", concept: "カードのタイトル候補")
        #expect(idea.displayTitle == "カードのタイトル候補")
    }

    @Test func tagsAreNormalizedAndDeduplicated() async throws {
        let normalized = Idea.normalizeTags(from: "SwiftUI,swiftui,  iOS  , ,テスト")
        #expect(normalized == ["SwiftUI", "iOS", "テスト"])
    }

    @Test func markdownExportIncludesIdeaSections() async throws {
        let idea = Idea(
            title: "クイック保存",
            kind: .feature,
            status: .ready,
            concept: "起動直後に保存できる",
            rationale: "思考の中断を減らせる",
            tags: ["SwiftUI", "UX"],
            priority: 4
        )

        let markdown = idea.markdownExport

        #expect(markdown.contains("# クイック保存"))
        #expect(markdown.contains("- 種類: 機能案"))
        #expect(markdown.contains("## 何を思いついたか"))
        #expect(markdown.contains("#SwiftUI #UX"))
    }

    @Test func githubIssueExportIncludesLabelsAndNextAction() async throws {
        let idea = Idea(
            title: "Issue化",
            kind: .bug,
            status: .refining,
            concept: "再現条件を保存する",
            nextAction: "最小再現を作る",
            tags: ["Crash"]
        )

        let issue = idea.githubIssueExport

        #expect(issue.contains("## 概要"))
        #expect(issue.contains("## 次のアクション"))
        #expect(issue.contains("- ラベル候補: バグ仮説, 育成中, tag: Crash"))
    }

    @Test func freePlanAllowsBaseLimitPlusExtraSlots() async throws {
        let dates = Array(repeating: Date(), count: 75)
        let allowance = IdeaCreationPolicy.allowance(
            plan: .free,
            ideaCreatedDates: dates,
            extraSlots: 25
        )

        #expect(allowance.limit == 75)
        #expect(allowance.remaining == 0)
        #expect(!allowance.allowed)
    }

    @Test func plusPlanCountsOnlyCurrentMonthCreations() async throws {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(secondsFromGMT: 0)!
        let now = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 5, day: 4).date!
        let previousMonth = DateComponents(calendar: calendar, timeZone: calendar.timeZone, year: 2026, month: 4, day: 30).date!
        let dates = Array(repeating: now, count: 299) + [previousMonth]

        let allowance = IdeaCreationPolicy.allowance(
            plan: .plus,
            ideaCreatedDates: dates,
            extraSlots: 0,
            now: now,
            calendar: calendar
        )

        #expect(allowance.limit == 300)
        #expect(allowance.remaining == 1)
        #expect(allowance.allowed)
    }

    @Test func proPlanStopsAtMonthlyLimit() async throws {
        let dates = Array(repeating: Date(), count: 1_500)
        let allowance = IdeaCreationPolicy.allowance(
            plan: .pro,
            ideaCreatedDates: dates,
            extraSlots: 0
        )

        #expect(allowance.limit == 1_500)
        #expect(!allowance.allowed)
    }

    @Test func templatesCarryDefaultKindAndSeeds() async throws {
        #expect(IdeaTemplate.bug.kind == .bug)
        #expect(IdeaTemplate.tech.approachSeed.contains("検証手順"))
        #expect(IdeaTemplate.article.nextActionSeed.contains("見出し"))
    }

    @Test func billingProductsMapToPlansAndPacks() async throws {
        #expect(BillingProduct.subscriptionProducts(for: .plus) == [.plusMonthly, .plusYearly])
        #expect(BillingProduct.subscriptionProducts(for: .pro) == [.proMonthly, .proYearly])
        #expect(BillingProduct.extraProduct(for: .small) == .extra25)
        #expect(BillingProduct.extra100.extraSlotPack == .medium)
        #expect(BillingProduct.proYearly.plan == .pro)
        #expect(BillingProduct.plusMonthly.rawValue == "katachi.developers.plus.monthly")
    }

    @Test func cloudRecordPreservesIdeaFields() async throws {
        let id = UUID()
        let createdAt = Date(timeIntervalSince1970: 1_777_777_777)
        let updatedAt = Date(timeIntervalSince1970: 1_777_778_888)
        let idea = Idea(
            id: id,
            title: "同期カード",
            kind: .tech,
            status: .ready,
            concept: "Firestoreへ保存する",
            rationale: "複数端末で使うため",
            approach: "Codableにする",
            nextAction: "SDKを追加する",
            projectName: "収益化",
            tags: ["Firebase", "StoreKit"],
            priority: 5,
            isFavorite: true,
            createdAt: createdAt,
            updatedAt: updatedAt
        )

        let record = IdeaCloudRecord(idea: idea)

        #expect(record.id == id.uuidString)
        #expect(record.kind == "tech")
        #expect(record.status == "ready")
        #expect(record.tags == ["Firebase", "StoreKit"])
        #expect(record.firestoreData["priority"] as? Int == 5)
    }

}
