#!/usr/bin/env node
/**
 * STT/TTS bake-off runner.
 *
 * Preferred (single key):
 *   OPENROUTER_API_KEY — Whisper STT + optional TTS via chat completions
 *
 * Optional direct providers for comparison:
 *   OPENAI_API_KEY, DEEPGRAM_API_KEY, ELEVENLABS_API_KEY, CARTESIA_API_KEY
 *
 * Usage: node business-tech-thoughts/voice/run-bakeoff.mjs
 * Output: business-tech-thoughts/voice/bakeoff-results.json
 */

import fs from 'fs/promises';
import path from 'path';
import { fileURLToPath } from 'url';
import crypto from 'node:crypto';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const SAMPLES_DIR = path.join(__dirname, 'samples');
const OUT_PATH = path.join(__dirname, 'bakeoff-results.json');

const OPENROUTER_BASE = 'https://openrouter.ai/api/v1';
const OPENROUTER_STT_MODELS = (
  process.env.OPENROUTER_STT_MODELS ??
  'mistralai/voxtral-mini-transcribe,nvidia/parakeet-tdt-0.6b-v3'
).split(',');
const TTS_MODEL = process.env.OPENROUTER_TTS_MODEL ?? 'openai/gpt-audio-mini';

const manifest = JSON.parse(
  await fs.readFile(path.join(SAMPLES_DIR, 'manifest.json'), 'utf8'),
);

function openRouterHeaders() {
  const key = process.env.OPENROUTER_API_KEY;
  if (!key) return null;
  return {
    Authorization: `Bearer ${key}`,
    'Content-Type': 'application/json',
    ...(process.env.OPENROUTER_HTTP_REFERER
      ? { 'HTTP-Referer': process.env.OPENROUTER_HTTP_REFERER }
      : {}),
    ...(process.env.OPENROUTER_APP_TITLE
      ? { 'X-OpenRouter-Title': process.env.OPENROUTER_APP_TITLE }
      : {}),
  };
}

function normalize(text) {
  return text
    .toLowerCase()
    .replace(/[^\w\s]/g, '')
    .replace(/\s+/g, ' ')
    .trim();
}

function wer(reference, hypothesis) {
  const ref = normalize(reference).split(' ').filter(Boolean);
  const hyp = normalize(hypothesis).split(' ').filter(Boolean);
  if (ref.length === 0) return hyp.length === 0 ? 0 : 1;
  const dp = Array.from({ length: ref.length + 1 }, (_, i) =>
    Array.from({ length: hyp.length + 1 }, (_, j) => (i === 0 ? j : j === 0 ? i : 0)),
  );
  for (let i = 1; i <= ref.length; i++) {
    for (let j = 1; j <= hyp.length; j++) {
      const cost = ref[i - 1] === hyp[j - 1] ? 0 : 1;
      dp[i][j] = Math.min(
        dp[i - 1][j] + 1,
        dp[i][j - 1] + 1,
        dp[i - 1][j - 1] + cost,
      );
    }
  }
  return dp[ref.length][hyp.length] / ref.length;
}

async function timed(label, fn) {
  const start = performance.now();
  const result = await fn();
  return { label, ms: Math.round(performance.now() - start), result };
}

async function transcribeOpenRouter(wavPath, model) {
  const headers = openRouterHeaders();
  if (!headers) return null;
  const audio = await fs.readFile(wavPath);
  const res = await fetch(`${OPENROUTER_BASE}/audio/transcriptions`, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      model,
      input_audio: {
        data: Buffer.from(audio).toString('base64'),
        format: 'wav',
      },
    }),
  });
  if (!res.ok) throw new Error(`OpenRouter STT ${model} ${res.status}: ${await res.text()}`);
  const data = await res.json();
  return data.text;
}

async function transcribeWhisperDirect(wavPath) {
  const key = process.env.OPENAI_API_KEY;
  if (!key) return null;
  const form = new FormData();
  form.append('file', new Blob([await fs.readFile(wavPath)]), path.basename(wavPath));
  form.append('model', 'whisper-1');
  const res = await fetch('https://api.openai.com/v1/audio/transcriptions', {
    method: 'POST',
    headers: { Authorization: `Bearer ${key}` },
    body: form,
  });
  if (!res.ok) throw new Error(`Whisper ${res.status}: ${await res.text()}`);
  const data = await res.json();
  return data.text;
}

