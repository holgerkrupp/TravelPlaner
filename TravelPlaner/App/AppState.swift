import Foundation
import Combine
import SwiftUI

enum AppServiceError: LocalizedError, Equatable, Sendable {
    case locationUnavailable
    case routeUnavailable
    case persistenceFailure
    case discoveryFailure
    case cloudKitFailure

    var errorDescription: String? {
        switch self {
        case .locationUnavailable: "Current location is unavailable."
        case .routeUnavailable: "The route is currently unavailable."
        case .persistenceFailure: "Your local trip data could not be saved."
        case .discoveryFailure: "Discoveries could not be loaded."
        case .cloudKitFailure: "Shared discoveries are currently unavailable."
        }
    }
}

@MainActor
final class AppState: ObservableObject {
    @Published private(set) var error: AppServiceError?
    let offlineWriteQueue = OfflineWriteQueue()

    func report(_ error: AppServiceError) { self.error = error }
    func clearError() { error = nil }
}
