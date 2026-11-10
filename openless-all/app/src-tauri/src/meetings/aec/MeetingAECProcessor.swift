// Adapted from FluidVoice; see vendor/licenses/FluidVoice-GPL-3.0.txt.
import FluidAEC3Bridge
import Foundation
import Darwin

nonisolated protocol MeetingAECProcessing: AnyObject, Sendable {
    var upstreamRevision: String { get }
    var configurationID: String { get }
    func process(render: [Float], capture: [Float]) throws
        -> (samples: [Float], statistics: MeetingAECBridgeStatistics)
    func reset() throws
}

/// Single-owner Swift wrapper around the opaque C ABI. The runtime calls it only on the shared
/// SCK callback queue; the bridge itself performs reverse-stream then capture-stream processing.
final nonisolated class MeetingAECProcessor: MeetingAECProcessing, @unchecked Sendable {
    private var engine: OpaquePointer?
    private let library: UnsafeMutableRawPointer
    private typealias Create = @convention(c) () -> OpaquePointer?
    private typealias Destroy = @convention(c) (OpaquePointer?) -> Void
    private typealias Reset = @convention(c) (OpaquePointer?) -> Int32
    private typealias Process = @convention(c) (OpaquePointer?, UnsafePointer<Float>?, UnsafePointer<Float>?, UnsafeMutablePointer<Float>?, UnsafeMutablePointer<FVAEC3Stats>?) -> Int32
    private typealias Text = @convention(c) () -> UnsafePointer<CChar>?
    private let destroy: Destroy
    private let resetEngine: Reset
    private let processFrame: Process

    let upstreamRevision: String
    let configurationID: String

    init(libraryURL: URL? = nil) throws {
        guard #available(macOS 15.0, *) else { throw MeetingAECFailure.bridgeInitialization }
        let file = "libOpenLessMeetingAEC.dylib"
        let candidates = [libraryURL] + [Bundle.main.privateFrameworksURL, Bundle.main.resourceURL,
                          Bundle.main.executableURL?.deletingLastPathComponent()].compactMap { $0?.appendingPathComponent(file) }
        guard let location = candidates.compactMap({ $0 })
            .first(where: { FileManager.default.fileExists(atPath: $0.path) }),
              let handle = dlopen(location.path, RTLD_NOW | RTLD_LOCAL) else {
            throw MeetingAECFailure.bridgeInitialization
        }
        var retained = false
        defer { if !retained { dlclose(handle) } }
        func symbol<T>(_ name: String, _ type: T.Type) throws -> T {
            guard let address = dlsym(handle, name.replacingOccurrences(of: "fv_aec3_", with: "openless_aec3_")) else { throw MeetingAECFailure.bridgeInitialization }
            return unsafeBitCast(address, to: type)
        }
        let revision = try symbol("fv_aec3_upstream_revision", Text.self)
        let configuration = try symbol("fv_aec3_configuration_id", Text.self)
        let create = try symbol("fv_aec3_create_48k_mono", Create.self)
        let destroy = try symbol("fv_aec3_destroy", Destroy.self)
        let reset = try symbol("fv_aec3_reset", Reset.self)
        let process = try symbol("fv_aec3_process_10ms", Process.self)
        guard let revisionPointer = revision(), let configurationPointer = configuration() else {
            throw MeetingAECFailure.bridgeInitialization
        }
        let upstreamRevision = String(cString: revisionPointer)
        let configurationID = String(cString: configurationPointer)
        guard upstreamRevision == MeetingAECConstants.provenance.upstreamRevision,
              configurationID == MeetingAECConstants.provenance.bridgeConfigurationID,
              let engine = create() else { throw MeetingAECFailure.bridgeInitialization }
        self.upstreamRevision = upstreamRevision
        self.configurationID = configurationID
        self.engine = engine; self.library = handle
        self.destroy = destroy; self.resetEngine = reset; self.processFrame = process
        retained = true
    }

    deinit {
        if let engine = self.engine { destroy(engine) }
        dlclose(library)
    }

    func reset() throws {
        guard let engine = self.engine else { throw MeetingAECFailure.bridgeInitialization }
        guard resetEngine(engine) == 0 else {
            throw MeetingAECFailure.bridgeInitialization
        }
    }

    func process(render: [Float], capture: [Float]) throws
        -> (samples: [Float], statistics: MeetingAECBridgeStatistics)
    {
        guard let engine = self.engine,
              render.count == MeetingAECConstants.frameSamples,
              capture.count == MeetingAECConstants.frameSamples,
              render.allSatisfy(\.isFinite),
              capture.allSatisfy(\.isFinite)
        else { throw MeetingAECFailure.bridgeProcessing }

        var output = [Float](repeating: 0, count: MeetingAECConstants.frameSamples)
        var stats = FVAEC3Stats(
            render_frames: 0,
            capture_frames: 0,
            resets: 0,
            estimated_delay_ms: -1,
            residual_echo_likelihood: .nan
        )
        let status = render.withUnsafeBufferPointer { renderBuffer in
            capture.withUnsafeBufferPointer { captureBuffer in
                output.withUnsafeMutableBufferPointer { outputBuffer in
                    processFrame(
                        engine,
                        renderBuffer.baseAddress,
                        captureBuffer.baseAddress,
                        outputBuffer.baseAddress,
                        &stats
                    )
                }
            }
        }
        guard status == 0 else {
            if status == 4 {
                throw MeetingAECFailure.bridgeNonFiniteOutput
            }
            throw MeetingAECFailure.bridgeProcessing
        }
        guard output.allSatisfy({ $0.isFinite && $0 >= -1 && $0 <= 1 }) else {
            throw MeetingAECFailure.bridgeNonFiniteOutput
        }

        return (
            output,
            MeetingAECBridgeStatistics(
                renderFrames: stats.render_frames,
                captureFrames: stats.capture_frames,
                resets: stats.resets,
                estimatedDelayMilliseconds: stats.estimated_delay_ms >= 0
                    ? Int(stats.estimated_delay_ms)
                    : nil,
                residualEchoLikelihood: stats.residual_echo_likelihood.isFinite
                    ? stats.residual_echo_likelihood
                    : nil
            )
        )
    }
}
