import SwiftUI
import SwiftData

#if canImport(GoogleSignIn)
import GoogleSignIn
#endif

@main
struct KatachiApp: App {
    init() {
        FirebaseBootstrap.configureIfPossible()
    }

    var sharedModelContainer: ModelContainer = {
        let schema = Schema([
            Idea.self
        ])
        let modelConfiguration = ModelConfiguration(schema: schema, isStoredInMemoryOnly: false)

        do {
            return try ModelContainer(for: schema, configurations: [modelConfiguration])
        } catch {
            fatalError("Could not create ModelContainer: \(error)")
        }
    }()

    var body: some Scene {
        WindowGroup {
            ContentView()
#if canImport(GoogleSignIn)
                .onOpenURL { url in
                    GIDSignIn.sharedInstance.handle(url)
                }
#endif
        }
        .modelContainer(sharedModelContainer)
    }
}
