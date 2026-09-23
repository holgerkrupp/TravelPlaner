import SwiftUI
import SwiftData
import UIKit

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
                .task {
                    _ = await appState.offlineWriteQueue.flush()
                    for await _ in NotificationCenter.default.notifications(named: UIApplication.didBecomeActiveNotification) {
                        _ = await appState.offlineWriteQueue.flush()
                    }
                }
        }
        .modelContainer(modelContainer)
    }
}