async function transcribeDeepgram(wavPath) {
  const key = process.env.DEEPGRAM_API_KEY;
  if (!key) return null;
  const audio = await fs.readFile(wavPath);
  const res = await fetch(
    'https://api.deepgram.com/v1/listen?model=nova-2&smart_format=true',
    {
      method: 'POST',
      headers: {
        Authorization: `Token ${key}`,
        'Content-Type': 'audio/wav',
      },
      body: audio,
    },
  );
  if (!res.ok) throw new Error(`Deepgram ${res.status}: ${await res.text()}`);
  const data = await res.json();
  return data.results?.channels?.[0]?.alternatives?.[0]?.transcript ?? '';
}

async function synthesizeOpenRouterTts(text) {
  const headers = openRouterHeaders();
  if (!headers) return null;
  const res = await fetch(`${OPENROUTER_BASE}/chat/completions`, {
    method: 'POST',
    headers,
    body: JSON.stringify({
      model: TTS_MODEL,
      messages: [{ role: 'user', content: text.slice(0, 200) }],
      modalities: ['text', 'audio'],
      audio: { voice: 'nova', format: 'wav' },
      stream: true,
    }),
  });
  if (!res.ok) throw new Error(`OpenRouter TTS ${res.status}: ${await res.text()}`);

  let bytes = 0;
  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  while (true) {
    const { done, value } = await reader.read();
    if (done) break;
    buffer += decoder.decode(value, { stream: true });
    for (const line of buffer.split('\n')) {
      if (!line.startsWith('data: ')) continue;
      const payload = line.slice(6).trim();
      if (payload === '[DONE]') continue;
      try {
        const chunk = JSON.parse(payload);
        const data = chunk.choices?.[0]?.delta?.audio?.data;
        if (data) bytes += Buffer.from(data, 'base64').length;
      } catch {
        /* skip malformed SSE */
      }
    }
    buffer = buffer.split('\n').pop() ?? '';
  }
  return bytes;
}

