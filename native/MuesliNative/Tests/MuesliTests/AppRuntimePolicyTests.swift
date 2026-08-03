import Foundation
import Testing
@testable import MuesliNativeApp

@Suite("AppRuntimePolicy")
struct AppRuntimePolicyTests {
    @Test("disables remote notification registration when the plist opts out")
    func disablesRemoteNotificationsWhenConfigured() {
        let enabled = AppRuntimePolicy.shouldRegisterForRemoteNotifications(
            infoDictionary: [AppRuntimePolicy.remoteNotificationsEnabledInfoKey: false]
        )

        #expect(!enabled)
    }

    @Test("preserves remote notification registration for existing builds")
    func preservesExistingDefault() {
        #expect(AppRuntimePolicy.shouldRegisterForRemoteNotifications(infoDictionary: [:]))
    }
}
