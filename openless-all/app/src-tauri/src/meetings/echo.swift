import CoreMedia
import Foundation

// Uses FluidVoice's pinned WebRTC AEC3 bridge and clock-attested, bounded joiner.
// Invalid inputs fall back to microphone audio; they never become silently missing speech.
final class MeetingEchoFilter {
    private var joiner = MeetingAECStreamJoiner()
    private let processor: MeetingAECProcessor
    private let output: (CMSampleBuffer) throws -> Void
    private let token = MeetingAECStreamToken(generation: 1, identity: 1)
    private var bypass = false
    private var warning: String?
    private var processedFrames: UInt64 = 0

    init(output: @escaping (CMSampleBuffer) throws -> Void) throws {
        processor = try MeetingAECProcessor()
        self.output = output
    }

    func render(_ buffer: CMSampleBuffer) throws { try consume(buffer, kind: .render) }
    func capture(_ buffer: CMSampleBuffer) throws { try consume(buffer, kind: .capture) }

    private func consume(_ buffer: CMSampleBuffer, kind: MeetingAECInputKind) throws {
        if bypass {
            if kind == .capture { try output(buffer) }
            return
        }
        switch MeetingAECPCMAdapter.extract(buffer, kind: kind, stream: token) {
        case .success(let block): try handle(joiner.append(block))
        case .failure(let error):
            try handle(joiner.flush(reason: error)); bypass = true
            warning = "Cancelamento de eco indisponível (\(error.localizedDescription)); áudio original preservado."
            if kind == .capture { try output(buffer) }
        }
    }

    private func emit(_ samples: [Float], at time: CMTime) throws {
        guard let buffer = MeetingAECPCMAdapter.synthesize(samples: samples, presentationTime: time) else {
            throw MediaFailure(message: "Não foi possível preservar o áudio do microfone durante o processamento de eco.")
        }
        try output(buffer)
    }

    private func handle(_ emissions: [MeetingAECJoinerEmission]) throws {
        let wasBypassing = bypass
        for emission in emissions {
            switch emission {
            case .paired(let pair):
                if bypass { try emit(pair.capture.samples, at: pair.capture.presentationTime); continue }
                let selected: [Float]
                do {
                    let result = try processor.process(render: pair.render.samples, capture: pair.capture.samples)
                    if pair.clockAttested && pair.pairedFrameCount > MeetingAECConstants.attestationFrames {
                        selected = result.samples
                        processedFrames += 1
                    } else { selected = pair.capture.samples }
                } catch {
                    bypass = true
                    warning = "O cancelamento de eco foi interrompido; o áudio original foi preservado."
                    selected = pair.capture.samples
                }
                // Storage failures propagate; an I/O error must not retry a partially written frame.
                try emit(selected, at: pair.capture.presentationTime)
            case .bypass(let slice, let failure):
                try emit(slice.samples, at: slice.presentationTime)
                if failure != .stopped {
                    bypass = true
                    warning = "Cancelamento de eco em modo original (\(failure.localizedDescription)); gravação preservada."
                }
            case .reset(let failure):
                if failure != .stopped {
                    bypass = true
                    warning = "A linha do tempo do áudio mudou (\(failure.localizedDescription)); gravação original preservada."
                }
            }
        }
        if !wasBypassing && bypass { try handle(joiner.flush()) }
    }

    func finish() throws { try handle(joiner.flush()) }

    func status() -> [String: Any] {
        ["enabled": true, "active": !bypass && processedFrames > 0,
         "processedFrames": processedFrames, "warning": warning as Any? ?? NSNull(),
         "upstreamRevision": processor.upstreamRevision, "configurationId": processor.configurationID]
    }
}
