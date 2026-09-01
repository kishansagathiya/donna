# Donna Desktop: Local Agent Runtime for macOS

## Summary

Build an internal macOS desktop app using **Tauri 2**, the existing React interface, and Donna’s existing Go agent harness.

The agent loop, HTTP requests, browser automation, filesystem operations, and shell commands will run on the user’s Mac. This makes external requests originate from the user’s network instead of a cloud-server IP. Donna’s cloud remains the source of truth for authentication, memory, integrations, run history, schedules, and model access.

All new agent runs will execute locally. If the assigned Mac is offline, runs remain queued until it reconnects; there is no automatic cloud fallback. Donna remains its own agent product and will not wrap Codex, Claude Code, or other agent CLIs.

## Architecture and Implementation

### 1. Desktop application and process model

- Add a Tauri desktop target to the existing `donna-web` React application rather than creating a second UI.
- The Tauri process owns authentication tokens, macOS Keychain access, updates, notifications, tray behavior, and child-process supervision.
- Bundle a new `donna-agent-local` Go sidecar built from the existing `internal/agents` harness.
- Communicate between Tauri and the Go worker through a Unix domain socket authenticated with a random per-launch secret. Do not expose a localhost control port.
- Keep the app resident in the menu bar when its window closes. Explicitly quitting Donna stops the worker; active runs return to the queue after their lease expires.
- Limit v1 to one active agent run per Mac. Additional runs remain queued in creation order.
- Produce signed and notarized universal macOS builds for Apple Silicon and Intel, distributed through an internal update channel.

### 2. Local Donna harness

Refactor the existing harness so the same orchestration code supports cloud and desktop dependencies through interfaces:

- `RunStore`: add an authenticated cloud-backed implementation for the desktop worker.
- `Completer`: add a remote implementation that calls Donna’s model gateway.
- `BrowserSession`: replace the concrete browser client dependency with an interface supporting local and remote implementations.
- Tool registry: compose tools according to the run’s execution target and selected workspace.

The desktop registry will contain:

- Existing orchestration tools: planning, user questions, approvals, skills, delegation, cancel, and redirect.
- Cloud-data tools: Donna memory, notes, skills, schedules, and integrations through authenticated Donna APIs.
- Local network tools: HTTP fetches and browser automation executed from the Mac.
- Local workspace tools: directory listing, file read, search, file creation, patching, and deletion.
- Local process tools: shell commands with working directory, timeout, output cap, environment allowlist, cancellation, and exit metadata.

The complete agent loop runs locally. For each model turn, the worker sends the transcript and tool definitions to Donna’s authenticated model gateway, receives content or tool calls, executes tools locally, and records the resulting steps.

### 3. Browser and local-network execution

- Add a supervised local Playwright browser service and retain the existing `BrowserClient` protocol.
- Bundle a compatible Chromium runtime so browser automation does not depend on the user installing development tools.
- Store a dedicated persistent browser profile under Donna’s macOS Application Support directory.
- Never attach to or read the user’s everyday Chrome profile.
- Run Chromium visibly when interactive automation starts, allowing the user to log in or take over manually.
- Persist cookies and sessions across app restarts, while keeping browser data separate from Donna cloud storage.
- Require irreversible browser actions such as purchases, sends, bookings, form submissions with external consequences, or account changes to pass through the existing approval flow.
- Execute `fetch_url` and related generic network tools in the Go sidecar so their traffic also uses the Mac’s network.
- Keep localhost, private-network, and link-local destinations blocked in v1. This release addresses public internet requests rejected because of cloud-origin traffic, not internal-network automation.

### 4. Devices, workspaces, and run routing

Add additive storage models:

- `desktop_devices`: user, device name, platform, architecture, app version, public device identifier, capabilities, last-seen time, default-device flag, and revocation time.
- `desktop_workspaces`: opaque workspace ID, device ID, user-visible name, capabilities, and last-seen time. Do not upload absolute filesystem paths.
- Extend `agent_runs` with:
  - `execution_target`: `local` or `cloud`.
  - `assigned_device_id`.
  - `workspace_id`, nullable for research-only runs.
  - `waiting_reason`: nullable values such as `device_offline`, `device_busy`, or `workspace_unavailable`.

