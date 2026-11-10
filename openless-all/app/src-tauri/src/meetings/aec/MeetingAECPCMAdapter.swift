// Adapted from FluidVoice; see vendor/licenses/FluidVoice-GPL-3.0.txt.
import AudioToolbox
@preconcurrency import AVFoundation
import CoreMedia
import Foundation

nonisolated enum MeetingAECPCMAdapter {
    static func extract(
        _ sampleBuffer: CMSampleBuffer,
        kind: MeetingAECInputKind,
        stream: MeetingAECStreamToken
    ) -> Result<MeetingAECPCMBlock, MeetingAECFailure> {
        guard CMSampleBufferIsValid(sampleBuffer), CMSampleBufferDataIsReady(sampleBuffer),
              let formatDescription = CMSampleBufferGetFormatDescription(sampleBuffer),
              let asbdPointer = CMAudioFormatDescriptionGetStreamBasicDescription(formatDescription)
        else { return .failure(.invalidSampleBuffer) }

        let presentationTime = CMSampleBufferGetPresentationTimeStamp(sampleBuffer)
        guard presentationTime.isValid, presentationTime.isNumeric,
              CMTimeGetSeconds(presentationTime).isFinite
        else { return .failure(.invalidTimestamp) }

        let frameCount = CMSampleBufferGetNumSamples(sampleBuffer)
        guard frameCount > 0 else { return .failure(.invalidSampleBuffer) }

        let asbd = asbdPointer.pointee
        guard asbd.mFormatID == kAudioFormatLinearPCM,
              asbd.mSampleRate == Double(MeetingAECConstants.sampleRateHz),
              asbd.mChannelsPerFrame > 0,
              asbd.mChannelsPerFrame <= 32,
              asbd.mFramesPerPacket == 1,
              asbd.mFormatFlags & kAudioFormatFlagIsFloat != 0,
              asbd.mFormatFlags & kAudioFormatFlagIsSignedInteger == 0,
              asbd.mFormatFlags & kAudioFormatFlagIsBigEndian == 0,
              asbd.mFormatFlags & kAudioFormatFlagIsPacked != 0,
              asbd.mBitsPerChannel == 32
        else {
            return asbd.mSampleRate == Double(MeetingAECConstants.sampleRateHz)
                ? .failure(.unsupportedFormat)
                : .failure(.unsupportedSampleRate)
        }

        let channels = Int(asbd.mChannelsPerFrame)
        let nonInterleaved = asbd.mFormatFlags & kAudioFormatFlagIsNonInterleaved != 0
        let expectedBytesPerFrame = UInt32(MemoryLayout<Float>.size * (nonInterleaved ? 1 : channels))
        guard asbd.mBytesPerFrame == expectedBytesPerFrame,
              asbd.mBytesPerPacket == expectedBytesPerFrame
        else { return .failure(.unsupportedFormat) }

        let duration = CMSampleBufferGetDuration(sampleBuffer)
        guard duration.isValid, duration.isNumeric, duration > .zero else {
            return .failure(.invalidDuration)
        }
        let nominalDuration = Double(frameCount) / Double(MeetingAECConstants.sampleRateHz)
        let actualDuration = CMTimeGetSeconds(duration)
        guard actualDuration.isFinite,
              abs(actualDuration - nominalDuration) <= 1.5 / Double(MeetingAECConstants.sampleRateHz)
        else { return .failure(.invalidDuration) }

        var requiredSize = 0
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: &requiredSize,
            bufferListOut: nil,
            bufferListSize: 0,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: 0,
            blockBufferOut: nil
        ) == noErr, requiredSize >= MemoryLayout<AudioBufferList>.size
        else { return .failure(.invalidSampleBuffer) }

        let rawList = UnsafeMutableRawPointer.allocate(
            byteCount: requiredSize,
            alignment: MemoryLayout<AudioBufferList>.alignment
        )
        defer { rawList.deallocate() }
        let audioBufferList = rawList.bindMemory(to: AudioBufferList.self, capacity: 1)
        var retainedBlockBuffer: CMBlockBuffer?
        guard CMSampleBufferGetAudioBufferListWithRetainedBlockBuffer(
            sampleBuffer,
            bufferListSizeNeededOut: nil,
            bufferListOut: audioBufferList,
            bufferListSize: requiredSize,
            blockBufferAllocator: nil,
            blockBufferMemoryAllocator: nil,
            flags: UInt32(kCMSampleBufferFlag_AudioBufferList_Assure16ByteAlignment),
            blockBufferOut: &retainedBlockBuffer
        ) == noErr
        else { return .failure(.invalidSampleBuffer) }

        let buffers = UnsafeMutableAudioBufferListPointer(audioBufferList)
        defer { withExtendedLifetime(retainedBlockBuffer) {} }
        guard !buffers.isEmpty,
              buffers.reduce(0, { $0 + Int($1.mNumberChannels) }) == channels
        else { return .failure(.unsupportedFormat) }

        var mono = [Float](repeating: 0, count: frameCount)
        for buffer in buffers {
            let bufferChannels = Int(buffer.mNumberChannels)
            let expectedByteCount = frameCount * bufferChannels * MemoryLayout<Float>.size
            guard bufferChannels > 0,
                  Int(buffer.mDataByteSize) == expectedByteCount,
                  let data = buffer.mData
            else { return .failure(.invalidSampleBuffer) }
            let values = data.assumingMemoryBound(to: Float.self)
            for frame in 0..<frameCount {
                let base = frame * bufferChannels
                for channel in 0..<bufferChannels {
                    let value = values[base + channel]
                    guard value.isFinite else { return .failure(.nonFiniteSamples) }
                    mono[frame] += value
                }
            }
        }
        if channels > 1 {
            let divisor = Float(channels)
            for index in mono.indices {
                mono[index] /= divisor
            }
        }
        guard mono.allSatisfy(\.isFinite) else { return .failure(.nonFiniteSamples) }

        return .success(MeetingAECPCMBlock(
            kind: kind,
            stream: stream,
            presentationTime: presentationTime,
            duration: duration,
            samples: mono,
            sourceFormat: MeetingAECPCMFormat(
                channelCount: channels,
                interleaved: !nonInterleaved
            )
        ))
    }

    /// Produces an owning mono Float32 sample buffer. `presentationTime` is always the source
    /// capture PTS (plus an exact source-sample offset), never an output ordinal.
    static func synthesize(samples: [Float], presentationTime: CMTime) -> CMSampleBuffer? {
        guard !samples.isEmpty,
              samples.allSatisfy(\.isFinite),
              presentationTime.isValid,
              presentationTime.isNumeric,
              let format = AVAudioFormat(
                  commonFormat: .pcmFormatFloat32,
                  sampleRate: Double(MeetingAECConstants.sampleRateHz),
                  channels: 1,
                  interleaved: false
              ),
              let buffer = AVAudioPCMBuffer(
                  pcmFormat: format,
                  frameCapacity: AVAudioFrameCount(samples.count)
              ),
              let channel = buffer.floatChannelData?[0]
        else { return nil }
        buffer.frameLength = AVAudioFrameCount(samples.count)
        channel.update(from: samples, count: samples.count)
        return meetingMicrophoneSynthesizeSampleBuffer(from: buffer, presentationTime: presentationTime)
    }
}