async function synthesizeCartesiaTts(text) {
  const key = process.env.CARTESIA_API_KEY;
  if (!key) return null;
  const res = await fetch('https://api.cartesia.ai/tts/bytes', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${key}`,
      'Cartesia-Version': '2026-03-01',
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model_id: 'sonic-3.5',
      transcript: text.slice(0, 200),
      voice: { mode: 'id', id: 'f786b574-daa5-4673-aa0c-cbe3e8534c02' },
      output_format: { container: 'wav', encoding: 'pcm_s16le', sample_rate: 44100 },
    }),
  });
  if (!res.ok) throw new Error(`Cartesia TTS ${res.status}: ${await res.text()}`);
  return (await res.arrayBuffer()).byteLength;
}

function synthesizeCartesiaStream(text) {
  const key = process.env.CARTESIA_API_KEY;
  if (!key) return Promise.resolve(null);
  return new Promise((resolve, reject) => {
    const ws = new WebSocket(
      'wss://api.cartesia.ai/tts/websocket?cartesia_version=2026-03-01',
      { headers: { 'X-Api-Key': key } },
    );
    const contextId = crypto.randomUUID();
    let ttfbMs = null;
    let totalBytes = 0;
    let chunks = 0;
    const t0 = performance.now();

    ws.addEventListener('open', () => {
      ws.send(JSON.stringify({
        model_id: 'sonic-3.5',
        transcript: text.slice(0, 200),
        voice: { mode: 'id', id: 'f786b574-daa5-4673-aa0c-cbe3e8534c02' },
        output_format: { container: 'raw', encoding: 'pcm_s16le', sample_rate: 44100 },
        context_id: contextId,
        continue: false,
      }));
    });

    ws.addEventListener('message', (event) => {
      const msg = JSON.parse(typeof event.data === 'string' ? event.data : event.data.toString());
      if (msg.type === 'chunk') {
        if (ttfbMs === null) ttfbMs = Math.round(performance.now() - t0);
        totalBytes += Buffer.from(msg.data, 'base64').length;
        chunks++;
        if (msg.done) {
          ws.close();
          resolve({ ttfbMs, totalMs: Math.round(performance.now() - t0), totalBytes, chunks });
        }
      } else if (msg.type === 'done') {
        ws.close();
        resolve({ ttfbMs, totalMs: Math.round(performance.now() - t0), totalBytes, chunks });
      } else if (msg.type === 'error') {
        ws.close();
        reject(new Error(`Cartesia WS error: ${msg.message}`));
      }
    });

    ws.addEventListener('error', (e) => {
      reject(new Error(`Cartesia WS connection error: ${e.message ?? e}`));
    });

    setTimeout(() => { ws.close(); reject(new Error('Cartesia WS timeout (15s)')); }, 15000);
  });
}

async function synthesizeOpenAITts(text) {
  const key = process.env.OPENAI_API_KEY;
  if (!key) return null;
  const res = await fetch('https://api.openai.com/v1/audio/speech', {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${key}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      model: 'tts-1',
      voice: 'nova',
      input: text.slice(0, 200),
    }),
  });
  if (!res.ok) throw new Error(`OpenAI TTS ${res.status}: ${await res.text()}`);
  return (await res.arrayBuffer()).byteLength;
}

async function synthesizeElevenLabsTts(text) {
  const key = process.env.ELEVENLABS_API_KEY;
  if (!key) return null;
  const voiceId = 'JBFqnCBsd6RMkjVDRZzb';
  const res = await fetch(
    `https://api.elevenlabs.io/v1/text-to-speech/${voiceId}?output_format=mp3_44100_128`,
    {
      method: 'POST',
      headers: {
        'xi-api-key': key,
        'Content-Type': 'application/json',
      },
      body: JSON.stringify({
        text: text.slice(0, 200),
        model_id: 'eleven_turbo_v2_5',
      }),
    },
  );
  if (!res.ok) throw new Error(`ElevenLabs TTS ${res.status}: ${await res.text()}`);
  return (await res.arrayBuffer()).byteLength;
}

