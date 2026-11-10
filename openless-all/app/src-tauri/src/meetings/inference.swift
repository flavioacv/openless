import AVFoundation
import CoreML
import CryptoKit
import FluidAudio
import Foundation

struct MeetingVoiceTurn {
    let slot: Int
    let start: Double
    let end: Double
}

// Alignment is independent of inference and is tested with overlapping/missing voice intervals.
func meetingSpeaker(for start: Double, end: Double, turns: [MeetingVoiceTurn]) -> Int? {
    guard start.isFinite, end.isFinite, end > start else { return nil }
    let scores = turns.compactMap { turn -> (Int, Double)? in
        let overlap = min(end, turn.end) - max(start, turn.start)
        return overlap > 0 ? (turn.slot, overlap) : nil
    }.sorted { $0.1 > $1.1 }
    guard let best = scores.first, best.1 >= (end - start) * 0.5 else { return nil }
    if scores.dropFirst().contains(where: { $0.0 != best.0 && $0.1 >= best.1 * 0.8 }) { return nil }
    return best.0
}

private func diarizeMeetingFile(_ path: URL, root: URL) async throws -> [MeetingVoiceTurn] {
    let directory = try MeetingModelStore.shared.validated(.nemotron, root: root)
    let data = try Data(contentsOf: directory.appendingPathComponent("learnable_sil_emb.f32"))
    guard data.count == 2048,
          SHA256.hash(data: data).map({ String(format: "%02x", $0) }).joined()
            == "d4417b3c0eabdf7c47032fac2b5b5a7ee83d819a6ddda8fd8eaf74e2b5cc4ac7" else {
        throw MediaFailure(message: "A referência de silêncio do Nemotron está danificada.")
    }
    let silence = stride(from: 0, to: data.count, by: 4).map { offset in
        let bits = data.withUnsafeBytes { raw in raw.loadUnaligned(fromByteOffset: offset, as: UInt32.self) }
        return Float(bitPattern: UInt32(littleEndian: bits))
    }
    let config = try SortformerConfig.nemotron(spkcacheUpdatePeriod: 300,
        spkcacheSilFramesPerSpk: 1, predScoreThreshold: 0.25, learnedSilenceEmbedding: silence)
    let configuration = MLModelConfiguration(); configuration.computeUnits = .cpuAndGPU
    let models = try await SortformerModels.load(config: config,
        mainModelPath: directory.appendingPathComponent("nemotron_3_diarization.mlpackage"), configuration: configuration)
    let diarizer = SortformerDiarizer(config: config); diarizer.initialize(models: models)
    defer { diarizer.cleanup() }
    let file = try AVAudioFile(forReading: path)
    guard file.processingFormat.sampleRate == 16_000, file.processingFormat.channelCount == 1,
          let buffer = AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 32_000) else {
        throw MediaFailure(message: "A diarização exige áudio mono de 16 kHz.")
    }
    while file.framePosition < file.length {
        try Task.checkCancellation()
        guard !isMediaCancelled() else { throw CancellationError() }
        try file.read(into: buffer)
        guard let data = buffer.floatChannelData?[0] else { throw MediaFailure(message: "Áudio de análise inválido.") }
        _ = try diarizer.process(samples: UnsafeBufferPointer(start: data, count: Int(buffer.frameLength)))
    }
    let duration = Double(file.length) / file.processingFormat.sampleRate
    let requiredFrames = Int(ceil(duration / Double(config.frameDurationSeconds)))
    // Streaming Nemotron needs right context, including for files shorter than one chunk.
    // Pad only model context, then clip its output to the original duration.
    let silenceContext = [Float](repeating: 0, count: 32_000)
    for _ in 0..<32 {
        if diarizer.numFramesProcessed >= requiredFrames { break }
        try Task.checkCancellation()
        _ = try diarizer.process(samples: silenceContext)
    }
    guard diarizer.numFramesProcessed >= requiredFrames else {
        throw MediaFailure(message: "A diarização não conseguiu finalizar todo o áudio. A gravação foi preservada.")
    }
    _ = try diarizer.finalizeSession()
    return diarizer.timeline.speakers.sorted { $0.key < $1.key }.flatMap { slot, speaker in
        speaker.finalizedSegments.compactMap { segment in
            let start = max(0, Double(segment.startTime))
            let end = min(duration, Double(segment.endTime))
            return segment.isFinalized && end > start ? MeetingVoiceTurn(slot: slot, start: start, end: end) : nil
        }
    }
}

func transcribeMeetingLocally(path: URL, root: URL) async throws -> [String: Any] {
    guard MeetingModelStore.supported else { throw MediaFailure(message: "A transcrição local exige Apple Silicon.") }
    // Nemotron weights leave this scope before Parakeet is loaded. Track state is fresh per file.
    let turns = try await diarizeMeetingFile(path, root: root)
    try Task.checkCancellation()
    let directory = try MeetingModelStore.shared.validated(.parakeet, root: root)
    let models = try await AsrModels.loadLocalOnly(from: directory, version: .v3)
    let manager = AsrManager(config: .default)
    do {
        try await manager.initialize(models: models)
        let audio = try AVAudioFile(forReading: path)
        // The SDK streaming entry point rejects files shorter than one second.
        let result: ASRResult
        if Double(audio.length) < audio.processingFormat.sampleRate {
            result = try await manager.transcribe(path, source: .system)
        } else {
            result = try await manager.transcribeStreaming(path, source: .system)
        }
        try Task.checkCancellation()
        guard let timings = result.tokenTimings, !timings.isEmpty else {
            throw MediaFailure(message: "O modelo local não retornou tempos de fala. O áudio foi preservado.")
        }
        let words = WordAudioChunkExtractor.words(from: timings)
        let output: [[String: Any]] = words.map { word in
            var result: [String: Any] = ["text": word.text, "start": word.startTime, "end": word.endTime, "type": "word"]
            if let slot = meetingSpeaker(for: word.startTime, end: word.endTime, turns: turns) {
                result["speaker_id"] = "speaker_\(slot)"
            }
            return result
        }
        await manager.cleanup()
        return ["words": output]
    } catch {
        await manager.cleanup()
        throw error
    }
}
