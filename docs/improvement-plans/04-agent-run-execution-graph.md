# Agent Run Execution Graph

## Summary

Add a dedicated authenticated route, `/app/agents/:runId/graph`, showing an agent run as a live, top-to-bottom execution graph. Successful steps are green, failures red, active steps blue, waiting or blocked steps amber, and unknown legacy states gray. Node shape, icon, and label identify prompts, tools, decisions, and outputs without relying on color.

The existing conversation timeline remains unchanged. A “View flow” action opens the graph, and “Back to run” returns to `/app?mode=agent&run=:runId`. Public shared-agent links remain prompt/output-only.

## Implementation Changes

- Instrument the existing cloud/local harness with structured tool-result metadata:
  - `outcome: "succeeded" | "failed" | "blocked"`
  - `duration_ms`
  - Optional `error`
  - `call_id` on approval events
  - `recovery_from: string[]` on the first logical event produced after the model observes failed calls
- Add an optional outcome to `ToolResult`. Resolve omitted outcomes centrally: a handler error or nonzero shell exit is failed, `Error:` is failed, `Refused:` is blocked, and all other results are succeeded. Persist the resolved outcome for every new run.
- Keep the existing `agent_steps.payload` JSONB schema and endpoints. No database migration is required, and desktop step batching passes the added fields unchanged.
- Build a pure frontend graph normalizer that:
  - Creates prompt nodes from the initial goal and later `user_message` events.
  - Pairs `tool_call` and `tool_result` by call ID into one tool-attempt node.
  - Combines `ask_user`/`request_approval` calls with their approval event into one decision node.
  - Adds turn outputs and terminal errors as output/error nodes.
  - Folds status, compression, memory-retrieval, and non-output thought events into the related node’s raw-event inspector so every stored sequence remains inspectable.
  - Uses explicit recovery links for new runs. For legacy runs, infer only a same-tool next attempt as “Likely retry”; otherwise show chronological continuation without inventing a recovery edge.
- Render a repository-native vertical graph without adding a graph framework:
  - Main chronological spine with failed attempts offset into a recovery lane.
  - Labeled dashed recovery/retry edges returning to the main path.
  - Compact fixed-height summaries; selecting a node opens a desktop side inspector or mobile bottom sheet containing arguments, result, timestamps, duration, error, recovery source, and folded raw events.
  - On narrow screens, reduce the failed-node offset while retaining a visible recovery gutter.
- Add a header with the goal, run status, live indicator, logical-step count, failure count, elapsed duration, legend, and navigation.
- Load all history through `after_seq` pagination rather than the current 200-step default. During queued/running runs, poll run state and only steps after the highest received sequence every 2.5 seconds; stop polling at terminal status while retaining manual retry after fetch errors.

## Interfaces and Acceptance Criteria

- Add frontend types `RunGraphNode`, `RunGraphEdge`, `GraphNodeType`, and `GraphOutcome`.
- Keep `AgentStep` backward-compatible by making the new payload fields optional.
- Every logical prompt, tool attempt, decision, output, and terminal error appears exactly once and in sequence order.
- Every raw `agent_steps.seq` is either represented directly or reachable through a logical node’s inspector.
- Completed or successful nodes display green plus a success icon and text; failures display red plus an error icon and text.
- Prompt, tool, decision, and output nodes have distinct markers, icons, and accessible type labels.
- A failed attempt followed by an explicitly linked recovery renders as a side branch that rejoins the main path.
- Active runs surface new steps within one polling interval without duplicating or reordering nodes.
- Missing, unmatched, or legacy events render as unknown or pending rather than being incorrectly marked successful.
- Only the authenticated run owner can load the graph; missing or unauthorized runs show the standard unavailable state.
- Public share payloads and pages do not expose tool arguments, results, file paths, or the graph.

## Test Plan

- Add backend harness tests for successful, failed, blocked, shell-exit, and handler-error outcomes; duration recording; approval call IDs; recovery links; consecutive failures; and no false recovery link between calls generated in the same model response.
- Add graph-normalizer unit tests for ordering, call/result pairing, redirects, approvals, active calls without results, multiple retries, terminal errors, legacy inference, and the raw-event coverage invariant.
- Add API and hook tests for histories exceeding 200 events, paginated initial loading, incremental polling, deduplication, terminal polling shutdown, and retained data after transient errors.
- Add component tests for node colors, icons, accessible labels, recovery edges, inspector contents, mobile behavior, live updates, and graph/back navigation.
- Add an end-to-end fixture covering prompt → successful tool → failed tool → corrected retry → successful output, verified both while running and after completion.

## Assumptions

- This is an end-user-friendly view with power-user details available on selection.
- The graph covers both cloud and desktop-local agents because they share the same harness event format.
- “Went back” means the model selected a recovery action after observing a failure; it does not imply that immutable history was rewritten.
- The current conversation step list is preserved as the compact view.
- Shared execution graphs, subagent-to-parent graph composition, arbitrary DAG editing, export, and cross-run comparison are out of scope.
