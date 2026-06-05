/**
 * Donna voice turn pipeline — server-side sketch (not wired to app yet).
 *
 * Flow: commit audio → STT → augment → LLM → stream TTS → client.
 * All three provider calls can use OPENROUTER_API_KEY (see tech.md).
 */

export type MicState = 'idle' | 'requesting' | 'listening' | 'processing' | 'error';

export type VoiceTurnPhase =
  | 'idle'
  | 'buffering'
  | 'transcribing'
  | 'augmenting'
  | 'generating'
  | 'synthesizing'
  | 'done'
  | 'error';

export type CommittedAudio = {
  userId: string;
  sessionId: string;
  /** PCM or encoded blob; WAV recommended for v1 */
  audio: Uint8Array;
  mimeType: string;
  committedAt: number;
};

export type TranscriptAugmentation = {
  transcript: string;
  /** Final user message for the LLM */
  text: string;
  retrieved?: string[];
  sessionNotes?: string;
};

export type SttProvider = {
  transcribe(audio: CommittedAudio): Promise<{ transcript: string; ms: number }>;
};

export type LlmProvider = {
  complete(messages: ChatMessage[]): Promise<AsyncIterable<string>>;
};

export type TtsProvider = {
  synthesize(text: string): Promise<AsyncIterable<Uint8Array>>;
};

export type ChatMessage = {
  role: 'system' | 'user' | 'assistant';
  content: string;
};

export type VoiceSessionConfig = {
  silenceMs: number;
  systemPrompt: string;
  stt: SttProvider;
  llm: LlmProvider;
  tts: TtsProvider;
  augment: (input: {
    transcript: string;
    userId: string;
    sessionId: string;
  }) => Promise<TranscriptAugmentation>;
};

export type VoiceTurnResult = {
  transcript: string;
  replyText: string;
  timings: {
    sttMs: number;
    augmentMs: number;
    llmFirstTokenMs: number;
    ttsFirstByteMs: number;
    totalMs: number;
  };
};

/** Build OpenRouter-compatible messages after augmentation. */
export function buildLlmMessages(
  systemPrompt: string,
  augmented: TranscriptAugmentation,
): ChatMessage[] {
  return [
    { role: 'system', content: systemPrompt },
    { role: 'user', content: augmented.text },
  ];
}

export function formatAugmentedUserMessage(
  augmented: TranscriptAugmentation,
): string {
  const parts: string[] = [];
  if (augmented.retrieved?.length) {
    parts.push(`[Retrieved: ${augmented.retrieved.join(' | ')}]`);
  }
  if (augmented.sessionNotes) {
    parts.push(`[Session: ${augmented.sessionNotes}]`);
  }
  parts.push(`User said: "${augmented.transcript}"`);
  return parts.join('\n');
}

/** Default augment: wrap transcript; plug RAG in later. */
export async function defaultAugment(input: {
  transcript: string;
  userId: string;
  sessionId: string;
}): Promise<TranscriptAugmentation> {
  const base: TranscriptAugmentation = {
    transcript: input.transcript,
    text: '',
  };
  base.text = formatAugmentedUserMessage(base);
  return base;
}

/**
 * Run one voice turn after the client commits audio (push-to-talk or VAD).
 */
export async function runVoiceTurn(
  config: VoiceSessionConfig,
  audio: CommittedAudio,
  onPhase?: (phase: VoiceTurnPhase) => void,
): Promise<VoiceTurnResult> {
  const t0 = performance.now();
  const timings = {
    sttMs: 0,
    augmentMs: 0,
    llmFirstTokenMs: 0,
    ttsFirstByteMs: 0,
    totalMs: 0,
  };

  const phase = (p: VoiceTurnPhase) => onPhase?.(p);

  phase('transcribing');
  const sttStart = performance.now();
  const { transcript, ms: sttMs } = await config.stt.transcribe(audio);
  timings.sttMs = sttMs ?? Math.round(performance.now() - sttStart);

  if (!transcript.trim()) {
    phase('error');
    throw new Error('Empty transcript');
  }

  phase('augmenting');
  const augStart = performance.now();
  const augmented = await config.augment({
    transcript,
    userId: audio.userId,
    sessionId: audio.sessionId,
  });
  augmented.text = formatAugmentedUserMessage(augmented);
  timings.augmentMs = Math.round(performance.now() - augStart);

  phase('generating');
  const messages = buildLlmMessages(config.systemPrompt, augmented);
  const llmStart = performance.now();
  let replyText = '';
  let firstToken = true;
  const llmStream = await config.llm.complete(messages);
  for await (const chunk of llmStream) {
    if (firstToken) {
      timings.llmFirstTokenMs = Math.round(performance.now() - llmStart);
      firstToken = false;
    }
    replyText += chunk;
  }

  phase('synthesizing');
  const ttsStart = performance.now();
  let firstByte = true;
  const ttsStream = await config.tts.synthesize(replyText);
  for await (const _chunk of ttsStream) {
    if (firstByte) {
      timings.ttsFirstByteMs = Math.round(performance.now() - ttsStart);
      firstByte = false;
    }
    // Stream to client WebSocket / HTTP chunk here
  }

  timings.totalMs = Math.round(performance.now() - t0);
  phase('done');

  return { transcript, replyText, timings };
}

/**
 * VAD helper: call when a silence window elapses after speech.
 * Returns true when audio should commit to runVoiceTurn.
 */
export function shouldCommitTurn(input: {
  hadSpeech: boolean;
  silenceDurationMs: number;
  silenceMs: number;
}): boolean {
  return input.hadSpeech && input.silenceDurationMs >= input.silenceMs;
}
