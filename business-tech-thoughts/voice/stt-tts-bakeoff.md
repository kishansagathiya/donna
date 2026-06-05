# STT / TTS bake-off (Donna v1)

## Samples

Five near-live utterances (scheduling, memory query, reminder, technical phrase, self-correction):

| ID | File | Reference transcript |
|----|------|----------------------|
| 1 | `samples/utterance-1.wav` | Schedule a meeting with Alex for tomorrow at three PM. |
| 2 | `samples/utterance-2.wav` | Donna, what did I say about the Q3 roadmap in last week's notes? |
| 3 | `samples/utterance-3.wav` | Remind me to call the dentist after lunch. |
| 4 | `samples/utterance-4.wav` | The API rate limit is four hundred twenty requests per minute. |
| 5 | `samples/utterance-5.wav` | Um, actually, cancel that—just add milk to my grocery list. |

Generated with macOS `say` (clear EN-US). Re-run live scoring with:

```bash
export OPENROUTER_API_KEY=...   # recommended — STT + TTS in one key
# optional comparison:
# export OPENAI_API_KEY=...
# export DEEPGRAM_API_KEY=...
# export CARTESIA_API_KEY=...
# export ELEVENLABS_API_KEY=...
node business-tech-thoughts/voice/run-bakeoff.mjs
```

Output: `bakeoff-results.json` (WER per utterance, avg latency).

## Live run (2026-06-04)

| STT model | Avg latency | Avg WER |
|-----------|-------------|---------|
| `mistralai/voxtral-mini-transcribe` | 1927 ms | 0.115 |
| `nvidia/parakeet-tdt-0.6b-v3` | 1303 ms | 0.115 |

**Winner (STT):** `nvidia/parakeet-tdt-0.6b-v3` — same accuracy, ~32% faster. **Default for v1:** `mistralai/voxtral-mini-transcribe` (simpler vendor, sub-2s on 4/5 clips).

`openai/whisper-1` returned **403** (provider ToS) on this OpenRouter account. OpenAI/Google **TTS** (`gpt-audio-mini`) also **403** — use a direct `OPENAI_API_KEY` for TTS or enable [BYOK](https://openrouter.ai/docs/guides/overview/multimodal/stt) on OpenRouter.

## STT comparison

| Criterion | OpenAI Whisper (`whisper-1`) | Deepgram Nova-2 |
|-----------|-------------------------------|-----------------|
| **Latency (typical)** | ~300–800ms per short clip | ~200–400ms; streaming partials |
| **Streaming partials** | No (batch file API) | Yes — good for live captions |
| **Cost** | ~$0.006 / min | ~$0.0043–0.0125 / min (tier/model) |
| **Accuracy (general)** | Strong baseline | Competitive; often faster TTFT |
| **OpenRouter** | Yes — `openai/whisper-1` via `/audio/transcriptions` | Direct API only |
| **v1 fit** | **Default** with single `OPENROUTER_API_KEY` | When streaming partials needed |

### STT recommendation (v1)

- **OpenRouter** + `openai/whisper-1` at `POST /api/v1/audio/transcriptions` — same key as LLM/TTS.
- **Add Deepgram** (separate key) only when VAD + streaming partials are required.

## TTS comparison

| Criterion | OpenAI `tts-1` | ElevenLabs `eleven_turbo_v2_5` | Cartesia `sonic-3.5` |
|-----------|----------------|--------------------------------|----------------------|
| **Latency (short phrase)** | ~200–500ms to first byte | ~300–600ms | ~80–150ms |
| **Voice quality** | Good, limited presets | Premium, brand voices | Natural, expressive |
| **Cost** | ~$15 / 1M chars | Higher; plan-dependent | ~$10 / 1M chars |
| **Streaming** | Yes | Yes | Yes (WebSocket + HTTP) |
| **v1 fit** | Default for Donna | Optional polish / A-B later | Best for real-time agents |

### TTS recommendation (v1)

- **OpenRouter** chat completions with `openai/gpt-4o-mini-tts`, `modalities: ["text","audio"]`, `stream: true` — same key as STT/LLM.
- **Cartesia** `sonic-3.5` for lowest latency real-time TTS (~80–150ms).
- Direct OpenAI `tts-1` or **ElevenLabs** only if you need a dedicated speech API or brand voice later.

## Live metrics

No API keys were available in the automated environment run. After exporting keys, `run-bakeoff.mjs` writes:

```json
{
  "stt": {
    "whisper": { "avgMs": 0, "avgWer": 0, "rows": [] },
    "deepgram": { "avgMs": 0, "avgWer": 0, "rows": [] }
  },
  "tts": { "openai_tts_1": { "ms": 0, "bytes": 0 } }
}
```

**Scoring:** average word-error rate (WER) vs `samples/manifest.json` references; lower is better. Target avg WER &lt; 0.15 on clean samples.

## v1 stack (selected)

| Layer | Choice |
|-------|--------|
| API key | **`OPENROUTER_API_KEY`** (+ optional `OPENAI_API_KEY` for TTS until OR audio unblocks) |
| STT | **OpenRouter** → `mistralai/voxtral-mini-transcribe` (or `nvidia/parakeet-tdt-0.6b-v3` for speed) |
| LLM | **OpenRouter** `/chat/completions` (text, streaming) |
| TTS | Direct OpenAI `tts-1` or Cartesia `sonic-3.5` (lowest latency); OpenRouter BYOK until `gpt-audio-mini` works on account |
| Deferred | Deepgram STT, ElevenLabs TTS, GPT Realtime |

## Qualitative notes (clean TTS samples)

- Utterances 1–4 are single-intent; Whisper should score well.
- Utterance 5 tests disfluency (“um, actually, cancel that”); watch WER — may need prompt tuning, not STT swap.
- Domain terms (“Q3”, “API”, “Donna”) — verify on first live run; add vocabulary hints to Whisper `prompt` if needed.
