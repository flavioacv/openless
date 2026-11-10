// Native media boundary for OpenLess meetings. Uses public macOS 14 APIs only.
// Audio is written in bounded, independently recoverable WAV blocks. No video is saved.
import AVFoundation
import AudioToolbox
import CoreMedia
import Foundation
import ScreenCaptureKit

struct MediaFailure: LocalizedError {
    let message: String
    var errorDescription: String? { message }
}

private let cancellationLock = NSLock()
private var mediaCancelled = false
private var nativeOperationTask: Task<Void, Never>?
func isMediaCancelled() -> Bool {
    cancellationLock.lock(); defer { cancellationLock.unlock() }
    return mediaCancelled
}
private func resetMediaCancellation() {
    cancellationLock.lock(); mediaCancelled = false; cancellationLock.unlock()
}

@_cdecl("openless_meeting_media_cancel")
public func openlessMeetingMediaCancel() {
    cancellationLock.lock(); mediaCancelled = true; let pending = nativeOperationTask; cancellationLock.unlock()
    pending?.cancel()
}

private struct AudioBlock: Codable {
    let kind: String
    let relativePath: String
    let startMs: UInt64
    let durationMs: UInt64
    let byteCount: UInt64
}

private final class MediaLedger {
    let directory: URL
    var blocks: [AudioBlock] = []
    init(directory: URL) { self.directory = directory }

    func append(_ block: AudioBlock) throws {
        blocks.append(block)
        let data = try JSONEncoder().encode(blocks)
        try data.write(to: directory.appendingPathComponent("media.json"), options: .atomic)
    }
}

private final class BlockWriter {
    static let sampleRate: Double = 16_000
    static let framesPerBlock: Int64 = 60 * 16_000
    let ledger: MediaLedger
    let kind: String
    var onCanonical: ((AVAudioPCMBuffer, Double) -> Void)?
    let target = AVAudioFormat(commonFormat: .pcmFormatInt16, sampleRate: sampleRate,
                               channels: 1, interleaved: true)!
    private var converter: AVAudioConverter?
    private var inputFormat: AVAudioFormat?
    private var file: AVAudioFile?
    private var fileURL: URL?
    private var blockStart: Double = 0
    private var frames: Int64 = 0
    private var nextTime: Double?
    private var nextInputTime: Double?

    init(ledger: MediaLedger, kind: String) { self.ledger = ledger; self.kind = kind }

