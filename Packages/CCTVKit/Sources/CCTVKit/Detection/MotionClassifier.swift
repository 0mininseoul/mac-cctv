import Foundation

public struct MotionFrame: Equatable, Sendable {
    public let width: Int
    public let height: Int
    public let luma: [UInt8]

    public init(width: Int, height: Int, luma: [UInt8]) {
        self.width = width
        self.height = height
        self.luma = luma
    }
}

public enum MotionClassification: Equatable, Sendable {
    case noMotion
    case personMotion(confidence: Double)
    case deviceMotion(confidence: Double)
}

public enum MotionClassifierError: Error, Equatable, Sendable {
    case invalidFrame
}

public struct MotionClassifier: Sendable {
    public struct Settings: Equatable, Sendable {
        public let gridColumns: Int
        public let gridRows: Int
        public let blockChangeThreshold: Double
        public let minimumMotionBlockRatio: Double
        public let deviceMotionBlockRatio: Double

        public init(
            gridColumns: Int = 8,
            gridRows: Int = 8,
            blockChangeThreshold: Double = 24,
            minimumMotionBlockRatio: Double = 0.06,
            deviceMotionBlockRatio: Double = 0.72
        ) {
            self.gridColumns = gridColumns
            self.gridRows = gridRows
            self.blockChangeThreshold = blockChangeThreshold
            self.minimumMotionBlockRatio = minimumMotionBlockRatio
            self.deviceMotionBlockRatio = deviceMotionBlockRatio
        }
    }

    private let settings: Settings

    public init(settings: Settings = Settings()) {
        self.settings = settings
    }

    public func classify(previous: MotionFrame, current: MotionFrame) throws -> MotionClassification {
        try validate(previous, current)

        let columns = max(1, settings.gridColumns)
        let rows = max(1, settings.gridRows)
        var changedBlocks = 0
        let totalBlocks = columns * rows

        for row in 0..<rows {
            for column in 0..<columns where averageDifference(
                previous: previous,
                current: current,
                column: column,
                row: row,
                columns: columns,
                rows: rows
            ) >= settings.blockChangeThreshold {
                changedBlocks += 1
            }
        }

        let ratio = Double(changedBlocks) / Double(totalBlocks)
        if ratio < settings.minimumMotionBlockRatio {
            return .noMotion
        }
        if ratio >= settings.deviceMotionBlockRatio {
            return .deviceMotion(confidence: min(1, ratio))
        }
        return .personMotion(confidence: ratio)
    }

    private func validate(_ previous: MotionFrame, _ current: MotionFrame) throws {
        guard previous.width == current.width,
              previous.height == current.height,
              previous.width > 0,
              previous.height > 0,
              previous.luma.count == previous.width * previous.height,
              current.luma.count == current.width * current.height else {
            throw MotionClassifierError.invalidFrame
        }
    }

    private func averageDifference(
        previous: MotionFrame,
        current: MotionFrame,
        column: Int,
        row: Int,
        columns: Int,
        rows: Int
    ) -> Double {
        let xStart = column * previous.width / columns
        let xEnd = (column + 1) * previous.width / columns
        let yStart = row * previous.height / rows
        let yEnd = (row + 1) * previous.height / rows
        var totalDifference = 0
        var sampleCount = 0

        for y in yStart..<yEnd {
            for x in xStart..<xEnd {
                let index = (y * previous.width) + x
                totalDifference += abs(Int(previous.luma[index]) - Int(current.luma[index]))
                sampleCount += 1
            }
        }

        guard sampleCount > 0 else {
            return 0
        }
        return Double(totalDifference) / Double(sampleCount)
    }
}