Run behavior:

- New runs default to `execution_target=local`.
- The server assigns the user’s default non-revoked Mac.
- If no desktop device is registered, run creation returns `desktop_required` and the UI displays installation/onboarding guidance.
- If the device is offline or busy, the run remains `queued` with the appropriate `waiting_reason`.
- Cloud background workers must never claim runs whose execution target is `local`.
- The desktop worker claims runs with the existing lease and heartbeat semantics.
- If the worker disconnects or crashes, its lease expires and the run returns to the local device queue.
- Redirects, cancellation, and approval responses resume the same `agent_run_id`.
- Existing cloud runs may finish during rollout, but no local run may silently fall back to cloud execution.

Workspace paths are stored only in an encrypted local SQLite database. The cloud stores the workspace’s opaque ID and display name so web and mobile clients can target a workspace without learning its path.

### 5. Desktop control-plane APIs

Add authenticated APIs:

- `POST /desktop/devices/register`
- `POST /desktop/devices/{id}/heartbeat`
- `POST /desktop/devices/{id}/revoke`
- `GET /desktop/devices`
- `GET /desktop/workspaces`
- `PUT /desktop/devices/{id}/workspaces`
- `GET /desktop/runner` as an authenticated WebSocket
- `POST /desktop/runs/{id}/claim`
- `POST /desktop/runs/{id}/heartbeat`
- `POST /desktop/runs/{id}/steps/batch`
- `PATCH /desktop/runs/{id}/state`
- `POST /desktop/model/complete`

WebSocket events from server to desktop:

- `run.available`
- `run.cancel`
- `run.redirect`
- `run.approval_resolved`
- `device.revoked`

All mutations must validate that the authenticated user owns the run, device, and workspace and that the run is assigned to that device. Step batches are idempotent using the existing `(agent_run_id, seq)` uniqueness rule.

The model gateway must accept only requests tied to an active, assigned run. It uses Donna’s existing model configuration and credentials; model keys are never shipped in the desktop application.

### 6. Authentication and security

- Reuse the current Donna/Supabase account.
- Open OAuth in the system browser and return through a `donna://auth/callback` deep link.
- Store the refresh token in macOS Keychain through the Tauri process.
- Give the Go worker only short-lived access tokens in memory; it never receives the refresh token.
- Do not bundle the Supabase service-role key, OpenRouter key, connector encryption key, or integration credentials.
- Canonicalize every workspace path before use and reject symlink or traversal escapes.
- Shell processes must run inside the selected workspace, in their own process group, with bounded runtime and output.
- Allow reads, writes, patches, builds, and tests inside the workspace without repeated prompts.
- Require approval for destructive commands, access outside the workspace, privilege escalation, external writes, payments, sends, publishing, or account changes.
- Record commands, affected paths, exit status, duration, and approval decisions in agent steps, while redacting environment secrets and browser credentials.
- Maintain a local SQLite spool for unsynced steps. If Donna cloud becomes unavailable, finish only the current local tool operation, persist its result, pause the run, and resume after reconnection.

### 7. Product experience

Add desktop-specific UI states to the existing React app:

- Desktop onboarding and macOS permission checks.
- Device online/offline and worker-health indicator.
- Workspace manager using the native folder picker.
- Optional workspace selector in the agent composer.
- “Waiting for Mac,” “Mac busy,” and “Workspace unavailable” run states.
- Visible local-tool timeline including commands, files, browser actions, and approvals.
- Native notifications for questions, approvals, completed runs, and failed runs.
- Browser takeover control.
- Menu-bar controls for opening Donna, pausing new runs, viewing the active run, restarting the worker, and quitting.
- Diagnostics screen showing app version, worker version, device ID, cloud connection, browser state, queued runs, and redacted logs.

Web and mobile retain their existing run views. They can create, monitor, redirect, cancel, and approve local runs, but the assigned Mac performs the work.

## Delivery Sequence

1. **Local runner foundation**
   - Tauri shell, authentication bridge, Keychain storage, Go sidecar supervision, device registration, local run assignment, remote model completer, and cloud step synchronization.
   - Demonstrate a locally executed read-only agent run without browser, shell, or filesystem tools.