    func append(_ input: AVAudioPCMBuffer, at seconds: Double) throws {
        guard seconds.isFinite, input.frameLength > 0 else { return }
        if input.format == target {
            if converter != nil { try complete() }
            try appendCanonical(input, at: max(0, seconds))
            nextInputTime = seconds + Double(input.frameLength) / input.format.sampleRate
            return
        }
        let inputJump = nextInputTime.map { abs(seconds - $0) > 0.15 } ?? false
        if inputFormat != input.format || converter == nil || inputJump {
            try complete()
            nextTime = max(0, seconds)
            inputFormat = input.format
            converter = AVAudioConverter(from: input.format, to: target)
        }
        guard let converter else { throw MediaFailure(message: "Não foi possível converter o formato do áudio.") }
        let capacity = AVAudioFrameCount(ceil(Double(input.frameLength) * Self.sampleRate / input.format.sampleRate) + 64)
        guard let output = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: capacity) else {
            throw MediaFailure(message: "Não foi possível reservar memória para converter o áudio.")
        }
        var supplied = false
        var conversionError: NSError?
        let status = converter.convert(to: output, error: &conversionError) { _, result in
            if supplied { result.pointee = .noDataNow; return nil }
            supplied = true
            result.pointee = .haveData
            return input
        }
        if let conversionError { throw conversionError }
        guard status != .error else { throw MediaFailure(message: "Falha na conversão do áudio.") }
        // Resampling can retain output between callbacks. Anchor discontinuities to input
        // timestamps, then advance output by actual written samples, including the drain.
        // Using the next input timestamp here invents gaps at low sample rates (e.g. 8 kHz).
        try appendCanonical(output, at: nextTime ?? max(0, seconds))
        nextInputTime = seconds + Double(input.frameLength) / input.format.sampleRate
    }

    func appendCanonical(_ buffer: AVAudioPCMBuffer, at seconds: Double) throws {
        guard buffer.frameLength > 0, let samples = buffer.int16ChannelData?[0] else { return }
        var alignedStart = seconds
        // A clock jump creates a new span instead of pretending missing audio was recorded.
        if let nextTime {
            if abs(seconds - nextTime) > 0.15 { try finish() }
            else { alignedStart = nextTime }
        }
        var offset = 0
        while offset < Int(buffer.frameLength) {
            if file == nil {
                blockStart = alignedStart + Double(offset) / Self.sampleRate
                let name = "\(kind)-\(UUID().uuidString).wav"
                let url = ledger.directory.appendingPathComponent(name)
                fileURL = url
                file = try AVAudioFile(forWriting: url, settings: target.settings,
                                       commonFormat: .pcmFormatInt16, interleaved: true)
                frames = 0
            }
            let count = min(Int(buffer.frameLength) - offset, Int(Self.framesPerBlock - frames))
            guard let slice = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: AVAudioFrameCount(count)),
                  let destination = slice.int16ChannelData?[0] else {
                throw MediaFailure(message: "Não foi possível reservar memória para gravar o áudio.")
            }
            slice.frameLength = AVAudioFrameCount(count)
            destination.update(from: samples.advanced(by: offset), count: count)
            try file?.write(from: slice)
            offset += count
            frames += Int64(count)
            if frames == Self.framesPerBlock { try finish() }
        }
        onCanonical?(buffer, alignedStart)
        nextTime = alignedStart + Double(buffer.frameLength) / Self.sampleRate
    }

    func finish() throws {
        guard let url = fileURL, file != nil else { return }
        file = nil // close AVAudioFile and finalize the WAV header before publishing its receipt.
        fileURL = nil
        guard frames > 0 else { try FileManager.default.removeItem(at: url); return }
        let handle = try FileHandle(forWritingTo: url)
        try handle.synchronize()
        try handle.close()
        let size = try url.resourceValues(forKeys: [.fileSizeKey]).fileSize ?? 0
        try ledger.append(AudioBlock(kind: kind, relativePath: url.lastPathComponent,
            startMs: UInt64((blockStart * 1000).rounded()),
            durationMs: UInt64(frames * 1000 / 16_000), byteCount: UInt64(size)))
        frames = 0
    }

    func complete() throws {
        if let converter {
            for _ in 0..<64 {
                guard let tail = AVAudioPCMBuffer(pcmFormat: target, frameCapacity: 8192) else {
                    throw MediaFailure(message: "Não foi possível reservar memória para finalizar o áudio.")
                }
                var error: NSError?
                let status = converter.convert(to: tail, error: &error) { _, state in
                    state.pointee = .endOfStream
                    return nil
                }
                if let error { throw error }
                if tail.frameLength > 0 { try appendCanonical(tail, at: nextTime ?? 0) }
                if status == .endOfStream || tail.frameLength == 0 {
                    self.converter = nil
                    break
                }
            }
            if self.converter != nil { throw MediaFailure(message: "Não foi possível finalizar a conversão do áudio com segurança.") }
        }
        try finish()
    }
}

func audioBuffer(_ sample: CMSampleBuffer) throws -> AVAudioPCMBuffer {
    guard let description = CMSampleBufferGetFormatDescription(sample) else {
        throw MediaFailure(message: "O formato do áudio capturado é inválido.")
    }
    let format = AVAudioFormat(cmAudioFormatDescription: description)
    var size = 0
    var retained: CMBlockBuffer?
    var status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample,
        bufferListSizeNeededOut: &size, bufferListOut: nil, bufferListSize: 0,
        blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
        flags: 0, blockBufferOut: nil)
    guard status == noErr, size >= MemoryLayout<AudioBufferList>.size else {
        throw MediaFailure(message: "Não foi possível verificar as amostras de áudio.")
    }
    let raw = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 16)
    defer { raw.deallocate() }
    let list = raw.bindMemory(to: AudioBufferList.self, capacity: 1)
    status = CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(sample,
        bufferListSizeNeededOut: nil, bufferListOut: list, bufferListSize: size,
        blockBufferAllocator: nil, blockBufferMemoryAllocator: nil,
        flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
        blockBufferOut: &retained)
    guard status == noErr,
          let result = AVAudioPCMBuffer(pcmFormat: format,
              frameCapacity: AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))) else {
        throw MediaFailure(message: "Não foi possível ler as amostras de áudio.")
    }
    result.frameLength = AVAudioFrameCount(CMSampleBufferGetNumSamples(sample))
    let source = UnsafeMutableAudioBufferListPointer(list)
    defer { withExtendedLifetime(retained) {} }
    let destination = UnsafeMutableAudioBufferListPointer(result.mutableAudioBufferList)
    guard source.count == destination.count else { throw MediaFailure(message: "Os canais de áudio são incompatíveis.") }
    for index in source.indices {
        guard let from = source[index].mData, let to = destination[index].mData,
              source[index].mDataByteSize <= destination[index].mDataByteSize else {
            throw MediaFailure(message: "O tamanho da amostra de áudio capturada é inválido.")
        }
        memcpy(to, from, Int(source[index].mDataByteSize))
    }
    return result
}

