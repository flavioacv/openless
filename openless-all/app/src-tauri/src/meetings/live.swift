import AVFoundation
import CoreML
import FluidAudio
import Foundation

// The multilingual model is offline ASR. Re-decode a bounded window every three seconds,
// keep the last second provisional, and publish only words beyond the committed time.
struct MeetingCaptionWindow {
    static let sampleRate = 16_000
    static let maximumSamples = 12 * sampleRate
    private(set) var samples: [Float] = []
    private(set) var start: Double = 0
    private var received = 0
    private var committedThrough = -Double.infinity
    private var lastCommittedWord = ""

    mutating func append(_ input: [Float], at time: Double) {
        if samples.isEmpty { start = time }
        samples.append(contentsOf: input)
        received += input.count
        let excess = max(0, samples.count - Self.maximumSamples)
        if excess > 0 {
            samples.removeFirst(excess)
            start += Double(excess) / Double(Self.sampleRate)
        }
    }

    mutating func takeAudio(final: Bool = false) -> [Float]? {
        guard !samples.isEmpty, final || received >= 3 * Self.sampleRate else { return nil }
        received = 0
        return samples
    }

    mutating func admit(_ words: [TimedTranscriptWord], final: Bool = false) -> (confirmed: String, partial: String) {
        let duration = Double(samples.count) / Double(Self.sampleRate)
        var valid = words.filter {
            $0.startTime.isFinite && $0.endTime.isFinite && $0.startTime >= 0 &&
            $0.endTime > $0.startTime && $0.endTime <= duration + 0.05 &&
            start + $0.endTime > committedThrough + 0.02
        }
        // Re-decoding context may move the end of the already published boundary word.
        // Remove that word only if its text matches and its time overlaps committed audio;
        // genuine adjacent repetitions ("muito muito") remain separate words.
        if let first = valid.first,
           first.text.lowercased().trimmingCharacters(in: .punctuationCharacters) == lastCommittedWord,
           start + first.startTime < committedThrough - 0.05 {
            committedThrough = max(committedThrough, start + first.endTime)
            valid.removeFirst()
        }
        let confirmed = valid.filter { final || $0.endTime <= duration - 1 }
        let partial = valid.filter { !final && $0.endTime > duration - 1 }
        if let last = confirmed.last {
            committedThrough = start + last.endTime
            lastCommittedWord = last.text.lowercased().trimmingCharacters(in: .punctuationCharacters)
        }
        return (confirmed.map(\.text).joined(separator: " "), partial.map(\.text).joined(separator: " "))
    }
}

private final class MeetingMultilingualCaptions {
    let manager: AsrManager
    var window = MeetingCaptionWindow()

    init(manager: AsrManager) { self.manager = manager }

    func process(_ samples: [Float], at time: Double, final: Bool = false) async throws -> (confirmed: String, partial: String)? {
        if !samples.isEmpty { window.append(samples, at: time) }
        guard let audio = window.takeAudio(final: final) else { return nil }
        try Task.checkCancellation()
        let result = try await manager.transcribe(audio, source: .system)
        guard let timings = result.tokenTimings else {
            if result.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return ("", "") }
            throw MediaFailure(message: "O modelo não retornou tempos para atualizar as legendas. A gravação foi preservada.")
        }
        return window.admit(WordAudioChunkExtractor.words(from: timings), final: final)
    }

    func reset() async throws {
        window = MeetingCaptionWindow()
        try await manager.resetDecoderState(for: .system)
    }
}

// Capture writes audio first. This bounded queue may degrade captions but never discards recording.
final class MeetingLiveTranscriber: @unchecked Sendable {
    private struct Sample { let kind: String; let samples: [Float]; let start: Double }
    private let lock = NSLock()
    private var queue: [Sample] = []
    private var worker: Task<Void, Never>?
    private var stopping = false
    private var partials: [String: String] = [:]
    private var turns: [[String: Any]] = []
    private var warning: String?
    private var pendingResets: Set<String> = []
    // Only the single drain worker accesses these positions; preserve them between batches.
    private var ends: [String: Double] = [:]
    private let engines: [String: StreamingEouAsrManager]
    private let multilingual: [String: MeetingMultilingualCaptions]
    private let logURL: URL

