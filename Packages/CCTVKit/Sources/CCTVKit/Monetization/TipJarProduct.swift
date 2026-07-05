import Foundation

public enum TipJarProduct: String, CaseIterable, Identifiable, Sendable {
    case smallCoffee = "com.youngminpark.maccctv.tip.small"
    case largeCoffee = "com.youngminpark.maccctv.tip.large"
    case supporter = "com.youngminpark.maccctv.tip.supporter"

    public var id: String {
        rawValue
    }
}
