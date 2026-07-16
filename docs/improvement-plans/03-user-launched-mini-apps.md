# Epic: Mini Apps

**Status:** Draft — living plan (no implementation yet)  
**Type:** Epic (will be broken into issues/PRs later)  
**Owner:** TBD  
**Last updated:** 2026-07-16

> This document is the working plan for Mini Apps on Donna.  
> We will keep editing it until the shape feels right, then slice it into an epic + tickets.  
> **Do not treat early sections as locked product decisions.**

---

## 1. Why this exists

Donna is strong as a conversational second brain (chat, voice, notes, memory, daily briefing). People also want **small, durable things that keep working for them** — not only one-off chats they have to remember to start.

Mini Apps are how users **launch their own little apps on Donna**: built primarily for personal use, then optionally made available to other users.

A scheduled “news I’m interested in” brief is **one** example of a mini app — not the definition of the product.

---

## 2. Working definition (broad)

A **Mini App** is a user-owned (or installed) product surface on Donna that:

1. Has a clear job (one primary outcome users return for)
2. Can run on demand and/or from triggers (time, events, chat, etc.)
3. Can use Donna’s brain (memory, notes, tools, models) under the user’s identity
4. Has its own identity in the product (name, home screen, history/state — not buried as a saved prompt)
5. Can stay private, or be published so others can install / fork it

Mini Apps are **not** merely saved prompts. Prompts may be one building block inside a richer app model.

---

## 3. Product principles

1. **Personal-first.** Creating something useful for yourself is the default success path. Sharing is optional and later.
2. **Feels like an app, not a macro.** Named home, repeatable job, history/state, clear controls — not a paste-bin of prompts.
3. **Donna-native.** Apps should compose with memory, notes, chat, and voice where it helps — not be a bolted-on automation island.
4. **Authorable by normals.** Power users can go deep; most people should create via guided UI and/or by asking Donna to build/configure the app.
5. **Safe by default.** Private until published. Runs as the installing user. No silent access to other people’s data.
6. **Expandable platform.** Start with a coherent core model; leave room for richer UI, tools, workflows, and distribution without rewriting the concept.

---

## 4. Example scenarios (illustrative, not exhaustive)

These are prompts for the epic shape — not a v1 scope commitment.

| Scenario | Why it’s more than a prompt recipe |
|----------|-------------------------------------|
| Morning news / interest brief at a fixed time | Schedule, preferences, sources, delivery, history |
| Weekly personal review from notes + chats | Multi-source context, structured output, archive |
| “Prep me for this meeting” from a calendar event | Event trigger, inputs, short-lived UI |
| Habit / accountability check-ins | State over time, reminders, streak or log |
| Research desk on a topic | Saved configuration, tools, iterative runs, artifacts |
| Shared team ritual (e.g. standup helper) | Install/share, per-user config, permissions |
| “Turn this chat into an app” | Authoring UX: Donna helps create the mini app |
| Lightweight tool with a tiny form UI | Inputs → run → rendered result (not only chat transcript) |

Add/remove scenarios here as the plan evolves.

---

## 5. Capability areas (epic backlog themes)

Treat these as **themes to refine**, not an implementation checklist. Ordering and depth TBD.

### 5.1 App identity & lifecycle
- Create, rename, archive, delete
- App home (overview, last run, controls)
- Versioning / drafts vs published definition
- Ownership transfer / fork lineage (later)

### 5.2 Authoring
- Form-based builder (structured config)
- Natural-language authoring (“Donna, make me an app that…”)
- Edit after create; test run while building
- Templates / starter apps (first-party + community later)

### 5.3 Logic & intelligence
- Instructions / system behavior beyond a single user prompt
- Parameters & user inputs (forms, choices, files, links)
- Multi-step flows (gather → think → act → present)
- Tool use policies (web, memory, notes, future integrations)
- Structured outputs (not only free text) for reliable UI

### 5.4 Triggers & runtime
- Manual run
- Time schedules (daily/weekly/cron-like) with timezone
- Event triggers (note added, calendar, webhook, chat command — explore)
- Background execution with reliable server-side scheduling
- Run history, logs, failures, retries
- Quotas / rate limits / cost awareness

