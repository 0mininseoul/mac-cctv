import Foundation

public enum CKSchema {
    public static let containerIdentifier = "iCloud.com.youngminpark.maccctv"
    public static let appGroupIdentifier = "group.com.youngminpark.maccctv"

    public enum RecordType {
        public static let session = "Session"
        public static let chunk = "Chunk"
        public static let event = "Event"
        public static let signal = "Signal"
        public static let testProbe = "TestProbe"
    }

    public enum Session {
        public static let startedAt = "startedAt"
        public static let endedAt = "endedAt"
        public static let deviceName = "deviceName"
        public static let status = "status"
        public static let escalationDeadline = "escalationDeadline"
    }

    public enum Chunk {
        public static let session = "session"
        public static let index = "index"
        public static let startedAt = "startedAt"
        public static let duration = "duration"
        public static let byteCount = "byteCount"
        public static let uploadedAt = "uploadedAt"
        public static let video = "video"
    }

    public enum Event {
        public static let session = "session"
        public static let type = "type"
        public static let occurredAt = "occurredAt"
        public static let confidence = "confidence"
    }

    public enum Signal {
        public static let session = "session"
        public static let kind = "kind"
        public static let payload = "payload"
        public static let sender = "sender"
        public static let createdAt = "createdAt"
    }

    public enum TestProbe {
        public static let source = "source"
        public static let message = "message"
        public static let createdAt = "createdAt"
        public static let deviceName = "deviceName"
    }
}
