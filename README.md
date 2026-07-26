Another AI second brain, but this one is the BEST!!

## Repos

| Project | Description |
|---------|-------------|
| [donna-app](./donna-app) | iOS app |
| [donna-web](./donna-web) | Landing page |
| [donna-server-go](./donna-server-go) | Chat + voice backend (HTTP chat; WebSocket STT) |

## Auth (Supabase + Sign in with Apple / Google)

Donna uses Supabase Auth with Postgres, same pattern as [glucose-ai](https://github.com/kishansagathiya/glucose-ai).

1. Create a Supabase project.
2. Enable Apple provider in Supabase Auth (Client ID: `com.kishansagathiya.donna`; web Services ID: `com.kishansagathiya.donna.web`).
3. Enable Google provider in Supabase Auth with a Google Cloud **Web** OAuth Client ID + Secret (and the iOS Client ID for the app). For native iOS Google Sign-In, enable **Skip nonce check**.
4. Set `SUPABASE_URL` and publishable key in `donna-app/src/config.ts`.
5. Set `GOOGLE_WEB_CLIENT_ID` / `GOOGLE_IOS_CLIENT_ID` in `donna-app/src/config.ts`, and add the iOS `REVERSED_CLIENT_ID` URL scheme to `donna-app/ios/Donna/Info.plist`.
6. Set `SUPABASE_URL` in root `.env` so `donna-server-go` requires a valid JWT on `/voice`.

Web Google sign-in uses Supabase OAuth redirect (no client ID in `donna-web`). See `donna-web/README.md` for redirect URL setup.

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

## Tests

```bash
npm test                                   # Go server tests (go test ./...)
npm run test:voice                         # live voice smoke test (needs server + keys)

# Time-to-first-token benchmarks (live server, report-only, no pass/fail):
DONNA_AUTH_TOKEN=<supabase JWT> npm run test:ttft        # both web + RN paths
DONNA_AUTH_TOKEN=<supabase JWT> npm run test:ttft:web    # web client path
DONNA_AUTH_TOKEN=<supabase JWT> npm run test:ttft:rn     # iOS/RN client path

# Benchmark a specific model (switches via PATCH /account, restores after):
DONNA_AUTH_TOKEN=<JWT> DONNA_TTFT_MODEL=z-ai/glm-5.2 npm run test:ttft
DONNA_AUTH_TOKEN=<JWT> DONNA_TTFT_MODEL=moonshotai/kimi-k2.6 npm run test:ttft:web
```

TTFT benchmarks measure wall-clock time from chat request send to the first `chunk` SSE event, against `DONNA_API_BASE` (default: Railway production). They reproduce each client's exact request contract (`donna-web/src/services/chatApi.ts` and `donna-app/src/services/chatApi.ts`). Setting `DONNA_TTFT_MODEL` PATCHes `/account` to that model before the runs and restores the original model afterwards (the slug must be in the server's allowlist — `GET /account` shows `available_models`).

When the server returns turn timings, each run also prints the pre-LLM,
augmentation, preferences, and provider first-token breakdown. This separates
Donna's setup time from model-provider latency while wall-clock TTFT remains the
primary client-visible measurement.

| Env | Default | Notes |
|-----|---------|-------|
| `DONNA_API_BASE` | `https://donna-server-go-production.up.railway.app` | set to `http://localhost:8787` for local |
| `DONNA_AUTH_TOKEN` | _(required for prod)_ | user access_token JWT from Supabase (Apple or Google Sign-In) |
| `DONNA_TTFT_RUNS` | `5` | iterations per client |
| `DONNA_TTFT_PROMPT` | `Hello` | prompt sent each run |
| `DONNA_TTFT_MODEL` | _(server default)_ | LLM slug to benchmark; must be in server's `available_models` |

`test:ttft = 2 × runs` real LLM calls (10 by default). Each run starts a fresh session so history doesn't inflate TTFT. The RN script reproduces the RN request contract in Node (`react-native-sse` can't run outside the app), so it measures server + network TTFT — not on-device native overhead.

Get a `DONNA_AUTH_TOKEN` from the web app after signing in: DevTools console →
```js
const k = Object.keys(localStorage).find(k => k.endsWith('-auth-token'));
copy(JSON.parse(localStorage.getItem(k)).access_token);
```
The token expires (~1hr); grab a fresh one if a run returns 401.
