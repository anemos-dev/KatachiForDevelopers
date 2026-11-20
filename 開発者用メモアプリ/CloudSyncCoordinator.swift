import Foundation
import SwiftData

/// The coordinator only needs card transfer and a way to report local persistence failure.
@MainActor
protocol CloudSyncClient: AnyObject {
    func fetchCloudIdeas(plan: AppPlan, pageSize: Int) async -> [IdeaCloudRecord]?
    func sync(ideas: [Idea], plan: AppPlan) async -> Date?
    func reportLocalSaveFailure(_ error: Error)
}

extension CloudSyncManager: CloudSyncClient {}

/// Coordinates download, merge, local persistence, upload and the incremental-sync watermark.
@MainActor
final class CloudSyncCoordinator {
    private static let lastSuccessfulSyncKey = "cloudSync.lastSuccessfulSyncAt"
    private let defaults: UserDefaults
    private let now: () -> Date
    private var isSyncing = false

    var lastSuccessfulSyncDate: Date? {
        let timestamp = defaults.double(forKey: Self.lastSuccessfulSyncKey)
        return timestamp > 0 ? Date(timeIntervalSince1970: timestamp) : nil
    }

    init(defaults: UserDefaults = .standard, now: @escaping () -> Date = Date.init) {
        self.defaults = defaults
        self.now = now
    }

    @discardableResult
    func sync(
        localIdeas: () -> [Idea],
        plan: AppPlan,
        in context: ModelContext,
        cloud: any CloudSyncClient,
        onLocalChanges: () -> Void = {}
    ) async -> CloudMergeSummary? {
        guard plan.usesCloudStorage, !isSyncing else {
            return nil
        }
        isSyncing = true
        defer { isSyncing = false }

        let syncCutoff = now()
        let changedIdeas = ideasForCloudSync(localIdeas(), upTo: syncCutoff)
        guard let cloudRecords = await cloud.fetchCloudIdeas(plan: plan, pageSize: 100) else {
            return nil
        }

        let mergeSummary = mergeCloudRecords(cloudRecords, ideas: localIdeas(), context: context)
        do {
            // Pending changes include a merge whose previous save failed. Save it before advancing.
            if mergeSummary.hasChanges || context.hasChanges {
                try context.save()
            }
        } catch {
            cloud.reportLocalSaveFailure(error)
            return nil
        }
        if mergeSummary.hasChanges {
            onLocalChanges()
        }

        if await cloud.sync(ideas: changedIdeas, plan: plan) != nil {
            // Use the start cutoff so edits made during the request remain eligible next time.
            defaults.set(syncCutoff.timeIntervalSince1970, forKey: Self.lastSuccessfulSyncKey)
        }
        return mergeSummary
    }

    private func ideasForCloudSync(_ ideas: [Idea], upTo cutoff: Date) -> [Idea] {
        guard let lastSuccessfulSyncDate else {
            return ideas.filter { $0.updatedAt <= cutoff }
        }
        return ideas.filter {
            $0.updatedAt > lastSuccessfulSyncDate && $0.updatedAt <= cutoff
        }
    }

    private func mergeCloudRecords(_ records: [IdeaCloudRecord], ideas: [Idea], context: ModelContext) -> CloudMergeSummary {
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
                context.insert(idea)
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
}

struct CloudMergeSummary: Equatable {
    var inserted = 0
    var updated = 0
    var skipped = 0

    var hasChanges: Bool {
        inserted > 0 || updated > 0
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
