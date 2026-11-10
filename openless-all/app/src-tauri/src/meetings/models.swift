import CryptoKit
import Foundation

// Revisions are fixed independently of the SDK. Opening Meetings never downloads weights.
enum MeetingModelID: String, CaseIterable, Codable {
    case parakeet, nemotron, live
    var repository: String {
        switch self {
        case .parakeet: return "FluidInference/parakeet-tdt-0.6b-v3-coreml"
        case .nemotron: return "altic-dev/nemotron-3-diarization-coreml"
        case .live: return "FluidInference/parakeet-realtime-eou-120m-coreml"
        }
    }
    var revision: String {
        switch self {
        case .parakeet: return "7dd20fe6b1797d35f5e3307e8b1732d9a178edfe"
        case .nemotron: return "8976c3c40a752cd6468a08f2aa08626770bc048f"
        case .live: return "40a23f4c0b333aa17ad8c0f2ea47ec2347f2f355"
        }
    }
    var license: String {
        switch self {
        case .parakeet: return "CC-BY-4.0"
        case .nemotron: return "OpenMDW-1.1"
        case .live: return "NVIDIA Open Model License"
        }
    }
    var requiredPaths: [String] {
        let names: [String]
        switch self {
        case .parakeet: names = ["Preprocessor", "Encoder", "Decoder", "JointDecision"]
        case .live: names = ["streaming_encoder", "decoder", "joint_decision"]
        case .nemotron: return ["nemotron_3_diarization.mlpackage/Manifest.json", "nemotron_3_diarization.mlpackage/Data/com.apple.CoreML/model.mlmodel", "nemotron_3_diarization.mlpackage/Data/com.apple.CoreML/weights/weight.bin", "learnable_sil_emb.f32"]
        }
        return names.flatMap { name in ["coremldata.bin", "metadata.json", "model.mil", "weights/weight.bin"].map { "\(name).mlmodelc/\($0)" } }
            + [self == .parakeet ? "parakeet_vocab.json" : "vocab.json"]
    }

    func localPath(_ remote: String) -> String? {
        guard !remote.hasPrefix("/"), !remote.split(separator: "/").contains("..") else { return nil }
        switch self {
        case .parakeet:
            let models = ["Preprocessor.mlmodelc/", "Encoder.mlmodelc/", "Decoder.mlmodelc/", "JointDecision.mlmodelc/"]
            return models.contains(where: remote.hasPrefix) || ["parakeet_v3_vocab.json", "parakeet_vocab.json", "config.json", "README.md", "LICENSE"].contains(remote) ? remote : nil
        case .nemotron:
            return remote.hasPrefix("nemotron_3_diarization.mlpackage/") || ["learnable_sil_emb.f32", "config.json", "README.md", "LICENSE"].contains(remote) ? remote : nil
        case .live:
            if ["README.md", "LICENSE", "LICENSE.txt"].contains(remote) { return remote }
            guard remote.hasPrefix("160ms/") else { return nil }
            let path = String(remote.dropFirst(6))
            let models = ["streaming_encoder.mlmodelc/", "decoder.mlmodelc/", "joint_decision.mlmodelc/"]
            return models.contains(where: path.hasPrefix) || path == "vocab.json" ? path : nil
        }
    }
}

private struct ModelFile: Codable {
    let path: String
    let size: Int64
    let digest: String
    let sha256: Bool
}
private struct ModelReceipt: Codable {
    let repository: String
    let revision: String
    let files: [ModelFile]
}
private struct TreeEntry: Decodable {
    struct LFS: Decodable { let oid: String }
    let type: String
    let path: String
    let size: Int64?
    let oid: String?
    let lfs: LFS?
}

final class MeetingModelStore: @unchecked Sendable {
    static let shared = MeetingModelStore()
    private let sessionConfiguration: URLSessionConfiguration
    private let lock = NSLock()
    private var job: Task<Void, Never>?
    private var downloading: MeetingModelID?
    private var completed: Int64 = 0
    private var total: Int64 = 0
    private var error: String?

    init(sessionConfiguration: URLSessionConfiguration = .ephemeral) {
        self.sessionConfiguration = sessionConfiguration.copy() as! URLSessionConfiguration
    }

    static var supported: Bool {
        #if arch(arm64)
        return true
        #else
        return false
        #endif
    }

