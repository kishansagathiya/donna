# Donna voice stack (v1)

## Decision

**Primary path: cascaded STT → LLM → TTS** (near-live, control-first).

| Priority | Choice |
|----------|--------|
| Interaction | Near-live (push-to-talk or VAD + commit; ~1–2s per turn OK) |
| Architecture | Full control over transcript augmentation, RAG, swappable providers |
| API keys | **Single `OPENROUTER_API_KEY`** for STT, LLM, and TTS (v1) |
| LLM routing | **OpenRouter** for chat/completions and tools |
| Deferred | **GPT Realtime** — only if we later need sub-500ms duplex voice and barge-in |

### Separate Voice harness (Gemini Live)

Additive path for Gemini-style duplex conversations (app/web **Voice** tab → `GET /voice/live`). Does **not** replace chat mic / `/voice` STT. Requires `GEMINI_API_KEY`. Memory: seed + `retrieve_memory` tool → Donna `memory.Retriever`; turns persist via conversation store.

## Pipeline

```
Client (audio) → Donna server → STT → augment + RAG → LLM → TTS → Client (audio)
```

See [voice/orchestration.md](./voice/orchestration.md) for turn flow and server sketch.

## Components

| Layer | Role | v1 candidates |
|-------|------|----------------|
| **STT** | Audio → text | OpenRouter `openai/whisper-1` *or* `mistralai/voxtral-mini-transcribe` (see bake-off) |
| **Orchestration** | VAD/commit, context injection, session state | Donna server |
| **LLM** | Reasoning, tools | OpenRouter `POST /api/v1/chat/completions` (text only) |
| **TTS** | Text → speech | OpenRouter `openai/gpt-audio-mini` when provider allows; else direct OpenAI TTS / BYOK |

## Context injection

On each committed turn the server builds the LLM payload explicitly (no provider-specific realtime events):

```text
system: persona + stable user facts
user: [Retrieved: ...] [Session: ...] User said: "{transcript}"
```

## OpenRouter scope (one key)

| Capability | OpenRouter endpoint | Donna v1 |
|------------|---------------------|----------|
| **STT** | `POST /api/v1/audio/transcriptions` | Yes — **v1 pick:** `mistralai/voxtral-mini-transcribe` |
| **LLM** | `POST /api/v1/chat/completions` (text) | Yes |
| **TTS** | Chat completions + `modalities: ["text","audio"]` | Blocked for some accounts on OpenAI/Google; use BYOK or direct TTS |
| **GPT Realtime** (WebSocket/WebRTC) | No | Deferred |

Use **three separate calls** (STT → augment → LLM → TTS), not a single `gpt-audio` turn, so you keep transcript middleware.

Optional later: direct **Deepgram** or **ElevenLabs** keys for streaming STT or brand voice — not required for v1.

Env: `OPENROUTER_API_KEY` only (see [OpenRouter STT](https://openrouter.ai/docs/guides/overview/multimodal/stt), [Audio output](https://openrouter.ai/docs/guides/overview/multimodal/audio)).

## Near-live UX patterns

1. **Push-to-talk** — record → STT → augment → LLM → TTS → play (simplest v1).
2. **VAD + commit** — auto end-of-speech + debounce, then same pipeline.
3. **Streaming STT partials** — live caption; LLM only after commit.

## STT / TTS selection

Results and methodology: [voice/stt-tts-bakeoff.md](./voice/stt-tts-bakeoff.md).

## When to reconsider GPT Realtime

- Users need **barge-in** and **&lt;500ms** spoken turns.
- Willing to trade simple transcript middleware for Realtime session events + tools.

## Cost / latency (expectations)

| Metric | STT-first (near-live) | GPT Realtime |
|--------|------------------------|--------------|
| Control over user message | High | Medium |
| Typical turn latency | ~1–2s | ~300–500ms |
| Cost per minute (stacked) | ~$0.05–0.20 | ~$0.30–0.60 |
| OpenRouter for voice agent | STT + LLM + TTS yes | N/A |