private func checkMediaStatus(_ status: OSStatus, _ operation: String) throws {
    guard status == noErr else {
        throw NSError(domain: NSOSStatusErrorDomain, code: Int(status),
                      userInfo: [NSLocalizedDescriptionKey: "\(operation) (código \(status))."])
    }
}

// ExtAudioFile reports codec failures as OSStatus. AVAudioFile's framePosition getter can
// raise an Objective-C exception for the same unsupported AAC, escaping Swift's do/catch.
private func importAudioFile(path: String, directory: URL) throws -> [String: Any] {
    var opened: ExtAudioFileRef?
    try checkMediaStatus(ExtAudioFileOpenURL(URL(fileURLWithPath: path) as CFURL, &opened), "Não foi possível abrir o áudio")
    guard let source = opened else { throw MediaFailure(message: "O arquivo de áudio não pôde ser aberto.") }
    defer { ExtAudioFileDispose(source) }
    let ledger = MediaLedger(directory: directory)
    let writer = BlockWriter(ledger: ledger, kind: "imported")
    var format = writer.target.streamDescription.pointee
    try checkMediaStatus(ExtAudioFileSetProperty(source, kExtAudioFileProperty_ClientDataFormat,
        UInt32(MemoryLayout<AudioStreamBasicDescription>.size), &format), "O decodificador nativo não aceita este formato de áudio")
    guard let buffer = AVAudioPCMBuffer(pcmFormat: writer.target, frameCapacity: 32_768) else {
        throw MediaFailure(message: "Não foi possível reservar memória para importar o áudio.")
    }
    var position: Int64 = 0
    do {
        while true {
            if isMediaCancelled() || Task.isCancelled { throw CancellationError() }
            var count: UInt32 = buffer.frameCapacity
            buffer.frameLength = buffer.frameCapacity
            try checkMediaStatus(ExtAudioFileRead(source, &count, buffer.mutableAudioBufferList), "Não foi possível decodificar o áudio")
            guard count > 0 else { break }
            buffer.frameLength = count
            try writer.appendCanonical(buffer, at: Double(position) / BlockWriter.sampleRate)
            position += Int64(count)
        }
    } catch {
        do { try writer.complete() }
        catch let storageError {
            throw MediaFailure(message: "\(error.localizedDescription); não foi possível finalizar o áudio parcial: \(storageError.localizedDescription)")
        }
        throw error
    }
    try writer.complete()
    guard !ledger.blocks.isEmpty else { throw MediaFailure(message: "O arquivo de áudio está vazio.") }
    return ["blocks": try JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger.blocks)), "video": false]
}

private final class LocalMediaProcess: @unchecked Sendable {
    let process = Process()
    let output = Pipe()
    let diagnostics = Pipe()
    private let lock = NSLock()
    private var cancelled = false

    init(executable: URL, path: String) {
        process.executableURL = executable
        process.arguments = ["-nostdin", "-hide_banner", "-loglevel", "info",
            "-protocol_whitelist", "file,pipe", "-i", path,
            "-map", "0:a:0", "-vn", "-ac", "1", "-ar", "16000", "-f", "s16le", "pipe:1"]
        process.standardInput = FileHandle.nullDevice
        process.standardOutput = output
        process.standardError = diagnostics
    }

    func start() throws {
        try lock.withLock {
            guard !cancelled else { throw CancellationError() }
            try process.run()
        }
    }

    func cancel() {
        lock.withLock {
            cancelled = true
            if process.isRunning { process.terminate() }
        }
    }