    func status(root: URL) -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return ["supported": Self.supported, "downloading": downloading?.rawValue as Any? ?? NSNull(),
            "completedBytes": completed, "totalBytes": total, "error": error as Any? ?? NSNull(),
            "echoSupported": ProcessInfo.processInfo.operatingSystemVersion.majorVersion >= 15,
            "liveSupported": Self.supported && ProcessInfo.processInfo.physicalMemory >= 8 * 1024 * 1024 * 1024,
            "items": MeetingModelID.allCases.map { model in
                ["id": model.rawValue, "ready": (try? receipt(model, root: root)) != nil,
                 "license": model.license, "repository": model.repository, "revision": model.revision] as [String: Any]
            }]
    }

    func start(_ model: MeetingModelID, root: URL) throws {
        guard Self.supported else { throw MediaFailure(message: "Os modelos locais exigem Apple Silicon.") }
        lock.lock(); defer { lock.unlock() }
        guard job == nil else { throw MediaFailure(message: "Aguarde ou cancele o download atual.") }
        downloading = model; completed = 0; total = 0; error = nil
        job = Task.detached(priority: .utility) { [self] in
            do { try await install(model, root: root) }
            catch {
                let cancelled = Task.isCancelled || error is CancellationError || (error as? URLError)?.code == .cancelled
                lock.withLock { self.error = cancelled ? "Download cancelado; você pode tentar novamente." : error.localizedDescription }
            }
            lock.withLock { job = nil; downloading = nil }
        }
    }

    func cancel() { lock.lock(); let pending = job; lock.unlock(); pending?.cancel() }

    func remove(_ model: MeetingModelID, root: URL) throws {
        lock.lock(); defer { lock.unlock() }
        guard job == nil else { throw MediaFailure(message: "Cancele o download antes de excluir modelos.") }
        let directory = root.appendingPathComponent(model.rawValue, isDirectory: true)
        if FileManager.default.fileExists(atPath: directory.path) { try FileManager.default.removeItem(at: directory) }
        error = nil
    }

    func validated(_ model: MeetingModelID, root: URL) throws -> URL {
        let receipt = try receipt(model, root: root)
        let directory = root.appendingPathComponent(model.rawValue, isDirectory: true)
        for file in receipt.files {
            try Task.checkCancellation()
            guard try hash(directory.appendingPathComponent(file.path), size: file.size, sha256: file.sha256) == file.digest else {
                throw MediaFailure(message: "Modelo local danificado. Exclua-o e baixe novamente.")
            }
        }
        return directory
    }

    private func receipt(_ model: MeetingModelID, root: URL) throws -> ModelReceipt {
        let directory = root.appendingPathComponent(model.rawValue, isDirectory: true)
        let url = directory.appendingPathComponent("installed.json")
        guard try url.resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey]).isSymbolicLink != true,
              (try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? Int.max) < 4_194_304 else {
            throw MediaFailure(message: "Comprovante de instalação de modelo inválido.")
        }
        let result = try JSONDecoder().decode(ModelReceipt.self, from: Data(contentsOf: url))
        guard result.repository == model.repository, result.revision == model.revision,
              !result.files.isEmpty, result.files.count < 4096,
              Set(model.requiredPaths).isSubset(of: Set(result.files.map(\.path))) else {
            throw MediaFailure(message: "Baixe os modelos locais antes de transcrever.")
        }
        for file in result.files {
            guard !file.path.hasPrefix("/"), !file.path.split(separator: "/").contains(".."), file.size > 0 else {
                throw MediaFailure(message: "Caminho de modelo inválido.")
            }
            let properties = try directory.appendingPathComponent(file.path).resourceValues(forKeys: [.fileSizeKey, .isSymbolicLinkKey])
            guard properties.isSymbolicLink != true, Int64(properties.fileSize ?? 0) == file.size else {
                throw MediaFailure(message: "Modelo incompleto. Exclua-o e baixe novamente.")
            }
        }
        return result
    }

    private func hash(_ url: URL, size: Int64, sha256: Bool) throws -> String {
        let handle = try FileHandle(forReadingFrom: url); defer { try? handle.close() }
        var strong = SHA256(); var git = Insecure.SHA1()
        git.update(data: Data("blob \(size)\0".utf8))
        while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
            try Task.checkCancellation()
            if sha256 { strong.update(data: data) } else { git.update(data: data) }
        }
        return sha256 ? strong.finalize().map { String(format: "%02x", $0) }.joined()
            : git.finalize().map { String(format: "%02x", $0) }.joined()
    }

    private func install(_ model: MeetingModelID, root: URL) async throws {
        let manager = FileManager.default
        try manager.createDirectory(at: root, withIntermediateDirectories: true, attributes: [.posixPermissions: 0o700])
        let stage = root.appendingPathComponent("download-\(model.rawValue)", isDirectory: true)
        try manager.createDirectory(at: stage, withIntermediateDirectories: true)
        let session = URLSession(configuration: sessionConfiguration)
        defer { session.invalidateAndCancel() }
        var listing: URL? = URL(string: "https://huggingface.co/api/models/\(model.repository)/tree/\(model.revision)?recursive=true&expand=true&limit=100")!
        var files: [(remote: String, file: ModelFile)] = []
        for _ in 0..<64 {
            guard let page = listing else { break }
            try Task.checkCancellation()
            let (data, response) = try await session.data(from: page)
            guard let response = response as? HTTPURLResponse, response.statusCode == 200, data.count < 8_388_608 else {
                throw MediaFailure(message: "Não foi possível consultar os arquivos do modelo.")
            }
            for item in try JSONDecoder().decode([TreeEntry].self, from: data) where item.type == "file" {
                guard let path = model.localPath(item.path), let size = item.size, size > 0, size < 12 * 1024 * 1024 * 1024,
                      let digest = item.lfs?.oid ?? item.oid else { continue }
                files.append((item.path, ModelFile(path: path, size: size,
                    digest: digest.replacingOccurrences(of: "sha256:", with: ""), sha256: item.lfs != nil)))
            }
            listing = nil
            if let link = response.value(forHTTPHeaderField: "Link"),
               let range = link.range(of: "<([^>]+)>; rel=\"next\"", options: .regularExpression),
               let candidate = URL(string: String(link[range]).components(separatedBy: ">")[0].dropFirst().description),
               candidate.scheme == "https", candidate.host == "huggingface.co",
               candidate.path.hasPrefix("/api/models/\(model.repository)/tree/\(model.revision)") { listing = candidate }
        }
        guard listing == nil, !files.isEmpty, files.count < 4096,
              Set(model.requiredPaths).isSubset(of: Set(files.map { $0.file.path })),
              files.reduce(Int64(0), { $0 + $1.file.size }) < 12 * 1024 * 1024 * 1024 else {
            throw MediaFailure(message: "Lista de arquivos do modelo inválida ou incompleta.")
        }
        lock.withLock { total = files.reduce(0) { $0 + $1.file.size } }
        var receipts: [ModelFile] = []
        for entry in files {
            try Task.checkCancellation()
            let destination = stage.appendingPathComponent(entry.file.path)
            try manager.createDirectory(at: destination.deletingLastPathComponent(), withIntermediateDirectories: true)
            let validExisting = (try? destination.resourceValues(forKeys: [.fileSizeKey]).fileSize) == Int(entry.file.size)
                && (try? hash(destination, size: entry.file.size, sha256: entry.file.sha256)) == entry.file.digest
            if !validExisting {
                let base = URL(string: "https://huggingface.co/\(model.repository)/resolve/\(model.revision)/")!
                let (temporary, response) = try await session.download(from: base.appendingPathComponent(entry.remote))
                guard let response = response as? HTTPURLResponse, response.statusCode == 200,
                      try hash(temporary, size: entry.file.size, sha256: entry.file.sha256) == entry.file.digest else {
                    throw MediaFailure(message: "O arquivo baixado não corresponde ao modelo publicado.")
                }
                if manager.fileExists(atPath: destination.path) { try manager.removeItem(at: destination) }
                try manager.moveItem(at: temporary, to: destination)
            }
            receipts.append(entry.file)
            lock.withLock { completed += entry.file.size }
        }
        try Task.checkCancellation()
        let receipt = ModelReceipt(repository: model.repository, revision: model.revision, files: receipts)
        try JSONEncoder().encode(receipt).write(to: stage.appendingPathComponent("installed.json"), options: .atomic)
        let destination = root.appendingPathComponent(model.rawValue, isDirectory: true)
        if manager.fileExists(atPath: destination.path) {
            // Keep the installed version until the complete replacement is ready.
            _ = try manager.replaceItemAt(destination, withItemAt: stage)
        } else { try manager.moveItem(at: stage, to: destination) }
    }
}
