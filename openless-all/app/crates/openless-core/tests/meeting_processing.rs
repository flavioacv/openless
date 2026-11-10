use std::collections::HashSet;
use std::fs;
use openless_core::meetings::*;
use openless_core::meetings::processing::*;
use openless_core::asr::wav::encode_wav_16k_mono;
use serde_json::json;
use uuid::Uuid;

#[test]
fn scribe_keeps_one_identity_when_a_speaker_returns_after_another_voice() {
    let words = json!({"words":[
        {"text":"Vamos", "start":0.0,"end":0.2,"speaker_id":"speaker_0","type":"word"},
        {"text":"revisar.", "start":0.2,"end":0.5,"speaker_id":"speaker_0","type":"word"},
        {"text":"Sim.", "start":0.6,"end":0.8,"speaker_id":"speaker_1","type":"word"},
        {"text":"Amanhã.", "start":1.0,"end":1.5,"speaker_id":"speaker_0","type":"word"}
    ]});
    let (speakers, segments) = admit_scribe(&serde_json::to_vec(&words).unwrap(), Uuid::new_v4(), 2000, 0).unwrap();
    assert_eq!(speakers.len(), 2);
    assert_eq!(segments.len(), 3);
    assert_eq!(segments[0].text, "Vamos revisar.");
    assert_eq!(segments[0].speaker_id, segments[2].speaker_id);
    assert_ne!(segments[0].speaker_id, segments[1].speaker_id);
}

#[test]
fn missing_speaker_stays_unassigned_and_events_do_not_become_speech() {
    let words = json!({"words":[
        {"text":"(risos)","start":0.0,"end":0.2,"type":"audio_event"},
        {"text":"Proposta.","start":0.3,"end":0.7,"type":"word"}
    ]});
    let (speakers, segments) = admit_scribe(&serde_json::to_vec(&words).unwrap(), Uuid::new_v4(), 1000, 0).unwrap();
    assert!(speakers.is_empty());
    assert_eq!(segments.len(), 1);
    assert_eq!(segments[0].attribution, SpeakerAttribution::Unassigned);
}

#[test]
fn invalid_or_absent_provider_timings_are_never_fabricated() {
    for word in [
        json!({"text":"fala","type":"word"}),
        json!({"text":"fala","type":"word","start":-1,"end":1}),
        json!({"text":"fala","type":"word","start":1,"end":1}),
        json!({"text":"fala","type":"word","start":0,"end":20}),
    ] {
        let response = serde_json::to_vec(&json!({"words":[word]})).unwrap();
        assert!(admit_scribe(&response, Uuid::new_v4(), 1000, 0).is_err());
    }
}

#[test]
fn summary_retains_unspecified_fields_and_rejects_invented_source_references() {
    let id = Uuid::new_v4();
    let mut data = json!({"text":"Revisar a proposta.", "decisions":[], "tasks":[{
        "description":"Revisar a proposta", "owner":null, "deadline":null, "sourceSegmentIds":[id]
    }]});
    let allowed = HashSet::from([id]);
    let result = admit_summary(&data.to_string(), &allowed).unwrap();
    assert_eq!(result.tasks[0].owner, None);
    assert_eq!(result.tasks[0].deadline, None);
    data["tasks"][0]["sourceSegmentIds"] = json!([Uuid::new_v4()]);
    assert!(admit_summary(&data.to_string(), &allowed).is_err());
    assert!(admit_summary("```json\n{}\n```", &allowed).is_err());
}

#[test]
fn summary_rejects_empty_results_and_unexpected_top_level_fields() {
    let allowed = HashSet::new();
    for data in [
        json!({"text":"", "decisions":[], "tasks":[]}),
        json!({"text":"Resumo", "decisions":[], "tasks":[], "unrequested":"data"}),
        json!({"text":"Resumo", "decisions":[{"description":"", "sourceSegmentIds":[]}], "tasks":[]}),
    ] {
        assert!(admit_summary(&data.to_string(), &allowed).is_err());
    }
}

struct Fixture(std::path::PathBuf);
impl Fixture {
    fn new() -> Self {
        let path = std::env::temp_dir().join(format!("openless-meeting-processing-{}", Uuid::new_v4()));
        fs::create_dir_all(&path).unwrap();
        Self(path)
    }
}
impl Drop for Fixture {
    fn drop(&mut self) { fs::remove_dir_all(&self.0).unwrap(); }
}

