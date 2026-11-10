import { invokeOrMock } from './shared';

export interface MeetingSpeaker {
  id: string;
  name: string;
}
export interface MeetingSegment {
  id: string;
  trackId: string;
  speakerId: string | null;
  attribution: 'assigned' | 'unassigned' | 'overlapping' | 'uncertain';
  startMs: number;
  endMs: number;
  text: string;
  originalText: string | null;
}
export interface MeetingChunk {
  id: string;
  trackId: string;
  relativePath: string;
  startMs: number;
  durationMs: number;
  byteCount: number;
  finalized: boolean;
}
export interface MeetingSummary {
  transcriptRevision: number;
  provider: string;
  model: string;
  generatedAt: string;
  text: string;
  decisions: { description: string; sourceSegmentIds: string[] }[];
  tasks: {
    description: string;
    owner: string | null;
    deadline: string | null;
    sourceSegmentIds: string[];
  }[];
}
export interface MeetingEchoInfo {
  enabled: boolean;
  active: boolean;
  processedFrames: number;
  warning: string | null;
  upstreamRevision: string;
  configurationId: string;
}
export interface MeetingModelStatus {
  supported: boolean;
  liveSupported: boolean;
  echoSupported: boolean;
  downloading: 'parakeet' | 'nemotron' | 'live' | null;
  completedBytes: number;
  totalBytes: number;
  error: string | null;
  items: {
    id: 'parakeet' | 'nemotron' | 'live';
    ready: boolean;
    license: string;
    repository: string;
    revision: string;
  }[];
}
export interface MeetingLiveCaptions {
  enabled: boolean;
  partials: Record<string, string>;
  turns: { kind: string; text: string; draft: boolean }[];
  warning: string | null;
}
export interface MeetingDocument {
  id: string;
  revision: number;
  title: string;
  language: string;
  origin: 'onlineCall' | 'inRoom' | 'importedAudio' | 'importedVideo';
  state:
    'preparing' | 'recording' | 'stopping' | 'processing' | 'completed' | 'interrupted' | 'failed';
  createdAt: string;
  tracks: {
    id: string;
    kind: 'microphone' | 'microphoneClean' | 'application' | 'imported';
    sampleRate: number;
    channels: number;
  }[];
  chunks: MeetingChunk[];
  transcriptRevision: number;
  speakers: MeetingSpeaker[];
  segments: MeetingSegment[];
  summary: MeetingSummary | null;
  captureInfo?: { echoCancellation: MeetingEchoInfo | null; liveCaptions: boolean } | null;
}
export interface MeetingSnapshot {
  models?: MeetingModelStatus | null;
  echo?: MeetingEchoInfo | null;
  echoSupported?: boolean;
  live?: MeetingLiveCaptions | null;
  captureError?: string | null;
  busy: boolean;
  catalog: { meetings: MeetingDocument[]; errors: string[] };
  activeId: string | null;
  supported: boolean;
}
export interface MeetingApplication {
  pid: number;
  name: string;
  bundleId: string;
}
export interface MeetingProgress {
  id: string;
  stage: string;
  completed: number;
  total: number;
}

export interface MeetingChannelOption {
  id: string;
  name: string;
  providerType: string;
  model: string | null;
}
export interface MeetingProviders {
  asr: MeetingChannelOption[];
  llm: MeetingChannelOption[];
}

export type MeetingRequest =
  | { action: 'list' | 'applications' | 'providers' | 'stop' | 'cancel' | 'cancelModelDownload' }
  | {
      action: 'start';
      title: string;
      language: string;
      pid: number | null;
      live?: boolean;
      echoCancellation?: boolean;
    }
  | { action: 'import'; language: string }
  | { action: 'downloadModel' | 'removeModel'; model: 'parakeet' | 'nemotron' | 'live' }
  | { action: 'transcribe' | 'summarize'; id: string; channelId?: string; local?: boolean }
  | { action: 'recover'; id: string }
  | {
      action: 'edit';
      id: string;
      revision: number;
      title: string;
      speakers: MeetingSpeaker[];
      segments: MeetingSegment[];
    }
  | { action: 'readAudio'; id: string; chunkId: string }
  | { action: 'export'; id: string; format: 'json' | 'md' | 'txt' };

export function meetingCommand<T>(request: MeetingRequest): Promise<T> {
  return invokeOrMock<T>('meetings_command', { request }, () => {
    if (request.action === 'providers') return { asr: [], llm: [] } as T;
    if (request.action === 'list') {
      return {
        catalog: { meetings: [], errors: [] },
        activeId: null,
        supported: false,
        busy: false,
      } as T;
    }
    throw new Error('Meetings require the OpenLess desktop application.');
  });
}
