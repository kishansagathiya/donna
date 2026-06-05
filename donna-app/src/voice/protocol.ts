export type TurnPhase =
  | 'idle'
  | 'busy'
  | 'transcribing'
  | 'generating'
  | 'synthesizing'
  | 'done'
  | 'error';

export type ClientMessage =
  | { type: 'session.start'; userId?: string; sessionId?: string }
  | {
      type: 'audio.chunk';
      seq: number;
      format: 'pcm16';
      sampleRate: number;
      channels: number;
      data: string;
    }
  | { type: 'turn.end' }
  | { type: 'session.end' };

export type ServerMessage =
  | { type: 'session.ready'; sessionId: string; userId: string }
  | { type: 'turn.phase'; phase: TurnPhase }
  | { type: 'turn.transcript'; text: string }
  | { type: 'turn.reply'; text: string }
  | {
      type: 'audio.out';
      seq: number;
      format: 'mp3' | 'wav';
      data: string;
    }
  | {
      type: 'turn.done';
      timings: Record<string, number>;
    }
  | { type: 'error'; code: string; message: string };

export function parseServerMessage(raw: string): ServerMessage {
  return JSON.parse(raw) as ServerMessage;
}
