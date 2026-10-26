import SwiftUI
import UserNotifications
#if canImport(FirebaseMessaging)
import FirebaseCore
import FirebaseMessaging
#endif

/// Push notifications: "You've been outbid" and award alerts, sent by the Cloud Functions.
/// Needs the Push Notifications capability on the App ID and an APNs key in Firebase (see README).
final class AppDelegate: NSObject, UIApplicationDelegate, UNUserNotificationCenterDelegate {
    func application(_ application: UIApplication,
                     didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil) -> Bool {
        UNUserNotificationCenter.current().delegate = self
        return true
    }

    func application(_ application: UIApplication, didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data) {
        #if canImport(FirebaseMessaging)
        if FirebaseApp.app() != nil { Messaging.messaging().apnsToken = deviceToken }
        #endif
    }

    func application(_ application: UIApplication, didFailToRegisterForRemoteNotificationsWithError error: Error) {
        print("Push registration failed: \(error.localizedDescription)")
    }

    /// Shows alerts as banners even while the app is open.
    func userNotificationCenter(_ center: UNUserNotificationCenter,
                                willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }
}

/// Asks for notification permission and hands the Firebase push token to the store, which saves it on the account.
final class PushRelay: NSObject {
    static let shared = PushRelay()
    var onToken: ((String) -> Void)?

    @MainActor
    func register() async {
        #if canImport(FirebaseMessaging)
        guard FirebaseApp.app() != nil else { return }
        Messaging.messaging().delegate = self
        let granted = (try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .sound, .badge])) ?? false
        guard granted else { return }
        UIApplication.shared.registerForRemoteNotifications()
        #endif
    }
}

#if canImport(FirebaseMessaging)
extension PushRelay: MessagingDelegate {
    func messaging(_ messaging: Messaging, didReceiveRegistrationToken fcmToken: String?) {
        guard let fcmToken else { return }
        onToken?(fcmToken)
    }
}
#endif
