import CoreGraphics
import Dispatch
import Testing
@testable import MuesliNativeApp

@Suite("Input safety policy")
struct InputSafetyPolicyTests {
    @Test("onboarding presentation activates before showing its window")
    @MainActor
    func onboardingPresentationOrder() {
        var actions: [String] = []
        let coordinator = OnboardingPresentationCoordinator(
            useRegularActivationPolicy: { actions.append("regular") },
            activateApplication: { actions.append("activate") },
            presentWindow: { actions.append("window") }
        )

        coordinator.present()

        #expect(actions == ["regular", "activate", "window"])
    }

    @Test("synthetic events are denied before the main runtime is enabled")
    func syntheticEventsDeniedDuringOnboarding() {
        #expect(
            !SyntheticEventPostingPolicy.canPost(
                runtimeEnabled: false,
                postEventAccessGranted: true
            )
        )
    }

    @Test("synthetic events are denied without post-event authorisation")
    func syntheticEventsDeniedWithoutAuthorisation() {
        #expect(
            !SyntheticEventPostingPolicy.canPost(
                runtimeEnabled: true,
                postEventAccessGranted: false
            )
        )
    }

    @Test("synthetic events require both runtime enablement and authorisation")
    func syntheticEventsAllowedOnlyWhenFullyEnabled() {
        #expect(
            SyntheticEventPostingPolicy.canPost(
                runtimeEnabled: true,
                postEventAccessGranted: true
            )
        )
    }

    @Test("status menu exposes runtime actions only when the runtime is ready")
    func statusMenuIsRecoveryOnlyUntilRuntimeReady() {
        #expect(
            !StatusBarRuntimePolicy.shouldExposeRuntimeActions(
                runtimeEnabled: false
            )
        )
        #expect(
            StatusBarRuntimePolicy.shouldExposeRuntimeActions(
                runtimeEnabled: true
            )
        )
    }

    @Test("floating indicator requires both runtime and user enablement")
    func floatingIndicatorIsHiddenUntilRuntimeReady() {
        #expect(
            !FloatingIndicatorRuntimePolicy.shouldShow(
                runtimeEnabled: false,
                userEnabled: true
            )
        )
        #expect(
            !FloatingIndicatorRuntimePolicy.shouldShow(
                runtimeEnabled: true,
                userEnabled: false
            )
        )
        #expect(
            FloatingIndicatorRuntimePolicy.shouldShow(
                runtimeEnabled: true,
                userEnabled: true
            )
        )
    }

    @Test("floating indicator visibility distinguishes runtime shutdown from user preference")
    func floatingIndicatorVisibilityActionIsFailClosedWithoutDisruptingActiveRuntime() {
        #expect(
            FloatingIndicatorRuntimePolicy.action(runtimeEnabled: false, userEnabled: true)
                == .close
        )
        #expect(
            FloatingIndicatorRuntimePolicy.action(runtimeEnabled: true, userEnabled: false)
                == .closeIfIdle
        )
        #expect(
            FloatingIndicatorRuntimePolicy.action(runtimeEnabled: true, userEnabled: true)
                == .show
        )
    }

    @Test("direct floating indicator presentation requires the main runtime")
    func floatingIndicatorPresentationRequiresRuntime() {
        #expect(!FloatingIndicatorPresentationPolicy.canPresent(runtimeEnabled: false))
        #expect(FloatingIndicatorPresentationPolicy.canPresent(runtimeEnabled: true))
    }

    @Test("runtime disable waits for an admitted synthetic input sequence")
    func syntheticSequenceAdmissionIsAtomic() {
        let gate = SyntheticEventPostingGate(postEventAccessGranted: { true })
        gate.setRuntimeEnabled(true)
        let sequenceStarted = DispatchSemaphore(value: 0)
        let releaseSequence = DispatchSemaphore(value: 0)
        let sequenceFinished = DispatchSemaphore(value: 0)
        let disableFinished = DispatchSemaphore(value: 0)

        DispatchQueue.global().async {
            _ = gate.withAuthorizedSequence { _ in
                sequenceStarted.signal()
                _ = releaseSequence.wait(timeout: .now() + 1)
            }
            sequenceFinished.signal()
        }
        #expect(sequenceStarted.wait(timeout: .now() + 1) == .success)

        DispatchQueue.global().async {
            gate.setRuntimeEnabled(false)
            disableFinished.signal()
        }
        #expect(disableFinished.wait(timeout: .now() + 0.05) == .timedOut)

        releaseSequence.signal()
        #expect(sequenceFinished.wait(timeout: .now() + 1) == .success)
        #expect(disableFinished.wait(timeout: .now() + 1) == .success)
        #expect(!gate.isRuntimeEnabled())
    }

    @Test("synthetic input sequence capability expires when its closure returns")
    func syntheticSequenceCannotEscapeAdmissionScope() {
        let gate = SyntheticEventPostingGate(postEventAccessGranted: { true })
        gate.setRuntimeEnabled(true)
        var escaped: SyntheticEventPostingSequence?

        let admitted = gate.withAuthorizedSequence { escaped = $0 }
        #expect(admitted)
        #expect(escaped?.isValid == false)
    }

    @Test("nested synthetic sequence admission fails closed without deadlocking")
    func syntheticSequenceAdmissionRejectsReentrancy() {
        let gate = SyntheticEventPostingGate(postEventAccessGranted: { true })
        gate.setRuntimeEnabled(true)
        var nestedAdmitted = true
        var observedEnabled = false
        var outerCompleted = false

        let outerAdmitted = gate.withAuthorizedSequence { _ in
            observedEnabled = gate.isRuntimeEnabled()
            nestedAdmitted = gate.withAuthorizedSequence { _ in }
            gate.setRuntimeEnabled(false)
            outerCompleted = true
        }

        #expect(outerAdmitted)
        #expect(observedEnabled)
        #expect(!nestedAdmitted)
        #expect(outerCompleted)
        #expect(!gate.isRuntimeEnabled())
    }

    @Test("computer use is unavailable until the main runtime is ready")
    func computerUseRequiresRuntime() {
        #expect(!ComputerUseRuntimePolicy.canExecute(runtimeEnabled: false))
        #expect(ComputerUseRuntimePolicy.canExecute(runtimeEnabled: true))
    }

    @Test("onboarding hotkey observation never requests or consumes input")
    func onboardingHotkeyModeIsPassive() {
        #expect(!HotkeyMonitorStartPolicy.onboarding.requestListenEventAccess)
        #expect(!HotkeyMonitorStartPolicy.onboarding.consumeLocalEvents)
        #expect(!HotkeyMonitorStartPolicy.onboarding.startComputerUseMonitor)
        #expect(HotkeyMonitorStartPolicy.production.requestListenEventAccess)
        #expect(HotkeyMonitorStartPolicy.production.consumeLocalEvents)
        #expect(HotkeyMonitorStartPolicy.production.startComputerUseMonitor)
    }
}
