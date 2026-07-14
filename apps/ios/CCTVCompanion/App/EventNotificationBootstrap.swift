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
            await synchronizeSubscriptions()
        }
    }

    /// Idempotent, non-destructive subscription sync.
    ///
    /// Idempotent subscription sync with a production-safe fallback.
    ///
    /// Root cause (confirmed by probing production directly): a CKQuerySubscription
    /// whose predicate is `type == X` is rejected in the *production* container with
    /// "attempting to create a subscription in a production container" unless the
    /// Event `type` field's queryable index is actually deployed there — which it
    /// isn't, despite the dashboard showing it. Only `NSPredicate(value: true)`
    /// subscriptions (the Signal one, build 8's old event catch-all) save in
    /// production. So: try the friendly per-type subs; if production rejects them,
    /// fall back to a single match-all Event subscription so pushes still arrive
    /// (with one generic line instead of per-type copy). Once the index is genuinely
    /// deployed, the per-type subs start succeeding and the fallback is removed —
    /// self-healing. Every step is logged to `m-notif-result.txt`.
    private static func synchronizeSubscriptions() async {
        let store = CloudKitStore()

        let existing: Set<String>
        do {
            existing = try await store.fetchExistingSubscriptionIDs()
        } catch {
            IOSDiagnostics.append(
                "M11_SUBS_FETCH_FAILED error=\(error.localizedDescription)",
                filename: "m-notif-result.txt"
            )
            return
        }
        IOSDiagnostics.append(
            "M11_SUBS_EXISTING count=\(existing.count) ids=\(existing.sorted().joined(separator: ","))",
            filename: "m-notif-result.txt"
        )

        // Create `id` if missing; returns true if it now exists (created or already
        // present), false if creation failed.
        func ensure(_ id: String, _ create: @Sendable () async throws -> Void) async -> Bool {
            if existing.contains(id) {
                IOSDiagnostics.append("M11_SUBS_SKIP id=\(id)", filename: "m-notif-result.txt")
                return true
            }
            do {
                try await create()
                IOSDiagnostics.append("M11_SUBS_CREATED id=\(id)", filename: "m-notif-result.txt")
                return true
            } catch {
                IOSDiagnostics.append(
                    "M11_SUBS_CREATE_FAILED id=\(id) error=\(error.localizedDescription)",
                    filename: "m-notif-result.txt"
                )
                return false
            }
        }

        // Signal sync (value:true) — always accepted, drives live macState mirroring.
        _ = await ensure("signal-created-v1") { try await store.ensureSignalSubscription() }

        // Friendly per-type + escalation (type == X). These only succeed where the
        // Event.type queryable index is deployed (dev, or prod once deployed).
        var perTypeAllPresent = await ensure("escalation-created-v1") {
            try await store.ensureEscalationSubscription()
        }
        for type in CloudKitStore.friendlyEventTypes {
            let id = "event-\(type.rawValue)-v3"
            let present = await ensure(id) {
                try await store.ensureEventTypeSubscription(
                    type: type,
                    subscriptionID: id,
                    alertLocalizationKey: "event_\(type.rawValue)_notification_body"
                )
            }
            perTypeAllPresent = present && perTypeAllPresent
        }

        // Legacy IDs that must never linger (old copy / broken versions).
        var legacy = ["event-created-v1"]
        for type in CloudKitStore.friendlyEventTypes {
            legacy.append("event-\(type.rawValue)-v1")
            legacy.append("event-\(type.rawValue)-v2")
        }

        func delete(_ ids: [String]) async {
            for id in ids where existing.contains(id) {
                do {
                    try await store.deleteSubscription(id: id)
                    IOSDiagnostics.append("M11_SUBS_DELETED id=\(id)", filename: "m-notif-result.txt")
                } catch {
                    IOSDiagnostics.append(
                        "M11_SUBS_DELETE_FAILED id=\(id) error=\(error.localizedDescription)",
                        filename: "m-notif-result.txt"
                    )
                }
            }
        }

        if perTypeAllPresent {
            // Per-type mode: friendly copy is live — drop the generic fallback + legacy.
            IOSDiagnostics.append("M11_SUBS_MODE per-type", filename: "m-notif-result.txt")
            await delete(legacy + ["event-all-v1"])
        } else {
            // Fallback mode: production rejected the per-type subs. Guarantee pushes
            // still arrive via a single match-all subscription (create it *before*
            // removing the old catch-all so there's never a coverage gap).
            IOSDiagnostics.append("M11_SUBS_MODE fallback", filename: "m-notif-result.txt")
            _ = await ensure("event-all-v1") { try await store.ensureGenericEventSubscription() }
            await delete(legacy)
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
