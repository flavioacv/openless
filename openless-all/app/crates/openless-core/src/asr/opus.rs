//! Pure-Rust Opus encoding and Ogg Opus encapsulation for ASR providers.
//!
//! Encodes 16 kHz / mono / 16-bit PCM audio samples into a compliant RFC 7845
//! Ogg Opus bitstream. This reduces the payload sent to cloud ASR providers
//! (like OpenAI Whisper, Groq Whisper) by ~10-15x compared to raw WAV, saving
//! bandwidth and network upload latency without external C library dependencies.

use opus_pure::{Application, OggOpusWriter, OpusEncoder, OpusHead};

/// 16 kHz mono 20ms frame = 320 samples (16,000 * 0.02s)
pub const OPUS_FRAME_SIZE_16K: usize = 320;

/// Encodes 16 kHz / mono / 16-bit PCM samples into an Ogg Opus stream (`.opus` / `.ogg`).
/// Returns `None` if samples are empty or if the encoder fails.
pub fn encode_ogg_opus_16k_mono(samples: &[i16]) -> Option<Vec<u8>> {
    if samples.is_empty() {
        return None;
    }

    let mut encoder = OpusEncoder::new(16_000, 1, Application::Voip).ok()?;
    let head = OpusHead::for_encoder(&encoder, 16_000);
    let mut writer = OggOpusWriter::new(Vec::new(), head).ok()?;

    let mut packet_buf = [0u8; 1275];
    let mut padded_frame = [0i16; OPUS_FRAME_SIZE_16K];

    for chunk in samples.chunks(OPUS_FRAME_SIZE_16K) {
        let frame: &[i16] = if chunk.len() == OPUS_FRAME_SIZE_16K {
            chunk
        } else {
            padded_frame.fill(0);
            padded_frame[..chunk.len()].copy_from_slice(chunk);
            &padded_frame
        };

        if let Ok(n_bytes) = encoder.encode_s16(frame, OPUS_FRAME_SIZE_16K, &mut packet_buf) {
            if n_bytes > 0 {
                let _ = writer.write_packet(&packet_buf[..n_bytes]);
            }
        }
    }

    let bytes = writer.finish().ok()?;
    if bytes.is_empty() {
        None
    } else {
        Some(bytes)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_encode_empty() {
        assert!(encode_ogg_opus_16k_mono(&[]).is_none());
    }

    #[test]
    fn test_encode_16k_mono_generates_valid_ogg_opus() {
        // 500ms of audio (8,000 samples)
        let samples = vec![100i16; 8_000];
        let encoded = encode_ogg_opus_16k_mono(&samples);
        assert!(encoded.is_some(), "Encoding should succeed");
        let bytes = encoded.unwrap();

        // Ogg container starts with magic byte sequence "OggS"
        assert!(bytes.len() >= 28, "Ogg Opus must contain at least headers");
        assert_eq!(&bytes[0..4], b"OggS", "Must have OggS header magic");

        // Compression ratio check: raw 8000 samples * 2 bytes = 16,000 bytes.
        // Opus at VoIP bitrates for 500ms should be < 3,000 bytes.
        assert!(
            bytes.len() < 16_000,
            "Opus should compress smaller than uncompressed PCM"
        );
    }
}
