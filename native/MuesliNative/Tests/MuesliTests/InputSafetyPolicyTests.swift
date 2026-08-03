import CoreGraphics
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

    @Test("pre-onboarding status menu does not expose runtime actions")
    func preOnboardingStatusMenuIsRecoveryOnly() {
        #expect(
            !StatusBarRuntimePolicy.shouldExposeRuntimeActions(
                hasCompletedOnboarding: false
            )
        )
        #expect(
            StatusBarRuntimePolicy.shouldExposeRuntimeActions(
                hasCompletedOnboarding: true
            )
        )
    }
}
