//! Desktop orchestration for the shared meeting documents and native media ports.
mod native;

use std::collections::{HashMap, HashSet};
use std::sync::{Arc, Mutex, OnceLock, atomic::{AtomicBool, Ordering}};

use base64::Engine;
use openless_core::meetings::*;
use openless_core::meetings::processing::*;
use serde::Deserialize;
use serde_json::{json, Value};
use tauri::{Emitter, Manager};
use tauri_plugin_dialog::{DialogExt, FilePath};
use tokio::io::AsyncReadExt;
use uuid::Uuid;

use crate::persistence::CredentialsVault;

fn meeting_summary_error(error: openless_core::polish::LLMError) -> String {
    use openless_core::polish::LLMError;
    match error {
        LLMError::MissingCredentials => "Configure a chave do canal de IA selecionado para gerar o resumo.".into(),
        LLMError::Network(_) => "Não foi possível conectar ao provedor do resumo. Confira sua conexão e o endpoint do canal.".into(),
        LLMError::Timeout => "O provedor demorou demais para gerar o resumo. A transcrição foi preservada; tente novamente.".into(),
        LLMError::InvalidResponse { status, .. } => format!("O provedor de resumo retornou HTTP {status}. Confira a chave, o modelo e o endpoint do canal selecionado."),
        LLMError::ParseError(_) => "O modelo não retornou um resumo válido. Confira o modelo selecionado e tente novamente.".into(),
        LLMError::CodexAuth(_) | LLMError::Siwc(_) => "Não foi possível autenticar o canal do resumo. Confira a configuração do provedor.".into(),
    }
}

#[derive(Default)]
pub struct MeetingRuntime {
    store: OnceLock<MeetingStore>,
    operation: tokio::sync::Mutex<()>,
    active: Mutex<Option<(Uuid, openless_core::MeetingResourceLease)>>,
    cancelled: Arc<AtomicBool>,
    cancel_notify: tokio::sync::Notify,
    exiting: AtomicBool,
}

