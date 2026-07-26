#!/usr/bin/env node
/**
 * End-to-end voice STT test without the iOS/web app.
 *
 * Voice is speech-to-text only; talk replies go through POST /chat.
 *
 * Usage:
 *   npm run dev:server   # in another terminal
 *   npm run test:voice
 *
 * Optional:
 *   DONNA_WS_URL=ws://localhost:8787/voice
 *   DONNA_SAMPLE_WAV=business-tech-thoughts/voice/samples/utterance-1.wav
 */

import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { WebSocket } from 'ws';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const repoRoot = path.resolve(__dirname, '..');
const wsUrl = process.env.DONNA_WS_URL ?? 'ws://localhost:8787/voice';
const samplePath =
  process.env.DONNA_SAMPLE_WAV ??
  path.join(repoRoot, 'business-tech-thoughts/voice/samples/utterance-1.wav');

function parseWavPcm16(buffer) {
  const view = new DataView(buffer.buffer, buffer.byteOffset, buffer.byteLength);
  const channels = view.getUint16(22, true);
  const sampleRate = view.getUint32(24, true);
  const bitsPerSample = view.getUint16(34, true);
  if (bitsPerSample !== 16) {
    throw new Error(`Expected 16-bit PCM, got ${bitsPerSample}`);
  }

  let dataOffset = 12;
  while (dataOffset < buffer.length - 8) {
    const chunkId = String.fromCharCode(
      buffer[dataOffset],
      buffer[dataOffset + 1],
      buffer[dataOffset + 2],
      buffer[dataOffset + 3],
    );
    const chunkSize = view.getUint32(dataOffset + 4, true);
    if (chunkId === 'data') {
      const pcm = buffer.subarray(dataOffset + 8, dataOffset + 8 + chunkSize);
      return { pcm, sampleRate, channels };
    }
    dataOffset += 8 + chunkSize;
  }
  throw new Error('WAV data chunk not found');
}

function send(ws, message) {
  ws.send(JSON.stringify(message));
}

function waitFor(ws, predicate, timeoutMs = 120_000) {
  return new Promise((resolve, reject) => {
    const timer = setTimeout(() => {
      cleanup();
      reject(new Error(`Timed out waiting for server message`));
    }, timeoutMs);

    const onMessage = (raw) => {
      const message = JSON.parse(raw.toString());
      if (predicate(message)) {
        cleanup();
        resolve(message);
      }
    };

    const cleanup = () => {
      clearTimeout(timer);
      ws.off('message', onMessage);
    };

    ws.on('message', onMessage);
  });
}

async function main() {
  const wavBuffer = await fs.readFile(samplePath);
  const { pcm, sampleRate, channels } = parseWavPcm16(wavBuffer);
  const chunkSize = 3200;
  const audioChunks = [];

  for (let offset = 0; offset < pcm.length; offset += chunkSize) {
    audioChunks.push(pcm.subarray(offset, offset + chunkSize));
  }

  const ws = new WebSocket(wsUrl);
  await new Promise((resolve, reject) => {
    ws.once('open', resolve);
    ws.once('error', reject);
  });

  let transcript = null;

  ws.on('message', (raw) => {
    const message = JSON.parse(raw.toString());
    if (message.type === 'turn.phase') {
      console.log(`phase: ${message.phase}`);
    } else if (message.type === 'turn.transcript') {
      transcript = message.text;
      console.log(`transcript: ${message.text}`);
    } else if (message.type === 'error') {
      console.error(`error [${message.code}]: ${message.message}`);
    }
  });

  send(ws, { type: 'session.start', mode: 'talk' });
  await waitFor(ws, (m) => m.type === 'session.ready');
  console.log('session ready');

  for (let seq = 0; seq < audioChunks.length; seq++) {
    send(ws, {
      type: 'audio.chunk',
      seq,
      format: 'pcm16',
      sampleRate,
      channels,
      data: Buffer.from(audioChunks[seq]).toString('base64'),
    });
  }

  send(ws, { type: 'turn.end' });

  const done = await waitFor(
    ws,
    (m) => m.type === 'turn.done' || m.type === 'error',
  );
  if (done.type === 'error') {
    throw new Error(`${done.code}: ${done.message}`);
  }

  console.log('timings:', done.timings);
  if (done.skipped) {
    console.log('turn skipped');
  } else if (!transcript) {
    throw new Error('turn.done without turn.transcript');
  } else {
    console.log('STT ok — send this transcript through POST /chat');
  }

  send(ws, { type: 'session.end' });
  ws.close();
}

main().catch((err) => {
  console.error(err.message ?? err);
  process.exit(1);
});
