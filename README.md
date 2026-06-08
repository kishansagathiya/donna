Another AI second brain, but this one is the BEST!!

## Repos

| Project | Description |
|---------|-------------|
| [donna-app](./donna-app) | iOS app |
| [donna-web](./donna-web) | Landing page |
| [donna-server](./donna-server) | Voice backend (WebSocket STT → LLM → TTS) |

## Auth (Supabase + Sign in with Apple)

Donna uses Supabase Auth with Postgres, same pattern as [glucose-ai](https://github.com/kishansagathiya/glucose-ai).

1. Create a Supabase project.
2. Enable Apple provider in Supabase Auth (Client ID: `com.kishansagathiya.donna`).
3. Set `SUPABASE_URL` and publishable key in `donna-app/src/config.ts`.
4. Set `SUPABASE_URL` in root `.env` so `donna-server` requires a valid JWT on `/voice`.

## Voice backend (local dev)

```bash
cp .env.example .env   # add OPENROUTER_API_KEY + a TTS key (Cartesia, ElevenLabs, or OpenAI)
set -a
source .env
set +a
npm install
npm run dev:server     # http://localhost:8787, ws://localhost:8787/voice
npm run test:voice     # sends a sample utterance, writes reply audio to voice/ws-test-reply.bin
```

### App → local backend (no code changes)

The iOS app reads voice settings from the same root `.env` (synced when you `npm start` in `donna-app`).

| Scenario | `.env` |
|----------|--------|
| iOS Simulator + local server (default) | `DONNA_VOICE_TARGET=local` |
| Physical iPhone on LAN | `DONNA_VOICE_TARGET=local` (Mac host auto-detected on `npm start`) |
| Dev build → production Railway | `DONNA_VOICE_TARGET=production` |

Release builds always use production. Restart Metro after changing `.env`.