    func readDiagnostics() -> (text: String, video: Bool) {
        var retained = Data(), pending = Data(), video = false
        do {
            while let bytes = try diagnostics.fileHandleForReading.read(upToCount: 4096), !bytes.isEmpty {
                if retained.count < 8192 { retained.append(bytes.prefix(8192 - retained.count)) }
                pending.append(bytes)
                while let newline = pending.firstIndex(of: 10) {
                    let line = String(decoding: pending[..<newline], as: UTF8.self).trimmingCharacters(in: .whitespaces)
                    if line.hasPrefix("Stream #"), line.contains("Video:") { video = true }
                    pending.removeSubrange(...newline)
                }
                if pending.count > 16_384 { pending.removeFirst(pending.count - 16_384) }
            }
        } catch { return ("Não foi possível ler o diagnóstico do decodificador local: \(error.localizedDescription)", video) }
        return (String(decoding: retained, as: UTF8.self), video)
    }
}

private func installedFFmpeg() -> URL? {
    // Optional existing installation only: never download software, invoke a shell, or execute
    // a program from the media directory. Native decoding remains the default path.
    guard ProcessInfo.processInfo.environment["OPENLESS_MEETING_NATIVE_ONLY"] != "1" else { return nil }
    return ["/opt/homebrew/bin/ffmpeg", "/usr/local/bin/ffmpeg", "/usr/bin/ffmpeg"].first {
        FileManager.default.isExecutableFile(atPath: $0)
    }.map { URL(fileURLWithPath: $0) }
}

func importWithFFmpeg(path: String, directory: URL, executable: URL) async throws -> [String: Any] {
    let child = LocalMediaProcess(executable: executable, path: path)
    return try await withTaskCancellationHandler {
        try child.start()
        let diagnostics = Task.detached { child.readDiagnostics() }
        let ledger = MediaLedger(directory: directory)
        let writer = BlockWriter(ledger: ledger, kind: "imported")
        var retained = Data(), frames: Int64 = 0
        do {
            while let bytes = try child.output.fileHandleForReading.read(upToCount: 65_536), !bytes.isEmpty {
                try Task.checkCancellation()
                guard !isMediaCancelled() else { throw CancellationError() }
                retained.append(bytes)
                let count = retained.count / 2
                guard count > 0 else { continue }
                guard let buffer = AVAudioPCMBuffer(pcmFormat: writer.target, frameCapacity: AVAudioFrameCount(count)),
                      let samples = buffer.int16ChannelData?[0] else {
                    throw MediaFailure(message: "Não foi possível reservar memória para o áudio decodificado.")
                }
                buffer.frameLength = AVAudioFrameCount(count)
                retained.withUnsafeBytes { memcpy(samples, $0.baseAddress!, count * 2) }
                try writer.appendCanonical(buffer, at: Double(frames) / BlockWriter.sampleRate)
                frames += Int64(count)
                retained.removeFirst(count * 2)
            }
            child.process.waitUntilExit()
            let diagnostic = await diagnostics.value
            try Task.checkCancellation()
            guard !isMediaCancelled() else { throw CancellationError() }
            guard child.process.terminationStatus == 0, retained.isEmpty else {
                throw MediaFailure(message: "O decodificador local não conseguiu importar o áudio (código \(child.process.terminationStatus)). \(diagnostic.text)")
            }
            try writer.complete()
            guard !ledger.blocks.isEmpty else { throw MediaFailure(message: "O arquivo não contém áudio utilizável.") }
            return ["blocks": try JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger.blocks)),
                    "video": diagnostic.video, "decoder": "ffmpeg"]
        } catch {
            child.cancel()
            // Let a decoder blocked on stdout observe a broken pipe before waiting for it.
            // This also prevents a storage error from leaving the child waiting on our reader.
            try? child.output.fileHandleForReading.close()
            child.process.waitUntilExit()
            _ = await diagnostics.value
            do { try writer.complete() }
            catch let storageError {
                throw MediaFailure(message: "\(error.localizedDescription); não foi possível finalizar o áudio parcial: \(storageError.localizedDescription)")
            }
            throw error
        }
    } onCancel: { child.cancel() }
}

