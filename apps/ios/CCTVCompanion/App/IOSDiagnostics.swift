import CCTVKit
import Foundation

/// Mirrors the Mac app's writeDiagnostic/appendDiagnostic convention so WebRTC
/// receiver events (already emitted via its `diagnostics` callback but previously
/// wired to nothing on iOS) land in a file the app group container that can be
/// pulled via Xcode's "Download Container..." even on a TestFlight/Release build.
enum IOSDiagnostics {
    static func append(_ line: String, filename: String) {
        guard let appGroupURL = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: CKSchema.appGroupIdentifier) else {
            return
        }
        let resultURL = appGroupURL.appendingPathComponent(filename)
        let data = Data(line.appending("\n").utf8)
        if FileManager.default.fileExists(atPath: resultURL.path),
           let handle = try? FileHandle(forWritingTo: resultURL) {
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: data)
            try? handle.close()
        } else {
            try? data.write(to: resultURL, options: .atomic)
        }
    }
}
