import { useCallback, useEffect, useRef, useState } from 'react';
import { useTranslation } from 'react-i18next';
import { isTauriNow } from '../lib/ipc/shared';
import {
  meetingCommand,
  type MeetingApplication,
  type MeetingDocument,
  type MeetingProgress,
  type MeetingProviders,
  type MeetingRequest,
  type MeetingSnapshot,
} from '../lib/ipc/meetings';
import { Btn, Card, PageHeader } from './_atoms';
import './meetings.css';

const empty: MeetingSnapshot = {
  busy: false,
  catalog: { meetings: [], errors: [] },
  activeId: null,
  supported: false,
};
const LOCAL_ASR = 'local:parakeet-nemotron';
const clock = (ms: number) =>
  `${Math.floor(ms / 60000)
    .toString()
    .padStart(2, '0')}:${Math.floor((ms / 1000) % 60)
    .toString()
    .padStart(2, '0')}`;

export function Meetings() {
  const { t } = useTranslation();
  const [snapshot, setSnapshot] = useState<MeetingSnapshot>(empty);
  const [selected, setSelected] = useState<MeetingDocument | null>(null);
  const selectedRef = useRef<string | null>(null);
  const [dirty, setDirty] = useState(false);
  const dirtyRef = useRef(false);
  const [localBusy, setBusy] = useState(false);
  const busy = localBusy || snapshot.busy;
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState('');
  const [applications, setApplications] = useState<MeetingApplication[]>([]);
  const [pid, setPid] = useState('');
  const [title, setTitle] = useState('');
  const [providers, setProviders] = useState<MeetingProviders>({ asr: [], llm: [] });
  const [asrChannel, setAsrChannel] = useState('');
  const [summaryChannel, setSummaryChannel] = useState('');
  const [language, setLanguage] = useState('pt-BR');
  const [live, setLive] = useState(false);
  const [echo, setEcho] = useState(true);
  const models = snapshot.models;
  const downloaded = (id: 'parakeet' | 'nemotron' | 'live') =>
    models?.items.some((model) => model.id === id && model.ready) ?? false;
  const localReady = !!models?.supported && downloaded('parakeet') && downloaded('nemotron');
  const liveLanguage = language.split('-')[0];
  const liveReady =
    !!models?.liveSupported &&
    ['en', 'pt', 'es', 'fr', 'de'].includes(liveLanguage) &&
    downloaded(liveLanguage === 'en' ? 'live' : 'parakeet');
  const [progress, setProgress] = useState<MeetingProgress | null>(null);
  const [audio, setAudio] = useState<{ url: string; offset: number } | null>(null);
  const player = useRef<HTMLAudioElement>(null);
  const alive = useRef(true);
  const label = (key: string) => t(`meetings.${key}`);

  const refresh = useCallback(async () => {
    const result = await meetingCommand<MeetingSnapshot>({ action: 'list' });
    if (!alive.current) return;
    setSnapshot((previous) => ({
      ...result,
      models: result.models ?? previous.models,
      echoSupported: result.models ? result.echoSupported : previous.echoSupported,
      live: result.live ?? (result.activeId ? previous.live : null),
    }));
    if (!dirtyRef.current) {
      setSelected(
        result.catalog.meetings.find((item) => item.id === selectedRef.current) ??
          result.catalog.meetings[0] ??
          null,
      );
    }
  }, []);

  useEffect(() => {
    alive.current = true;
    void refresh()
      .catch((e) => {
        if (alive.current) setError(String(e));
      })
      .finally(() => {
        if (alive.current) setLoading(false);
      });
    return () => {
      alive.current = false;
    };
  }, [refresh]);

  useEffect(() => {
    let disposed = false;
    void meetingCommand<MeetingProviders>({ action: 'providers' })
      .then((result) => {
        if (!disposed) setProviders(result);
      })
      .catch((error) => {
        if (!disposed) setError(String(error));
      });
    return () => {
      disposed = true;
    };
  }, []);

  useEffect(() => {
    if (!isTauriNow()) return;
    let disposed = false;
    let unlisten: (() => void) | undefined;
    void import('@tauri-apps/api/event')
      .then(async ({ listen }) => {
        const release = await listen<MeetingProgress>('meeting:progress', (event) => {
          if (!disposed) setProgress(event.payload);
        });
        if (disposed) release();
        else unlisten = release;
      })
      .catch((e) => {
        if (!disposed) setError(String(e));
      });
    return () => {
      disposed = true;
      unlisten?.();
    };
  }, []);

  useEffect(() => {
    if (!snapshot.busy && !snapshot.activeId && !snapshot.models?.downloading) return;
    const timer = window.setInterval(() => {
      void refresh().catch((e) => {
        if (alive.current) setError(String(e));
      });
    }, 1500);
    return () => window.clearInterval(timer);
  }, [snapshot.busy, snapshot.activeId, snapshot.models?.downloading, refresh]);

  async function run<T>(request: MeetingRequest, apply?: (result: T) => void) {
    setBusy(true);
    setError('');
    setProgress(null);
    try {
      const result = await meetingCommand<T>(request);
      if (alive.current) apply?.(result);
    } catch (e) {
      if (alive.current) setError(String(e));
    } finally {
      try {
        await refresh();
      } catch (e) {
        if (alive.current) setError(String(e));
      }
      if (alive.current) {
        setBusy(false);
        setProgress(null);
      }
    }
  }

  function accept(doc: MeetingDocument | null) {
    if (!doc) return;
    selectedRef.current = doc.id;
    dirtyRef.current = false;
    setDirty(false);
    setSelected(doc);
    setAudio(null);
  }

  function edit(doc: MeetingDocument) {
    dirtyRef.current = true;
    setDirty(true);
    setSelected(doc);
  }

  const hasActive = snapshot.activeId !== null;
  const canProcess = !!selected && !busy && !hasActive && !dirty;
  const interrupted =
    !!selected &&
    ['preparing', 'recording', 'stopping', 'processing', 'interrupted'].includes(selected.state) &&
    selected.id !== snapshot.activeId &&
    !snapshot.busy;

  async function play(chunkId: string, offset = 0) {
    if (!selected) return;
    setError('');
    try {
      const url = await meetingCommand<string>({ action: 'readAudio', id: selected.id, chunkId });
      setAudio({ url, offset });
    } catch (e) {
      setError(String(e));
    }
  }

  function exportFile(format: 'md' | 'txt' | 'json') {
    if (!selected) return;
    void run<string>({ action: 'export', id: selected.id, format }, (content) => {
      const url = URL.createObjectURL(
        new Blob([content], {
          type: format === 'json' ? 'application/json' : 'text/plain;charset=utf-8',
        }),
      );
      const link = document.createElement('a');
      link.href = url;
      link.download = `meeting-${selected.id}.${format}`;
      document.body.append(link);
      link.click();
      link.remove();
      window.setTimeout(() => URL.revokeObjectURL(url), 1000);
    });
  }

  return (
    <div className="meetings-page">
      <PageHeader title={label('title')} desc={label('subtitle')} />
      <Card>
        <div className="meetings-controls">
          <label>
            {label('recordingTitle')}
            <input
              value={title}
              disabled={busy || hasActive}
              onChange={(e) => setTitle(e.target.value)}
            />
          </label>
          <label>
            {label('language')}
            <select
              value={language}
              disabled={busy || hasActive}
              onChange={(e) => {
                setLanguage(e.target.value);
              }}
            >
              <option value="pt-BR">{label('language_pt')}</option>
              <option value="en">{label('language_en')}</option>
              <option value="es">{label('language_es')}</option>
              <option value="fr">{label('language_fr')}</option>
              <option value="de">{label('language_de')}</option>
              <option value="zh">{label('language_zh')}</option>
            </select>
          </label>
          <label>
            {label('source')}
            <select
              value={pid}
              disabled={busy || hasActive}
              onChange={(e) => setPid(e.target.value)}
            >
              <option value="">{label('inRoom')}</option>
              {applications.map((app) => (
                <option key={app.pid} value={app.pid}>
                  {app.name} ({app.pid})
                </option>
              ))}
            </select>
          </label>
          <label className="meeting-option">
            <input
              type="checkbox"
              checked={live && liveReady}
              disabled={busy || hasActive || !liveReady}
              onChange={(event) => setLive(event.target.checked)}
            />
            {label('liveOption')}
          </label>
          <label className="meeting-option">
            <input
              type="checkbox"
              checked={echo && !!pid && !!snapshot.echoSupported}
              disabled={busy || hasActive || !pid || !snapshot.echoSupported}
              onChange={(event) => setEcho(event.target.checked)}
            />
            {label('echoOption')}
          </label>
          <Btn
            disabled={busy || hasActive || !snapshot.supported}
            onClick={() =>
              void run<{ applications: MeetingApplication[] }>(
                { action: 'applications' },
                (result) => setApplications(result.applications),
              )
            }
          >
            {label('refreshApps')}
          </Btn>
          {hasActive ? (
            <Btn
              disabled={busy}
              onClick={() => void run<MeetingDocument>({ action: 'stop' }, accept)}
            >
              {label('stop')}
            </Btn>
          ) : (
            <Btn
              disabled={busy || !snapshot.supported || !title.trim() || dirty}
              onClick={() =>
                void run<MeetingDocument>(
                  {
                    action: 'start',
                    title: title.trim(),
                    language,
                    pid: pid ? Number(pid) : null,
                    live: live && liveReady,
                    echoCancellation: !!pid && !!snapshot.echoSupported && echo,
                  },
                  accept,
                )
              }
            >
              {label('record')}
            </Btn>
          )}
          <Btn
            disabled={busy || hasActive || !snapshot.supported || dirty}
            onClick={() => void run<MeetingDocument | null>({ action: 'import', language }, accept)}
          >
            {label('import')}
          </Btn>
        </div>
        {pid && <p className="meetings-muted">{label('headphones')}</p>}
        {!loading && !snapshot.supported && <p>{label('unsupported')}</p>}
      </Card>
      {busy && (
        <div role="status" className="meetings-actions">
          {label('progress')} {progress && `${progress.completed + 1}/${progress.total}`}
          <Btn
            onClick={() => {
              void meetingCommand({ action: 'cancel' }).catch((e) => setError(String(e)));
            }}
          >
            {label('cancel')}
          </Btn>
        </div>
      )}
      {models && snapshot.supported && (
        <Card>
          <h3>{label('localModels')}</h3>
          <p className="meetings-muted">{label('localModelsHint')}</p>
          {!models.supported && <p>{label('localUnsupported')}</p>}
          <div className="meetings-models">
            {models.items.map((model) => (
              <div key={model.id}>
                <strong>{label(`model_${model.id}`)}</strong>
                <p className="meetings-muted">
                  {model.license} · {model.ready ? label('modelReady') : label('modelMissing')}
                </p>
                <Btn
                  disabled={busy || hasActive || !!models.downloading || !models.supported}
                  onClick={() =>
                    void run({
                      action: model.ready ? 'removeModel' : 'downloadModel',
                      model: model.id,
                    })
                  }
                >
                  {model.ready ? label('removeModel') : label('downloadModel')}
                </Btn>
              </div>
            ))}
          </div>
          {models.downloading && (
            <div role="status" className="meetings-actions">
              <span>
                {label('downloading')} {label(`model_${models.downloading}`)} ·{' '}
                {Math.floor(models.completedBytes / 1048576)} /{' '}
                {Math.ceil(models.totalBytes / 1048576)} MiB
              </span>
              <Btn disabled={busy} onClick={() => void run({ action: 'cancelModelDownload' })}>
                {label('cancel')}
              </Btn>
            </div>
          )}
          {models.error && (
            <p role="status" className="meetings-error">
              {models.error}
            </p>
          )}
        </Card>
      )}
      {hasActive && snapshot.live && (
        <Card>
          <h3>{label('liveTitle')}</h3>
          <p className="meetings-muted">{label('liveHint')}</p>
          {snapshot.live.warning && <p role="status">{snapshot.live.warning}</p>}
          <div className="meeting-live" aria-live="polite">
            {snapshot.live.turns.slice(-12).map((turn, index) => (
              <p key={index}>
                <strong>{label(`track_${turn.kind}`)}: </strong>
                {turn.text}
              </p>
            ))}
            {Object.entries(snapshot.live.partials)
              .filter(([, text]) => text)
              .map(([kind, text]) => (
                <p key={kind} className="meetings-muted">
                  <strong>{label(`track_${kind}`)}: </strong>
                  {text}
                </p>
              ))}
          </div>
        </Card>
      )}
      {hasActive && snapshot.echo && (
        <p role="status">
          {snapshot.echo.warning || label(snapshot.echo.active ? 'echoActive' : 'echoWarming')}
        </p>
      )}
      {snapshot.captureError && (
        <p role="alert" className="meetings-error">
          {snapshot.captureError}
        </p>
      )}
      {error && (
        <p role="alert" className="meetings-error">
          {error}
        </p>
      )}
      {snapshot.catalog.errors.map((message) => (
        <p role="alert" className="meetings-error" key={message}>
          {message}
        </p>
      ))}
      {loading ? (
        <p role="status">{label('loading')}</p>
      ) : !snapshot.catalog.meetings.length ? (
        <Card>{label('empty')}</Card>
      ) : (
        <div className="meetings-split">
          <aside aria-label={label('title')}>
            {snapshot.catalog.meetings.map((doc) => (
              <button
                key={doc.id}
                className={selected?.id === doc.id ? 'meeting-entry selected' : 'meeting-entry'}
                disabled={dirty || busy}
                onClick={() => accept(doc)}
              >
                <strong>{doc.title}</strong>
                <span>{new Date(doc.createdAt).toLocaleString()}</span>
                <span>
                  {doc.id === snapshot.activeId
                    ? label('active')
                    : doc.state === 'completed'
                      ? label('saved')
                      : doc.state === 'failed'
                        ? label('failed')
                        : label('interrupted')}
                </span>
              </button>
            ))}
          </aside>
          {selected && (
            <main className="meeting-detail">
              <label>
                {label('recordingTitle')}
                <input
                  value={selected.title}
                  disabled={busy || hasActive}
                  onChange={(e) => edit({ ...selected, title: e.target.value })}
                />
              </label>
              <div className="meetings-controls">
                <label>
                  {label('transcriptionModel')}
                  <select
                    value={asrChannel}
                    disabled={!canProcess}
                    onChange={(event) => setAsrChannel(event.target.value)}
                  >
                    <option value="">{label('currentAsrChannel')}</option>
                    <option value={LOCAL_ASR} disabled={!localReady}>
                      {label('localAsr')}
                    </option>
                    {providers.asr.map((channel) => (
                      <option key={channel.id} value={channel.id}>
                        {channel.name || channel.providerType}
                        {channel.model ? ` · ${channel.model}` : ''}
                      </option>
                    ))}
                  </select>
                </label>
                <label>
                  {label('summaryModel')}
                  <select
                    value={summaryChannel}
                    disabled={!canProcess}
                    onChange={(event) => setSummaryChannel(event.target.value)}
                  >
                    <option value="">{label('currentLlmChannel')}</option>
                    {providers.llm.map((channel) => (
                      <option key={channel.id} value={channel.id}>
                        {channel.name || channel.providerType}
                        {channel.model ? ` · ${channel.model}` : ''}
                      </option>
                    ))}
                  </select>
                </label>
              </div>
              <p className="meetings-muted">{label('providerHint')}</p>
              <div className="meetings-actions">
                <Btn
                  disabled={
                    !canProcess ||
                    !selected.chunks.length ||
                    (asrChannel === LOCAL_ASR && !localReady)
                  }
                  onClick={() =>
                    void run<MeetingDocument>(
                      {
                        action: 'transcribe',
                        id: selected.id,
                        channelId: asrChannel && asrChannel !== LOCAL_ASR ? asrChannel : undefined,
                        local: asrChannel === LOCAL_ASR,
                      },
                      accept,
                    )
                  }
                >
                  {label('transcribe')}
                </Btn>
                <Btn
                  disabled={!canProcess || !selected.segments.length}
                  onClick={() =>
                    void run<MeetingDocument>(
                      {
                        action: 'summarize',
                        id: selected.id,
                        channelId: summaryChannel || undefined,
                      },
                      accept,
                    )
                  }
                >
                  {label('summarize')}
                </Btn>
                <Btn
                  disabled={!dirty || busy || hasActive || !selected.title.trim()}
                  onClick={() =>
                    void run<MeetingDocument>(
                      {
                        action: 'edit',
                        id: selected.id,
                        revision: selected.revision,
                        title: selected.title,
                        speakers: selected.speakers,
                        segments: selected.segments,
                      },
                      accept,
                    )
                  }
                >
                  {label('save')}
                </Btn>
                {(['md', 'txt', 'json'] as const).map((format) => (
                  <Btn key={format} disabled={busy || dirty} onClick={() => exportFile(format)}>
                    {label('export')} {format.toUpperCase()}
                  </Btn>
                ))}
              </div>
              <p className="meetings-muted">
                {label(asrChannel === LOCAL_ASR ? 'localPrivacy' : 'cloud')}
              </p>
              {selected.captureInfo?.echoCancellation?.warning && (
                <p role="status">{selected.captureInfo.echoCancellation.warning}</p>
              )}
              {dirty && <p role="status">{label('unsaved')}</p>}
              {interrupted && (
                <Card>
                  <p>{label('recovery')}</p>
                  <Btn
                    disabled={busy || hasActive || dirty}
                    onClick={() =>
                      void run<MeetingDocument>({ action: 'recover', id: selected.id }, accept)
                    }
                  >
                    {label('recover')}
                  </Btn>
                </Card>
              )}
              <audio
                ref={player}
                controls
                src={audio?.url}
                onLoadedMetadata={() => {
                  if (player.current && audio) {
                    player.current.currentTime = audio.offset;
                    void player.current.play().catch((e) => setError(String(e)));
                  }
                }}
                onError={() => {
                  if (audio) setError('Não foi possível reproduzir este bloco de áudio.');
                }}
              />
              <details>
                <summary>
                  {label('audio')} ({selected.chunks.length})
                </summary>
                <div className="meetings-actions">
                  {selected.chunks.map((chunk) => (
                    <Btn key={chunk.id} disabled={busy} onClick={() => void play(chunk.id)}>
                      {label(
                        `track_${selected.tracks.find((track) => track.id === chunk.trackId)?.kind ?? 'microphone'}`,
                      )}{' '}
                      {clock(chunk.startMs)}
                    </Btn>
                  ))}
                </div>
              </details>
              {selected.speakers.length > 0 && (
                <Card>
                  <h3>{label('speakers')}</h3>
                  <div className="meetings-controls">
                    {selected.speakers.map((speaker) => (
                      <label key={speaker.id}>
                        {label('speakerName')}
                        <input
                          value={speaker.name}
                          disabled={busy || hasActive}
                          onChange={(e) =>
                            edit({
                              ...selected,
                              speakers: selected.speakers.map((item) =>
                                item.id === speaker.id ? { ...item, name: e.target.value } : item,
                              ),
                            })
                          }
                        />
                        {selected.speakers.length > 1 && (
                          <select
                            value=""
                            disabled={busy || hasActive}
                            aria-label={label('mergeSpeakers')}
                            onChange={(event) => {
                              const target = event.target.value;
                              if (!target) return;
                              edit({
                                ...selected,
                                speakers: selected.speakers.filter(
                                  (item) => item.id !== speaker.id,
                                ),
                                segments: selected.segments.map((segment) =>
                                  segment.speakerId === speaker.id
                                    ? { ...segment, speakerId: target, attribution: 'assigned' }
                                    : segment,
                                ),
                              });
                            }}
                          >
                            <option value="">{label('mergeSpeakers')}</option>
                            {selected.speakers
                              .filter((item) => item.id !== speaker.id)
                              .map((item) => (
                                <option key={item.id} value={item.id}>
                                  {item.name}
                                </option>
                              ))}
                          </select>
                        )}
                      </label>
                    ))}
                  </div>
                </Card>
              )}
              <h3>{label('transcript')}</h3>
              {!selected.segments.length && (
                <p className="meetings-muted">{label('noTranscript')}</p>
              )}
              {selected.segments.map((segment) => (
                <section key={segment.id} className="meeting-segment">
                  <div className="meetings-actions">
                    <button
                      type="button"
                      className="meeting-time"
                      title={label('play')}
                      disabled={busy}
                      onClick={() => {
                        const chunk = selected.chunks.find(
                          (item) =>
                            item.trackId === segment.trackId &&
                            item.startMs <= segment.startMs &&
                            item.startMs + item.durationMs > segment.startMs,
                        );
                        if (chunk) void play(chunk.id, (segment.startMs - chunk.startMs) / 1000);
                      }}
                    >
                      {clock(segment.startMs)}
                    </button>
                    <select
                      aria-label={label('speakers')}
                      disabled={busy || hasActive}
                      value={segment.speakerId ?? ''}
                      onChange={(e) =>
                        edit({
                          ...selected,
                          segments: selected.segments.map((item) =>
                            item.id === segment.id
                              ? {
                                  ...item,
                                  speakerId: e.target.value || null,
                                  attribution: e.target.value ? 'assigned' : 'unassigned',
                                }
                              : item,
                          ),
                        })
                      }
                    >
                      <option value="">{label('unassigned')}</option>
                      {selected.speakers.map((speaker) => (
                        <option key={speaker.id} value={speaker.id}>
                          {speaker.name}
                        </option>
                      ))}
                    </select>
                  </div>
                  <textarea
                    aria-label={`${label('transcript')} ${clock(segment.startMs)}`}
                    rows={2}
                    disabled={busy || hasActive}
                    value={segment.text}
                    onChange={(e) =>
                      edit({
                        ...selected,
                        segments: selected.segments.map((item) =>
                          item.id === segment.id
                            ? {
                                ...item,
                                originalText: item.originalText ?? item.text,
                                text: e.target.value,
                              }
                            : item,
                        ),
                      })
                    }
                  />
                </section>
              ))}
              <h3>{label('summary')}</h3>
              {selected.summary ? (
                <Card>
                  {(dirty ||
                    selected.summary.transcriptRevision !== selected.transcriptRevision) && (
                    <p role="status">{label('stale')}</p>
                  )}
                  <p className="meeting-summary">{selected.summary.text}</p>
                  <h4>{label('decisions')}</h4>
                  <ul>
                    {selected.summary.decisions.map((decision, index) => (
                      <li key={index}>{decision.description}</li>
                    ))}
                  </ul>
                  <h4>{label('tasks')}</h4>
                  <ul>
                    {selected.summary.tasks.map((task, index) => (
                      <li key={index}>
                        {task.description}
                        <div className="meetings-muted">
                          {label('owner')}: {task.owner ?? label('unspecified')} ·{' '}
                          {label('deadline')}: {task.deadline ?? label('unspecified')}
                        </div>
                      </li>
                    ))}
                  </ul>
                </Card>
              ) : (
                <p className="meetings-muted">{label('noSummary')}</p>
              )}
            </main>
          )}
        </div>
      )}
    </div>
  );
}