### 5.5 State, memory & artifacts
- Per-install configuration (preferences that aren’t the shared definition)
- Per-app memory/state (what this app remembers across runs)
- Artifacts (saved briefs, reports, lists) browsable in the app
- Optional write-back into Notes / Memory with clear user control

### 5.6 Experience / UI
- Dedicated Mini Apps area in web + iOS
- App detail: configure, run, history, share
- Result presentation beyond a chat bubble (simple layouts, lists, digests)
- Notifications / email / in-app inbox for completed runs
- Voice entry points where natural (“run my news app”)

### 5.7 Sharing & distribution
- Private (default), unlisted link, public gallery
- Install vs fork
- What installers can customize (schedule, preferences) vs locked definition
- Trust & safety (review, report, abuse limits)
- First-party apps (e.g. how Daily Briefing relates — see open questions)

### 5.8 Platform & admin
- Permissions model
- Observability for runs
- Migration/version compatibility as the app model grows
- Analytics that respect privacy

---

## 6. Relationship to existing Donna surfaces

| Existing | Relationship to Mini Apps (open) |
|----------|----------------------------------|
| Chat / voice | Authoring + invocation surface; not a replacement for general conversation |
| Notes | Possible input source and/or artifact sink |
| Memory | Available to apps under user control; apps may also keep scoped state |
| Daily briefing (`/notes/daily-check`) | Candidate first-party mini app **or** remains a built-in adjacent feature — decide later |
| Saved prompts (if any) | Insufficient alone; may migrate into mini-app authoring |

---

## 7. Non-goals (for now — revisit as epic matures)

These are provisional fences so the epic doesn’t become “build a whole OS”:

- Arbitrary untrusted code execution / full custom React bundles uploaded by users
- A general Zapier replacement on day one
- Paid marketplace / tipping (can be discussed later)
- Replacing core chat, notes, or memory products

As the plan firms up, some of these may move into later epic phases rather than stay forever out.

---

## 8. Open questions (actively edit this list)

1. **What is the minimum object model?** Definition vs install vs run vs artifact — how rich before first ship?
2. **How much UI can a mini app have?** Text digest only → simple structured views → user-defined layouts?
3. **How are apps authored?** Builder UI, Donna-assisted, code-like config, or all three over time?
4. **What triggers matter first** after manual + daily schedule?
5. **How does sharing work ethically/product-wise?** Show full definition on install? Allow updates to push to installers?
6. **Is Daily Briefing a mini app** or a sibling feature that teaches the pattern?
7. **Where do mini apps live in navigation** on iOS vs web without cluttering the core loop?
8. **What’s the first lovable vertical?** News brief is easy to explain — is it the right wedge, or is “apps from chat” the wedge?
9. **Multiplayer:** personal only at first, or early shared installs for households/teams?
10. **Success metric for the epic:** apps created? weekly active apps? retention lift? sharing rate?

---

## 9. Epic shape (placeholder milestones)

Milestones below are **intentionally coarse**. We will rewrite them after the open questions settle. No schema/API/UI work until then.

| Milestone | Intent |
|-----------|--------|
| **M0 — Plan** | This document; align on definition, principles, wedge |
| **M1 — Core model** | Agree object model + authoring + runtime story on paper |
| **M2 — Personal wedge** | First end-to-end personal mini app experience (scope TBD from §4/§8) |
| **M3 — Richer app behavior** | Inputs, state/artifacts, better results UI, more triggers |
| **M4 — Share & discover** | Publish, install, fork, gallery/trust basics |
| **M5 — Platform polish** | Notifications, templates, first-party apps, hardening |

---

## 10. How we’ll use this doc

1. Keep editing §§2–8 until the product story feels right.
2. Only then break **M1+** into GitHub epic + issues.
3. Implementation PRs should link back here; if reality diverges, update this plan first.

---

## 11. Decision log

| Date | Decision | Notes |
|------|----------|-------|
| 2026-07-16 | Treat Mini Apps as an epic-scale product surface, **not** “saved prompt recipes.” | Prompt/schedule news brief is an example scenario only. |
| 2026-07-16 | Plan-only for now; no schema/API/UI implementation in this pass. | Earlier narrow plan + migration were superseded. |