private func importMedia(path: String, directory: URL) async throws -> [String: Any] {
    do { return try await importMediaNatively(path: path, directory: directory) }
    catch {
        if Task.isCancelled || isMediaCancelled() || error is CancellationError { throw CancellationError() }
        // Never mix a retry beginning at zero with already finalized native chunks. Keep those
        // recoverable blocks and report the original failure instead of duplicating speech.
        if FileManager.default.fileExists(atPath: directory.appendingPathComponent("media.json").path) { throw error }
        guard let executable = installedFFmpeg() else {
            let reason = error.localizedDescription
            let separator = reason.hasSuffix(".") ? " " : ". "
            throw NSError(domain: "OpenLess.Media", code: 1, userInfo: [
                NSLocalizedDescriptionKey: "O macOS não conseguiu decodificar este arquivo: \(reason)\(separator)O FFmpeg opcional não está disponível ou foi desativado. O original foi preservado.",
                NSUnderlyingErrorKey: error,
            ])
        }
        return try await importWithFFmpeg(path: path, directory: directory, executable: executable)
    }
}

private func importMediaNatively(path: String, directory: URL) async throws -> [String: Any] {
    let audioExtensions = ["wav", "mp3", "m4a", "aac", "aiff", "aif", "caf", "flac", "ogg", "opus"]
    if audioExtensions.contains(URL(fileURLWithPath: path).pathExtension.lowercased()) {
        return try importAudioFile(path: path, directory: directory)
    }
    let asset = AVURLAsset(url: URL(fileURLWithPath: path))
    let tracks = try await asset.loadTracks(withMediaType: .audio)
    guard let track = tracks.first else { throw MediaFailure(message: "O arquivo não contém uma faixa de áudio.") }
    let formats = try await track.load(.formatDescriptions)
    let alreadyPCM = formats.first.flatMap { CMAudioFormatDescriptionGetStreamBasicDescription($0)?.pointee.mFormatID } == kAudioFormatLinearPCM
    let reader = try AVAssetReader(asset: asset)
    let output = AVAssetReaderTrackOutput(track: track, outputSettings: alreadyPCM ? nil : [
        AVFormatIDKey: kAudioFormatLinearPCM, AVLinearPCMBitDepthKey: 32,
        AVLinearPCMIsFloatKey: true, AVLinearPCMIsBigEndianKey: false,
        AVLinearPCMIsNonInterleaved: false,
    ])
    guard reader.canAdd(output) else { throw MediaFailure(message: "O decodificador não é compatível com esta mídia.") }
    reader.add(output)
    let ledger = MediaLedger(directory: directory)
    let writer = BlockWriter(ledger: ledger, kind: "imported")
    guard reader.startReading() else { throw reader.error ?? MediaFailure(message: "Não foi possível abrir a mídia.") }
    while let sample = output.copyNextSampleBuffer() {
        if isMediaCancelled() {
            reader.cancelReading()
            try writer.complete()
            throw MediaFailure(message: "Importação cancelada; os blocos finalizados foram preservados.")
        }
        // Empty end/discontinuity markers have no audio format or frames.
        guard CMSampleBufferGetNumSamples(sample) > 0 else { continue }
        try autoreleasepool {
            let time = CMSampleBufferGetPresentationTimeStamp(sample).seconds
            try writer.append(audioBuffer(sample), at: max(0, time))
        }
    }
    try writer.complete()
    guard reader.status == .completed else {
        throw reader.error ?? MediaFailure(message: "A decodificação da mídia foi interrompida.")
    }
    guard !ledger.blocks.isEmpty else { throw MediaFailure(message: "A faixa de áudio está vazia.") }
    let videos = try await asset.loadTracks(withMediaType: .video)
    return ["blocks": try JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger.blocks)),
            "video": !videos.isEmpty]
}

private final class MeetingCapture: NSObject, SCStreamOutput, SCStreamDelegate {
    let queue = DispatchQueue(label: "openless.meeting.audio")
    let ledger: MediaLedger
    let microphone: BlockWriter
    let application: BlockWriter
    var cleanedMicrophone: BlockWriter?
    var echo: MeetingEchoFilter?
    var live: MeetingLiveTranscriber?
    let engine = AVAudioEngine()
    var stream: SCStream?
    var failure: String?
    var origin: Double = 0
    var accepting = true
    private var tapInstalled = false
    private var configurationObserver: NSObjectProtocol?
    private let pendingLock = NSLock()
    private var pendingBuffers = 0

