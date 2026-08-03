import Foundation

enum AppRuntimePolicy {
    static let remoteNotificationsEnabledInfoKey = "MuesliRemoteNotificationsEnabled"

    static func shouldRegisterForRemoteNotifications(
        infoDictionary: [String: Any] = Bundle.main.infoDictionary ?? [:]
    ) -> Bool {
        infoDictionary[remoteNotificationsEnabledInfoKey] as? Bool ?? true
    }
}
