import Foundation
import Combine

#if canImport(FirebaseCore)
import FirebaseCore
#endif

#if canImport(FirebaseAuth)
import FirebaseAuth
#endif

#if canImport(FirebaseFirestore)
import FirebaseFirestore
#endif

#if canImport(FirebaseAuth) && canImport(GoogleSignIn) && canImport(UIKit)
import GoogleSignIn
import UIKit
#endif

enum FirebaseBootstrap {
    static func configureIfPossible() {
#if canImport(FirebaseCore)
        guard FirebaseApp.app() == nil else {
            return
        }
        guard Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil else {
            return
        }
        FirebaseApp.configure()
#endif
    }
}

struct IdeaCloudRecord: Codable, Equatable, Identifiable {
    let id: String
    let title: String
    let kind: String
    let status: String
    let concept: String
    let rationale: String
    let approach: String
    let nextAction: String
    let projectName: String
    let tags: [String]
    let priority: Int
    let isFavorite: Bool
    let createdAt: Date
    let updatedAt: Date

    init(idea: Idea) {
        id = idea.id.uuidString
        title = idea.title
        kind = idea.kind.rawValue
        status = idea.status.rawValue
        concept = idea.concept
        rationale = idea.rationale
        approach = idea.approach
        nextAction = idea.nextAction
        projectName = idea.projectName
        tags = idea.tags
        priority = idea.priority
        isFavorite = idea.isFavorite
        createdAt = idea.createdAt
        updatedAt = idea.updatedAt
    }
}

enum CloudSyncState: Equatable {
    case localOnly
    case needsConfiguration(String)
    case signedOut
    case ready(String)
    case syncing
    case synced(Date)
    case failed(String)

    var label: String {
        switch self {
        case .localOnly:
            return "ローカル保存"
        case .needsConfiguration:
            return "Firebase未設定"
        case .signedOut:
            return "未ログイン"
        case .ready(let name):
            return "\(name)で同期可能"
        case .syncing:
            return "同期中"
        case .synced:
            return "同期済み"
        case .failed:
            return "同期失敗"
        }
    }

    var detail: String {
        switch self {
        case .localOnly:
            return "Freeでは端末内に保存されます。"
        case .needsConfiguration(let message):
            return message
        case .signedOut:
            return "Googleログインを接続するとクラウド保存に切り替えられます。"
        case .ready:
            return "Plus / Proのクラウド保存が使えます。"
        case .syncing:
            return "アイデアをFirebaseへ保存しています。"
        case .synced(let date):
            return "最終同期: \(date.formatted(date: .abbreviated, time: .shortened))"
        case .failed(let message):
            return message
        }
    }
}

@MainActor
final class CloudSyncManager: ObservableObject {
    @Published private(set) var state: CloudSyncState = .localOnly

    func refresh(for plan: AppPlan) {
        guard plan.usesCloudStorage else {
            state = .localOnly
            return
        }

#if canImport(FirebaseCore) && canImport(FirebaseAuth)
        if FirebaseApp.app() == nil {
            state = .needsConfiguration("GoogleService-Info.plistを追加してFirebaseApp.configure()を呼び出してください。")
            return
        }

        if let user = Auth.auth().currentUser {
            state = .ready(user.email ?? user.displayName ?? "Googleアカウント")
        } else {
            state = .signedOut
        }
#else
        state = .needsConfiguration("Firebase SDK / FirebaseAuth / GoogleSignInをSwift Package Managerで追加すると同期できます。")
#endif
    }

    func signInWithGoogle() async {
#if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(GoogleSignIn) && canImport(UIKit)
        FirebaseBootstrap.configureIfPossible()

        guard let app = FirebaseApp.app() else {
            state = .needsConfiguration("GoogleService-Info.plistを追加してFirebaseを初期化してください。")
            return
        }
        guard let clientID = app.options.clientID else {
            state = .needsConfiguration("GoogleService-Info.plistにCLIENT_IDがありません。")
            return
        }
        guard let presentingViewController = UIApplication.shared.topMostViewController else {
            state = .failed("Googleログイン画面を表示できませんでした。")
            return
        }

        state = .syncing
        do {
            GIDSignIn.sharedInstance.configuration = GIDConfiguration(clientID: clientID)
            let result = try await GIDSignIn.sharedInstance.signIn(withPresenting: presentingViewController)
            guard let idToken = result.user.idToken?.tokenString else {
                state = .failed("Google IDトークンを取得できませんでした。")
                return
            }

            let credential = GoogleAuthProvider.credential(
                withIDToken: idToken,
                accessToken: result.user.accessToken.tokenString
            )
            let authResult = try await Auth.auth().signIn(with: credential)
            state = .ready(authResult.user.email ?? authResult.user.displayName ?? "Googleアカウント")
        } catch {
            state = .failed("Googleログインに失敗しました: \(error.localizedDescription)")
        }
#else
        state = .needsConfiguration("FirebaseAuthとGoogleSignIn SDKを追加すると、このボタンでGoogleログインできます。")
#endif
    }

    func sync(ideas: [Idea], plan: AppPlan) async {
        guard plan.usesCloudStorage else {
            state = .localOnly
            return
        }

        let records = ideas.map(IdeaCloudRecord.init)

#if canImport(FirebaseCore) && canImport(FirebaseAuth) && canImport(FirebaseFirestore)
        guard FirebaseApp.app() != nil else {
            state = .needsConfiguration("GoogleService-Info.plistを追加してFirebaseを初期化してください。")
            return
        }
        guard let userID = Auth.auth().currentUser?.uid else {
            state = .signedOut
            return
        }

        state = .syncing
        do {
            let database = Firestore.firestore()
            let batch = database.batch()
            for record in records {
                let reference = database
                    .collection("users")
                    .document(userID)
                    .collection("ideas")
                    .document(record.id)
                batch.setData(record.firestoreData, forDocument: reference, merge: true)
            }
            try await batch.commit()
            state = .synced(Date())
        } catch {
            state = .failed("Firebase同期に失敗しました: \(error.localizedDescription)")
        }
#else
        _ = records
        state = .needsConfiguration("Firestore SDKを追加すると、この同期ボタンからクラウド保存できます。")
#endif
    }
}

#if canImport(FirebaseAuth) && canImport(GoogleSignIn) && canImport(UIKit)
private extension UIApplication {
    var topMostViewController: UIViewController? {
        connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .flatMap(\.windows)
            .first { $0.isKeyWindow }?
            .rootViewController?
            .topMostPresentedViewController
    }
}

private extension UIViewController {
    var topMostPresentedViewController: UIViewController {
        if let presentedViewController {
            return presentedViewController.topMostPresentedViewController
        }
        if let navigationController = self as? UINavigationController,
           let visibleViewController = navigationController.visibleViewController {
            return visibleViewController.topMostPresentedViewController
        }
        if let tabBarController = self as? UITabBarController,
           let selectedViewController = tabBarController.selectedViewController {
            return selectedViewController.topMostPresentedViewController
        }
        return self
    }
}
#endif

extension IdeaCloudRecord {
    var firestoreData: [String: Any] {
        [
            "id": id,
            "title": title,
            "kind": kind,
            "status": status,
            "concept": concept,
            "rationale": rationale,
            "approach": approach,
            "nextAction": nextAction,
            "projectName": projectName,
            "tags": tags,
            "priority": priority,
            "isFavorite": isFavorite,
            "createdAt": createdAt,
            "updatedAt": updatedAt
        ]
    }
}