    private init(engines: [String: StreamingEouAsrManager], multilingual: [String: MeetingMultilingualCaptions] = [:], directory: URL) {
        self.engines = engines
        self.multilingual = multilingual
        logURL = directory.appendingPathComponent("live.jsonl")
    }

    static func prepare(root: URL, directory: URL, online: Bool, language: String) async throws -> MeetingLiveTranscriber {
        guard MeetingModelStore.supported, ProcessInfo.processInfo.physicalMemory >= 8 * 1024 * 1024 * 1024 else {
            throw MediaFailure(message: "As legendas locais exigem Apple Silicon e pelo menos 8 GB de memória.")
        }
        let primary = language.lowercased().split(separator: "-").first.map(String.init) ?? ""
        guard ["en", "pt", "es", "fr", "de"].contains(primary) else {
            throw MediaFailure(message: "As legendas locais aceitam português, inglês, espanhol, francês e alemão.")
        }
        if primary != "en" {
            let folder = try MeetingModelStore.shared.validated(.parakeet, root: root)
            let models = try await AsrModels.loadLocalOnly(from: folder, version: .v3)
            var prepared: [String: MeetingMultilingualCaptions] = [:]
            do {
                for kind in online ? ["microphone", "application"] : ["microphone"] {
                    try Task.checkCancellation()
                    let manager = AsrManager(config: .default)
                    do { try await manager.initialize(models: models) }
                    catch { await manager.cleanup(); throw error }
                    prepared[kind] = MeetingMultilingualCaptions(manager: manager)
                }
            } catch {
                for engine in prepared.values { await engine.manager.cleanup() }
                throw error
            }
            return MeetingLiveTranscriber(engines: [:], multilingual: prepared, directory: directory)
        }
        let folder = try MeetingModelStore.shared.validated(.live, root: root)
        var engines: [String: StreamingEouAsrManager] = [:]
        for kind in online ? ["microphone", "application"] : ["microphone"] {
            try Task.checkCancellation()
            let configuration = MLModelConfiguration(); configuration.computeUnits = .cpuAndNeuralEngine
            let engine = StreamingEouAsrManager(configuration: configuration, chunkSize: .ms160)
            try await engine.loadModels(modelDir: folder)
            engines[kind] = engine
        }
        let result = MeetingLiveTranscriber(engines: engines, directory: directory)
        for (kind, engine) in engines {
            await engine.setPartialCallback { [weak result] text in result?.updatePartial(kind, text: text) }
            await engine.setEouCallback { [weak result] text in result?.commit(kind, text: text) }
        }
        return result
    }

    func offer(kind: String, buffer: AVAudioPCMBuffer, start: Double) {
        guard let channel = buffer.int16ChannelData?[0], buffer.frameLength > 0 else { return }
        lock.lock(); defer { lock.unlock() }
        guard !stopping else { return }
        guard queue.count < 32 else {
            warning = "As legendas não acompanharam o áudio. A gravação foi preservada; gere a transcrição final ao encerrar."
            return
        }
        let samples = (0..<Int(buffer.frameLength)).map { Float(channel[$0]) / 32768 }
        queue.append(Sample(kind: kind, samples: samples, start: start))
        if worker == nil { worker = Task.detached(priority: .userInitiated) { [self] in await drain() } }
    }