const sttResults = {
  whisper_direct: [],
  deepgram: [],
  ...Object.fromEntries(
    OPENROUTER_STT_MODELS.map((m) => [m.replace(/\//g, '_'), []]),
  ),
};
const ttsProbe = 'Thanks Donna, I will check my calendar now.';

for (const item of manifest) {
  const wavPath = path.join(SAMPLES_DIR, item.file);
  if (process.env.OPENROUTER_API_KEY) {
    for (const model of OPENROUTER_STT_MODELS) {
      const key = model.replace(/\//g, '_');
      try {
        const { ms, result } = await timed(model, () =>
          transcribeOpenRouter(wavPath, model),
        );
        sttResults[key].push({
          id: item.id,
          ms,
          model,
          transcript: result,
          wer: wer(item.reference, result),
          reference: item.reference,
        });
      } catch (err) {
        console.error(`STT failed for ${model} utterance ${item.id}:`, err.message);
      }
    }
  }
  if (process.env.OPENAI_API_KEY) {
    const { ms, result } = await timed('whisper_direct', () =>
      transcribeWhisperDirect(wavPath),
    );
    sttResults.whisper_direct.push({
      id: item.id,
      ms,
      transcript: result,
      wer: wer(item.reference, result),
      reference: item.reference,
    });
  }
  if (process.env.DEEPGRAM_API_KEY) {
    const { ms, result } = await timed('deepgram', () => transcribeDeepgram(wavPath));
    sttResults.deepgram.push({
      id: item.id,
      ms,
      transcript: result,
      wer: wer(item.reference, result),
      reference: item.reference,
    });
  }
}

const ttsResults = {};
if (process.env.OPENROUTER_API_KEY) {
  try {
    ttsResults.openrouter = await timed('openrouter_tts', () =>
      synthesizeOpenRouterTts(ttsProbe),
    );
  } catch (err) {
    ttsResults.openrouter_error = err.message;
    console.error('TTS failed:', err.message);
  }
}
if (process.env.OPENAI_API_KEY) {
  ttsResults.openai_tts_1 = await timed('openai_tts', () =>
    synthesizeOpenAITts(ttsProbe),
  );
}
if (process.env.CARTESIA_API_KEY) {
  try {
    ttsResults.cartesia_sonic_3_5 = await timed('cartesia_tts', () =>
      synthesizeCartesiaTts(ttsProbe),
    );
  } catch (err) {
    ttsResults.cartesia_error = err.message;
    console.error('Cartesia TTS failed:', err.message);
  }
  try {
    ttsResults.cartesia_stream = await synthesizeCartesiaStream(ttsProbe);
  } catch (err) {
    ttsResults.cartesia_stream_error = err.message;
    console.error('Cartesia streaming TTS failed:', err.message);
  }
}
if (process.env.ELEVENLABS_API_KEY) {
  try {
    ttsResults.elevenlabs_turbo = await timed('elevenlabs_tts', () =>
      synthesizeElevenLabsTts(ttsProbe),
    );
  } catch (err) {
    ttsResults.elevenlabs_error = err.message;
    console.error('ElevenLabs TTS failed:', err.message);
  }
}

function summarizeStt(rows) {
  if (!rows.length) return null;
  return {
    avgMs: Math.round(rows.reduce((s, r) => s + r.ms, 0) / rows.length),
    avgWer: rows.reduce((s, r) => s + r.wer, 0) / rows.length,
    rows,
  };
}

const output = {
  ranAt: new Date().toISOString(),
  keysPresent: {
    openrouter: Boolean(process.env.OPENROUTER_API_KEY),
    openai: Boolean(process.env.OPENAI_API_KEY),
    deepgram: Boolean(process.env.DEEPGRAM_API_KEY),
    cartesia: Boolean(process.env.CARTESIA_API_KEY),
    elevenlabs: Boolean(process.env.ELEVENLABS_API_KEY),
  },
  models: { stt: OPENROUTER_STT_MODELS, tts: TTS_MODEL },
  stt: Object.fromEntries(
    Object.entries(sttResults).map(([k, rows]) => [k, summarizeStt(rows)]),
  ),
  tts: {
    probeText: ttsProbe,
    openrouter: ttsResults.openrouter
      ? { ms: ttsResults.openrouter.ms, bytes: ttsResults.openrouter.result }
      : null,
    openrouter_error: ttsResults.openrouter_error ?? null,
    openai_tts_1: ttsResults.openai_tts_1
      ? { ms: ttsResults.openai_tts_1.ms, bytes: ttsResults.openai_tts_1.result }
      : null,
    cartesia_sonic_3_5: ttsResults.cartesia_sonic_3_5
      ? { ms: ttsResults.cartesia_sonic_3_5.ms, bytes: ttsResults.cartesia_sonic_3_5.result }
      : null,
    cartesia_error: ttsResults.cartesia_error ?? null,
    cartesia_stream: ttsResults.cartesia_stream
      ? { ttfbMs: ttsResults.cartesia_stream.ttfbMs, totalMs: ttsResults.cartesia_stream.totalMs, bytes: ttsResults.cartesia_stream.totalBytes, chunks: ttsResults.cartesia_stream.chunks }
      : null,
    cartesia_stream_error: ttsResults.cartesia_stream_error ?? null,
    elevenlabs_turbo: ttsResults.elevenlabs_turbo
      ? { ms: ttsResults.elevenlabs_turbo.ms, bytes: ttsResults.elevenlabs_turbo.result }
      : null,
    elevenlabs_error: ttsResults.elevenlabs_error ?? null,
  },
};

await fs.writeFile(OUT_PATH, JSON.stringify(output, null, 2));
console.log(JSON.stringify(output, null, 2));

if (!output.keysPresent.openrouter && !output.keysPresent.openai && !output.keysPresent.deepgram && !output.keysPresent.cartesia && !output.keysPresent.elevenlabs) {
  console.error('\nSet OPENROUTER_API_KEY (recommended) or OPENAI_API_KEY / DEEPGRAM_API_KEY / CARTESIA_API_KEY / ELEVENLABS_API_KEY, then re-run.');
  process.exit(1);
}