#[derive(Deserialize)]
#[serde(tag = "action", rename_all = "camelCase", rename_all_fields = "camelCase")]
pub enum MeetingRequest {
    List,
    Applications,
    Providers,
    DownloadModel { model: String },
    RemoveModel { model: String },
    CancelModelDownload,
    Start { title: String, language: String, pid: Option<i32>, #[serde(default)] live: bool, #[serde(default)] echo_cancellation: bool },
    Stop,
    Import { language: String },
    Transcribe { id: Uuid, channel_id: Option<String>, #[serde(default)] local: bool },
    Summarize { id: Uuid, channel_id: Option<String> },
    Cancel,
    Edit { id: Uuid, revision: u64, title: String, speakers: Vec<MeetingSpeaker>, segments: Vec<MeetingSegment> },
    ReadAudio { id: Uuid, chunk_id: Uuid },
    Export { id: Uuid, format: String },
    Recover { id: Uuid },
}

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct NativeBlock {
    kind: MeetingTrackKind,
    relative_path: std::path::PathBuf,
    start_ms: u64,
    duration_ms: u64,
    byte_count: u64,
}

impl MeetingRuntime {
    fn store(&self, core: &openless_core::OpenLessBackend) -> &MeetingStore {
        self.store.get_or_init(|| MeetingStore::at_data_dir(&core.config().data_dir))
    }

    fn model_directory(&self, core: &openless_core::OpenLessBackend) -> std::path::PathBuf {
        core.config().data_dir.join("meeting-models")
    }

    fn cancelled(&self) -> Result<(), String> {
        if self.cancelled.load(Ordering::Acquire) { Err("Operação cancelada; o áudio foi preservado.".into()) }
        else { Ok(()) }
    }

    fn attach_blocks(&self, doc: &mut MeetingDocument, blocks: Vec<NativeBlock>) -> Result<(), String> {
        let previous_tracks: HashMap<_, _> = doc.tracks.iter()
            .map(|track| (format!("{:?}", track.kind), track.id)).collect();
        let previous_chunks: HashMap<_, _> = doc.chunks.iter()
            .map(|chunk| (chunk.relative_path.clone(), chunk.id)).collect();
        doc.tracks.clear();
        doc.chunks.clear();
        let mut tracks: HashMap<String, Uuid> = HashMap::new();
        for block in blocks {
            let kind_key = format!("{:?}", block.kind);
            let track_id = *tracks.entry(kind_key).or_insert_with(|| {
                let id = previous_tracks.get(&format!("{:?}", block.kind)).copied().unwrap_or_else(Uuid::new_v4);
                doc.tracks.push(MeetingTrack { id, kind: block.kind, sample_rate: 16_000, channels: 1 });
                id
            });
            doc.chunks.push(MeetingAudioChunk {
                id: previous_chunks.get(&block.relative_path).copied().unwrap_or_else(Uuid::new_v4),
                track_id, relative_path: block.relative_path,
                start_ms: block.start_ms, duration_ms: block.duration_ms,
                byte_count: block.byte_count, finalized: true,
            });
        }
        doc.validate().map_err(|e| e.message)
    }

    fn recover_media(&self, store: &MeetingStore, doc: &mut MeetingDocument) -> Result<(), String> {
        let path = store.media_directory(doc.id).map_err(|e| e.message)?.join("media.json");
        if path.exists() {
            let metadata = std::fs::symlink_metadata(&path).map_err(|e| e.to_string())?;
            if metadata.file_type().is_symlink() || metadata.len() > 4 * 1024 * 1024 {
                return Err("Manifesto de áudio inválido.".into());
            }
            let bytes = std::fs::read(path).map_err(|e| e.to_string())?;
            let blocks: Vec<NativeBlock> = serde_json::from_slice(&bytes).map_err(|e| e.to_string())?;
            self.attach_blocks(doc, blocks)?;
        }
        let processing = store.media_directory(doc.id).map_err(|e| e.message)?.join("processing.json");
        if processing.exists() {
            let metadata = std::fs::symlink_metadata(&processing).map_err(|e| e.to_string())?;
            if metadata.file_type().is_symlink() || metadata.len() > 65_536 { return Err("Metadados de captura inválidos.".into()); }
            doc.capture_info = Some(serde_json::from_slice(&std::fs::read(processing).map_err(|e| e.to_string())?).map_err(|e| e.to_string())?);
        }
        Ok(())
    }

    fn progress(app: &tauri::AppHandle, id: Uuid, stage: &str, completed: usize, total: usize) {
        if let Err(error) = app.emit("meeting:progress", json!({"id":id,"stage":stage,"completed":completed,"total":total})) {
            log::warn!("meeting progress could not reach the UI: {error}");
        }
    }

    async fn transcribe(&self, app: &tauri::AppHandle, store: &MeetingStore, mut doc: MeetingDocument, channel_id: Option<String>, local: bool, model_directory: std::path::PathBuf) -> Result<MeetingDocument, String> {
        let cloud = if local { None } else {
        let configuration = tokio::task::spawn_blocking(move || CredentialsVault::meeting_transcription_snapshot(channel_id.as_deref()))
            .await.map_err(|e| e.to_string())?.map_err(|e| e.to_string())?;
        if !openless_core::provider_rules::is_elevenlabs_provider(&configuration.active_asr_provider) {
            return Err("Selecione um canal ElevenLabs nas configurações de reconhecimento para transcrever com falantes. A gravação e a importação permanecem locais.".into());
        }
        let credentials = configuration.credentials;
        let key = credentials.asr_api_key.clone().filter(|value| !value.trim().is_empty())
            .ok_or("Configure a chave do canal ElevenLabs.")?;
        let endpoint = credentials.asr_endpoint.clone().unwrap_or_else(|| "https://api.elevenlabs.io/v1".into());
        let mut url = url::Url::parse(&endpoint).map_err(|_| "Endpoint de reconhecimento inválido")?;
        if url.scheme() != "https" || !url.username().is_empty() || url.password().is_some() {
            return Err("O reconhecimento de reuniões exige um endpoint HTTPS sem credenciais na URL.".into());
        }
        url.set_path(&format!("{}/speech-to-text", url.path().trim_end_matches('/')));
        let client = openless_core::polish::http_client_builder(url.as_str(), 900)
            .redirect(reqwest::redirect::Policy::none()).build().map_err(|e| e.to_string())?;
        Some((client, url, key, credentials))
        };
        let mut speakers = Vec::new();
        let mut segments = Vec::new();
        let tracks = doc.analysis_tracks();
        if tracks.is_empty() { return Err("Não há áudio finalizado para transcrever.".into()); }
        for (index, track) in tracks.iter().enumerate() {
            self.cancelled()?;
            Self::progress(app, doc.id, "transcribing", index, tracks.len());
            let path = store.media_directory(doc.id).map_err(|e| e.message)?
                .join(format!("analysis-{}.wav", Uuid::new_v4()));
            let working = WorkingFile(path.clone());
            let cloned_store = store.clone();
            let document = doc.clone();
            let cancelled = Arc::clone(&self.cancelled);
            let track_id = track.id;
            let duration = tokio::task::spawn_blocking(move || {
                materialize_track(&cloned_store, &document, track_id, &path, || cancelled.load(Ordering::Acquire))
            }).await.map_err(|e| e.to_string())?.map_err(|e| e.message)?;
            let bytes = if local {
                let response = native::call(json!({"command":"transcribeLocal", "path":working.0,"modelDirectory":model_directory})).await?;
                serde_json::to_vec(&response).map_err(|error| error.to_string())?
            } else {
            let (client, url, key, credentials) = cloud.as_ref().ok_or("Configuração de reconhecimento ausente")?;
            let file = tokio::fs::File::open(&working.0).await.map_err(|e| e.to_string())?;
            let length = file.metadata().await.map_err(|e| e.to_string())?.len();
            let stream = futures_util::stream::try_unfold(file, |mut file| async move {
                let mut buffer = vec![0u8; 64 * 1024];
                let count = file.read(&mut buffer).await?;
                if count == 0 { Ok::<_, std::io::Error>(None) }
                else { buffer.truncate(count); Ok(Some((buffer, file))) }
            });
            let part = reqwest::multipart::Part::stream_with_length(reqwest::Body::wrap_stream(stream), length)
                .file_name("meeting.wav").mime_str("audio/wav").map_err(|e| e.to_string())?;
            let mut form = reqwest::multipart::Form::new().part("file", part)
                .text("model_id", credentials.asr_model.clone().filter(|value| !value.is_empty())
                    .unwrap_or_else(|| openless_core::asr::elevenlabs::DEFAULT_MODEL.into()))
                .text("diarize", "true").text("timestamps_granularity", "word")
                .text("tag_audio_events", "false");
            if !doc.language.trim().is_empty() {
                form = form.text("language_code", doc.language.split('-').next().unwrap_or(&doc.language).to_owned());
            }
            let request = async {
                let mut response = client.post(url.clone()).header("xi-api-key", key.as_str()).multipart(form)
                    .send().await.map_err(|_| "Falha de rede no reconhecimento da reunião".to_string())?;
                if !response.status().is_success() { return Err(format!("O reconhecimento retornou HTTP {}. O áudio foi preservado.", response.status().as_u16())); }
                let mut bytes = Vec::new();
                while let Some(part) = response.chunk().await.map_err(|_| "Resposta de reconhecimento interrompida")? {
                    if bytes.len() + part.len() > 64 * 1024 * 1024 { return Err("Resposta de reconhecimento excedeu o limite de memória.".into()); }
                    bytes.extend_from_slice(&part);
                }
                Ok(bytes)
            };
            let cancellation = self.cancel_notify.notified();
            tokio::pin!(cancellation);
            cancellation.as_mut().enable();
            self.cancelled()?;
            let bytes = tokio::select! {
                result = request => result?,
                _ = cancellation => return Err("Transcrição cancelada; o áudio foi preservado.".into()),
            };
            bytes
            };
            self.cancelled()?;
            let (new_speakers, new_segments) = admit_scribe(&bytes, track.id, duration, speakers.len()).map_err(|e| e.message)?;
            speakers.extend(new_speakers); segments.extend(new_segments);
        }
        segments.sort_by_key(|segment| segment.start_ms);
        self.cancelled()?;
        if segments.is_empty() { return Err("O provedor não encontrou fala. O áudio foi preservado.".into()); }
        doc.replace_transcript(speakers, segments).map_err(|e| e.message)?;
        doc.state = MeetingState::Completed;
        store.save(&doc).map_err(|e| e.message)
    }

    async fn summarize(&self, app: &tauri::AppHandle, store: &MeetingStore, mut doc: MeetingDocument, channel_id: Option<String>) -> Result<MeetingDocument, String> {
        if doc.segments.is_empty() { return Err("Transcreva a reunião antes de gerar o resumo.".into()); }
        let (configuration, protocol, extra_headers) = tokio::task::spawn_blocking(move || CredentialsVault::meeting_summary_snapshot(channel_id.as_deref()))
            .await.map_err(|e| e.to_string())?.map_err(|e| e.to_string())?;
        let provider_id = configuration.active_llm_provider;
        if matches!(provider_id.as_str(), "codex-oauth" | "siwc") {
            return Err("Selecione um canal de IA com endpoint de API para gerar resumos de reuniões.".into());
        }
        let credentials = configuration.credentials;
        let model = credentials.ark_model_id.filter(|value| !value.trim().is_empty())
            .or_else(|| openless_core::provider_rules::default_llm_model(&provider_id).map(str::to_owned))
            .ok_or("Configure o modelo de IA para resumos.")?;
        let endpoint = credentials.ark_endpoint.filter(|value| !value.trim().is_empty())
            .or_else(|| openless_core::provider_rules::default_llm_endpoint(&provider_id).map(str::to_owned))
            .ok_or("Configure o endpoint de IA para resumos.")?;
        let mut config = openless_core::polish::OpenAICompatibleConfig::new(
            &provider_id, &provider_id, endpoint, credentials.ark_api_key.unwrap_or_default(), &model);
        config.protocol = protocol;
        config.extra_headers = extra_headers;
        config.request_timeout_secs = 240;
        let gemini = if provider_id == "gemini" {
            let mut gemini = openless_core::llm_gemini::GeminiConfig::new(&config.api_key, &model, &config.base_url);
            gemini.request_timeout_secs = 240;
            gemini.extra_headers = config.extra_headers.clone();
            Some(openless_core::llm_gemini::GeminiProvider::new(gemini))
        } else { None };
        let provider = openless_core::polish::OpenAICompatibleLLMProvider::new(config);
        let ids: HashSet<_> = doc.segments.iter().map(|segment| segment.id).collect();
        let speaker_names: HashMap<_, _> = doc.speakers.iter().map(|speaker| (speaker.id, &speaker.name)).collect();
        let mut batches = Vec::new();
        let mut batch = String::new();
        for segment in &doc.segments {
            let line = json!({"id":segment.id,"startMs":segment.start_ms,"speaker":segment.speaker_id.and_then(|id| speaker_names.get(&id)),"text":segment.text}).to_string();
            if line.len() > 24_000 { return Err("Um trecho excede o limite de contexto. Divida-o antes de resumir.".into()); }
            if !batch.is_empty() && batch.len() + line.len() > 24_000 { batches.push(std::mem::take(&mut batch)); }
            batch.push_str(&line); batch.push('\n');
        }
        if !batch.is_empty() { batches.push(batch); }
        // Each map/reduce round is bounded. Fail visibly if a model cannot condense its output.
        for round in 0..8 {
            let total = batches.len();
            let mut outputs = Vec::new();
            for (index, source) in batches.iter().enumerate() {
                self.cancelled()?;
                Self::progress(app, doc.id, "summarizing", index, total);
                let cancellation = self.cancel_notify.notified();
                tokio::pin!(cancellation);
                cancellation.as_mut().enable();
                self.cancelled()?;
                let result = tokio::select! {
                    result = async {
                        match &gemini {
                            Some(provider) => provider.summarize_meeting(SUMMARY_INSTRUCTIONS, source).await,
                            None => provider.summarize_meeting(SUMMARY_INSTRUCTIONS, source).await,
                        }
                    } => result.map_err(meeting_summary_error)?,
                    _ = cancellation => return Err("Resumo cancelado; o resultado anterior foi preservado.".into()),
                };
                let result = admit_summary(&result, &ids).map_err(|e| e.message)?;
                outputs.push(result);
            }
            if outputs.len() == 1 {
                let result = outputs.remove(0);
                self.cancelled()?;
                doc.summary = Some(MeetingSummary {
                    transcript_revision: doc.transcript_revision, provider: provider_id, model,
                    prompt_version: 1, generated_at: chrono::Utc::now(), text: result.text,
                    decisions: result.decisions, tasks: result.tasks,
                });
                return store.save(&doc).map_err(|e| e.message);
            }
            batches.clear();
            let mut batch = String::new();
            for output in outputs {
                let source = serde_json::to_string(&output).map_err(|e| e.to_string())?;
                if source.len() > 24_000 { return Err("O modelo produziu um resumo intermediário muito grande. Selecione outro modelo.".into()); }
                if !batch.is_empty() && batch.len() + source.len() > 24_000 { batches.push(std::mem::take(&mut batch)); }
                batch.push_str(&source); batch.push('\n');
            }
            if !batch.is_empty() { batches.push(batch); }
            if batches.len() >= total && round > 0 { return Err("O modelo não conseguiu consolidar os resumos sem exceder o contexto.".into()); }
        }
        Err("A reunião excedeu o limite de consolidação do modelo. O resumo anterior foi preservado.".into())
    }
}

struct WorkingFile(std::path::PathBuf);
impl Drop for WorkingFile {
    fn drop(&mut self) {
        if let Err(error) = std::fs::remove_file(&self.0) {
            if error.kind() != std::io::ErrorKind::NotFound { log::warn!("could not remove meeting working audio: {error}"); }
        }
    }
}

#[tauri::command]
pub async fn meetings_command(
    window: tauri::Window, app: tauri::AppHandle,
    core: tauri::State<'_, Arc<openless_core::OpenLessBackend>>,
    runtime: tauri::State<'_, MeetingRuntime>, request: MeetingRequest,
) -> Result<Value, String> {
    if window.label() != "main" { return Err("meeting_main_window_required".into()); }
    let store = runtime.store(&core);
    if matches!(&request, MeetingRequest::Providers) {
        return tokio::task::spawn_blocking(CredentialsVault::meeting_channels)
            .await.map_err(|error| error.to_string())?.map_err(|error| error.to_string());
    }
    if matches!(&request, MeetingRequest::List) {
        let catalog = store.list().map_err(|e| e.message)?;
        let active = runtime.active.lock().map_err(|_| "Não foi possível acessar o estado da reunião")?.as_ref().map(|entry| entry.0);
        let busy = runtime.operation.try_lock().is_err();
        let health = if active.is_some() && !busy {
            native::call(json!({"command":"status"})).await?
        } else { Value::Null };
        let models = if cfg!(target_os="macos") && !busy {
            native::call(json!({"command":"modelsStatus","modelDirectory":runtime.model_directory(&core)})).await?
        } else { Value::Null };
        let echo_supported = models.get("echoSupported").and_then(Value::as_bool).unwrap_or(false);
        return Ok(json!({"catalog":catalog,"activeId":active,"models":models,"echo":health.get("echo"),"live":health.get("live"),
            "echoSupported":echo_supported,
            "busy":busy,"captureError":health.get("captureError"),"supported":cfg!(target_os="macos")}));
    }
    if matches!(&request, MeetingRequest::Cancel) {
        runtime.cancelled.store(true, Ordering::Release);
        runtime.cancel_notify.notify_waiters();
        native::cancel();
        return Ok(Value::Null);
    }
    let _operation = runtime.operation.try_lock().map_err(|_| "Aguarde a operação de reunião atual ou cancele-a.")?;
    if runtime.exiting.load(Ordering::Acquire) { return Err("O aplicativo está encerrando.".into()); }
    runtime.cancelled.store(false, Ordering::Release);
    match request {
        MeetingRequest::Applications => native::call(json!({"command":"applications"})).await,
        MeetingRequest::DownloadModel { model } => native::call(json!({"command":"downloadModel","id":model,"modelDirectory":runtime.model_directory(&core)})).await,
        MeetingRequest::CancelModelDownload => native::call(json!({"command":"cancelModelDownload"})).await,
        MeetingRequest::RemoveModel { model } => {
            if runtime.active.lock().map_err(|_| "Não foi possível acessar o estado da reunião")?.is_some() { return Err("Finalize a gravação antes de excluir modelos.".into()); }
            native::call(json!({"command":"removeModel","id":model,"modelDirectory":runtime.model_directory(&core)})).await
        }
        MeetingRequest::Start { title, language, pid, live, echo_cancellation } => {
            if runtime.active.lock().map_err(|_| "Não foi possível acessar o estado da reunião")?.is_some() { return Err("Já há uma reunião gravando.".into()); }
            let lease = core.reserve_meeting_resources().await.map_err(|e| e.message)?;
            let mut doc = MeetingDocument::new(title, language.clone(), if pid.is_some() { MeetingOrigin::OnlineCall } else { MeetingOrigin::InRoom });
            store.create(&doc).map_err(|e| e.message)?;
            let directory = store.media_directory(doc.id).map_err(|e| e.message)?;
            match native::call(json!({"command":"start","directory":directory,"pid":pid,"language":language,"live":live,"echoCancellation":echo_cancellation,"modelDirectory":runtime.model_directory(&core)})).await {
                Ok(_) => {
                    if runtime.cancelled.load(Ordering::Acquire) {
                        native::call(json!({"command":"stop"})).await?;
                        runtime.recover_media(store, &mut doc)?;
                        doc.state = MeetingState::Interrupted;
                        store.save(&doc).map_err(|e| e.message)?;
                        return Err("Gravação cancelada; o áudio finalizado foi preservado.".into());
                    }
                    doc.state = MeetingState::Recording;
                    let saved = match store.save(&doc) {
                        Ok(saved) => saved,
                        Err(error) => {
                            if let Err(stop_error) = native::call(json!({"command":"stop"})).await {
                                log::error!("meeting capture cleanup failed after persistence failure: {stop_error}");
                            }
                            return Err(error.message);
                        }
                    };
                    *runtime.active.lock().map_err(|_| "Não foi possível acessar o estado da reunião")? = Some((doc.id, lease));
                    Ok(json!(saved))
                }
                Err(error) => { doc.state = MeetingState::Failed; store.save(&doc).map_err(|e| e.message)?; Err(error) }
            }
        }
        MeetingRequest::Stop => {
            let id = runtime.active.lock().map_err(|_| "Não foi possível acessar o estado da reunião")?
                .as_ref().map(|entry| entry.0).ok_or("Não há reunião gravando.")?;
            // The lease stays alive until native capture and its writers have drained.
            let stopped = native::call(json!({"command":"stop"})).await;
            let active = runtime.active.lock().map_err(|_| "Não foi possível acessar o estado da reunião")?.take();
            let mut doc = store.load(id).map_err(|e| e.message)?;
            runtime.recover_media(store, &mut doc)?;
            doc.state = if stopped.as_ref().is_ok_and(|result| result.get("captureError").is_none()) { MeetingState::Completed } else { MeetingState::Interrupted };
            let saved = store.save(&doc).map_err(|e| e.message)?;
            drop(active);
            if let Some(error) = stopped?.get("captureError").and_then(Value::as_str) {
                return Err(format!("A gravação foi interrompida: {error}. O áudio finalizado foi preservado."));
            }
            Ok(json!(saved))
        }
        MeetingRequest::Import { language } => {
            let _lease = core.reserve_meeting_resources().await.map_err(|e| e.message)?;
            let dialog_app = app.clone();
            let selected = tokio::task::spawn_blocking(move || dialog_app.dialog().file()
                .add_filter("Áudio e vídeo", &["wav","mp3","m4a","aac","aiff","caf","flac","ogg","opus","mp4","mov","m4v"])
                .blocking_pick_file()).await.map_err(|e| e.to_string())?;
            let Some(selected) = selected else { return Ok(Value::Null); };
            runtime.cancelled()?;
            let path = match selected { FilePath::Path(path) => path, FilePath::Url(url) => url.to_file_path().map_err(|_| "Selecione um arquivo local")? };
            let title = path.file_stem().and_then(|name| name.to_str()).unwrap_or("Reunião importada").to_owned();
            let mut doc = MeetingDocument::new(title, language, MeetingOrigin::ImportedAudio);
            store.create(&doc).map_err(|e| e.message)?;
            let directory = store.media_directory(doc.id).map_err(|e| e.message)?;
            MeetingRuntime::progress(&app, doc.id, "importing", 0, 1);
            let result = native::call(json!({"command":"import","directory":directory,"path":path})).await;
            runtime.recover_media(store, &mut doc)?;
            match result {
                Ok(result) => {
                    if result.get("video").and_then(Value::as_bool) == Some(true) { doc.origin = MeetingOrigin::ImportedVideo; }
                    doc.state = if runtime.cancelled.load(Ordering::Acquire) { MeetingState::Interrupted } else { MeetingState::Completed };
                    let saved = store.save(&doc).map_err(|e| e.message)?;
                    runtime.cancelled()?;
                    Ok(json!(saved))
                }
                Err(error) => { doc.state = MeetingState::Interrupted; store.save(&doc).map_err(|e| e.message)?; Err(error) }
            }
        }
        MeetingRequest::Transcribe { id, channel_id, local } => {
            let _lease = core.reserve_meeting_resources().await.map_err(|e| e.message)?;
            let doc = store.load(id).map_err(|e| e.message)?;
            runtime.transcribe(&app, store, doc, channel_id, local, runtime.model_directory(&core)).await.map(|doc| json!(doc))
        }
        MeetingRequest::Summarize { id, channel_id } => {
            let _lease = core.reserve_meeting_resources().await.map_err(|e| e.message)?;
            let doc = store.load(id).map_err(|e| e.message)?;
            runtime.summarize(&app, store, doc, channel_id).await.map(|doc| json!(doc))
        }
        MeetingRequest::Recover { id } => {
            let _lease = core.reserve_meeting_resources().await.map_err(|e| e.message)?;
            let mut doc = store.load(id).map_err(|e| e.message)?;
            runtime.recover_media(store, &mut doc)?;
            doc.state = MeetingState::Interrupted;
            Ok(json!(store.save(&doc).map_err(|e| e.message)?))
        }
        MeetingRequest::Edit { id, revision, title, speakers, segments } => {
            if runtime.active.lock().map_err(|_| "Não foi possível acessar o estado da reunião")?.is_some() { return Err("Finalize a gravação antes de editar.".into()); }
            let mut doc = store.load(id).map_err(|e| e.message)?;
            if revision != doc.revision { return Err("A reunião mudou. Atualize antes de salvar.".into()); }
            doc.title = title;
            if doc.speakers != speakers || doc.segments != segments { doc.replace_transcript(speakers, segments).map_err(|e| e.message)?; }
            Ok(json!(store.save(&doc).map_err(|e| e.message)?))
        }
        MeetingRequest::ReadAudio { id, chunk_id } => {
            let path = store.chunk_path(id, chunk_id).map_err(|e| e.message)?;
            let size = tokio::fs::metadata(&path).await.map_err(|e| e.to_string())?.len();
            if size > 4 * 1024 * 1024 { return Err("Bloco de áudio excede o limite de reprodução.".into()); }
            let bytes = tokio::fs::read(path).await.map_err(|e| e.to_string())?;
            Ok(json!(format!("data:audio/wav;base64,{}", base64::engine::general_purpose::STANDARD.encode(bytes))))
        }
        MeetingRequest::Export { id, format } => {
            let doc = store.load(id).map_err(|e| e.message)?;
            if format == "json" { return Ok(json!(serde_json::to_string_pretty(&doc).map_err(|e| e.to_string())?)); }
            if !matches!(format.as_str(), "txt" | "md") { return Err("Formato de exportação inválido".into()); }
            let names: HashMap<_, _> = doc.speakers.iter().map(|speaker| (speaker.id, speaker.name.as_str())).collect();
            let mut text = format!("# {}\n\n", doc.title);
            for segment in &doc.segments {
                let name = segment.speaker_id.and_then(|id| names.get(&id).copied()).unwrap_or("Sem atribuição");
                text.push_str(&format!("[{:02}:{:02}] {}: {}\n\n", segment.start_ms / 60000, segment.start_ms / 1000 % 60, name, segment.text));
            }
            if doc.summary_is_current() {
                if let Some(summary) = &doc.summary {
                    text.push_str(&format!("## Resumo\n\n{}\n\n## Decisões\n\n", summary.text));
                    for decision in &summary.decisions { text.push_str(&format!("- {}\n", decision.description)); }
                    text.push_str("\n## Tarefas\n\n");
                    for task in &summary.tasks { text.push_str(&format!("- {} — responsável: {}; prazo: {}\n", task.description, task.owner.as_deref().unwrap_or("não definido"), task.deadline.as_deref().unwrap_or("não definido"))); }
                }
            }
            Ok(json!(text))
        }
        MeetingRequest::List | MeetingRequest::Providers | MeetingRequest::Cancel => unreachable!("handled before operation admission"),
    }
}

/// Keep the event loop alive while the final recording block is made durable.
pub fn defer_exit(app: &tauri::AppHandle, code: Option<i32>) -> bool {
    let Some(runtime) = app.try_state::<MeetingRuntime>() else { return false; };
    if !runtime.active.lock().is_ok_and(|active| active.is_some()) { return false; }
    if runtime.exiting.swap(true, Ordering::AcqRel) { return true; }
    let app = app.clone();
    tauri::async_runtime::spawn(async move {
        let cleanup = async {
            let runtime = app.state::<MeetingRuntime>();
            let _operation = runtime.operation.lock().await;
            let active = runtime.active.lock().map_err(|_| "Não foi possível acessar o estado da reunião")?.take();
            if let Some((id, _lease)) = active {
                let result = native::call(json!({"command":"stop"})).await;
                let core = app.state::<Arc<openless_core::OpenLessBackend>>();
                let store = runtime.store(&core);
                let mut doc = store.load(id).map_err(|error| error.message)?;
                runtime.recover_media(store, &mut doc)?;
                doc.state = if result.as_ref().is_ok_and(|value| value.get("captureError").is_none()) {
                    MeetingState::Completed
                } else { MeetingState::Interrupted };
                store.save(&doc).map_err(|error| error.message)?;
                result?;
            }
            Ok::<(), String>(())
        };
        match tokio::time::timeout(std::time::Duration::from_secs(8), cleanup).await {
            Ok(Ok(())) => {},
            Ok(Err(error)) => log::error!("meeting exit cleanup failed; finalized blocks remain recoverable: {error}"),
            Err(_) => log::error!("meeting exit cleanup timed out; finalized blocks remain recoverable"),
        }
        if let Some(runtime) = app.try_state::<MeetingRuntime>() {
            if let Ok(mut active) = runtime.active.lock() { active.take(); }
        }
        app.exit(code.unwrap_or(0));
    });
    true
}

pub fn prepare_restart(app: &tauri::AppHandle) -> Result<(), String> {
    let Some(runtime) = app.try_state::<MeetingRuntime>() else { return Ok(()); };
    let _operation = runtime.operation.try_lock()
        .map_err(|_| "Finalize a operação de reunião antes de reiniciar o aplicativo.")?;
    if runtime.active.lock().map_err(|_| "Não foi possível acessar o estado da reunião")?.is_some() {
        return Err("Finalize a gravação da reunião antes de reiniciar o aplicativo.".into());
    }
    runtime.exiting.store(true, Ordering::Release);
    Ok(())
}

