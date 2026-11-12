import Foundation
import SwiftData

/// Values submitted by either capture screen. UI state stays in the owning View.
struct IdeaSaveValues {
    var title = ""
    var kindRaw = IdeaKind.feature.rawValue
    var status = IdeaStatus.inbox
    var concept = ""
    var rationale = ""
    var approach = ""
    var nextAction = ""
    var projectName = ""
    var tags: [String] = []
    var priority = 3
    var isFavorite = false
    var dueAt: Date?

    fileprivate var resolvedTitle: String {
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
    }

    fileprivate func apply(to idea: Idea) {
        idea.title = resolvedTitle
        idea.kindValue = kindRaw
        idea.status = status
        idea.concept = concept.trimmed
        idea.rationale = rationale.trimmed
        idea.approach = approach.trimmed
        idea.nextAction = nextAction.trimmed
        idea.projectName = IdeaGroupCatalog.storedName(from: projectName)
        idea.tags = Idea.normalizeTags(tags)
        idea.priority = Idea.normalizePriority(priority)
        idea.isFavorite = isFavorite
        idea.dueAt = dueAt
    }
}

/// Owns the insert/update/save sequence; the caller handles allowance checks and UI feedback.
@MainActor
enum IdeaSaveService {
    @discardableResult
    static func save(
        _ values: IdeaSaveValues,
        updating existingIdea: Idea? = nil,
        in context: ModelContext
    ) throws -> Idea {
        let idea = existingIdea ?? Idea(title: "")
        values.apply(to: idea)

        if existingIdea == nil {
            context.insert(idea)
        } else {
            idea.touch()
        }

        do {
            try context.save()
            return idea
        } catch {
            // Do not leave a failed insertion behind for a retry or autosave to duplicate.
            // Avoid rolling back unrelated edits in the shared context.
            if existingIdea == nil {
                context.delete(idea)
                context.processPendingChanges()
            }
            throw error
        }
    }
}
