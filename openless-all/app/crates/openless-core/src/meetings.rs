//! Durable meeting documents, independent of dictation history and native capture.

use std::collections::HashSet;
use std::fs;
use std::path::{Component, Path, PathBuf};
use std::sync::{Arc, Mutex};

use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::errors::{BackendError, BackendErrorCode};

pub const MEETING_SCHEMA_VERSION: u32 = 1;
pub mod processing;

// Keep the core's existing Chrono feature set; timestamps on disk are RFC 3339 strings.
mod timestamp {
    use chrono::{DateTime, Utc};
    use serde::{Deserialize, Deserializer, Serializer};

    pub fn serialize<S: Serializer>(value: &DateTime<Utc>, serializer: S) -> Result<S::Ok, S::Error> {
        serializer.serialize_str(&value.to_rfc3339())
    }

    pub fn deserialize<'de, D: Deserializer<'de>>(deserializer: D) -> Result<DateTime<Utc>, D::Error> {
        let value = String::deserialize(deserializer)?;
        DateTime::parse_from_rfc3339(&value)
            .map(|timestamp| timestamp.with_timezone(&Utc))
            .map_err(serde::de::Error::custom)
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum MeetingOrigin {
    OnlineCall,
    InRoom,
    ImportedAudio,
    ImportedVideo,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum MeetingState {
    Preparing,
    Recording,
    Stopping,
    Processing,
    Completed,
    Interrupted,
    Failed,
}

impl MeetingState {
    pub fn requires_recovery(self) -> bool {
        matches!(
            self,
            Self::Preparing | Self::Recording | Self::Stopping | Self::Processing
        )
    }
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum MeetingTrackKind {
    Microphone,
    MicrophoneClean,
    Application,
    Imported,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MeetingAudioChunk {
    pub id: Uuid,
    pub track_id: Uuid,
    /// Relative to this meeting's private directory, never to the imported original.
    pub relative_path: PathBuf,
    pub start_ms: u64,
    pub duration_ms: u64,
    pub byte_count: u64,
    pub finalized: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MeetingTrack {
    pub id: Uuid,
    pub kind: MeetingTrackKind,
    pub sample_rate: u32,
    pub channels: u16,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MeetingSpeaker {
    pub id: Uuid,
    pub name: String,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub enum SpeakerAttribution {
    Assigned,
    Unassigned,
    Overlapping,
    Uncertain,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MeetingSegment {
    pub id: Uuid,
    pub track_id: Uuid,
    pub speaker_id: Option<Uuid>,
    pub attribution: SpeakerAttribution,
    pub start_ms: u64,
    pub end_ms: u64,
    pub text: String,
    pub original_text: Option<String>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MeetingTask {
    pub description: String,
    pub owner: Option<String>,
    pub deadline: Option<String>,
    pub source_segment_ids: Vec<Uuid>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MeetingDecision {
    pub description: String,
    pub source_segment_ids: Vec<Uuid>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MeetingSummary {
    pub transcript_revision: u64,
    pub provider: String,
    pub model: String,
    pub prompt_version: u32,
    #[serde(with = "timestamp")]
    pub generated_at: DateTime<Utc>,
    pub text: String,
    pub decisions: Vec<MeetingDecision>,
    pub tasks: Vec<MeetingTask>,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MeetingEchoInfo {
    pub enabled: bool,
    pub active: bool,
    pub processed_frames: u64,
    pub warning: Option<String>,
    pub upstream_revision: String,
    pub configuration_id: String,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MeetingCaptureInfo {
    pub echo_cancellation: Option<MeetingEchoInfo>,
    pub live_captions: bool,
}

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MeetingDocument {
    pub schema_version: u32,
    pub id: Uuid,
    pub revision: u64,
    pub title: String,
    pub language: String,
    pub origin: MeetingOrigin,
    pub state: MeetingState,
    #[serde(with = "timestamp")]
    pub created_at: DateTime<Utc>,
    pub tracks: Vec<MeetingTrack>,
    pub chunks: Vec<MeetingAudioChunk>,
    pub transcript_revision: u64,
    pub speakers: Vec<MeetingSpeaker>,
    pub segments: Vec<MeetingSegment>,
    pub summary: Option<MeetingSummary>,
    #[serde(default)]
    pub capture_info: Option<MeetingCaptureInfo>,
}

impl MeetingDocument {
    /// Prefer a cleaned microphone only when it covers every finalized raw microphone span.
    /// Partial AEC output must never make the remaining original speech disappear from analysis.
    pub fn analysis_tracks(&self) -> Vec<MeetingTrack> {
        let cleaned_ids: std::collections::HashSet<_> = self.tracks.iter()
            .filter(|track| track.kind == MeetingTrackKind::MicrophoneClean).map(|track| track.id).collect();
        let mut clean: Vec<_> = self.chunks.iter().filter(|chunk| chunk.finalized && cleaned_ids.contains(&chunk.track_id))
            .map(|chunk| (chunk.start_ms, chunk.start_ms.saturating_add(chunk.duration_ms))).collect();
        clean.sort_unstable();
        let raw: Vec<_> = self.chunks.iter().filter(|chunk| chunk.finalized && self.tracks.iter()
            .any(|track| track.id == chunk.track_id && track.kind == MeetingTrackKind::Microphone)).collect();
        let complete = !raw.is_empty() && raw.iter().all(|chunk| {
            let mut cursor = chunk.start_ms;
            let end = chunk.start_ms.saturating_add(chunk.duration_ms);
            for &(start, next) in &clean {
                if start <= cursor.saturating_add(2) && next > cursor { cursor = next; }
                if cursor.saturating_add(2) >= end { return true; }
            }
            false
        });
        self.tracks.iter().filter(|track| {
            let selected = match track.kind {
                MeetingTrackKind::Microphone => !complete,
                MeetingTrackKind::MicrophoneClean => complete,
                _ => true,
            };
            selected && self.chunks.iter().any(|chunk| chunk.track_id == track.id && chunk.finalized)
        }).cloned().collect()
    }

    pub fn new(title: String, language: String, origin: MeetingOrigin) -> Self {
        Self {
            schema_version: MEETING_SCHEMA_VERSION,
            id: Uuid::new_v4(),
            revision: 0,
            title,
            language,
            origin,
            state: MeetingState::Preparing,
            created_at: Utc::now(),
            tracks: Vec::new(),
            chunks: Vec::new(),
            transcript_revision: 0,
            speakers: Vec::new(),
            segments: Vec::new(),
            summary: None,
            capture_info: None,
        }
    }

    pub fn summary_is_current(&self) -> bool {
        self.summary.as_ref().is_some_and(|summary| {
            summary.transcript_revision == self.transcript_revision
        })
    }

    /// Keep the previous summary as history, but invalidate it when its source changes.
    pub fn replace_transcript(
        &mut self,
        speakers: Vec<MeetingSpeaker>,
        segments: Vec<MeetingSegment>,
    ) -> Result<(), BackendError> {
        let mut updated = self.clone();
        updated.transcript_revision = updated
            .transcript_revision
            .checked_add(1)
            .ok_or_else(|| invalid("O limite de revisões da transcrição foi atingido"))?;
        updated.speakers = speakers;
        updated.segments = segments;
        updated.validate()?;
        *self = updated;
        Ok(())
    }

    pub fn validate(&self) -> Result<(), BackendError> {
        if self.schema_version != MEETING_SCHEMA_VERSION {
            return Err(BackendError::new(
                BackendErrorCode::Unsupported,
                "A versão do formato da reunião não é compatível; o documento foi preservado",
            ));
        }
        if self.id.is_nil() || self.title.trim().is_empty() || self.language.trim().is_empty() {
            return Err(invalid("A reunião precisa de identificação, título e idioma"));
        }
        let tracks = unique_ids(self.tracks.iter().map(|track| track.id))?;
        let speakers = unique_ids(self.speakers.iter().map(|speaker| speaker.id))?;
        unique_ids(self.chunks.iter().map(|chunk| chunk.id))?;
        let segment_ids = unique_ids(self.segments.iter().map(|segment| segment.id))?;
        if self.tracks.iter().any(|track| track.sample_rate == 0 || track.channels == 0) {
            return Err(invalid("A faixa da reunião precisa de um formato de áudio válido"));
        }
        let mut chunk_paths = HashSet::new();
        for chunk in &self.chunks {
            if !tracks.contains(&chunk.track_id)
                || !private_relative_path(&chunk.relative_path)
                || !chunk_paths.insert(&chunk.relative_path)
                || chunk.start_ms.checked_add(chunk.duration_ms).is_none()
                || (chunk.finalized && (chunk.duration_ms == 0 || chunk.byte_count == 0))
            {
                return Err(invalid("Um bloco de áudio contém fonte, caminho, tempo ou tamanho inválido"));
            }
        }
        if self.speakers.iter().any(|speaker| speaker.name.trim().is_empty()) {
            return Err(invalid("O falante precisa de um nome de exibição"));
        }
        for segment in &self.segments {
            if !tracks.contains(&segment.track_id)
                || segment.start_ms >= segment.end_ms
                || segment.text.trim().is_empty()
                || segment.speaker_id.is_some_and(|id| !speakers.contains(&id))
                || (segment.attribution == SpeakerAttribution::Assigned && segment.speaker_id.is_none())
            {
                return Err(invalid("Um trecho contém fonte, falante, texto ou tempo inválido"));
            }
        }
        if let Some(summary) = &self.summary {
            if summary.transcript_revision > self.transcript_revision
                || summary.provider.trim().is_empty()
                || summary.model.trim().is_empty()
                || summary.prompt_version == 0
                || summary.text.trim().is_empty()
            {
                return Err(invalid("O resumo contém referências ou conteúdo inválidos"));
            }
            // Stale summaries retain the IDs of their original transcript. They must remain
            // readable after edits remove segments, rather than making the document unloadable.
            if self.summary_is_current()
                && (summary.decisions.iter().any(|decision| {
                    decision.description.trim().is_empty()
                        || decision.source_segment_ids.iter().any(|id| !segment_ids.contains(id))
                }) || summary.tasks.iter().any(|task| {
                    task.description.trim().is_empty()
                        || task.source_segment_ids.iter().any(|id| !segment_ids.contains(id))
                }))
            {
                return Err(invalid("O resumo faz referência a um trecho desconhecido da transcrição"));
            }
        }
        Ok(())
    }
}

fn private_relative_path(path: &Path) -> bool {
    !path.as_os_str().is_empty()
        && path.to_str().is_some_and(|value| !value.contains('\\') && !value.contains(':'))
        && path.components().all(|part| matches!(part, Component::Normal(_)))
}

fn unique_ids(ids: impl Iterator<Item = Uuid>) -> Result<HashSet<Uuid>, BackendError> {
    let mut result = HashSet::new();
    for id in ids {
        if id.is_nil() || !result.insert(id) {
            return Err(invalid("A reunião contém uma identificação vazia ou duplicada"));
        }
    }
    Ok(result)
}

fn invalid(message: &str) -> BackendError {
    BackendError::new(BackendErrorCode::InvalidArgument, message)
}

fn persistence(message: &str) -> BackendError {
    BackendError::new(BackendErrorCode::Persistence, message)
}

/// One instance (or clones) per backend, mirroring the shared repository ownership policy.
#[derive(Clone)]
pub struct MeetingStore {
    root: PathBuf,
    lock: Arc<Mutex<()>>,
}

impl MeetingStore {
    pub fn list(&self) -> Result<MeetingCatalog, BackendError> {
        let _guard = self.lock.lock().map_err(|_| persistence("Não foi possível obter acesso exclusivo às reuniões"))?;
        let mut catalog = MeetingCatalog::default();
        if !self.root.exists() { return Ok(catalog); }
        if fs::symlink_metadata(&self.root)
            .map_err(|_| persistence("Não foi possível verificar a pasta das reuniões"))?.file_type().is_symlink()
        { return Err(persistence("A pasta das reuniões não pode ser um link simbólico")); }
        for entry in fs::read_dir(&self.root).map_err(|_| persistence("Não foi possível listar as reuniões"))? {
            let entry = entry.map_err(|_| persistence("Não foi possível ler a pasta da reunião"))?;
            let Ok(id) = Uuid::parse_str(&entry.file_name().to_string_lossy()) else { continue };
            match self.read(id) {
                Ok(document) => catalog.meetings.push(document),
                Err(error) => catalog.errors.push(format!("{id}: {}", error.message)),
            }
        }
        catalog.meetings.sort_by_key(|document| std::cmp::Reverse(document.created_at));
        Ok(catalog)
    }

    pub fn media_directory(&self, id: Uuid) -> Result<PathBuf, BackendError> {
        self.load(id)?;
        Ok(self.directory(id))
    }

    pub fn chunk_path(&self, id: Uuid, chunk_id: Uuid) -> Result<PathBuf, BackendError> {
        let document = self.load(id)?;
        let chunk = document.chunks.iter().find(|chunk| chunk.id == chunk_id && chunk.finalized)
            .ok_or_else(|| invalid("O bloco de áudio finalizado não foi encontrado"))?;
        let directory = self.directory(id).canonicalize()
            .map_err(|_| persistence("Não foi possível localizar a pasta da reunião"))?;
        let path = directory.join(&chunk.relative_path).canonicalize()
            .map_err(|_| persistence("Não foi possível localizar o áudio da reunião"))?;
        if !path.starts_with(&directory) {
            return Err(persistence("O áudio da reunião está fora da pasta permitida"));
        }
        Ok(path)
    }

    pub fn at_data_dir(data_dir: &Path) -> Self {
        Self {
            root: data_dir.join("meetings"),
            lock: Arc::new(Mutex::new(())),
        }
    }

    pub fn create(&self, document: &MeetingDocument) -> Result<(), BackendError> {
        let _guard = self.lock.lock().map_err(|_| persistence("Não foi possível obter acesso exclusivo às reuniões"))?;
        document.validate()?;
        if document.revision != 0 {
            return Err(invalid("Uma nova reunião precisa começar na revisão zero"));
        }
        self.ensure_root()?;
        let directory = self.directory(document.id);
        // create_dir is intentional: never replace a meeting, even after a partial write.
        fs::create_dir(&directory).map_err(|_| persistence("Não foi possível criar a pasta da reunião"))?;
        self.write(document)
    }

    pub fn load(&self, id: Uuid) -> Result<MeetingDocument, BackendError> {
        let _guard = self.lock.lock().map_err(|_| persistence("Não foi possível obter acesso exclusivo às reuniões"))?;
        self.read(id)
    }

    /// Optimistic revision checks prevent an older UI or processing task overwriting newer edits.
    pub fn save(&self, document: &MeetingDocument) -> Result<MeetingDocument, BackendError> {
        let _guard = self.lock.lock().map_err(|_| persistence("Não foi possível obter acesso exclusivo às reuniões"))?;
        document.validate()?;
        let current = self.read(document.id)?;
        if document.revision != current.revision {
            return Err(BackendError::new(
                BackendErrorCode::InvalidState,
                "A reunião foi alterada; recarregue antes de salvar",
            ));
        }
        if document.transcript_revision < current.transcript_revision
            || ((document.segments != current.segments || document.speakers != current.speakers)
                && document.transcript_revision == current.transcript_revision)
        {
            return Err(invalid("As alterações precisam atualizar a revisão da transcrição"));
        }
        let mut updated = document.clone();
        updated.revision = current.revision.checked_add(1)
            .ok_or_else(|| invalid("O limite de revisões da reunião foi atingido"))?;
        self.write(&updated)?;
        Ok(updated)
    }

    /// A bad manifest is returned as an error, never silently replaced by an empty meeting.
    fn read(&self, id: Uuid) -> Result<MeetingDocument, BackendError> {
        self.reject_symlinks(id)?;
        let bytes = fs::read(self.directory(id).join("manifest.json"))
            .map_err(|_| persistence("Não foi possível ler o registro da reunião"))?;
        let document: MeetingDocument = serde_json::from_slice(&bytes)
            .map_err(|_| persistence("Não foi possível ler o formato do registro da reunião; o original foi preservado"))?;
        document.validate()?;
        if document.id != id {
            return Err(persistence("A identificação do registro não corresponde à pasta da reunião"));
        }
        Ok(document)
    }

    fn directory(&self, id: Uuid) -> PathBuf {
        self.root.join(id.to_string())
    }

    fn ensure_root(&self) -> Result<(), BackendError> {
        if fs::symlink_metadata(&self.root).is_ok_and(|metadata| metadata.file_type().is_symlink()) {
            return Err(persistence("A pasta das reuniões não pode ser um link simbólico"));
        }
        fs::create_dir_all(&self.root).map_err(|_| persistence("Não foi possível criar a pasta das reuniões"))?;
        #[cfg(unix)]
        {
            use std::os::unix::fs::PermissionsExt;
            fs::set_permissions(&self.root, fs::Permissions::from_mode(0o700))
                .map_err(|_| persistence("Não foi possível proteger a pasta das reuniões"))?;
        }
        Ok(())
    }

    fn reject_symlinks(&self, id: Uuid) -> Result<(), BackendError> {
        for path in [&self.root, &self.directory(id), &self.directory(id).join("manifest.json")] {
            if fs::symlink_metadata(path).is_ok_and(|metadata| metadata.file_type().is_symlink()) {
                return Err(persistence("A pasta das reuniões não pode acessar links simbólicos"));
            }
        }
        Ok(())
    }

    fn write(&self, document: &MeetingDocument) -> Result<(), BackendError> {
        self.reject_symlinks(document.id)?;
        let bytes = serde_json::to_vec_pretty(document)
            .map_err(|_| persistence("Não foi possível gerar o registro da reunião"))?;
        crate::persistence::atomic_write(&self.directory(document.id).join("manifest.json"), &bytes)
    }
}

#[derive(Default, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct MeetingCatalog {
    pub meetings: Vec<MeetingDocument>,
    pub errors: Vec<String>,
}