    private func offerMicrophone(_ buffer: AVAudioPCMBuffer, at seconds: Double) {
        guard buffer.frameLength > 0 else { return }
        pendingLock.lock()
        guard pendingBuffers < 16 else {
            pendingLock.unlock()
            queue.async { self.failure = "A gravação não acompanhou a captura; parte do áudio do microfone foi perdida." }
            return
        }
        pendingBuffers += 1
        pendingLock.unlock()
        guard let copy = AVAudioPCMBuffer(pcmFormat: buffer.format, frameCapacity: buffer.frameLength) else {
            pendingLock.lock(); pendingBuffers -= 1; pendingLock.unlock()
            queue.async { self.failure = "Não foi possível copiar o áudio do microfone." }
            return
        }
        copy.frameLength = buffer.frameLength
        let source = UnsafeMutableAudioBufferListPointer(UnsafeMutablePointer(mutating: buffer.audioBufferList))
        let destination = UnsafeMutableAudioBufferListPointer(copy.mutableAudioBufferList)
        for index in source.indices {
            guard index < destination.count, let from = source[index].mData,
                  let to = destination[index].mData,
                  source[index].mDataByteSize <= destination[index].mDataByteSize else {
                pendingLock.lock(); pendingBuffers -= 1; pendingLock.unlock()
                queue.async { self.failure = "Os dados de áudio do microfone são inválidos." }
                return
            }
            memcpy(to, from, Int(source[index].mDataByteSize))
        }
        queue.async {
            defer { self.pendingLock.lock(); self.pendingBuffers -= 1; self.pendingLock.unlock() }
            guard self.accepting, self.failure == nil else { return }
            do { try self.microphone.append(copy, at: seconds) }
            catch { self.failure = error.localizedDescription }
        }
    }

    init(directory: URL) {
        ledger = MediaLedger(directory: directory)
        microphone = BlockWriter(ledger: ledger, kind: "microphone")
        application = BlockWriter(ledger: ledger, kind: "application")
    }

