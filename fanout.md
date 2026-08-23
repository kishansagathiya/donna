# Plan: "Donna Learn" — a fanout-style learning mini-app

## Product concept

Fanout's core loop — *structured curriculum + daily bite-sized content + interactive explanation + concept map* — rebuilt natively so it compounds with Donna's memory. Every lesson completed, paper read, and equation decoded becomes something Donna *remembers*, can quiz you on in chat, and surfaces in your Today briefing. Fanout is a destination; Donna Learn is a study partner that lives in your second brain.

**Name/route:** "Learn" at `/app/learn`, sidebar entry with `GraduationCap` icon.

## The four features, mapped to Donna

| Fanout feature | Donna version | Integration hook |
|---|---|---|
| Structured roadmaps/courses | **Tracks & Lessons** — markdown curriculum with progress tracking | Lesson completion → memory fact (`completed_lesson`) |
| Daily paper explanations | **Daily Paper** — one landmark AI paper/day, LLM-explained | Injected into Today briefing; saveable as note |
| Math decoder | **Decoder** — paste equation/concept → streamed plain-English breakdown | One-click "Save to notes" (`#learn` hashtag) |
| Knowledge graph | **Concept Graph** — concepts + prerequisite edges, clickable SVG map | Per-user mastery overlay from your progress |

## Architecture

### Backend — new `donna-server-go/internal/learn/` package

Following the established recipe (handler + storage + routes registered in `cmd/server/main.go`):

- `handler.go` — REST endpoints:
  - `GET /learn/tracks` / `GET /learn/tracks/:slug` — curriculum tree
  - `POST /learn/lessons/:id/complete` — marks progress, fires memory + note hooks
  - `GET /learn/progress` — per-user state for dashboard
  - `GET /learn/daily` — today's paper (generate-once-per-date, cached in DB — no scheduler exists, so generate on first request, same on-demand pattern as the briefing)
  - `POST /learn/explain` — decoder endpoint (SSE stream, mirrors `POST /chat?stream=1` pattern)
  - `GET /learn/graph` — concepts + edges + user's mastery
- `storage.go` — queries via `storage.Supabase` (PostgREST, per repo convention)
- `papers.go` — curated list of ~30 landmark papers (Attention Is All You Need, etc.) rotated by date; LLM generates the explanation from the abstract on first request, then it's cached. *Deliberately no arXiv scraping in v1 — deterministic and offline-safe.*
- `memory.go` — on lesson complete: direct `Knowledge.InsertMemoryFact` (`MemoryKind: "event"`, `Predicate: "completed_lesson"`, confidence 1.0) — deterministic, bypasses the LLM extraction gate

### Database — one migration, `0025_learn.sql`

```
learn_tracks        (id, slug, title, description, domain, position)
learn_lessons       (id, track_id, slug, title, content_md, position, est_minutes)
learn_progress      (user_id, lesson_id, status, completed_at)
learn_concepts      (id, slug, name, domain, description_md)
learn_concept_edges (from_id, to_id, relation)          -- the knowledge graph
learn_user_concepts (user_id, concept_id, familiarity)  -- mastery overlay
learn_daily_papers  (date, title, abstract, explanation_md, concepts[], unique on date)
```

### Frontend — `donna-web/src/pages/learn/`

Following the `NotesPage`/`DailyTasksPage` conventions (sticky header, `Card` grid, TanStack Query, `authorizedFetch`):

- `LearnPage.tsx` — dashboard: "Continue learning" card, track grid, today's paper teaser
- `TrackDetailPage.tsx` → `LessonPage.tsx` — markdown lesson, "Mark complete", next-lesson nav
- `DecoderPage.tsx` — textarea → streamed explanation → "Save to notes" / "Ask in chat" buttons
- `DailyPaperPage.tsx` — paper explanation with linked concepts
- `GraphPage.tsx` — custom lightweight SVG radial layout (no new deps), click node → concept popover, colored by your mastery
- `services/learnApi.ts` + `learnQueryKeys.ts` per repo pattern
- Route + `PageTitle` entries in `App.tsx`, nav item in `Sidebar.tsx`, `/learn` prefix in `vite.config.ts` proxy

### Integration hooks (the Donna-specific value)

1. **Memory**: lesson completion → `InsertMemoryFact` event (backend, automatic)
2. **Notes**: every explanation/paper/lesson has "Save to notes" → `POST /notes` (uses `source_type: "manual"` + `#learn` hashtag — avoids relaxing the DB CHECK constraint); the note then flows into memory extraction, tags, and FTS search for free
3. **Today briefing**: add `Learn *LearnBriefing` field to `DailyBriefing` in `internal/notes/daily.go` (there's precedent — `Outdated` was added the same way), render a new section in `DailyTasksPage.tsx`
4. **Agent study partner**: new `"learn"` toolset in `internal/agents/tools.go` — `lookup_learning_progress`, `recommend_next_lesson`, `quiz_me`; plus a chat tool `explain_concept` in `internal/pipeline/tools/`; add `"learn"` to the spawner's default allowlist
5. **Chat deep-link**: "Ask Donna about this" → `navigate("/app", { state: { prefillPrompt } })`, consumed in `ChatApp.tsx`'s existing `location.state` effect (small new handler, pattern already exists for `ingestToast`)

### Feature gating

Add to `ExperimentalSection.tsx`'s `FEATURES` list (currently empty — first citizen) + sidebar item hidden unless enabled. Ship dark, iterate, then default-on.

## Phasing

| Phase | Scope | Rough size |
|---|---|---|
| **1. MVP curriculum** | Migration, seed 1 track (~6 lessons, authored markdown), tracks/lessons/progress endpoints, Learn dashboard + lesson pages, sidebar, experimental gate | L |
| **2. Decoder** | `/learn/explain` SSE endpoint, DecoderPage, save-to-notes, ask-in-chat deep-link | M |
| **3. Daily paper + Today** | Curated paper list, `/learn/daily`, briefing injection, DailyPaperPage | M |
| **4. Concept graph** | Concepts/edges seed, `/learn/graph`, GraphPage SVG viz, mastery overlay | M |
| **5. Study partner** | Agent toolset + chat tool, `quiz_me`, progress memory facts | M |

**Content note:** the one genuinely new burden vs. normal feature work is *authoring curriculum*. Phase 1 ships with one well-crafted track to validate the loop; more content is an ongoing editorial task, not engineering.

**Testing:** Go handler/storage tests per package convention; vitest for `learnApi` hooks and the progress mutation (mirroring `useNotes` tests).

## Open questions

1. **Content authorship** — do you want to write the seed track yourself, or should I draft "AI Research Foundations" (6 lessons) as the initial content?
2. **Decoder scope** — math-only (LaTeX equations → plain English), or any concept ("explain KV caching like I'm lost")? I'd recommend *any concept* — it's the same endpoint and more useful.
3. Anything from fanout's model you explicitly *don't* want? (e.g., quizzes per-lesson — I left them out of MVP since the agent `quiz_me` covers it better.)
