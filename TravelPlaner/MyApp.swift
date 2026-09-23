import SwiftUI

@main struct MyApp: App {
    private let dependencies = AppDependencies()
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
    }
}
