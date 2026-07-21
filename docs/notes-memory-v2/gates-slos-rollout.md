# Notes & Memory V2 — Evaluation gates, SLOs, and staged rollout

Parent: Epic #155 · Delivery issues: #164 (review UI), #165 (this doc)  
Related Chat epic work (linked only — **do not reparent**): [#117](https://github.com/kishansagathiya/donna/issues/117) eval scenarios, [#118](https://github.com/kishansagathiya/donna/issues/118) SLO instrumentation, [#119](https://github.com/kishansagathiya/donna/issues/119) privacy-conscious retrieval logging.

Canonical fixtures: `donna-server-go/evals/notes_memory_v2_scenarios.json` (≥120 scenarios, multilingual + mixed-language).  
Gate constants: `donna-server-go/internal/memory/gates.go`.

---

## Definition-of-Done gates

| Gate | Threshold | How we measure | Fixture suite |
| --- | --- | --- | --- |
| Notes cache render | **≤ 100 ms p95** | Client paint / feed hydrate from TanStack Query + optimistic cache (#158); no network wait on warm cache | `notes_write_path` |
| Notes writes | **No sync LLM / embeddings** | Write handlers enqueue background jobs only; assert zero LLM/embed calls in request span (#118) | `notes_write_path` |
| Smart-tag auto-apply | **≥ 90% precision** | Offline judge vs gold labels on `smart_tagging` fixtures | `smart_tagging` |
| High-confidence extraction | **≥ 95% precision** | Extraction judge on `memory_extraction` (confidence ≥ 0.90 auto-activate path) | `memory_extraction` |
| Durable recall | **≥ 90%** | Seed memory → later query must retrieve; measured on `memory_recall` | `memory_recall` |
| Generic prompts | **No embedding request** | Retrieval planner short-circuits greetings/thanks (`retrieval_plan`) | `retrieval_plan` |
| Memory retrieval latency | **≤ 500 ms p95** | Server `memory_retrieval_events.latency_ms` (+ #118 SLOs) | `memory_recall` |
| Sensitive review | **Required before activation** | Sensitive/restricted never auto-activate; review inbox + accept path (#164) | `memory_safety` |
| Credentials / protected traits | **Never stored** | Safety rejectors in `internal/memory/safety.go`; fixtures assert no fact write | `memory_safety` |

All gates must be green on the fixture set before advancing past the **25%** cohort. Web + iOS parity for Notes, tag management, Memory review, and provenance is required before **100%**.

---

## Eval scenarios (#165 → extends #117)

- **Count:** see `scenario_count` in `notes_memory_v2_scenarios.json` (currently ≥ 120).
- **Coverage:** English, ES/FR/DE/HI/JA/ZH/PT, and mixed-language (`mixed_en_*`) notes/queries.
- **Suites:** extraction, smart-tag, recall/retrieval, generic no-embed, notes write path, safety.
- **Runner (local):**

```bash
cd donna-server-go
go test ./internal/memory/ ./internal/storage/ -count=1
python3 -c "import json; d=json.load(open('evals/notes_memory_v2_scenarios.json')); assert d['scenario_count']>=120"
```

Full LLM judge harness remains under Chat #117; this suite is the Notes/Memory V2 extension those runners should consume.

---

## Instrumentation (#118 / #119)

Consume (do not duplicate ownership of) Chat epic instrumentation:

- **#118** — latency histograms for notes feed hydrate, memory retrieval, background job lag.
- **#119** — privacy-conscious retrieval logs (query redaction, no raw note bodies in hot logs; prefer `memory_retrieval_events.result_summary`).

Operators should alert on:

- retrieval p95 > 500 ms for 15 minutes
- extraction precision rolling window < 95%
- smart-tag precision < 90%
- any credential-like write attempt (safety reject counter spike)

---

## Staged rollout (stable cohorts)

Feature flags (per-user overrides on `user_preferences`):

- `flag_notes_v2_feed`
- `flag_notes_v2_smart_tagging`
- `flag_memory_v2_extraction`
- `flag_memory_v2_retrieval`

Server defaults come from env / `config.Config`; overrides via `featureflags.Resolver`.

### Cohort plan

| Stage | Cohort | Targeting | Hold |
| --- | --- | --- | --- |
| 0 · Internal | Donna team + dogfood accounts | Explicit allow-list overrides = `true` | ≥ 3 days green gates |
| 1 · 5% | Stable 5% of users | `hash(user_id) % 100 < 5` **or** sticky cohort table | ≥ 5 days |
| 2 · 25% | Stable 25% | `hash(user_id) % 100 < 25` (superset of 5%) | ≥ 7 days |
| 3 · 100% | Everyone | Server defaults `true`; clear temporary overrides | Continuous |

**Stable cohorts:** once a user is in a stage, they stay in that stage (and all later stages) for the campaign. Do not reshuffle daily — use a fixed hash salt `notes-memory-v2-2026` documented in ops runbooks.

Suggested enablement order inside a stage: Notes feed → smart tagging → memory extraction → memory retrieval (retrieval last so review inbox from #164 is already available for sensitive/conflict queues).

---

## Pause / fallback / rollback

### Pause

1. Freeze cohort expansion (do not raise hash threshold).
2. Set server defaults for the failing flag to `false` (or force overrides for affected cohort).
3. Keep serving Notes CRUD + legacy memory facts (`/memory/facts`) so clients remain usable.

### Fallback

| Symptom | Fallback |
| --- | --- |
| Extraction quality / safety | Disable `flag_memory_v2_extraction`; pending suggestions remain reviewable; no new auto-writes |
| Retrieval latency / relevance | Disable `flag_memory_v2_retrieval`; chat falls back to legacy `RetrieveMemory` |
| Smart-tag precision | Disable `flag_notes_v2_smart_tagging`; manual + hashtag tags only |
| Feed / cache issues | Disable `flag_notes_v2_feed`; clients use prior notes list endpoints |

### Rollback

1. Flip the specific flag default to `false` in config / env and redeploy server.
2. Optionally PATCH `user_preferences` overrides to `false` for the active cohort.
3. Do **not** drop V2 schema columns (0014/0016 are additive). Leave pending `memory_suggestions` unresolved rather than bulk-activating.
4. Confirm #118 dashboards return to baseline; file incident notes against #165.

Emergency “all off” matrix: all four `flag_*` defaults `false`. Clients keep working with pre-V2 paths.

---

## Parity checklist before 100%

- [ ] Web Memory: grouped kinds + pending/sensitive/conflicting/rejected/outdated inboxes (#164)
- [ ] iOS Memory: same filters and actions
- [ ] Provenance: evidence on memory items; derived memories on note detail (web + iOS)
- [ ] Citation feedback: Not relevant / Outdated
- [ ] Sensitive memories require explicit accept
- [ ] Eval suite ≥120 scenarios green against gates above
- [ ] #117/#118/#119 dashboards linked and alerting
