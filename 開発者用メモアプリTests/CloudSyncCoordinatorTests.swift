import Foundation
import SwiftData
import Testing
@testable import Katachi

@MainActor
struct CloudSyncCoordinatorTests {
    private let key = "cloudSync.lastSuccessfulSyncAt"

    @Test func incrementalSyncKeepsExistingWatermarkAndCutoffBoundaries() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(100.0, forKey: key)
        let container = try makeContainer()
        let context = ModelContext(container)
        let ideas = [100.0, 150.0, 200.0, 250.0].map {
            Idea(title: "カード", updatedAt: date($0))
        }
        ideas.forEach(context.insert)
        try context.save()
        let cloud = TestCloudSyncClient()
        let coordinator = CloudSyncCoordinator(defaults: defaults, now: { date(200) })
        #expect(coordinator.lastSuccessfulSyncDate == date(100))

        await coordinator.sync(localIdeas: { ideas }, plan: .plus, in: context, cloud: cloud)

        #expect(cloud.uploadedIDs == [[ideas[1].id, ideas[2].id]])
        #expect(coordinator.lastSuccessfulSyncDate == date(200))
        #expect(defaults.double(forKey: key) == 200)
        #expect(cloud.pageSizes == [100])

        let next = CloudSyncCoordinator(defaults: defaults, now: { date(300) })
        await next.sync(localIdeas: { ideas }, plan: .plus, in: context, cloud: cloud)
        #expect(cloud.uploadedIDs.last == [ideas[3].id])
    }

    @Test func firstSyncIncludesCardsThroughStartCutoff() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let container = try makeContainer()
        let context = ModelContext(container)
        let early = Idea(title: "既存", updatedAt: date(50))
        let future = Idea(title: "同期開始後", updatedAt: date(250))
        context.insert(early)
        context.insert(future)
        try context.save()
        let cloud = TestCloudSyncClient()
        let coordinator = CloudSyncCoordinator(defaults: defaults, now: { date(200) })
        #expect(coordinator.lastSuccessfulSyncDate == nil)

        await coordinator.sync(localIdeas: { [early, future] }, plan: .plus, in: context, cloud: cloud)

        #expect(cloud.uploadedIDs == [[early.id]])
        #expect(coordinator.lastSuccessfulSyncDate == date(200))
    }

    @Test func mergePersistsNewerRecordsBeforeUploadAndSkipsOtherConflicts() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let container = try makeContainer()
        let context = ModelContext(container)
        let newer = Idea(title: "旧版", updatedAt: date(50))
        let same = Idea(title: "同日時のローカル", updatedAt: date(80))
        let older = Idea(title: "新しいローカル", updatedAt: date(90))
        [newer, same, older].forEach(context.insert)
        try context.save()
        let dueAt = date(180)
        let remote = Idea(
            id: newer.id, title: "クラウド新版", kind: .tech, status: .ready,
            concept: "本文", rationale: "理由", approach: "方法", nextAction: "次の行動",
            projectName: "仕事", tags: ["Swift"], priority: 5, isFavorite: true,
            dueAt: dueAt, createdAt: date(10), updatedAt: date(100)
        )
        let added = Idea(title: "新規復元", createdAt: date(20), updatedAt: date(110))
        let cloud = TestCloudSyncClient()
        cloud.records = [
            try record(remote, overrides: ["kind": "custom.kind", "tags": [" Swift ", "swift"], "priority": 9]),
            IdeaCloudRecord(idea: Idea(id: same.id, title: "同日時のクラウド", updatedAt: date(80))),
            IdeaCloudRecord(idea: Idea(id: older.id, title: "古いクラウド", updatedAt: date(70))),
            try record(added, overrides: ["kind": "custom.added"]),
            try record(added, overrides: ["id": "invalid-id"])
        ]
        var changesNotified = false
        cloud.beforeUpload = {
            #expect(changesNotified)
            let persisted = try? ModelContext(container).fetch(FetchDescriptor<Idea>())
            #expect(persisted?.count == 4)
            #expect(persisted?.first(where: { $0.id == newer.id })?.title == "クラウド新版")
        }
        let coordinator = CloudSyncCoordinator(defaults: defaults, now: { date(200) })

        let summary = await coordinator.sync(
            localIdeas: { [newer, same, older] }, plan: .plus, in: context, cloud: cloud,
            onLocalChanges: { changesNotified = true }
        )

        #expect(summary == CloudMergeSummary(inserted: 1, updated: 1, skipped: 3))
        #expect(newer.kindRaw == "custom.kind")
        #expect(newer.status == .ready)
        #expect(newer.concept == "本文")
        #expect(newer.rationale == "理由")
        #expect(newer.approach == "方法")
        #expect(newer.nextAction == "次の行動")
        #expect(newer.projectName == "仕事")
        #expect(newer.tags == ["Swift"])
        #expect(newer.priority == 5)
        #expect(newer.isFavorite)
        #expect(newer.dueAt == dueAt)
        #expect(newer.createdAt == date(10))
        #expect(newer.updatedAt == date(100))
        #expect(same.title == "同日時のローカル")
        #expect(older.title == "新しいローカル")
        let saved = try ModelContext(container).fetch(FetchDescriptor<Idea>())
        #expect(saved.first(where: { $0.id == added.id })?.kindRaw == "custom.added")
    }

    @Test func mergeUsesCurrentLocalCardsAfterDownload() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let container = try makeContainer()
        let context = ModelContext(container)
        let local = Idea(title: "ダウンロード中に作成したカード", updatedAt: date(180))
        let cloud = TestCloudSyncClient()
        cloud.records = [IdeaCloudRecord(idea: Idea(id: local.id, title: "古いクラウド", updatedAt: date(100)))]
        var currentIdeas: [Idea] = []
        cloud.duringFetch = {
            context.insert(local)
            currentIdeas = [local]
        }
        let coordinator = CloudSyncCoordinator(defaults: defaults, now: { date(200) })

        let summary = await coordinator.sync(localIdeas: { currentIdeas }, plan: .plus, in: context, cloud: cloud)

        #expect(summary == CloudMergeSummary(inserted: 0, updated: 0, skipped: 1))
        #expect(local.title == "ダウンロード中に作成したカード")
        #expect(try context.fetchCount(FetchDescriptor<Idea>()) == 1)
    }

    @Test func downloadFailureLeavesLocalCardsAndWatermarkUntouched() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(100.0, forKey: key)
        let container = try makeContainer()
        let context = ModelContext(container)
        let idea = Idea(title: "元の内容", updatedAt: date(150))
        context.insert(idea)
        try context.save()
        let cloud = TestCloudSyncClient()
        cloud.records = nil
        let coordinator = CloudSyncCoordinator(defaults: defaults, now: { date(200) })

        let result = await coordinator.sync(localIdeas: { [idea] }, plan: .plus, in: context, cloud: cloud)

        #expect(result == nil)
        #expect(idea.title == "元の内容")
        #expect(cloud.uploadedIDs.isEmpty)
        #expect(coordinator.lastSuccessfulSyncDate == date(100))
    }

    @Test func uploadFailurePreservesMergedCardsAndAllowsRetry() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(100.0, forKey: key)
        let container = try makeContainer()
        let context = ModelContext(container)
        let local = Idea(title: "送信するカード", updatedAt: date(150))
        context.insert(local)
        try context.save()
        let restored = Idea(title: "復元したカード", updatedAt: date(160))
        let cloud = TestCloudSyncClient()
        cloud.records = [IdeaCloudRecord(idea: restored)]
        cloud.uploadSucceeds = false
        let coordinator = CloudSyncCoordinator(defaults: defaults, now: { date(200) })

        let summary = await coordinator.sync(localIdeas: { [local] }, plan: .plus, in: context, cloud: cloud)
        #expect(summary?.inserted == 1)
        #expect(coordinator.lastSuccessfulSyncDate == date(100))
        let saved = try context.fetch(FetchDescriptor<Idea>())
        #expect(saved.count == 2)

        cloud.uploadSucceeds = true
        await coordinator.sync(localIdeas: { saved }, plan: .plus, in: context, cloud: cloud)
        #expect(coordinator.lastSuccessfulSyncDate == date(200))
        #expect(cloud.uploadedIDs.count == 2)
        #expect(try context.fetchCount(FetchDescriptor<Idea>()) == 2)
    }

    @Test func localSaveFailureStopsUploadAndWatermarkOnRetryToo() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        defaults.set(100.0, forKey: key)
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let url = directory.appendingPathComponent("Ideas.store")
        let writable = try ModelContainer(for: Idea.self, configurations: ModelConfiguration(url: url, cloudKitDatabase: .none))
        let writer = ModelContext(writable)
        let original = Idea(title: "元の内容", updatedAt: date(150))
        writer.insert(original)
        try writer.save()
        let readOnly = try ModelContainer(for: Idea.self, configurations: ModelConfiguration(url: url, allowsSave: false, cloudKitDatabase: .none))
        let context = ModelContext(readOnly)
        context.autosaveEnabled = false
        let ideas = try context.fetch(FetchDescriptor<Idea>())
        let cloud = TestCloudSyncClient()
        cloud.records = [IdeaCloudRecord(idea: Idea(id: original.id, title: "更新内容", updatedAt: date(170)))]
        let coordinator = CloudSyncCoordinator(defaults: defaults, now: { date(200) })
        var changesNotified = false

        for _ in 0..<2 {
            let result = await coordinator.sync(
                localIdeas: { ideas }, plan: .plus, in: context, cloud: cloud,
                onLocalChanges: { changesNotified = true }
            )
            #expect(result == nil)
            #expect(coordinator.lastSuccessfulSyncDate == date(100))
        }
        #expect(!changesNotified)
        #expect(cloud.uploadedIDs.isEmpty)
        #expect(cloud.localSaveFailures == 2)
        let persisted = try ModelContext(writable).fetch(FetchDescriptor<Idea>())
        #expect(persisted.first?.title == "元の内容")
    }

    @Test func localOnlyPlanDoesNotAccessCloudOrAdvanceWatermark() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let container = try makeContainer()
        let cloud = TestCloudSyncClient()
        let coordinator = CloudSyncCoordinator(defaults: defaults, now: { date(200) })

        let result = await coordinator.sync(localIdeas: { [] }, plan: .free, in: ModelContext(container), cloud: cloud)

        #expect(result == nil)
        #expect(cloud.pageSizes.isEmpty)
        #expect(cloud.uploadedIDs.isEmpty)
        #expect(coordinator.lastSuccessfulSyncDate == nil)
    }

    @Test func overlappingRequestIsIgnoredUntilCurrentRunCompletes() async throws {
        let (defaults, suiteName) = makeDefaults()
        defer { defaults.removePersistentDomain(forName: suiteName) }
        let container = try makeContainer()
        let context = ModelContext(container)
        let cloud = TestCloudSyncClient()
        let coordinator = CloudSyncCoordinator(defaults: defaults, now: { date(200) })
        cloud.duringFetch = {
            let nested = await coordinator.sync(localIdeas: { [] }, plan: .plus, in: context, cloud: cloud)
            #expect(nested == nil)
        }

        await coordinator.sync(localIdeas: { [] }, plan: .plus, in: context, cloud: cloud)
        #expect(cloud.pageSizes.count == 1)
        #expect(cloud.uploadedIDs.count == 1)

        cloud.duringFetch = nil
        await coordinator.sync(localIdeas: { [] }, plan: .plus, in: context, cloud: cloud)
        #expect(cloud.pageSizes.count == 2)
    }

    private func makeContainer() throws -> ModelContainer {
        try ModelContainer(for: Idea.self, configurations: ModelConfiguration(isStoredInMemoryOnly: true, cloudKitDatabase: .none))
    }

    private func makeDefaults() -> (UserDefaults, String) {
        // A unique suite isolates the production sync watermark and is removed after the test.
        let suiteName = "KatachiSyncTests.\(UUID().uuidString)"
        return (UserDefaults(suiteName: suiteName)!, suiteName)
    }

    private func record(_ idea: Idea, overrides: [String: Any]) throws -> IdeaCloudRecord {
        let data = try JSONEncoder().encode(IdeaCloudRecord(idea: idea))
        var fields = try #require(JSONSerialization.jsonObject(with: data) as? [String: Any])
        fields.merge(overrides) { _, value in value }
        return try JSONDecoder().decode(IdeaCloudRecord.self, from: JSONSerialization.data(withJSONObject: fields))
    }
}

private func date(_ timestamp: Double) -> Date {
    Date(timeIntervalSince1970: timestamp)
}

@MainActor
private final class TestCloudSyncClient: CloudSyncClient {
    var records: [IdeaCloudRecord]? = []
    var uploadSucceeds = true
    var pageSizes: [Int] = []
    var uploadedIDs: [[UUID]] = []
    var localSaveFailures = 0
    var beforeUpload: (() -> Void)?
    var duringFetch: (() async -> Void)?

    func fetchCloudIdeas(plan: AppPlan, pageSize: Int) async -> [IdeaCloudRecord]? {
        pageSizes.append(pageSize)
        await duringFetch?()
        return records
    }

    func sync(ideas: [Idea], plan: AppPlan) async -> Date? {
        beforeUpload?()
        uploadedIDs.append(ideas.map(\.id))
        return uploadSucceeds ? date(999) : nil
    }

    func reportLocalSaveFailure(_ error: Error) {
        localSaveFailures += 1
    }
}
