import XCTest
@testable import CCTVKit

final class ChunkAssetCacheTests: XCTestCase {
    private var cacheDirectory: URL!
    private var cache: ChunkAssetCache!

    override func setUp() {
        super.setUp()
        cacheDirectory = FileManager.default.temporaryDirectory
            .appendingPathComponent("ChunkAssetCacheTests-\(UUID().uuidString)", isDirectory: true)
        cache = ChunkAssetCache(cacheDirectory: cacheDirectory)
    }

    override func tearDown() {
        try? FileManager.default.removeItem(at: cacheDirectory)
        cache = nil
        cacheDirectory = nil
        super.tearDown()
    }

    func testCopiesSourceFileToStableCacheLocation() throws {
        let source = try makeSourceFile(contents: "chunk-a")

        let cached = cache.stableFileURL(chunkID: "chunk-a", sourceURL: source)

        XCTAssertNotNil(cached)
        XCTAssertNotEqual(cached, source)
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(cached), encoding: .utf8), "chunk-a")
    }

    func testReturnsExistingCachedFileWithoutNeedingSourceStillAlive() throws {
        let source = try makeSourceFile(contents: "chunk-b")
        let firstResult = cache.stableFileURL(chunkID: "chunk-b", sourceURL: source)
        try FileManager.default.removeItem(at: source)

        let secondResult = cache.stableFileURL(chunkID: "chunk-b", sourceURL: nil)

        XCTAssertEqual(firstResult, secondResult)
        XCTAssertEqual(try String(contentsOf: XCTUnwrap(secondResult), encoding: .utf8), "chunk-b")
    }

    func testDoesNotRecopyWhenAlreadyCached() throws {
        let source = try makeSourceFile(contents: "chunk-c")
        _ = cache.stableFileURL(chunkID: "chunk-c", sourceURL: source)
        try "mutated".write(to: source, atomically: true, encoding: .utf8)

        let secondResult = cache.stableFileURL(chunkID: "chunk-c", sourceURL: source)

        XCTAssertEqual(try String(contentsOf: XCTUnwrap(secondResult), encoding: .utf8), "chunk-c")
    }

    func testReturnsNilWhenNoSourceAndNothingCached() {
        XCTAssertNil(cache.stableFileURL(chunkID: "missing", sourceURL: nil))
    }

    func testReturnsNilWhenSourceURLPointsToMissingFile() {
        let ghostURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")

        XCTAssertNil(cache.stableFileURL(chunkID: "ghost", sourceURL: ghostURL))
    }

    private func makeSourceFile(contents: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".mp4")
        try contents.write(to: url, atomically: true, encoding: .utf8)
        return url
    }
}
