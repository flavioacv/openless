import AVFoundation
import CoreMedia
import FluidAudio
import XCTest
@testable import OpenLessMeetings

final class MeetingNativeTests: XCTestCase {
    func testCapturedSampleBufferIsCopiedBeforeItsBackingStorageIsReleased() throws {
        let values = Array(repeating: Float(0.125), count: 480)
        let sample = try XCTUnwrap(MeetingAECPCMAdapter.synthesize(samples: values,
            presentationTime: CMTime(value: 48_000, timescale: 48_000)))
        let copied = try audioBuffer(sample)
        XCTAssertEqual(copied.frameLength, 480)
        XCTAssertEqual(copied.format.sampleRate, 48_000)
        let channel = try XCTUnwrap(copied.floatChannelData?[0])
        XCTAssertEqual(channel[0], 0.125, accuracy: 0.00001)
        XCTAssertEqual(channel[479], 0.125, accuracy: 0.00001)
    }
    func testPortugueseCaptionsKeepUnstableTailAndNeverPublishTheSameWordTwice() {
        var window = MeetingCaptionWindow()
        window.append(Array(repeating: 0, count: 4 * 16_000), at: 0)
        XCTAssertNotNil(window.takeAudio())
        let words = [
            ("Bom", 0.1, 0.4), ("dia", 0.5, 0.9), ("reunião", 3.2, 3.8)
        ].map { text, start, end in
            // Uses the actual SDK timing type through the admission signature.
            TimedTranscriptWord(text: text, startTime: start, endTime: end, confidence: 1)
        }
        let first = window.admit(words)
        XCTAssertEqual(first.confirmed, "Bom dia")
        XCTAssertEqual(first.partial, "reunião")
        XCTAssertEqual(window.admit(words).confirmed, "")
        let final = window.admit(words, final: true)
        XCTAssertEqual(final.confirmed, "reunião")
        XCTAssertEqual(window.admit(words, final: true).confirmed, "")
    }

    func testCaptionWindowIsBoundedAndRetainsAbsoluteTimeAcrossRollovers() {
        var window = MeetingCaptionWindow()
        window.append(Array(repeating: 0, count: 30 * 16_000), at: 10)
        XCTAssertEqual(window.samples.count, 12 * 16_000)
        XCTAssertEqual(window.start, 28)
        let word = TimedTranscriptWord(text: "prazo", startTime: 5, endTime: 6, confidence: 1)
        XCTAssertEqual(window.admit([word]).confirmed, "prazo")
        window.append(Array(repeating: 0, count: 3 * 16_000), at: 40)
        let repeated = TimedTranscriptWord(text: "prazo", startTime: 2, endTime: 3, confidence: 1)
        XCTAssertEqual(window.admit([repeated]).confirmed, "")
        let invalid = TimedTranscriptWord(text: "inválido", startTime: .nan, endTime: 4, confidence: 1)
        XCTAssertEqual(window.admit([invalid]).confirmed, "")
    }

    func testCaptionTimingDriftDoesNotDuplicateTheBoundaryWordOrRemoveSpokenRepetition() {
        var window = MeetingCaptionWindow()
        window.append(Array(repeating: 0, count: 4 * 16_000), at: 0)
        let first = TimedTranscriptWord(text: "posso", startTime: 0.1, endTime: 0.5, confidence: 1)
        XCTAssertEqual(window.admit([first]).confirmed, "posso")
        let shifted = TimedTranscriptWord(text: "posso", startTime: 0.15, endTime: 0.6, confidence: 1)
        let repeated = TimedTranscriptWord(text: "posso", startTime: 0.65, endTime: 0.9, confidence: 1)
        XCTAssertEqual(window.admit([shifted, repeated]).confirmed, "posso")
    }

