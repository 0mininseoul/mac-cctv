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
    /// Build 9 regressed all pushes by deleting the (stale) catch-all subscription
    /// and *then* recreating per-type ones — every step wrapped in `try?`, so if a
    /// recreate failed after the delete succeeded, the user was left with zero
    /// subscriptions and no pushes at all. This instead: fetch what exists, create
    /// only what's missing, and delete the obsolete IDs *only after* all desired
    /// ones are confirmed present — so there is never a window with no coverage.
    /// Every step is logged to `m-notif-result.txt` (pull via Xcode "Download
    /// Container…") so the subscription state can be verified on a TestFlight build.
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

        // The full set we want present, each with an idempotent creator.
        var desired: [(id: String, create: () async throws -> Void)] = [
            ("signal-created-v1", { try await store.ensureSignalSubscription() }),
            ("escalation-created-v1", { try await store.ensureEscalationSubscription() })
        ]
        for type in CloudKitStore.friendlyEventTypes {
            // v3: the v2 IDs may exist on the server in a non-firing state (a
            // `type == X` predicate requires the Event `type` field to be marked
            // Queryable in the *production* schema; until that's deployed the save is
            // rejected/inert). Bumping the ID forces a clean recreation once type is
            // queryable, instead of the idempotent "skip if exists" keeping a broken one.
            let id = "event-\(type.rawValue)-v3"
            desired.append((id, {
                try await store.ensureEventTypeSubscription(
                    type: type,
                    subscriptionID: id,
                    alertLocalizationKey: "event_\(type.rawValue)_notification_body"
                )
            }))
        }

        var allDesiredPresent = true
        for entry in desired {
            if existing.contains(entry.id) {
                IOSDiagnostics.append("M11_SUBS_SKIP id=\(entry.id)", filename: "m-notif-result.txt")
                continue
            }
            do {
                try await entry.create()
                IOSDiagnostics.append("M11_SUBS_CREATED id=\(entry.id)", filename: "m-notif-result.txt")
            } catch {
                allDesiredPresent = false
                IOSDiagnostics.append(
                    "M11_SUBS_CREATE_FAILED id=\(entry.id) error=\(error.localizedDescription)",
                    filename: "m-notif-result.txt"
                )
            }
        }

        // Only remove the legacy catch-all + older per-type IDs once the friendly v3
        // set is fully in place, so a transient create failure never strands the user
        // with no working subscription. The stale generic keeps firing (old copy)
        // until then — an ugly push beats a missing one.
        guard allDesiredPresent else {
            IOSDiagnostics.append(
                "M11_SUBS_KEEP_LEGACY reason=desired-incomplete",
                filename: "m-notif-result.txt"
            )
            return
        }
        var obsolete = ["event-created-v1"]
        for type in CloudKitStore.friendlyEventTypes {
            obsolete.append("event-\(type.rawValue)-v1")
            obsolete.append("event-\(type.rawValue)-v2")
        }
        for id in obsolete where existing.contains(id) {
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
