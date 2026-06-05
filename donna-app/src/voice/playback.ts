import { AudioContext, AudioManager } from 'react-native-audio-api';
import { base64ToBytes } from './pcm';

let audioContext: AudioContext | null = null;

async function getAudioContext(): Promise<AudioContext> {
  if (!audioContext) {
    audioContext = new AudioContext();
  }
  await AudioManager.setAudioSessionActivity(true);
  return audioContext;
}

export async function playEncodedAudio(
  chunks: Array<{ data: string; format: 'mp3' | 'wav' }>,
): Promise<void> {
  if (chunks.length === 0) return;

  const bytes = concatBytes(chunks.map((chunk) => base64ToBytes(chunk.data)));
  const ctx = await getAudioContext();
  const arrayBuffer = bytes.buffer.slice(
    bytes.byteOffset,
    bytes.byteOffset + bytes.byteLength,
  ) as ArrayBuffer;
  const audioBuffer = await ctx.decodeAudioData(arrayBuffer);

  await new Promise<void>((resolve, reject) => {
    try {
      const source = ctx.createBufferSource();
      source.buffer = audioBuffer;
      source.connect(ctx.destination);
      source.onEnded = () => resolve();
      source.start();
    } catch (err) {
      reject(err);
    }
  });
}

function concatBytes(chunks: Uint8Array[]): Uint8Array {
  const total = chunks.reduce((sum, chunk) => sum + chunk.length, 0);
  const out = new Uint8Array(total);
  let offset = 0;
  for (const chunk of chunks) {
    out.set(chunk, offset);
    offset += chunk.length;
  }
  return out;
}

export async function resetPlaybackSession(): Promise<void> {
  await AudioManager.setAudioSessionActivity(false);
}
