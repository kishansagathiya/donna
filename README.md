Another AI second brain, but this one is the BEST!!

## Repos

| Project | Description |
|---------|-------------|
| [donna-app](./donna-app) | iOS app |
| [donna-web](./donna-web) | Landing page |
| [donna-server](./donna-server) | Voice backend (WebSocket STT → LLM → TTS) |

## Voice backend (local dev)

```bash
cp .env.example .env   # add OPENROUTER_API_KEY + a TTS key (Cartesia, ElevenLabs, or OpenAI)
npm install
npm run dev:server     # http://localhost:8787, ws://localhost:8787/voice
npm run test:voice     # sends a sample utterance, writes reply audio to voice/ws-test-reply.bin
```