nonisolated func meetingMicrophoneSynthesizeSampleBuffer(
    from buffer: AVAudioPCMBuffer,
    presentationTime: CMTime
) -> CMSampleBuffer? {
    guard buffer.frameLength > 0 else { return nil }
    let frameCount = Int(buffer.frameLength)
    let channelCount = Int(buffer.format.channelCount)
    guard channelCount > 0 else { return nil }

    var asbd = buffer.format.streamDescription.pointee
    // CMSampleBuffer's block buffer below is canonical interleaved LPCM, regardless of whether
    // the tap supplied planar or interleaved AVAudioPCMBuffer storage. Keep the description and
    // payload topology truthful so downstream sinks can validate frame/byte totals.
    asbd.mFormatFlags &= ~kAudioFormatFlagIsNonInterleaved
    asbd.mBytesPerFrame = UInt32(channelCount * MemoryLayout<Float>.size)
    asbd.mBytesPerPacket = asbd.mBytesPerFrame
    var formatDescription: CMAudioFormatDescription?
    let formatStatus = CMAudioFormatDescriptionCreate(
        allocator: kCFAllocatorDefault,
        asbd: &asbd,
        layoutSize: 0,
        layout: nil,
        magicCookieSize: 0,
        magicCookie: nil,
        extensions: nil,
        formatDescriptionOut: &formatDescription
    )
    guard formatStatus == noErr, let formatDescription else { return nil }

    let byteCount = frameCount * channelCount * MemoryLayout<Float>.size
    var interleaved = Data(count: byteCount)
    if buffer.format.isInterleaved {
        guard let source = buffer.audioBufferList.pointee.mBuffers.mData else { return nil }
        interleaved.withUnsafeMutableBytes { destination in
            destination.copyBytes(from: UnsafeRawBufferPointer(start: source, count: byteCount))
        }
    } else {
        guard let channelData = buffer.floatChannelData else { return nil }
        interleaved.withUnsafeMutableBytes { destination in
            // Buffer size and channel topology are validated before this synchronous C call.
            // swiftlint:disable:next force_unwrapping
            let output = destination.baseAddress!.assumingMemoryBound(to: Float.self)
            for frame in 0..<frameCount {
                for channel in 0..<channelCount {
                    output[frame * channelCount + channel] = channelData[channel][frame]
                }
            }
        }
    }

    var blockBuffer: CMBlockBuffer?
    let blockStatus = CMBlockBufferCreateWithMemoryBlock(
        allocator: kCFAllocatorDefault,
        memoryBlock: nil,
        blockLength: byteCount,
        blockAllocator: kCFAllocatorDefault,
        customBlockSource: nil,
        offsetToData: 0,
        dataLength: byteCount,
        flags: kCMBlockBufferAssureMemoryNowFlag,
        blockBufferOut: &blockBuffer
    )
    guard blockStatus == noErr, let blockBuffer else { return nil }

    let copyStatus = interleaved.withUnsafeBytes { bytes in
        CMBlockBufferReplaceDataBytes(
            // Buffer size and channel topology are validated before this synchronous C call.
            // swiftlint:disable:next force_unwrapping
            with: bytes.baseAddress!,
            blockBuffer: blockBuffer,
            offsetIntoDestination: 0,
            dataLength: byteCount
        )
    }
    guard copyStatus == noErr else { return nil }

    var timing = CMSampleTimingInfo(
        duration: CMTime(value: 1, timescale: CMTimeScale(buffer.format.sampleRate.rounded())),
        presentationTimeStamp: presentationTime,
        decodeTimeStamp: .invalid
    )

    var sampleBuffer: CMSampleBuffer?
    let sampleStatus = CMSampleBufferCreate(
        allocator: kCFAllocatorDefault,
        dataBuffer: blockBuffer,
        dataReady: true,
        makeDataReadyCallback: nil,
        refcon: nil,
        formatDescription: formatDescription,
        sampleCount: frameCount,
        sampleTimingEntryCount: 1,
        sampleTimingArray: &timing,
        sampleSizeEntryCount: 0,
        sampleSizeArray: nil,
        sampleBufferOut: &sampleBuffer
    )
    guard sampleStatus == noErr else { return nil }
    return sampleBuffer
}

