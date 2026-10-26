import SwiftUI
#if canImport(FirebaseCore)
import FirebaseCore
#endif

@main
struct EliskopesApp: App {
    @UIApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var store = ProjectStore(backend: EliskopesApp.makeBackend())

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .tint(Theme.blue)
                .preferredColorScheme(.light)
                .task { await store.start() }
        }
    }

    /// Uses Firebase once GoogleService-Info.plist is added to the Eliskopes folder; the sample project until then.
    @MainActor
    private static func makeBackend() -> ProjectBackend {
        #if canImport(FirebaseCore)
        if Bundle.main.path(forResource: "GoogleService-Info", ofType: "plist") != nil {
            if FirebaseApp.app() == nil { FirebaseApp.configure() }
            return FirebaseBackend()
        }
        #endif
        return SampleBackend()
    }
}
