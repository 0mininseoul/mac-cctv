import CCTVKit
import CloudKit
import Foundation
import UIKit
import UserNotifications

enum EscalationNotificationAction {
    static let categoryIdentifier = "SIREN_ESCALATION"
    static let dismissActionIdentifier = "DISMISS_ESCALATION_ACTION"
}

enum EventNotificationBootstrap {
    static func start() {
        UNUserNotificationCenter.current().delegate = EventNotificationDelegate.shared
        registerNotificationCategories()

        Task {
            _ = try? await UNUserNotificationCenter.current().requestAuthorization(options: [.alert, .badge, .sound])
            await MainActor.run {
                UIApplication.shared.registerForRemoteNotifications()
            }
            let store = CloudKitStore()
            // Remove the legacy catch-all ("Event detected: <rawType>") and the v1
            // per-type subscriptions. Re-saving an existing subscription ID does not
            // reliably update its copy/predicate on the server, so a stale one keeps
            // firing with the old text — the only reliable path is delete + recreate
            // under a bumped version ID.
            try? await store.deleteSubscription(id: "event-created-v1")
            for type in CloudKitStore.friendlyEventTypes {
                try? await store.deleteSubscription(id: "event-\(type.rawValue)-v1")
            }

            try? await store.ensureSignalSubscription()
            try? await store.ensureEscalationSubscription()
            // Friendly natural-language push per event type. sirenAuto/sirenManual/
            // escalationDismissed intentionally get no push (they're not alarming on
            // their own), so there is no generic catch-all anymore.
            for type in CloudKitStore.friendlyEventTypes {
                try? await store.ensureEventTypeSubscription(
                    type: type,
                    subscriptionID: "event-\(type.rawValue)-v2",
                    alertLocalizationKey: "event_\(type.rawValue)_notification_body"
                )
            }
        }
    }

    private static func registerNotificationCategories() {
        let dismissAction = UNNotificationAction(
            identifier: EscalationNotificationAction.dismissActionIdentifier,
            title: String(localized: "escalation_dismiss_action_title"),
            options: []
        )
        let escalationCategory = UNNotificationCategory(
            identifier: EscalationNotificationAction.categoryIdentifier,
            actions: [dismissAction],
            intentIdentifiers: [],
            options: []
        )
        UNUserNotificationCenter.current().setNotificationCategories([escalationCategory])
    }
}

final class EventNotificationDelegate: NSObject, UNUserNotificationCenterDelegate {
    static let shared = EventNotificationDelegate()

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let userInfo = response.notification.request.content.userInfo

        if response.actionIdentifier == EscalationNotificationAction.dismissActionIdentifier {
            if let queryNotification = CKQueryNotification(fromRemoteNotificationDictionary: userInfo),
               let sessionReference = queryNotification.recordFields?[CKSchema.Event.session] as? CKRecord.Reference {
                try? await EscalationDismissSender.send(sessionID: sessionReference.recordID.recordName)
            }
            return
        }

        if let queryNotification = CKQueryNotification(fromRemoteNotificationDictionary: userInfo),
           let recordName = queryNotification.recordID?.recordName {
            UserDefaults.standard.set(recordName, forKey: EventNavigationRouter.pendingEventRecordNameKey)
            await EventNavigationRouter.shared.open(eventRecordName: recordName)
        }
    }
}
