import Foundation
import SwiftData
import Testing
@testable import Katachi

@MainActor
struct IdeaSaveServiceTests {
    @Test func quickCapturePersistsDefaultsAndCustomKind() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let idea = try IdeaSaveService.save(
            IdeaSaveValues(kindRaw: "custom.kind", concept: "最初の行\n続きのメモ", projectName: " Inbox "),
            in: context
        )

        let saved = try #require(ModelContext(container).fetch(FetchDescriptor<Idea>()).first)
        #expect(saved.id == idea.id)
        #expect(saved.title == "最初の行")
        #expect(saved.concept == "最初の行\n続きのメモ")
        #expect(saved.kindRaw == "custom.kind")
        #expect(saved.projectName.isEmpty)
        #expect(saved.status == .inbox)
        #expect(saved.priority == 3)
        #expect(!saved.isFavorite)
        #expect(saved.tags.isEmpty)
        #expect(saved.dueAt == nil)
    }

    @Test func detailedCreationPersistsAllFields() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let dueAt = Date(timeIntervalSince1970: 1_800_000_000)
        try IdeaSaveService.save(
            IdeaSaveValues(
                title: "  明示したタイトル  ",
                kindRaw: IdeaKind.bug.rawValue,
                status: .ready,
                concept: "  本文  ",
                rationale: " 理由 ",
                approach: " 方法 ",
                nextAction: " 次の行動 ",
                projectName: " 仕事 ",
                tags: [" Swift ", "swift", "iOS", ""],
                priority: 99,
                isFavorite: true,
                dueAt: dueAt
            ),
            in: context
        )

        let saved = try #require(ModelContext(container).fetch(FetchDescriptor<Idea>()).first)
        #expect(saved.title == "明示したタイトル")
        #expect(saved.kind == .bug)
        #expect(saved.status == .ready)
        #expect(saved.concept == "本文")
        #expect(saved.rationale == "理由")
        #expect(saved.approach == "方法")
        #expect(saved.nextAction == "次の行動")
        #expect(saved.projectName == "仕事")
        #expect(saved.tags == ["Swift", "iOS"])
        #expect(saved.priority == 5)
        #expect(saved.isFavorite)
        #expect(saved.dueAt == dueAt)
    }

    @Test func editingUpdatesOneCardAndPreservesIdentityAndCreationDate() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let createdAt = Date(timeIntervalSince1970: 100)
        let oldUpdatedAt = Date(timeIntervalSince1970: 200)
        let idea = Idea(title: "編集前", dueAt: .now, createdAt: createdAt, updatedAt: oldUpdatedAt)
        context.insert(idea)
        try context.save()
        let originalID = idea.id

        let result = try IdeaSaveService.save(
            IdeaSaveValues(kindRaw: "custom.edited", status: .done, concept: "編集後", priority: -1),
            updating: idea,
            in: context
        )

        #expect(result === idea)
        let records = try ModelContext(container).fetch(FetchDescriptor<Idea>())
        let saved = try #require(records.first)
        #expect(records.count == 1)
        #expect(saved.id == originalID)
        #expect(saved.createdAt == createdAt)
        #expect(saved.updatedAt > oldUpdatedAt)
        #expect(saved.title == "編集後")
        #expect(saved.kindRaw == "custom.edited")
        #expect(saved.status == .done)
        #expect(saved.priority == 1)
        #expect(saved.dueAt == nil)
    }

    @Test func emptyValuesRetainTitleAndKindFallbacks() throws {
        let container = try makeContainer()
        let context = ModelContext(container)
        let idea = try IdeaSaveService.save(
            IdeaSaveValues(title: "  ", kindRaw: "  ", concept: ""),
            in: context
        )
        #expect(idea.title == "Untitled Idea")
        #expect(idea.kindRaw == IdeaKind.feature.rawValue)
    }

    @Test func failedInsertionThrowsWithoutLeavingAPendingDuplicate() throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Ideas.store")
        let writable = ModelConfiguration(url: url, cloudKitDatabase: .none)
        let container = try ModelContainer(for: Idea.self, configurations: writable)
        let context = ModelContext(container)
        context.insert(Idea(title: "既存カード"))
        try context.save()

        let readOnly = ModelConfiguration(url: url, allowsSave: false, cloudKitDatabase: .none)
        let readOnlyContainer = try ModelContainer(for: Idea.self, configurations: readOnly)
        let readOnlyContext = ModelContext(readOnlyContainer)
        readOnlyContext.autosaveEnabled = false

        #expect(throws: (any Error).self) {
            try IdeaSaveService.save(IdeaSaveValues(concept: "保存に失敗するカード"), in: readOnlyContext)
        }
        #expect(readOnlyContext.insertedModelsArray.isEmpty)

        let unrelated = Idea(title: "別の未保存カード")
        readOnlyContext.insert(unrelated)
        #expect(throws: (any Error).self) {
            try IdeaSaveService.save(IdeaSaveValues(concept: "再試行するカード"), in: readOnlyContext)
        }
        #expect(readOnlyContext.insertedModelsArray.count == 1)
        #expect(readOnlyContext.insertedModelsArray.first === unrelated)

        let saved = try ModelContext(container).fetch(FetchDescriptor<Idea>())
        #expect(saved.count == 1)
        #expect(saved.first?.title == "既存カード")
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(
            for: Idea.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none)
        )
    }
}
