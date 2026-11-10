import Foundation
import XCTest
@testable import OpenLessMeetings

final class MeetingImportCancellationTests: XCTestCase {
    func testCancellingDecoderTerminatesItAndKeepsFinalizedWavBlocks() async throws {
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let decoder = directory.appendingPathComponent("decoder-fixture")
        // A deterministic child process tests cancellation/pipe/ledger behavior, not codecs.
        // It publishes over 60 seconds of PCM immediately and then waits for termination.
        try Data("""
        #!/usr/bin/python3
        import sys, time
        sys.stdout.buffer.write(bytes(2_000_000))
        sys.stdout.buffer.flush()
        time.sleep(30)
        """.utf8).write(to: decoder)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: decoder.path)
        let task = Task {
            try await importWithFFmpeg(path: "decoder-fixture-input", directory: directory, executable: decoder)
        }
        let receipt = directory.appendingPathComponent("media.json")
        for _ in 0..<300 {
            if FileManager.default.fileExists(atPath: receipt.path) { break }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        task.cancel()
        do { _ = try await task.value; XCTFail("Cancelled decoding must not be admitted as a successful import") }
        catch is CancellationError { /* Cancellation is the expected result. */ }
        let blocks = try XCTUnwrap(JSONSerialization.jsonObject(with: Data(contentsOf: receipt)) as? [[String: Any]])
        XCTAssertFalse(blocks.isEmpty)
        for block in blocks {
            let path = try XCTUnwrap(block["relativePath"] as? String)
            XCTAssertTrue(FileManager.default.fileExists(atPath: directory.appendingPathComponent(path).path))
        }
    }
}