2. **Workspace and network tools**
   - Workspace management, filesystem boundary enforcement, shell execution, local HTTP fetches, permission policy, cancellation, and local step spool.
   - Demonstrate a repository task and confirm outbound HTTP traffic uses the Mac’s public IP.

3. **Persistent browser**
   - Bundled Playwright/Chromium service, dedicated profile, existing browser tool compatibility, visible takeover, login persistence, and approval gates.
   - Demonstrate a multi-step browser workflow across an app restart.

4. **Background reliability**
   - Menu-bar operation, scheduled runs, offline queuing, lease recovery, redirects, approvals, notifications, diagnostics, crash recovery, and automatic updates.

5. **Dogfood rollout**
   - Enable behind a per-user `local_agents_v1` flag.
   - Let existing cloud runs finish while routing new flagged runs locally.
   - After reliability gates pass, make local execution the default and disable cloud claiming for new agent runs.
   - Roll back by changing the execution default while retaining the additive device and run metadata.

## Test Plan and Acceptance Criteria

### Harness and control plane

- A desktop-created run and a web-created run both execute on the assigned Mac.
- A local run is never claimed by a cloud worker.
- An offline Mac leaves the run queued and the run starts after reconnection.
- There is no automatic cloud fallback.
- Lease expiry after a crash requeues the run without duplicating completed steps.
- Duplicate step batches do not create duplicate timeline entries.
- Redirect continues the same run with its existing transcript and plan.
- Cancel stops new tool calls and terminates an active subprocess within two seconds.
- Revoking a device prevents further claims and model requests immediately.

### Network and browser

- A diagnostic request reports the same public egress IP as the Mac.
- Generic fetch and browser traffic originate locally.
- Browser cookies survive app and worker restarts.
- Donna cannot read the user’s default Chrome profile.
- Browser navigation, snapshot, click, type, takeover, and cancellation work.
- Irreversible browser actions pause for approval before execution.
- Localhost, private IPs, metadata hosts, and unsafe redirects remain blocked.

### Filesystem and shell

- Reads and writes inside an approved workspace succeed.
- `..`, absolute-path escapes, symlink escapes, and workspace replacement are rejected.
- Destructive commands require approval.
- Commands respect timeout, output limits, working directory, cancellation, and environment redaction.
- A run without a workspace does not receive filesystem or shell tools.
- Removing a workspace while a run is queued changes it to `workspace_unavailable`.

### Authentication and secrets

- Refresh tokens are stored in Keychain, not browser local storage or SQLite.
- The Go worker never receives or persists a refresh token.
- No service-role, model-provider, connector-encryption, or OAuth client secret appears in the app bundle.
- Another local process cannot control the worker without the per-launch socket secret.
- Server APIs reject cross-user, wrong-device, expired-token, and revoked-device requests.

### Release gates

- Signed and notarized builds launch without Gatekeeper bypass instructions.
- Automatic updates verify signatures before installation.
- Worker and browser crashes surface actionable diagnostics rather than silently failing.
- A 20-minute, 40-step dogfood run survives browser use, shell commands, redirects, and an approval.
- At least 95% of the internal fixture suite completes without manual worker restart.
- Unauthorized external writes, sends, bookings, payments, or workspace escapes remain at zero.

## Assumptions and Explicit Exclusions

- V1 targets internal macOS dogfood; Windows and Linux follow after the local-run protocol stabilizes.
- Donna uses its own existing agent harness. Codex, Claude Code, generic CLI adapters, and third-party agent runtimes are out of scope.
- LLM inference continues through Donna’s cloud model gateway; on-device models and user-supplied provider keys are out of scope.
- Every agent run executes locally, but Donna memory, sync, model access, and credential-backed integrations remain cloud services.
- V1 supports one default Mac and one active run per Mac, although the schema permits multiple devices.
- General Accessibility-based control of arbitrary macOS applications is out of scope. V1 covers browser, network, approved workspaces, and shell tools.
- Private-network and localhost access are out of scope until a separate permission and SSRF policy is designed.
- The dedicated Donna browser profile is the only browser identity automated by the app.
