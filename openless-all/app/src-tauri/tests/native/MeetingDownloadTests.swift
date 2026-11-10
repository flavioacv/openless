import CryptoKit
import Foundation
import XCTest
@testable import OpenLessMeetings

// Real URLSession requests and the production installer, with HTTP bytes supplied in-process.
// No external server, credentials, socket permissions or model inference is involved here.
private final class MeetingDownloadProtocol: URLProtocol, @unchecked Sendable {
    static let state = NSLock()
    static var corrupt = false
    static var slow = false
    static var requests: [String: Int] = [:]
    private let lock = NSLock()
    private var stopped = false

    static func contents(_ path: String) -> Data { Data("fixture:\(path)".utf8) }
    static func digest(_ data: Data) -> String { SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined() }
    override class func canInit(with request: URLRequest) -> Bool { request.url?.host == "huggingface.co" }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        let isTree = url.path.contains("/tree/")
        let path = url.path.components(separatedBy: "/resolve/").last?.split(separator: "/").dropFirst().joined(separator: "/") ?? ""
        let settings = Self.state.withLock { () -> (Bool, Bool) in
            Self.requests[path, default: 0] += 1
            return (Self.corrupt, Self.slow)
        }
        let data: Data
        if isTree {
            let entries: [[String: Any]] = MeetingModelID.parakeet.requiredPaths.map { file in
                let bytes = Self.contents(file)
                return ["type": "file", "path": file, "size": bytes.count, "lfs": ["oid": Self.digest(bytes)]]
            }
            data = try! JSONSerialization.data(withJSONObject: entries)
        } else {
            data = settings.0 ? Data(repeating: 0, count: Self.contents(path).count) : Self.contents(path)
        }
        let deliver: @Sendable () -> Void = { [self] in
            lock.withLock {
                guard !stopped else { return }
                let response = HTTPURLResponse(url: url, statusCode: 200, httpVersion: "HTTP/1.1",
                    headerFields: ["Content-Length": String(data.count)])!
                client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
                client?.urlProtocol(self, didLoad: data)
                client?.urlProtocolDidFinishLoading(self)
            }
        }
        if settings.1 && !isTree && path != MeetingModelID.parakeet.requiredPaths.first {
            DispatchQueue.global().asyncAfter(deadline: .now() + 0.5, execute: deliver)
        } else { deliver() }
    }

    override func stopLoading() { lock.withLock { stopped = true } }
}

final class MeetingDownloadTests: XCTestCase {
    override func setUp() {
        MeetingDownloadProtocol.state.withLock {
            MeetingDownloadProtocol.corrupt = false; MeetingDownloadProtocol.slow = false
            MeetingDownloadProtocol.requests = [:]
        }
    }

    private func store() -> MeetingModelStore {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [MeetingDownloadProtocol.self]
        return MeetingModelStore(sessionConfiguration: configuration)
    }

    private func complete(_ store: MeetingModelStore, root: URL) async throws -> [String: Any] {
        for _ in 0..<400 {
            let state = store.status(root: root)
            if !(state["downloading"] is String) { return state }
            try await Task.sleep(nanoseconds: 10_000_000)
        }
        store.cancel()
        throw NSError(domain: "MeetingDownloadTests", code: 1, userInfo: [NSLocalizedDescriptionKey: "Timed out waiting for download completion"])
    }

    func testDownloadInstallsOnlyVerifiedFilesAndRemovalPreservesOtherData() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = store()
        try store.start(.parakeet, root: root)
        let result = try await complete(store, root: root)
        XCTAssertFalse(result["error"] is String, "\(result)")
        let installed = try store.validated(.parakeet, root: root)
        XCTAssertTrue(FileManager.default.fileExists(atPath: installed.appendingPathComponent("installed.json").path))
        XCTAssertEqual(result["completedBytes"] as? Int64, result["totalBytes"] as? Int64)
        let keep = root.appendingPathComponent("keep.txt")
        try Data("keep".utf8).write(to: keep)
        try store.remove(.parakeet, root: root)
        XCTAssertFalse(FileManager.default.fileExists(atPath: installed.path))
        XCTAssertEqual(try Data(contentsOf: keep), Data("keep".utf8))
    }

    func testCorruptReplacementDoesNotDestroyTheInstalledModel() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = store()
        try store.start(.parakeet, root: root)
        _ = try await complete(store, root: root)
        _ = try store.validated(.parakeet, root: root)
        MeetingDownloadProtocol.state.withLock { MeetingDownloadProtocol.corrupt = true }
        try store.start(.parakeet, root: root)
        let result = try await complete(store, root: root)
        XCTAssertTrue(result["error"] is String)
        _ = try store.validated(.parakeet, root: root)
    }

    func testCancelProducesPortugueseErrorAndCanRestart() async throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        defer { try? FileManager.default.removeItem(at: root) }
        let store = store()
        MeetingDownloadProtocol.state.withLock { MeetingDownloadProtocol.slow = true }
        try store.start(.parakeet, root: root)
        for _ in 0..<200 {
            if (store.status(root: root)["completedBytes"] as? Int64 ?? 0) > 0 { break }
            try await Task.sleep(nanoseconds: 5_000_000)
        }
        store.cancel()
        let cancelled = try await complete(store, root: root)
        XCTAssertEqual(cancelled["error"] as? String, "Download cancelado; você pode tentar novamente.")
        XCTAssertGreaterThan(cancelled["completedBytes"] as? Int64 ?? 0, 0)
        XCTAssertThrowsError(try store.validated(.parakeet, root: root))
        MeetingDownloadProtocol.state.withLock { MeetingDownloadProtocol.slow = false }
        try store.start(.parakeet, root: root)
        let result = try await complete(store, root: root)
        XCTAssertFalse(result["error"] is String, "\(result)")
        _ = try store.validated(.parakeet, root: root)
        let requests = MeetingDownloadProtocol.state.withLock {
            MeetingDownloadProtocol.requests[MeetingModelID.parakeet.requiredPaths[0]] ?? 0
        }
        XCTAssertEqual(requests, 1, "Restart must reuse a fully verified file rather than downloading it again")
    }
}