fn audio_document(store: &MeetingStore) -> MeetingDocument {
    let mut doc = MeetingDocument::new("Planejamento".into(), "pt-BR".into(), MeetingOrigin::ImportedVideo);
    let track_id = Uuid::new_v4();
    doc.tracks.push(MeetingTrack { id: track_id, kind: MeetingTrackKind::Imported, sample_rate:16_000, channels:1 });
    store.create(&doc).unwrap();
    for (index, start_ms) in [0, 200].into_iter().enumerate() {
        let relative_path = std::path::PathBuf::from(format!("part-{index}.wav"));
        let audio = encode_wav_16k_mono(&vec![1000; 1600]);
        fs::write(store.media_directory(doc.id).unwrap().join(&relative_path), &audio).unwrap();
        doc.chunks.push(MeetingAudioChunk {
            id:Uuid::new_v4(), track_id, relative_path, start_ms,
            duration_ms:100, byte_count:audio.len() as u64, finalized:true,
        });
    }
    store.save(&doc).unwrap()
}

#[test]
fn disk_materialization_preserves_meeting_offsets_without_loading_all_audio() {
    let fixture = Fixture::new();
    let store = MeetingStore::at_data_dir(&fixture.0);
    let doc = audio_document(&store);
    let target = fixture.0.join("analysis.wav");
    let duration = materialize_track(&store, &doc, doc.tracks[0].id, &target, || false).unwrap();
    assert_eq!(duration, 300);
    let audio = fs::read(target).unwrap();
    assert_eq!(audio.len(), 44 + 9600);
    assert!(audio[44+3200..44+6400].iter().all(|byte| *byte == 0));
    assert!(audio[44+6400..].chunks_exact(2).all(|sample| i16::from_le_bytes(sample.try_into().unwrap()) == 1000));
}

#[test]
fn materialization_rejects_modified_audio_and_can_be_cancelled() {
    let fixture = Fixture::new();
    let store = MeetingStore::at_data_dir(&fixture.0);
    let doc = audio_document(&store);
    let target = fixture.0.join("cancelled.wav");
    let error = materialize_track(&store, &doc, doc.tracks[0].id, &target, || true).unwrap_err();
    assert_eq!(error.code, openless_core::BackendErrorCode::Cancelled);
    let path = store.chunk_path(doc.id, doc.chunks[0].id).unwrap();
    fs::write(path, b"changed").unwrap();
    assert!(materialize_track(&store, &doc, doc.tracks[0].id, &fixture.0.join("changed.wav"), || false).is_err());
}

#[test]
fn catalog_reports_corruption_without_hiding_valid_meetings() {
    let fixture = Fixture::new();
    let store = MeetingStore::at_data_dir(&fixture.0);
    let first = audio_document(&store);
    let second = MeetingDocument::new("Outra reunião".into(),"pt".into(), MeetingOrigin::InRoom);
    store.create(&second).unwrap();
    let path = store.media_directory(second.id).unwrap().join("manifest.json");
    fs::write(&path,b"broken").unwrap();
    let catalog = store.list().unwrap();
    assert_eq!(catalog.meetings.len(),1);
    assert_eq!(catalog.meetings[0].id,first.id);
    assert_eq!(catalog.errors.len(),1);
    assert_eq!(fs::read(path).unwrap(),b"broken");
}

#[tokio::test]
async fn meeting_lease_excludes_other_meetings_and_wake_capture_then_releases_cleanly() {
    let fixture = Fixture::new();
    let backend = openless_core::OpenLessBackend::new(
        openless_core::BackendConfig { data_dir: fixture.0.clone(), ..Default::default() },
        openless_core::BackendDependencies::unsupported(),
    ).unwrap();
    let lease = backend.reserve_meeting_resources().await.unwrap();
    let error = backend.reserve_meeting_resources().await.err().expect("second meeting must be rejected");
    assert_eq!(error.code, openless_core::BackendErrorCode::Busy);
    assert_eq!(backend.configure_voice_activation().await.unwrap_err().code, openless_core::BackendErrorCode::Busy);
    drop(lease);
    let next = backend.reserve_meeting_resources().await.unwrap();
    drop(next);
}
