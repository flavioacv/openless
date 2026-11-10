use std::fs;
use std::path::PathBuf;

use chrono::Utc;
use openless_core::errors::BackendErrorCode;
use openless_core::meetings::*;
use uuid::Uuid;

struct Fixture {
    directory: PathBuf,
    store: MeetingStore,
}

impl Fixture {
    fn new() -> Self {
        let directory = std::env::temp_dir().join(format!("openless-meetings-{}", Uuid::new_v4()));
        Self {
            store: MeetingStore::at_data_dir(&directory),
            directory,
        }
    }

    fn manifest(&self, id: Uuid) -> PathBuf {
        self.directory.join("meetings").join(id.to_string()).join("manifest.json")
    }
}

impl Drop for Fixture {
    fn drop(&mut self) {
        if self.directory.exists() {
            fs::remove_dir_all(&self.directory).expect("remove private fixture");
        }
    }
}

fn document() -> MeetingDocument {
    MeetingDocument::new(
        "Reunião de planejamento".into(),
        "pt-BR".into(),
        MeetingOrigin::ImportedVideo,
    )
}

fn with_transcript() -> MeetingDocument {
    let mut document = document();
    let track_id = Uuid::new_v4();
    let speaker_id = Uuid::new_v4();
    document.tracks.push(MeetingTrack {
        id: track_id,
        kind: MeetingTrackKind::Imported,
        sample_rate: 16_000,
        channels: 1,
    });
    document.replace_transcript(
        vec![MeetingSpeaker { id: speaker_id, name: "Falante 1".into() }],
        vec![MeetingSegment {
            id: Uuid::new_v4(),
            track_id,
            speaker_id: Some(speaker_id),
            attribution: SpeakerAttribution::Assigned,
            start_ms: 1500,
            end_ms: 3300,
            text: "Vamos revisar a proposta.".into(),
            original_text: None,
        }],
    ).unwrap();
    document
}

fn summary(document: &MeetingDocument) -> MeetingSummary {
    MeetingSummary {
        transcript_revision: document.transcript_revision,
        provider: "configured-provider".into(),
        model: "configured-model".into(),
        prompt_version: 1,
        generated_at: Utc::now(),
        text: "Foi solicitada a revisão da proposta.".into(),
        decisions: vec![],
        tasks: vec![MeetingTask {
            description: "Revisar a proposta".into(),
            owner: None,
            deadline: None,
            source_segment_ids: vec![document.segments[0].id],
        }],
    }
}

#[test]
fn round_trip_preserves_video_origin_speaker_timing_and_unspecified_task_fields() {
    let fixture = Fixture::new();
    let mut document = with_transcript();
    document.summary = Some(summary(&document));
    fixture.store.create(&document).unwrap();
    assert_eq!(fixture.store.load(document.id).unwrap(), document);
    let bytes = fs::read(fixture.manifest(document.id)).unwrap();
    let value: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(value["origin"], "importedVideo");
    assert_eq!(value["segments"][0]["startMs"], 1500);
    assert!(value["summary"]["tasks"][0]["owner"].is_null());
    assert!(value["summary"]["tasks"][0]["deadline"].is_null());
    assert!(document.summary_is_current());
}

#[test]
fn transcript_edit_invalidates_but_keeps_previous_summary_even_when_source_segment_is_removed() {
    let fixture = Fixture::new();
    let mut document = with_transcript();
    document.summary = Some(summary(&document));
    fixture.store.create(&document).unwrap();
    document.replace_transcript(vec![], vec![]).unwrap();
    assert!(!document.summary_is_current());
    let saved = fixture.store.save(&document).unwrap();
    let loaded = fixture.store.load(document.id).unwrap();
    assert_eq!(loaded.summary, document.summary);
    assert_eq!(loaded.revision, 1);
    assert_eq!(saved, loaded);
}

#[test]
fn stale_writer_cannot_overwrite_newer_document() {
    let fixture = Fixture::new();
    let document = document();
    fixture.store.create(&document).unwrap();
    let mut first = document.clone();
    first.title = "Título revisado".into();
    fixture.store.clone().save(&first).unwrap();
    let error = fixture.store.save(&document).unwrap_err();
    assert_eq!(error.code, BackendErrorCode::InvalidState);
    assert_eq!(fixture.store.load(document.id).unwrap().title, first.title);
}

#[test]
fn transcript_cannot_change_without_advancing_revision() {
    let fixture = Fixture::new();
    let mut document = with_transcript();
    fixture.store.create(&document).unwrap();
    document.segments[0].text = "Outro texto".into();
    assert_eq!(fixture.store.save(&document).unwrap_err().code, BackendErrorCode::InvalidArgument);
}

