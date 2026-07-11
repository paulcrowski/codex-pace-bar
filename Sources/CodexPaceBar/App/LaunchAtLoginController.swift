import Foundation
import Observation
import ServiceManagement

@MainActor
@Observable
final class LaunchAtLoginController {
    private(set) var isEnabled = false
    private(set) var statusMessage: String?

    @ObservationIgnored
    private let service: SMAppService

    @ObservationIgnored
    private let defaults: UserDefaults

    init(service: SMAppService = .mainApp, defaults: UserDefaults = .standard) {
        self.service = service
        self.defaults = defaults
        enableByDefaultIfNeeded()
    }

    func setEnabled(_ enabled: Bool) {
        defaults.set(true, forKey: Keys.didApplyDefault)
        do {
            if enabled {
                try service.register()
            } else {
                try service.unregister()
            }
            updateStatus()
        } catch {
            updateStatus(errorMessage: error.localizedDescription)
        }
    }

    func refresh() {
        updateStatus()
    }

    private func enableByDefaultIfNeeded() {
        guard !defaults.bool(forKey: Keys.didApplyDefault) else {
            updateStatus()
            return
        }

        defaults.set(true, forKey: Keys.didApplyDefault)
        guard service.status == .notRegistered else {
            updateStatus()
            return
        }

        do {
            try service.register()
            updateStatus()
        } catch {
            updateStatus(errorMessage: error.localizedDescription)
        }
    }

    private func updateStatus(errorMessage: String? = nil) {
        switch service.status {
        case .enabled:
            isEnabled = true
            statusMessage = errorMessage
        case .requiresApproval:
            isEnabled = true
            statusMessage = errorMessage ?? "Approval is required in System Settings."
        case .notRegistered:
            isEnabled = false
            statusMessage = errorMessage
        case .notFound:
            isEnabled = false
            statusMessage = errorMessage ?? "The login item is unavailable."
        @unknown default:
            isEnabled = false
            statusMessage = errorMessage ?? "The login item status is unknown."
        }
    }

    private enum Keys {
        static let didApplyDefault = "didApplyLaunchAtLoginDefault"
    }
}
