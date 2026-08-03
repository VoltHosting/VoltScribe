import CoreGraphics
import Foundation

struct SyntheticEventPostingPolicy {
    static func canPost(runtimeEnabled: Bool, postEventAccessGranted: Bool) -> Bool {
        runtimeEnabled && postEventAccessGranted
    }
}

struct StatusBarRuntimePolicy {
    static func shouldExposeRuntimeActions(hasCompletedOnboarding: Bool) -> Bool {
        hasCompletedOnboarding
    }
}

/// Process-wide gate for all synthetic HID event posting.
///
/// The gate starts disabled and is enabled only after onboarding and required
/// permissions are complete. `CGPreflightPostEventAccess` never prompts; denied
/// events are dropped locally instead of being sent to WindowServer.
final class SyntheticEventPostingGate: @unchecked Sendable {
    static let shared = SyntheticEventPostingGate()

    private let lock = NSLock()
    private var runtimeEnabled = false

    func setRuntimeEnabled(_ enabled: Bool) {
        lock.lock()
        runtimeEnabled = enabled
        lock.unlock()
    }

    @discardableResult
    func isPostingAllowed() -> Bool {
        lock.lock()
        let enabled = runtimeEnabled
        lock.unlock()

        return SyntheticEventPostingPolicy.canPost(
            runtimeEnabled: enabled,
            postEventAccessGranted: CGPreflightPostEventAccess()
        )
    }

    @discardableResult
    func post(_ event: CGEvent, tap: CGEventTapLocation = .cghidEventTap) -> Bool {
        guard isPostingAllowed() else { return false }
        event.post(tap: tap)
        return true
    }
}

@MainActor
struct OnboardingPresentationCoordinator {
    let useRegularActivationPolicy: () -> Void
    let activateApplication: () -> Void
    let presentWindow: () -> Void

    func present() {
        useRegularActivationPolicy()
        activateApplication()
        presentWindow()
    }
}
