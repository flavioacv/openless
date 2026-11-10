use std::path::PathBuf;
use openless_core::meetings::*;
use uuid::Uuid;

fn captured(clean_duration: u64) -> MeetingDocument {
    let mut doc = MeetingDocument::new("Meeting".into(), "pt-BR".into(), MeetingOrigin::OnlineCall);
    for (kind, duration) in [(MeetingTrackKind::Microphone, 2000), (MeetingTrackKind::MicrophoneClean, clean_duration), (MeetingTrackKind::Application, 2000)] {
        let id = Uuid::new_v4();
        doc.tracks.push(MeetingTrack { id, kind, sample_rate: 16_000, channels: 1 });
        doc.chunks.push(MeetingAudioChunk { id: Uuid::new_v4(), track_id: id,
            relative_path: PathBuf::from(format!("{id}.wav")), start_ms: 0, duration_ms: duration,
            byte_count: duration * 32 + 44, finalized: true });
    }
    doc
}

#[test]
fn analysis_uses_complete_cleaned_microphone_once_and_keeps_application_audio() {
    let doc = captured(2000);
    let kinds: Vec<_> = doc.analysis_tracks().iter().map(|track| track.kind).collect();
    assert_eq!(kinds, vec![MeetingTrackKind::MicrophoneClean, MeetingTrackKind::Application]);
    assert_eq!(doc.tracks.len(), 3, "raw audio remains registered for playback and recovery");
}

#[test]
fn interrupted_cleaning_cannot_remove_the_original_speech_from_analysis() {
    let doc = captured(1000);
    let kinds: Vec<_> = doc.analysis_tracks().iter().map(|track| track.kind).collect();
    assert_eq!(kinds, vec![MeetingTrackKind::Microphone, MeetingTrackKind::Application]);
}

#[test]
fn aec_gap_is_not_mistaken_for_complete_cleaned_coverage() {
    let mut doc = captured(2000);
    let clean = doc.tracks.iter().find(|track| track.kind == MeetingTrackKind::MicrophoneClean).unwrap().id;
    let chunk = doc.chunks.iter_mut().find(|chunk| chunk.track_id == clean).unwrap();
    chunk.duration_ms = 800;
    let mut second = chunk.clone(); second.id = Uuid::new_v4(); second.start_ms = 1000; second.duration_ms = 1000;
    doc.chunks.push(second);
    assert!(doc.analysis_tracks().iter().any(|track| track.kind == MeetingTrackKind::Microphone));
    assert!(!doc.analysis_tracks().iter().any(|track| track.kind == MeetingTrackKind::MicrophoneClean));
}

#[test]
fn older_meetings_without_capture_metadata_still_load() {
    let mut wire = serde_json::to_value(captured(2000)).unwrap();
    wire.as_object_mut().unwrap().remove("captureInfo");
    let document: MeetingDocument = serde_json::from_value(wire).unwrap();
    assert!(document.capture_info.is_none());
}
