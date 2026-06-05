import type { ClientMessage, ServerMessage } from './protocol';
import { parseServerMessage } from './protocol';

export type VoiceClientHandlers = {
  onOpen?: () => void;
  onClose?: () => void;
  onError?: (message: string) => void;
  onMessage?: (message: ServerMessage) => void;
};

export class VoiceClient {
  private ws: WebSocket | null = null;
  private handlers: VoiceClientHandlers = {};

  constructor(private readonly url: string) {}

  setHandlers(handlers: VoiceClientHandlers): void {
    this.handlers = handlers;
  }

  connect(): Promise<void> {
    return new Promise((resolve, reject) => {
      if (this.ws?.readyState === WebSocket.OPEN) {
        resolve();
        return;
      }

      let settled = false;
      const fail = (message: string) => {
        if (settled) return;
        settled = true;
        this.handlers.onError?.(message);
        reject(new Error(message));
      };

      console.log('[donna-app] connecting to', this.url);
      const ws = new WebSocket(this.url);
      this.ws = ws;

      ws.onopen = () => {
        if (settled) return;
        settled = true;
        console.log('[donna-app] voice connected');
        this.handlers.onOpen?.();
        resolve();
      };

      ws.onerror = () => {
        fail(
          `Cannot reach Donna server at ${this.url}. ` +
            'Start it with npm run dev:server. ' +
            'On a physical iPhone, set VOICE_SERVER_HOST_OVERRIDE in src/config.ts to your Mac LAN IP.',
        );
      };

      ws.onclose = (event) => {
        if (!settled) {
          fail(
            `Voice socket closed before connect (${this.url}, code ${event.code}). ` +
              'Is donna-server running?',
          );
        }
        this.handlers.onClose?.();
        this.ws = null;
      };

      ws.onmessage = (event) => {
        try {
          const message = parseServerMessage(String(event.data));
          this.handlers.onMessage?.(message);
        } catch {
          this.handlers.onError?.('Invalid server message');
        }
      };
    });
  }

  send(message: ClientMessage): void {
    if (this.ws?.readyState !== WebSocket.OPEN) {
      throw new Error('Voice socket is not connected');
    }
    this.ws.send(JSON.stringify(message));
  }

  disconnect(): void {
    this.ws?.close();
    this.ws = null;
  }

  get isConnected(): boolean {
    return this.ws?.readyState === WebSocket.OPEN;
  }
}
