//
//  AppDelegate.swift
//  OpenClaw
//
//  Handles APNs registration callbacks and app lifecycle events
//

import UIKit
import UserNotifications

class AppDelegate: NSObject, UIApplicationDelegate {

    func application(
        _ application: UIApplication,
        didFinishLaunchingWithOptions launchOptions: [UIApplication.LaunchOptionsKey: Any]? = nil
    ) -> Bool {
        UNUserNotificationCenter.current().delegate = NotificationDelegate.shared

        if let notification = launchOptions?[.remoteNotification] as? [AnyHashable: Any] {
            handleLaunchNotification(notification)
        }

        return true
    }

    // MARK: - Remote Notification Registration

    func application(
        _ application: UIApplication,
        didRegisterForRemoteNotificationsWithDeviceToken deviceToken: Data
    ) {
        Task { @MainActor in
            PushNotificationManager.shared.handleDeviceToken(deviceToken)
        }
    }

    func application(
        _ application: UIApplication,
        didFailToRegisterForRemoteNotificationsWithError error: Error
    ) {
        Task { @MainActor in
            PushNotificationManager.shared.handleRegistrationError(error)
        }
    }

    // MARK: - Background Notification Handling

    func application(
        _ application: UIApplication,
        didReceiveRemoteNotification userInfo: [AnyHashable: Any],
        fetchCompletionHandler completionHandler: @escaping (UIBackgroundFetchResult) -> Void
    ) {
        Log.debug("Received remote notification in background")

        if let openclawData = userInfo["openclaw"] as? [String: Any] {
            processBackgroundNotification(openclawData)
        }

        completionHandler(.newData)
    }

    // MARK: - Private Methods

    private func handleLaunchNotification(_ userInfo: [AnyHashable: Any]) {
        Log.info("App launched from notification")

        if let openclawData = userInfo["openclaw"] as? [String: Any] {
            let type = openclawData["type"] as? String
            let context = openclawData["context"] as? String

            Task { @MainActor in
                switch type {
                case "start_conversation":
                    AppState.shared.pendingAction = .startConversation(context: context)
                case "open_settings":
                    AppState.shared.pendingAction = .openSettings
                default:
                    AppState.shared.pendingAction = .startConversation(context: nil)
                }
            }
        }
    }

    private func processBackgroundNotification(_ data: [String: Any]) {
        Log.debug("Processing background notification data")
    }
}
