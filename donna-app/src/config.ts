import { Platform } from 'react-native';

/**
 * Voice backend host — no protocol, no port.
 *
 * iOS Simulator: leave null (uses 127.0.0.1).
 * Physical iPhone: set to your Mac's LAN IP, e.g. '192.168.1.42'
 *   Find it: ipconfig getifaddr en0
 * Android emulator: leave null (uses 10.0.2.2).
 */
export const VOICE_SERVER_HOST_OVERRIDE: string | null = '192.168.8.7';

function resolveVoiceHost(): string {
  if (VOICE_SERVER_HOST_OVERRIDE) {
    return VOICE_SERVER_HOST_OVERRIDE;
  }
  if (Platform.OS === 'android') {
    return '10.0.2.2';
  }
  return '127.0.0.1';
}

export const VOICE_SERVER_HOST = resolveVoiceHost();
export const VOICE_WS_URL = `ws://${VOICE_SERVER_HOST}:8787/voice`;

export const AUDIO_SAMPLE_RATE = 16_000;
export const AUDIO_CHANNELS = 1;
export const VAD_SILENCE_MS = 500;
export const VAD_ENERGY_THRESHOLD = 0.015;
