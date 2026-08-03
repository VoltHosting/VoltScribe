import CoreGraphics
import Foundation

struct SyntheticEventPostingPolicy {
    static func canPost(runtimeEnabled: Bool, postEventAccessGranted: Bool) -> Bool {
        runtimeEnabled && postEventAccessGranted
    }
}

struct ComputerUseRuntimePolicy {
    static func canExecute(runtimeEnabled: Bool) -> Bool {
        runtimeEnabled
    }
}

struct HotkeyMonitorStartPolicy: Equatable, Sendable {
    let requestListenEventAccess: Bool
    let consumeLocalEvents: Bool
    let startComputerUseMonitor: Bool

    static let onboarding = HotkeyMonitorStartPolicy(
        requestListenEventAccess: false,
        consumeLocalEvents: false,
        startComputerUseMonitor: false
    )

    static let production = HotkeyMonitorStartPolicy(
        requestListenEventAccess: true,
        consumeLocalEvents: true,
        startComputerUseMonitor: true
    )
}

struct StatusBarRuntimePolicy {
    static func shouldExposeRuntimeActions(runtimeEnabled: Bool) -> Bool {
        runtimeEnabled
    }
}

enum FloatingIndicatorVisibilityAction: Equatable {
    case show
    case closeIfIdle
    case close
}

struct FloatingIndicatorRuntimePolicy {
    static func shouldShow(runtimeEnabled: Bool, userEnabled: Bool) -> Bool {
        action(runtimeEnabled: runtimeEnabled, userEnabled: userEnabled) == .show
    }

    static func action(
        runtimeEnabled: Bool,
        userEnabled: Bool
    ) -> FloatingIndicatorVisibilityAction {
        guard runtimeEnabled else { return .close }
        return userEnabled ? .show : .closeIfIdle
    }
}

struct FloatingIndicatorPresentationPolicy {
    static func canPresent(runtimeEnabled: Bool) -> Bool {
        runtimeEnabled
    }
}

fileprivate final class SyntheticEventPostingLease: @unchecked Sendable {
    private let lock = NSLock()
    private var active = true
    private let eventPoster: (CGEvent, CGEventTapLocation) -> Void

    init(eventPoster: @escaping (CGEvent, CGEventTapLocation) -> Void) {
        self.eventPoster = eventPoster
    }

    @discardableResult
    func post(_ event: CGEvent, tap: CGEventTapLocation) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard active else { return false }
        eventPoster(event, tap)
        return true
    }

    func invalidate() {
        lock.lock()
        active = false
        lock.unlock()
    }

    var isActive: Bool {
        lock.lock()
        let value = active
        lock.unlock()
        return value
    }
}

struct SyntheticEventPostingSequence {
    private let lease: SyntheticEventPostingLease

    fileprivate init(lease: SyntheticEventPostingLease) {
        self.lease = lease
    }

    @discardableResult
    func post(_ event: CGEvent, tap: CGEventTapLocation = .cghidEventTap) -> Bool {
        lease.post(event, tap: tap)
    }

    var isValid: Bool {
        lease.isActive
    }
}

/// Process-wide gate for all synthetic HID event posting.
///
/// The gate starts disabled and is enabled only after onboarding and required
/// permissions are complete. `CGPreflightPostEventAccess` never prompts; denied
/// sequences are dropped locally instead of being sent to WindowServer. Runtime
/// and TCC state are checked once per admitted sequence so shutdown cannot split
/// a key/button down-up transaction and leave input logically held.
final class SyntheticEventPostingGate: @unchecked Sendable {
    static let shared = SyntheticEventPostingGate()

    private let lock = NSLock()
    private let admissionThreadKey = "SyntheticEventPostingGate.admission.\(UUID().uuidString)"
    private var runtimeEnabled = false
    private let postEventAccessGranted: () -> Bool
    private let eventPoster: (CGEvent, CGEventTapLocation) -> Void

    init(
        postEventAccessGranted: @escaping () -> Bool = { CGPreflightPostEventAccess() },
        eventPoster: @escaping (CGEvent, CGEventTapLocation) -> Void = { event, tap in
            event.post(tap: tap)
        }
    ) {
        self.postEventAccessGranted = postEventAccessGranted
        self.eventPoster = eventPoster
    }

    func setRuntimeEnabled(_ enabled: Bool) {
        if Thread.current.threadDictionary[admissionThreadKey] != nil {
            runtimeEnabled = enabled
            return
        }
        lock.lock()
        runtimeEnabled = enabled
        lock.unlock()
    }

    func isRuntimeEnabled() -> Bool {
        if Thread.current.threadDictionary[admissionThreadKey] != nil {
            return runtimeEnabled
        }
        lock.lock()
        let enabled = runtimeEnabled
        lock.unlock()
        return enabled
    }

    @discardableResult
    func withAuthorizedSequence(_ action: (SyntheticEventPostingSequence) -> Void) -> Bool {
        guard Thread.current.threadDictionary[admissionThreadKey] == nil else {
            return false
        }
        lock.lock()
        Thread.current.threadDictionary[admissionThreadKey] = true
        defer {
            Thread.current.threadDictionary.removeObject(forKey: admissionThreadKey)
            lock.unlock()
        }
        guard SyntheticEventPostingPolicy.canPost(
            runtimeEnabled: runtimeEnabled,
            postEventAccessGranted: postEventAccessGranted()
        ) else { return false }

        let lease = SyntheticEventPostingLease(eventPoster: eventPoster)
        action(SyntheticEventPostingSequence(lease: lease))
        lease.invalidate()
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
