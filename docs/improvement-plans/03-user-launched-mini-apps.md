# Plan: Mini Apps Platform

**Status:** Draft plan → GitHub epic  
**Epic issue:** [#151 Mini Apps platform](https://github.com/kishansagathiya/donna/issues/151)  
**Phase issues:** [#146](https://github.com/kishansagathiya/donna/issues/146) · [#147](https://github.com/kishansagathiya/donna/issues/147) · [#148](https://github.com/kishansagathiya/donna/issues/148) · [#149](https://github.com/kishansagathiya/donna/issues/149) · [#150](https://github.com/kishansagathiya/donna/issues/150)  
**Related:** [Epic #132 Intent → Action platform](https://github.com/kishansagathiya/donna/issues/132)  
**Last updated:** 2026-07-16

---

## Summary

Build Donna’s **Mini Apps** platform so people can **launch their own little apps on Donna** — primarily for themselves, optionally shared with others.

ChatGPT is a blank chat. Donna already owns the user’s life stream (voice, chat, notes, memory, daily briefing). This epic makes that stream **productizable by the user**: package a job into an app with identity, configuration, triggers, runtime, state, results UI, and (later) distribution.

A scheduled “news I’m interested in” brief is **one** scenario. Mini Apps are **not** saved-prompt recipes. Prompts/instructions are one building block inside a richer app model (inputs, tools, state, artifacts, UI, sharing).

---

## Problem

Today, repeatable personal jobs live in the user’s head:

- Re-type the same prompt every morning
- Remember to open chat and ask for a review
- Hack schedules with calendar reminders that don’t run Donna
- No way to give a friend “the same tool I use” without copy-pasting instructions

Daily briefing is a first-party taste of this — but users cannot invent their own equivalents.

---

## Vision

Users can create, run, and (optionally) publish **Mini Apps**: named, durable product surfaces on Donna that:

1. Do one clear job well
2. Run on demand and/or from triggers
3. Use Donna’s brain under the **installing user’s** identity
4. Keep configuration, history, and artifacts of their own
5. Feel like apps (home screen, controls, results) — not macros buried in chat history

---

## Product principles

1. **Personal-first** — usefulness for yourself is the default win; sharing is optional
2. **App, not macro** — identity, home, history/state, controls
3. **Donna-native** — compose with memory, notes, chat, voice, and (where relevant) Actions
4. **Authorable by normals** — builder UI + “ask Donna to make this app”
5. **Safe by default** — private until published; runs as installer; no cross-user data bleed
6. **Platform that can grow** — coherent core object model that expands into richer UI/tools/workflows without a rewrite

---

## Core abstraction

| Object | Meaning |
|--------|---------|
| **Mini App (definition)** | Author-owned recipe: identity, instructions/behavior, input schema, tool policy, output schema, default triggers, visibility |
| **Install** | Per-user instance of a definition: enabled flag, schedule/timezone, personal config overrides, notification prefs |
| **Run** | One execution: trigger → pending/running → succeeded/failed; stores resolved inputs, output/artifacts, timings, errors |
| **Artifact** | Durable result from a run (brief, report, list, structured record) browsable in the app home |
| **Template** | First-party or curated starter definition users can install/fork |

### Trust & tenancy

- Runs always execute as the **installing user** (their memory, notes, connectors, quotas)
- Publishing shares the **definition**, never other users’ runs/artifacts
- Private by default; `unlisted` (link) and `public` (gallery) are explicit choices

### Relationship to Intent → Action (#132)

| Layer | Role |
|-------|------|
| **Actions** | Discrete executable capabilities (remind, HTTP call, draft message, …) with confirm/ledger |
| **Mini Apps** | Packaged **experiences** — UI + schedule + state + multi-step logic that may *call* actions, chat/LLM turns, and tools |

Mini Apps should not duplicate the action ledger. Prefer: Mini App run → (optional) propose/execute Actions via the Actions platform when side effects are needed. Chat remains for free-form conversation; Mini Apps for named recurring jobs.

---

## Architecture (high level)

```
Authoring
  ├─ Builder UI (web/iOS)
  └─ Donna-assisted (“make me an app that…”) → definition draft

Definitions (mini_apps)
  └─ Installs (per user: schedule, config, notify)

Triggers
  ├─ Manual “Run now”
  ├─ Server scheduler (time / cron-like, timezone-aware)
  ├─ Chat/voice invoke (“run my news app”)
  └─ Later: events (note added, calendar, webhook, action outcomes)

Runtime
  └─ Mini App runner
        ├─ Resolve inputs + placeholders
        ├─ Apply tool policy (memory, web, notes, actions…)
        ├─ Multi-step / LLM / structured output
        └─ Persist run + artifacts

Surfaces
  ├─ Mini Apps home / detail / history (web + iOS)
  ├─ Notifications on complete
  └─ Gallery / install / fork (share phase)
```

**Server (proposed):** `donna-server-go/internal/miniapps/` + storage + scheduler tick (or dedicated cron worker when multi-replica).

**Clients:** Mini Apps area in `donna-web` and `donna-app` (shared API client later via `@donna/client-core` if plan 02 lands).

---

## Example scenarios (drive requirements)

| Scenario | Capabilities exercised |
|----------|------------------------|
| Morning interest/news brief at a fixed time | Schedule, web tools, preferences, artifacts, notify |
| Weekly personal review from notes + chats | Multi-source context, structured output, archive |
| Meeting prep from a calendar event | Event trigger, inputs, short-lived result UI |
| Habit / accountability check-ins | Long-lived state, reminders, log/streak artifact |
| Research desk on a topic | Config, iterative runs, tool policy, artifact library |
| Shared standup / ritual helper | Install/share, per-user config, permissions |
| “Turn this chat into an app” | NL authoring from conversation context |
| Small form tool (inputs → rendered result) | Input schema, structured output, non-chat UI |

---

## Phased delivery

### Phase 1 — Platform skeleton (personal core) — [#146](https://github.com/kishansagathiya/donna/issues/146)

**Goal:** End-to-end personal Mini App without sharing.

**Scope (proposed):**

- [ ] Object model + Supabase migration (`mini_apps`, `mini_app_installs`, `mini_app_runs`, artifacts as needed)
- [ ] Go storage + CRUD APIs for definitions/installs/runs
- [ ] Manual **Run now** via runner (LLM path + tool flags; reuse pipeline where possible)
- [ ] Time schedule on installs (daily/weekly + timezone) + server tick / claim due installs
- [ ] Web: My Apps list, create/edit, detail, run history, latest artifact view
- [ ] Basic failure states and timeouts

**Out of scope:** Gallery, public/unlisted, iOS parity (can slip to Phase 1b), rich custom layouts, Actions integration.

**Acceptance:**

- User creates “My morning news,” sets 08:00 local, enables web search
- **Run now** produces a stored run + readable result
- Next due schedule fires without opening chat; history shows the run

---

### Phase 2 — App depth (inputs, state, results UI) — [#147](https://github.com/kishansagathiya/donna/issues/147)

**Goal:** Apps feel like apps, not scheduled prompts.

**Scope (proposed):**

- [ ] Input schema / parameters (form fields the user fills or saves as defaults)
- [ ] Structured output schema → simple rendered views (list, sections, digest)
- [ ] Per-install config + light per-app state
- [ ] Artifacts browser on app home
- [ ] Optional write-back to Notes (explicit user toggle)
- [ ] iOS Mini Apps surfaces (parity with web Phase 1+)
- [ ] Invoke from chat/voice by app name

**Acceptance:**

- User can configure preferences (topics, length, sources) without editing raw prompt text only
- Results show in a dedicated app result view, not only a chat transcript dump
- App retains useful history/artifacts across days

---

### Phase 3 — Authoring & templates — [#148](https://github.com/kishansagathiya/donna/issues/148)

**Goal:** Easy creation for non-power-users.

**Scope (proposed):**

- [ ] Guided builder (job, triggers, tools, output style)
- [ ] Donna-assisted authoring from chat (“make this an app”)
- [ ] First-party templates (morning brief, weekly review, …)
- [ ] Test-run while editing; draft vs active definition
- [ ] Clarify relationship: Daily Briefing as template vs built-in sibling

**Acceptance:**

- New user can create a useful app in under a few minutes without writing a “prompt essay”
- At least 2–3 first-party templates install cleanly

---

### Phase 4 — Share & discover — [#149](https://github.com/kishansagathiya/donna/issues/149)

**Goal:** Make an app available to other users.

**Scope (proposed):**

- [ ] Visibility: private / unlisted / public
- [ ] Install flow (copy schedule defaults; runs as installer)
- [ ] Fork-to-own
- [ ] Gallery (web + app)
- [ ] Trust & safety basics (report, rate limits, no run leakage)
- [ ] Policy for definition updates vs installed pins

**Acceptance:**

- Author publishes unlisted link; friend installs and gets their own schedule/results
- Friend cannot see author’s run history
- Fork lets friend customize without breaking author’s definition

---

### Phase 5 — Platform polish & integrations — [#150](https://github.com/kishansagathiya/donna/issues/150)

**Goal:** Harden and connect to the rest of Donna.

**Scope (proposed):**

- [ ] Push/email delivery for completed runs
- [ ] Deeper Actions integration (side effects via #132 with confirm where needed)
- [ ] Event triggers (notes/calendar/webhooks) as they become available
- [ ] Quotas, observability, admin/debug views
- [ ] Versioning / migration story for definitions

**Acceptance:**

- Scheduled apps reliably notify
- Side-effecting apps go through Actions trust model
- Ops can diagnose stuck/failed runs

---

## Surfaces (product UI)

| Surface | Web | iOS |
|---------|-----|-----|
| Mini Apps home | Sidebar section / `/app/mini-apps` | Tab or hub entry |
| Create / edit | Builder page | Builder screens |
| App detail | Config, run, history, artifacts | Same |
| Gallery | `/app/mini-apps/gallery` | Gallery screens |
| Notifications | Browser optional | Notifee (reuse daily briefing patterns) |
| Chat invoke | Slash/command or NL | Same + voice |

UI guidance: avoid marketplace chrome early; personal home + detail first. Gallery can be simple lists until share phase.

---

## Non-goals (initial)

- Arbitrary untrusted code / user-uploaded React bundles
- Full Zapier-style general automation on day one
- Paid marketplace / tipping
- Replacing chat, notes, memory, or daily briefing wholesale
- Fully autonomous irreversible external side effects without Actions-style confirmation

---

## Success criteria (epic-level)

- Users create Mini Apps for themselves and return to them (weekly active installs/runs)
- At least one flagship personal loop (e.g. morning brief) works reliably on a schedule
- Sharing works without leaking private runs/memory
- Authoring is possible without being a prompt engineer
- Clear composition story with Actions (#132), not two competing automation systems

---

## Open questions

1. Exact minimum object model for Phase 1 (are artifacts separate from runs?)
2. How rich is Mini App UI in Phase 2 (fixed renderers vs declarative layout)?
3. Wedge: news brief vs “apps from chat” vs templates-first?
4. Is Daily Briefing a Mini App template or a permanent built-in?
5. Definition updates: push to installers or pin versions?
6. Navigation placement without cluttering Chat/Notes/Today
7. Multiplayer household/team installs in Phase 4 or later?
8. Primary success metric (apps created, WAUs of apps, retention, share rate)?

---

## Decision log

| Date | Decision |
|------|----------|
| 2026-07-16 | Mini Apps ≠ prompt recipes; epic-scale platform |
| 2026-07-16 | Plan + GitHub epic first; implementation after phases are agreed |
| 2026-07-16 | Compose with Actions (#132); don’t fork a second side-effect system |
