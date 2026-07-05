import XCTest
@testable import CCTVKit

final class MotionClassifierTests: XCTestCase {
    func testClassifiesNoMotionWhenFramesAreIdentical() throws {
        let frame = makeSolidFrame(value: 24)
        let classifier = MotionClassifier()

        let result = try classifier.classify(previous: frame, current: frame)

        XCTAssertEqual(result, .noMotion)
    }

    func testClassifiesPersonMotionWhenOnlyPartOfTheFrameChanges() throws {
        let previous = makeSolidFrame(value: 24)
        let current = makeSolidFrame(value: 24, changedRect: Rect(x: 24, y: 16, width: 16, height: 32, value: 210))
        let classifier = MotionClassifier()

        let result = try classifier.classify(previous: previous, current: current)

        guard case let .personMotion(confidence) = result else {
            return XCTFail("Expected personMotion, got \(result)")
        }
        XCTAssertGreaterThan(confidence, 0.10)
        XCTAssertLessThan(confidence, 0.60)
    }

    func testClassifiesDeviceMotionWhenMostBlocksChangeTogether() throws {
        let previous = makeGradientFrame(shiftX: 0)
        let current = makeGradientFrame(shiftX: 9)
        let classifier = MotionClassifier()

        let result = try classifier.classify(previous: previous, current: current)

        guard case let .deviceMotion(confidence) = result else {
            return XCTFail("Expected deviceMotion, got \(result)")
        }
        XCTAssertGreaterThanOrEqual(confidence, 0.75)
    }
}

private struct Rect {
    let x: Int
    let y: Int
    let width: Int
    let height: Int
    let value: UInt8
}

private func makeSolidFrame(value: UInt8, changedRect: Rect? = nil) -> MotionFrame {
    let width = 64
    let height = 64
    var luma = Array(repeating: value, count: width * height)

    if let changedRect {
        for y in changedRect.y..<(changedRect.y + changedRect.height) {
            for x in changedRect.x..<(changedRect.x + changedRect.width) {
                luma[(y * width) + x] = changedRect.value
            }
        }
    }

    return MotionFrame(width: width, height: height, luma: luma)
}

private func makeGradientFrame(shiftX: Int) -> MotionFrame {
    let width = 64
    let height = 64
    let luma = (0..<height).flatMap { y in
        (0..<width).map { x in
            UInt8(((x + shiftX) * 9 + y * 5) % 256)
        }
    }
    return MotionFrame(width: width, height: height, luma: luma)
}
