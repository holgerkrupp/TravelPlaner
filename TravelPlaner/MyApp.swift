import SwiftUI
import SwiftData

@main struct MyApp: App {
    private let dependencies = AppDependencies()
    @StateObject private var appState = AppState()
    private let modelContainer: ModelContainer

    init() {
        modelContainer = (try? TravelPlanerSchema.container()) ?? (try! TravelPlanerSchema.container(inMemory: true))
    }

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
        }
        .modelContainer(modelContainer)
    }
}
