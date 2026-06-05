import { useCallback, useEffect, useRef, useState } from 'react';
import {
  AudioManager,
  AudioRecorder,
} from 'react-native-audio-api';
import {
  AUDIO_CHANNELS,
  AUDIO_SAMPLE_RATE,
  VAD_ENERGY_THRESHOLD,
  VAD_SILENCE_MS,
  VOICE_WS_URL,
} from '../config';
import type { MicState } from '../components/MicButton';
import { floatToPcm16, pcm16ToBase64 } from '../voice/pcm';
import { playEncodedAudio, resetPlaybackSession } from '../voice/playback';
import type { ServerMessage, TurnPhase } from '../voice/protocol';
import { EnergyVad } from '../voice/vad';
import { VoiceClient } from '../voice/voiceClient';

type VoiceStatus = {
  transcript: string | null;
  reply: string | null;
  phase: TurnPhase | null;
};

const BUSY_PHASES: TurnPhase[] = [
  'busy',
  'transcribing',
  'generating',
  'synthesizing',
];

export function useVoiceSession() {
  const [state, setState] = useState<MicState>('idle');
  const [errorMsg, setErrorMsg] = useState<string | null>(null);
  const [status, setStatus] = useState<VoiceStatus>({
    transcript: null,
    reply: null,
    phase: null,
  });

  const clientRef = useRef<VoiceClient | null>(null);
  const recorderRef = useRef<AudioRecorder | null>(null);
  const vadRef = useRef(
    new EnergyVad({
      silenceMs: VAD_SILENCE_MS,
      energyThreshold: VAD_ENERGY_THRESHOLD,
    }),
  );
  const chunkSeqRef = useRef(0);
  const sessionReadyRef = useRef(false);
  const audioOutRef = useRef<Array<{ data: string; format: 'mp3' | 'wav' }>>(
    [],
  );
  const activeRef = useRef(false);
  const readyResolverRef = useRef<(() => void) | null>(null);

  const setVoiceError = useCallback((message: string) => {
    setState('error');
    setErrorMsg(message);
    activeRef.current = false;
  }, []);

  const handleServerMessage = useCallback(async (message: ServerMessage) => {
    switch (message.type) {
      case 'session.ready':
        sessionReadyRef.current = true;
        readyResolverRef.current?.();
        readyResolverRef.current = null;
        break;
      case 'turn.phase':
        setStatus((prev) => ({ ...prev, phase: message.phase }));
        if (BUSY_PHASES.includes(message.phase)) {
          setState('processing');
          vadRef.current.pause();
        } else if (message.phase === 'idle' && activeRef.current) {
          setState('listening');
          vadRef.current.resume();
        }
        break;
      case 'turn.transcript':
        setStatus((prev) => ({ ...prev, transcript: message.text }));
        break;
      case 'turn.reply':
        setStatus((prev) => ({ ...prev, reply: message.text }));
        break;
      case 'audio.out':
        audioOutRef.current.push({
          data: message.data,
          format: message.format,
        });
        break;
      case 'turn.done':
        try {
          await playEncodedAudio(audioOutRef.current);
        } catch (err) {
          setVoiceError(
            err instanceof Error ? err.message : 'Playback failed',
          );
          return;
        } finally {
          audioOutRef.current = [];
          vadRef.current.reset();
        }
        break;
      case 'error':
        setVoiceError(message.message);
        break;
      default:
        break;
    }
  }, [setVoiceError]);

  const ensureClient = useCallback(() => {
    if (!clientRef.current) {
      const client = new VoiceClient(VOICE_WS_URL);
      client.setHandlers({
        onMessage: (message) => {
          void handleServerMessage(message);
        },
        onError: (message) => setVoiceError(message),
        onClose: () => {
          sessionReadyRef.current = false;
          if (activeRef.current) {
            setVoiceError('Disconnected from Donna server');
          }
        },
      });
      clientRef.current = client;
    }
    return clientRef.current;
  }, [handleServerMessage, setVoiceError]);

  const ensureRecorder = useCallback(() => {
    if (!recorderRef.current) {
      recorderRef.current = new AudioRecorder();
      recorderRef.current.onAudioReady(
        {
          sampleRate: AUDIO_SAMPLE_RATE,
          bufferLength: AUDIO_SAMPLE_RATE * 0.1,
          channelCount: AUDIO_CHANNELS,
        },
        ({ buffer }) => {
          if (!activeRef.current || !sessionReadyRef.current) return;
          if (!clientRef.current?.isConnected) return;

          const channel = buffer.getChannelData(0);
          const pcm = floatToPcm16(channel);
          const seq = chunkSeqRef.current++;
          clientRef.current.send({
            type: 'audio.chunk',
            seq,
            format: 'pcm16',
            sampleRate: AUDIO_SAMPLE_RATE,
            channels: AUDIO_CHANNELS,
            data: pcm16ToBase64(pcm),
          });

          if (vadRef.current.process(channel)) {
            clientRef.current.send({ type: 'turn.end' });
            vadRef.current.reset();
          }
        },
      );
    }
    return recorderRef.current;
  }, []);

  const stopSession = useCallback(async () => {
    activeRef.current = false;
    sessionReadyRef.current = false;
    chunkSeqRef.current = 0;
    audioOutRef.current = [];
    vadRef.current.resume();

    recorderRef.current?.stop();

    if (clientRef.current?.isConnected) {
      try {
        clientRef.current.send({ type: 'session.end' });
      } catch {
        // socket may already be closing
      }
      clientRef.current.disconnect();
    }

    await resetPlaybackSession();
    setState('idle');
    setStatus({ transcript: null, reply: null, phase: null });
  }, []);

  const startSession = useCallback(async () => {
    setState('requesting');
    setErrorMsg(null);
    setStatus({ transcript: null, reply: null, phase: null });

    AudioManager.setAudioSessionOptions({
      iosCategory: 'playAndRecord',
      iosMode: 'default',
      iosOptions: ['defaultToSpeaker'],
    });

    const permissions = await AudioManager.requestRecordingPermissions();
    if (permissions !== 'Granted') {
      setVoiceError('Microphone permission denied');
      return;
    }

    const sessionActive = await AudioManager.setAudioSessionActivity(true);
    if (!sessionActive) {
      setVoiceError('Could not activate audio session');
      return;
    }

    const client = ensureClient();
    await client.connect();

    const readyPromise = new Promise<void>((resolve, reject) => {
      const timeout = setTimeout(() => {
        readyResolverRef.current = null;
        reject(new Error('Session setup timed out'));
      }, 8_000);
      readyResolverRef.current = () => {
        clearTimeout(timeout);
        resolve();
      };
    });

    client.send({ type: 'session.start' });
    await readyPromise;

    const recorder = ensureRecorder();
    const result = recorder.start();
    if (result.status === 'error') {
      setVoiceError(result.message ?? 'Failed to start recording');
      client.disconnect();
      return;
    }

    activeRef.current = true;
    vadRef.current.resume();
    setState('listening');
  }, [ensureClient, ensureRecorder, setVoiceError]);

  const toggleTalk = useCallback(async () => {
    if (state === 'listening' || state === 'processing') {
      await stopSession();
      return;
    }
    if (state === 'requesting') return;
    await startSession();
  }, [startSession, state, stopSession]);

  useEffect(() => {
    return () => {
      void stopSession();
    };
  }, [stopSession]);

  const statusText =
    state === 'error'
      ? (errorMsg ?? 'Something went wrong')
      : status.transcript
        ? status.reply
          ? `You: ${status.transcript}\nDonna: ${status.reply}`
          : `You: ${status.transcript}`
        : state === 'processing'
          ? 'Donna is thinking…'
          : state === 'listening'
            ? 'Listening…'
            : null;

  return {
    state,
    toggleTalk,
    statusText,
    disabled: state === 'requesting',
  };
}
