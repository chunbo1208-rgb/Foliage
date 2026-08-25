import CloudKit
import Combine

enum CloudConfiguration {
    static let containerIdentifier = "iCloud.com.chunboblog.Foliage"
    // Personal development teams cannot sign CloudKit entitlements. Enable this
    // after moving the target to a paid Apple Developer team.
    static let isEnabled = false
}

@MainActor
final class CloudSyncMonitor: ObservableObject {
    enum State {
        case checking
        case available
        case unavailable(String)

        var title: String {
            switch self {
            case .checking: "Checking iCloud"
            case .available: "iCloud Library"
            case .unavailable: "Local Library"
            }
        }

        var detail: String {
            switch self {
            case .checking:
                "Checking account availability..."
            case .available:
                "Library information and reading notes sync automatically."
            case .unavailable(let reason):
                reason
            }
        }

        var systemImage: String {
            switch self {
            case .checking: "icloud"
            case .available: "icloud.fill"
            case .unavailable: "icloud.slash"
            }
        }
    }

    @Published private(set) var state = State.checking

    func refresh() async {
        guard CloudConfiguration.isEnabled else {
            state = .unavailable("Cloud sync is ready for activation with a paid Apple Developer team.")
            return
        }
        do {
            switch try await CKContainer(identifier: CloudConfiguration.containerIdentifier).accountStatus() {
            case .available:
                state = .available
            case .noAccount:
                state = .unavailable("Sign in to iCloud to sync between devices.")
            case .restricted:
                state = .unavailable("iCloud access is restricted on this device.")
            case .temporarilyUnavailable:
                state = .unavailable("iCloud is temporarily unavailable; changes remain local.")
            case .couldNotDetermine:
                state = .unavailable("Foliage could not determine the iCloud account status.")
            @unknown default:
                state = .unavailable("iCloud is unavailable; changes remain local.")
            }
        } catch {
            state = .unavailable("iCloud is unavailable; changes remain local.")
        }
    }
}