    private func drain() async {
        while true {
            let next: Sample? = lock.withLock {
                guard !queue.isEmpty else { worker = nil; return nil }
                return queue.removeFirst()
            }
            guard let sample = next else { return }
            do {
                if let engine = multilingual[sample.kind] {
                    if let end = ends[sample.kind], abs(sample.start - end) > 0.2 {
                        try await engine.reset()
                        lock.withLock { warning = "Houve uma lacuna nas legendas; gere a transcrição final para revisar todo o áudio salvo." }
                    }
                    if let text = try await engine.process(sample.samples, at: sample.start) {
                        commit(sample.kind, text: text.confirmed, reset: false)
                        updatePartial(sample.kind, text: text.partial)
                    }
                    ends[sample.kind] = sample.start + Double(sample.samples.count) / 16_000
                    continue
                }
                guard let engine = engines[sample.kind] else { continue }
                if let end = ends[sample.kind], abs(sample.start - end) > 0.2 {
                    await engine.reset()
                    updatePartial(sample.kind, text: "")
                }
                let format = AVAudioFormat(commonFormat: .pcmFormatFloat32, sampleRate: 16_000, channels: 1, interleaved: false)!
                guard let buffer = AVAudioPCMBuffer(pcmFormat: format, frameCapacity: AVAudioFrameCount(sample.samples.count)),
                      let output = buffer.floatChannelData?[0] else { throw MediaFailure(message: "Não foi possível preparar o áudio das legendas.") }
                buffer.frameLength = AVAudioFrameCount(sample.samples.count)
                sample.samples.withUnsafeBufferPointer { output.update(from: $0.baseAddress!, count: $0.count) }
                try await engine.appendAudio(buffer)
                try await engine.processBufferedAudio()
                if takeReset(sample.kind) { await engine.reset() }
                ends[sample.kind] = sample.start + Double(sample.samples.count) / 16_000
            } catch {
                lock.withLock { warning = error.localizedDescription }
                if let engine = engines[sample.kind] { await engine.reset() }
                if let engine = multilingual[sample.kind] {
                    do { try await engine.reset() }
                    catch { lock.withLock { warning = error.localizedDescription } }
                }
            }
        }
    }

    private func updatePartial(_ kind: String, text: String) {
        lock.lock(); partials[kind] = String(text.prefix(8000)); lock.unlock()
    }

    private func commit(_ kind: String, text: String, reset: Bool = true) {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return }
        lock.lock(); defer { lock.unlock() }
        let turn: [String: Any] = ["kind": kind, "text": text, "draft": true]
        turns.append(turn)
        if turns.count > 200 { turns.removeFirst(turns.count - 200) }
        partials[kind] = ""
        if reset { pendingResets.insert(kind) }
        do {
            var data = try JSONSerialization.data(withJSONObject: turn); data.append(10)
            if !FileManager.default.fileExists(atPath: logURL.path) { try Data().write(to: logURL, options: .atomic) }
            let file = try FileHandle(forWritingTo: logURL)
            defer { try? file.close() }
            try file.seekToEnd(); try file.write(contentsOf: data)
        } catch { warning = "As legendas não puderam ser salvas: \(error.localizedDescription)" }
    }

    private func takeReset(_ kind: String) -> Bool {
        lock.lock(); defer { lock.unlock() }
        return pendingResets.remove(kind) != nil
    }

    func status() -> [String: Any] {
        lock.lock(); defer { lock.unlock() }
        return ["enabled": true, "partials": partials, "turns": turns, "warning": warning as Any? ?? NSNull()]
    }

    func finish() async {
        let pending = lock.withLock { stopping = true; return worker }
        await pending?.value
        for (kind, engine) in multilingual {
            do {
                if let text = try await engine.process([], at: 0, final: true) {
                    commit(kind, text: text.confirmed, reset: false)
                    updatePartial(kind, text: "")
                }
            } catch { lock.withLock { warning = error.localizedDescription } }
            await engine.manager.cleanup()
        }
        for (kind, engine) in engines {
            do { let text = try await engine.finish(); if !takeReset(kind) { commit(kind, text: text) } }
            catch { lock.withLock { warning = error.localizedDescription } }
            await engine.reset()
        }
    }
}