    func start(pid: Int32?, root: URL, language: String, captions: Bool, cancelEcho: Bool) async throws {
        if captions {
            live = try await MeetingLiveTranscriber.prepare(root: root, directory: ledger.directory, online: pid != nil, language: language)
            application.onCanonical = { [weak self] buffer, time in self?.live?.offer(kind: "application", buffer: buffer, start: time) }
        }
        if cancelEcho && pid != nil {
            guard #available(macOS 15.0, *) else {
                throw MediaFailure(message: "O cancelamento de eco com a captura de microfone do sistema exige macOS 15 ou superior.")
            }
            cleanedMicrophone = BlockWriter(ledger: ledger, kind: "microphoneClean")
            cleanedMicrophone?.onCanonical = { [weak self] buffer, time in self?.live?.offer(kind: "microphone", buffer: buffer, start: time) }
            echo = try MeetingEchoFilter { [weak self] sample in
                guard let self else { return }
                try self.cleanedMicrophone?.append(audioBuffer(sample), at: CMSampleBufferGetPresentationTimeStamp(sample).seconds - self.origin)
            }
        } else {
            microphone.onCanonical = { [weak self] buffer, time in self?.live?.offer(kind: "microphone", buffer: buffer, start: time) }
        }
        let granted = await AVCaptureDevice.requestAccess(for: .audio)
        guard granted else { throw MediaFailure(message: "É necessário permitir o acesso ao microfone.") }
        guard !isMediaCancelled() else { throw MediaFailure(message: "O início da gravação foi cancelado.") }
        origin = CMClockGetTime(CMClockGetHostTimeClock()).seconds
        if let pid {
            let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
            guard let app = content.applications.first(where: { $0.processID == pid }),
                  let display = content.displays.first else {
                throw MediaFailure(message: "A aplicação selecionada não está mais disponível.")
            }
            let filter = SCContentFilter(display: display, including: [app], exceptingWindows: [])
            let configuration = SCStreamConfiguration()
            configuration.width = 2; configuration.height = 2
            configuration.minimumFrameInterval = CMTime(value: 1, timescale: 1)
            configuration.showsCursor = false
            configuration.capturesAudio = true
            configuration.sampleRate = 48_000; configuration.channelCount = 1
            if #available(macOS 15.0, *) {
                configuration.captureMicrophone = true
                configuration.microphoneCaptureDeviceID = AVCaptureDevice.default(for: .audio)?.uniqueID
            }
            configuration.excludesCurrentProcessAudio = true
            let capture = SCStream(filter: filter, configuration: configuration, delegate: self)
            try capture.addStreamOutput(self, type: .audio, sampleHandlerQueue: queue)
            if #available(macOS 15.0, *) { try capture.addStreamOutput(self, type: .microphone, sampleHandlerQueue: queue) }
            stream = capture
            try await capture.startCapture()
        }
        if #available(macOS 15.0, *), pid != nil { return }
        let input = engine.inputNode
        let format = input.outputFormat(forBus: 0)
        guard format.sampleRate > 0, format.channelCount > 0 else {
            throw MediaFailure(message: "O microfone está indisponível.")
        }
        input.installTap(onBus: 0, bufferSize: 4096, format: format) { [weak self] buffer, time in
            guard let self else { return }
            self.offerMicrophone(buffer, at: AVAudioTime.seconds(forHostTime: time.hostTime) - self.origin)
        }
        tapInstalled = true
        try engine.start()
        configurationObserver = NotificationCenter.default.addObserver(
            forName: .AVAudioEngineConfigurationChange, object: engine, queue: nil
        ) { [weak self] _ in
            guard let self else { return }
            self.queue.async { self.failure = "A configuração do microfone mudou; finalize a gravação e selecione o dispositivo novamente." }
        }
    }

    func stream(_ stream: SCStream, didOutputSampleBuffer sample: CMSampleBuffer, of type: SCStreamOutputType) {
        guard sample.isValid, CMSampleBufferGetNumSamples(sample) > 0, accepting, failure == nil else { return }
        do {
            if type == .audio {
                try echo?.render(sample)
                try application.append(audioBuffer(sample), at: CMSampleBufferGetPresentationTimeStamp(sample).seconds - origin)
            } else if #available(macOS 15.0, *), type == .microphone {
                try microphone.append(audioBuffer(sample), at: CMSampleBufferGetPresentationTimeStamp(sample).seconds - origin)
                try echo?.capture(sample)
            }
        } catch { failure = error.localizedDescription }
    }

    func stream(_ stream: SCStream, didStopWithError error: Error) {
        queue.async { self.failure = error.localizedDescription }
    }

    func stop() async throws -> [String: Any] {
        if let configurationObserver { NotificationCenter.default.removeObserver(configurationObserver) }
        configurationObserver = nil
        engine.stop()
        if tapInstalled { engine.inputNode.removeTap(onBus: 0); tapInstalled = false }
        if let stream {
            do { try await stream.stopCapture() }
            catch { queue.sync { self.failure = error.localizedDescription } }
        }
        var result = try queue.sync {
            accepting = false
            var errors: [String] = []
            do { try echo?.finish() } catch { errors.append(error.localizedDescription) }
            // One failed writer must not prevent the other source's tail from being saved.
            for writer in [microphone, application, cleanedMicrophone].compactMap({ $0 }) {
                do { try writer.complete() } catch { errors.append(error.localizedDescription) }
            }
            if !errors.isEmpty { failure = ([failure].compactMap { $0 } + errors).joined(separator: "; ") }
            if ledger.blocks.isEmpty { failure = failure ?? "Nenhum áudio foi gravado." }
            var result: [String: Any] = ["blocks": try JSONSerialization.jsonObject(with: JSONEncoder().encode(ledger.blocks))]
            if let failure { result["captureError"] = failure }
            return result
        }
        await live?.finish()
        let info: [String: Any] = ["echoCancellation": echo?.status() as Any? ?? NSNull(), "liveCaptions": live != nil]
        try JSONSerialization.data(withJSONObject: info).write(to: ledger.directory.appendingPathComponent("processing.json"), options: .atomic)
        result["processing"] = info
        if let live { result["live"] = live.status() }
        return result
    }
}

// Calls are serialized by the Rust host; capture callbacks own their dedicated queue.
private var activeCapture: MeetingCapture?