    func testRealInstalledModelsTranscribePortugueseAudio() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let audio = environment["OPENLESS_MEETING_SMOKE_AUDIO"],
              let models = environment["OPENLESS_MEETING_SMOKE_MODELS"] else {
            throw XCTSkip("Provide an actual Portuguese mono 16 kHz WAV and installed model directory")
        }
        let result = try await transcribeMeetingLocally(path: URL(fileURLWithPath: audio), root: URL(fileURLWithPath: models))
        let words = try XCTUnwrap(result["words"] as? [[String: Any]])
        XCTAssertGreaterThan(words.count, 2)
        XCTAssertTrue(words.allSatisfy { ($0["end"] as? Double ?? 0) > ($0["start"] as? Double ?? .infinity) })
        XCTAssertTrue(words.contains { $0["speaker_id"] is String }, "Nemotron must assign at least one voice interval")
        print("REAL_PORTUGUESE_TRANSCRIPT", words.compactMap { $0["text"] as? String }.joined(separator: " "))
    }

    func testRealPortugueseCaptionsUseParakeetWithoutTheEnglishEOUModel() async throws {
        let environment = ProcessInfo.processInfo.environment
        guard let audio = environment["OPENLESS_MEETING_SMOKE_AUDIO"],
              let models = environment["OPENLESS_MEETING_SMOKE_MODELS"] else {
            throw XCTSkip("Provide Portuguese audio and downloaded Parakeet weights")
        }
        let directory = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        let live = try await MeetingLiveTranscriber.prepare(root: URL(fileURLWithPath: models), directory: directory,
            online: false, language: "pt-BR")
        let file = try AVAudioFile(forReading: URL(fileURLWithPath: audio), commonFormat: .pcmFormatInt16, interleaved: true)
        let buffer = try XCTUnwrap(AVAudioPCMBuffer(pcmFormat: file.processingFormat, frameCapacity: 48_000))
        while file.framePosition < file.length {
            let start = Double(file.framePosition) / 16_000
            try file.read(into: buffer)
            live.offer(kind: "microphone", buffer: buffer, start: start)
            // Feed file data at a bounded rate; production capture arrives in real time.
            try await Task.sleep(nanoseconds: 100_000_000)
        }
        await live.finish()
        let status = live.status()
        XCTAssertFalse(status["warning"] is String, "\(status)")
        let turns = try XCTUnwrap(status["turns"] as? [[String: Any]])
        XCTAssertFalse(turns.isEmpty)
        print("REAL_PORTUGUESE_CAPTIONS", turns.compactMap { $0["text"] as? String }.joined(separator: " "))
    }

    func testModelPathsNeverEscapeAndOnlyAdmitRuntimeFiles() {
        XCTAssertNil(MeetingModelID.parakeet.localPath("../secret"))
        XCTAssertNil(MeetingModelID.live.localPath("160ms/../secret.mlmodelc/weights.bin"))
        XCTAssertNil(MeetingModelID.live.localPath("320ms/decoder.mlmodelc/model.mil"))
        XCTAssertNil(MeetingModelID.live.localPath("160ms/convert_parakeet_eou.py"))
        XCTAssertEqual(MeetingModelID.live.localPath("160ms/vocab.json"), "vocab.json")
        XCTAssertEqual(MeetingModelID.live.localPath("README.md"), "README.md")
        XCTAssertEqual(MeetingModelID.parakeet.localPath("Encoder.mlmodelc/weights/weight.bin"), "Encoder.mlmodelc/weights/weight.bin")
    }

    func testSpeakerAlignmentDoesNotInventAnIdentityForMissingOrOverlappingSpeech() {
        let first = MeetingVoiceTurn(slot: 0, start: 0, end: 1)
        let second = MeetingVoiceTurn(slot: 1, start: 0.4, end: 1)
        XCTAssertEqual(meetingSpeaker(for: 0.1, end: 0.3, turns: [first, second]), 0)
        XCTAssertNil(meetingSpeaker(for: 0.5, end: 0.8, turns: [first, second]))
        XCTAssertNil(meetingSpeaker(for: 2, end: 2.2, turns: [first]))
    }

    func testEchoJoinerAttestsTheCommonClockAndRetainsBoundedAudio() {
        var joiner = MeetingAECStreamJoiner()
        var attested = false
        var pairs = 0
        let stream = MeetingAECStreamToken(generation: 1, identity: 1)
        for frame in 0..<240 {
            for kind in [MeetingAECInputKind.render, .capture] {
                let block = MeetingAECPCMBlock(kind: kind, stream: stream,
                    presentationTime: CMTime(value: Int64(frame * 480), timescale: 48_000),
                    duration: CMTime(value: 480, timescale: 48_000), samples: Array(repeating: 0, count: 480))
                for emission in joiner.append(block) {
                    if case .paired(let pair) = emission { pairs += 1; attested = attested || pair.clockAttested }
                }
                XCTAssertLessThanOrEqual(joiner.diagnostics.retainedRenderSamples, MeetingAECConstants.maximumSamplesPerInput)
                XCTAssertLessThanOrEqual(joiner.diagnostics.retainedCaptureSamples, MeetingAECConstants.maximumSamplesPerInput)
            }
        }
        XCTAssertGreaterThan(pairs, 200)
        XCTAssertTrue(attested)
    }

    func testActualEchoBridgeMatchesThePinnedRevisionAndProcessesSilence() throws {
        guard #available(macOS 15.0, *) else { throw XCTSkip("AEC3 requires macOS 15 or later") }
        let packaged = URL(fileURLWithPath: #filePath).deletingLastPathComponent()
            .deletingLastPathComponent().deletingLastPathComponent()
            .appendingPathComponent("target/meeting-runtime-resources/libOpenLessMeetingAEC.dylib")
        let library = FileManager.default.fileExists(atPath: packaged.path) ? packaged :
            Bundle(for: Self.self).bundleURL.deletingLastPathComponent()
                .appendingPathComponent("libOpenLessMeetingAEC.dylib")
        let processor = try MeetingAECProcessor(libraryURL: library)
        XCTAssertEqual(processor.upstreamRevision, "d9bd07ba5f614156021df666ba4052ac73cf7953")
        let result = try processor.process(render: Array(repeating: 0, count: 480), capture: Array(repeating: 0, count: 480))
        XCTAssertEqual(result.samples.count, 480)
        XCTAssertTrue(result.samples.allSatisfy(\.isFinite))
        try processor.reset()
    }
}