#[test]
fn failed_transcript_edit_preserves_original_document() {
    let mut document = with_transcript();
    let before = document.clone();
    let mut segments = document.segments.clone();
    segments[0].speaker_id = Some(Uuid::new_v4());
    assert!(document.replace_transcript(document.speakers.clone(), segments).is_err());
    assert_eq!(document, before);
}

#[test]
fn malformed_and_future_manifests_are_not_replaced_or_reset() {
    let fixture = Fixture::new();
    let document = document();
    fixture.store.create(&document).unwrap();
    let path = fixture.manifest(document.id);
    fs::write(&path, b"{truncated").unwrap();
    assert_eq!(fixture.store.load(document.id).unwrap_err().code, BackendErrorCode::Persistence);
    assert_eq!(fs::read(&path).unwrap(), b"{truncated");
    let mut future = serde_json::to_value(&document).unwrap();
    future["schemaVersion"] = serde_json::json!(MEETING_SCHEMA_VERSION + 1);
    let bytes = serde_json::to_vec(&future).unwrap();
    fs::write(&path, &bytes).unwrap();
    assert_eq!(fixture.store.load(document.id).unwrap_err().code, BackendErrorCode::Unsupported);
    assert_eq!(fs::read(&path).unwrap(), bytes);
}

#[test]
fn duplicate_creation_never_replaces_existing_meeting() {
    let fixture = Fixture::new();
    let mut document = document();
    fixture.store.create(&document).unwrap();
    document.title = "Não substituir".into();
    assert!(fixture.store.create(&document).is_err());
    assert_ne!(fixture.store.load(document.id).unwrap().title, document.title);
}

#[test]
fn rejects_chunk_paths_outside_private_meeting_and_duplicate_paths() {
    let mut document = with_transcript();
    for path in [
        "../original.wav",
        "/tmp/original.wav",
        "C:\\original.wav",
        "audio/../../original.wav",
        "",
    ] {
        document.chunks = vec![MeetingAudioChunk {
            id: Uuid::new_v4(),
            track_id: document.tracks[0].id,
            relative_path: path.into(),
            start_ms: 0,
            duration_ms: 100,
            byte_count: 100,
            finalized: true,
        }];
        assert!(document.validate().is_err(), "accepted {path}");
    }
    document.chunks[0].relative_path = "audio/part.wav".into();
    document.validate().unwrap();
    let mut duplicate = document.chunks[0].clone();
    duplicate.id = Uuid::new_v4();
    document.chunks.push(duplicate);
    assert!(document.validate().is_err());
}

#[test]
fn distinguishes_recording_recovery_from_completed_and_failed_meetings() {
    for state in [
        MeetingState::Preparing,
        MeetingState::Recording,
        MeetingState::Stopping,
        MeetingState::Processing,
    ] {
        assert!(state.requires_recovery());
    }
    for state in [MeetingState::Completed, MeetingState::Interrupted, MeetingState::Failed] {
        assert!(!state.requires_recovery());
    }
}

#[test]
fn validates_cross_references_without_rejecting_real_overlapping_speech() {
    let mut document = with_transcript();
    let mut overlapping = document.segments[0].clone();
    overlapping.id = Uuid::new_v4();
    overlapping.attribution = SpeakerAttribution::Overlapping;
    overlapping.speaker_id = None;
    document.segments.push(overlapping);
    document.validate().unwrap();
    document.segments[0].track_id = Uuid::new_v4();
    assert!(document.validate().is_err());
}

#[test]
fn current_summary_cannot_reference_a_nonexistent_segment() {
    let mut document = with_transcript();
    let mut summary = summary(&document);
    summary.tasks[0].source_segment_ids = vec![Uuid::new_v4()];
    document.summary = Some(summary);
    assert!(document.validate().is_err());
}

#[test]
fn identity_in_manifest_must_match_directory() {
    let fixture = Fixture::new();
    let document = document();
    fixture.store.create(&document).unwrap();
    let mut other = document.clone();
    other.id = Uuid::new_v4();
    fs::write(fixture.manifest(document.id), serde_json::to_vec(&other).unwrap()).unwrap();
    assert_eq!(fixture.store.load(document.id).unwrap_err().code, BackendErrorCode::Persistence);
}

#[cfg(unix)]
#[test]
fn rejects_symlinked_manifest_without_modifying_target() {
    use std::os::unix::fs::symlink;
    let fixture = Fixture::new();
    let document = document();
    fixture.store.create(&document).unwrap();
    let original = fixture.directory.join("original.json");
    fs::write(&original, b"original").unwrap();
    fs::remove_file(fixture.manifest(document.id)).unwrap();
    symlink(&original, fixture.manifest(document.id)).unwrap();
    assert!(fixture.store.load(document.id).is_err());
    assert_eq!(fs::read(original).unwrap(), b"original");
}