@_cdecl("openless_meeting_media")
public func openlessMeetingMedia(_ request: UnsafePointer<CChar>) -> UnsafeMutablePointer<CChar>? {
    let input = String(cString: request)
    let completed = DispatchSemaphore(value: 0)
    var result: [String: Any] = [:]
    cancellationLock.lock()
    let operation = Task {
        do {
            guard let args = try JSONSerialization.jsonObject(with: Data(input.utf8)) as? [String: Any],
                  let command = args["command"] as? String else { throw MediaFailure(message: "A solicitação de mídia é inválida.") }
            let root = URL(fileURLWithPath: args["modelDirectory"] as? String ?? NSTemporaryDirectory(), isDirectory: true)
            switch command {
            case "modelsStatus": result = MeetingModelStore.shared.status(root: root)
            case "downloadModel", "removeModel":
                guard let id = args["id"] as? String, let model = MeetingModelID(rawValue: id), args["modelDirectory"] != nil else {
                    throw MediaFailure(message: "Modelo local inválido.")
                }
                if command == "downloadModel" { try MeetingModelStore.shared.start(model, root: root) }
                else { try MeetingModelStore.shared.remove(model, root: root) }
                result = MeetingModelStore.shared.status(root: root)
            case "cancelModelDownload": MeetingModelStore.shared.cancel(); result = [:]
            case "transcribeLocal":
                resetMediaCancellation()
                guard let path = args["path"] as? String, args["modelDirectory"] != nil else { throw MediaFailure(message: "Áudio local inválido.") }
                result = try await transcribeMeetingLocally(path: URL(fileURLWithPath: path), root: root)
            case "status":
                if let capture = activeCapture {
                    result = capture.queue.sync {
                        var status: [String: Any] = ["recording": true]
                        if let failure = capture.failure { status["captureError"] = failure }
                        if let echo = capture.echo { status["echo"] = echo.status() }
                        if let live = capture.live { status["live"] = live.status() }
                        return status
                    }
                } else { result = ["recording": false] }
            case "applications":
                let content = try await SCShareableContent.excludingDesktopWindows(true, onScreenWindowsOnly: false)
                result = ["applications": content.applications.filter { $0.processID != getpid() }.map {
                    ["pid": $0.processID, "name": $0.applicationName, "bundleId": $0.bundleIdentifier] as [String: Any]
                }]
            case "import", "start":
                resetMediaCancellation()
                guard let folder = args["directory"] as? String else { throw MediaFailure(message: "A pasta da mídia não foi informada.") }
                let directory = URL(fileURLWithPath: folder, isDirectory: true)
                if command == "import" {
                    guard activeCapture == nil, let path = args["path"] as? String else {
                        throw MediaFailure(message: "Finalize a gravação antes de importar mídia.")
                    }
                    result = try await importMedia(path: path, directory: directory)
                } else {
                    guard activeCapture == nil else { throw MediaFailure(message: "Já existe uma reunião sendo gravada.") }
                    let capture = MeetingCapture(directory: directory)
                    do { try await capture.start(pid: (args["pid"] as? NSNumber)?.int32Value,
                        root: root, language: args["language"] as? String ?? "pt-BR",
                        captions: args["live"] as? Bool ?? false, cancelEcho: args["echoCancellation"] as? Bool ?? false) }
                    catch {
                        let startupError = error
                        do { _ = try await capture.stop() }
                        catch { throw MediaFailure(message: "\(startupError.localizedDescription); falha ao finalizar: \(error.localizedDescription)") }
                        throw startupError
                    }
                    activeCapture = capture
                    result = ["recording": true]
                }
            case "stop":
                guard let capture = activeCapture else { throw MediaFailure(message: "Nenhuma reunião está sendo gravada.") }
                defer { activeCapture = nil }
                result = try await capture.stop()
            default: throw MediaFailure(message: "Esta operação de mídia não é compatível.")
            }
        } catch {
            let nativeError = error as NSError
            result = ["error": (Task.isCancelled || error is CancellationError) ? "Operação cancelada; o áudio finalizado e o arquivo original foram preservados." : error.localizedDescription,
                      "errorDomain": nativeError.domain, "errorCode": nativeError.code]
            if let underlying = nativeError.userInfo[NSUnderlyingErrorKey] as? NSError {
                result["underlyingCode"] = underlying.code
                result["underlyingDomain"] = underlying.domain
            }
        }
        cancellationLock.withLock { nativeOperationTask = nil }
        completed.signal()
    }
    nativeOperationTask = operation; cancellationLock.unlock()
    completed.wait()
    do {
        let data = try JSONSerialization.data(withJSONObject: result)
        return strdup(String(decoding: data, as: UTF8.self))
    } catch { return strdup("{\"error\":\"Cannot encode native media result.\"}") }
}

@_cdecl("openless_meeting_media_free")
public func openlessMeetingMediaFree(_ pointer: UnsafeMutablePointer<CChar>?) { free(pointer) }
