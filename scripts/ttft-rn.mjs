#!/usr/bin/env node
/**
 * Time-to-first-token (TTFT) benchmark for the iOS / REACT-NATIVE client path.
 *
 * Measures wall-clock time from chat request send to the first `chunk` SSE
 * event, reproducing the exact request contract sent by
 * `donna-app/src/services/chatApi.ts:streamChatMessage`:
 *   POST  ${API_BASE}/chat?stream=1
 *   body  { message }                 (history/session_id/mode omitted when absent)
 *   headers Authorization, Content-Type: application/json   (NO Accept header)
 *
 * Report-only: logs each run + a summary (min / median / p95 / mean). Never
 * fails on a slow TTFT — only exits non-zero on HTTP/SSE transport errors.
 *
 * Usage:
 *   node scripts/ttft-rn.mjs
 *
 * Env:
 *   DONNA_API_BASE      default https://donna-server-go-production.up.railway.app
 *   DONNA_AUTH_TOKEN    Supabase JWT for /chat (RequireAuth is on in prod). Required for prod.
 *   DONNA_TTFT_RUNS     iteration count, default 5
 *   DONNA_TTFT_PROMPT   prompt string, default "Hello"
 *   DONNA_TTFT_MODEL    LLM model slug to benchmark (e.g. "z-ai/glm-5.2"). If set, the
 *                       script PATCHes /account to this model before running and restores
 *                       the original model afterwards. Must be in the server's allowlist.
 *
 * Each iteration starts a fresh session (no session_id) so timings aren't
 * muddied by conversation history.
 *
 * IMPORTANT CAVEAT: The iOS app streams chat over an immediate XHR SSE
 * transport (`donna-app/src/services/sseXhr.ts`). That native XHR path cannot
 * run in Node, so this script reproduces the RN client's REQUEST CONTRACT (body
 * shape + headers) using Node's global fetch + a manual SSE byte parser. It
 * measures server + network TTFT for the RN request contract. It does NOT
 * measure on-device overhead (XHR progress buffering, JS thread scheduling,
 * React state update) — only request→first parsed `chunk`.
 * For true on-device mobile TTFT, add `performance.now()` instrumentation in
 * `donna-app/src/services/chatApi.ts` (the `chunk` event listener) and capture
 * from device logs.
 */

const apiBase =
  process.env.DONNA_API_BASE ??
  'https://donna-server-go-production.up.railway.app';
const token = process.env.DONNA_AUTH_TOKEN ?? '';
const runs = Number(process.env.DONNA_TTFT_RUNS ?? 5);
const prompt = process.env.DONNA_TTFT_PROMPT ?? 'Hello';
const model = process.env.DONNA_TTFT_MODEL ?? '';

async function setModel(token, m) {
  const res = await fetch(`${apiBase}/account`, {
    method: 'PATCH',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({ llm_model: m }),
  });
  if (!res.ok) {
    let detail = '';
    try { const b = await res.json(); detail = b.error ?? b.message ?? ''; } catch {}
    throw new Error(`PATCH /account ${res.status}${detail ? `: ${detail}` : ''}`);
  }
}

async function getModel(token) {
  const res = await fetch(`${apiBase}/account`, {
    headers: { Authorization: `Bearer ${token}` },
  });
  if (!res.ok) throw new Error(`GET /account ${res.status}`);
  const body = await res.json();
  return body.llm_model ?? '';
}

function summarize(values) {
  const sorted = [...values].sort((a, b) => a - b);
  const min = sorted[0];
  const max = sorted[sorted.length - 1];
  const median = sorted[Math.floor(sorted.length / 2)];
  const p95Index = Math.min(sorted.length - 1, Math.ceil(sorted.length * 0.95) - 1);
  const p95 = sorted[p95Index];
  const mean = sorted.reduce((sum, v) => sum + v, 0) / sorted.length;
  return { min, median, p95, mean, max };
}

async function runOnce() {
  const t0 = performance.now();

  // RN buildBody omits history/session_id/mode when absent — body is just { message }.
  // RN does NOT send an Accept header from chatApi (the XHR transport adds Accept itself).
  const res = await fetch(`${apiBase}/chat?stream=1`, {
    method: 'POST',
    headers: {
      Authorization: `Bearer ${token}`,
      'Content-Type': 'application/json',
    },
    body: JSON.stringify({
      message: prompt,
    }),
  });

  if (!res.ok) {
    let detail = '';
    try {
      const body = await res.json();
      detail = body.message ?? body.error ?? '';
    } catch {
      // ignore json parse failure
    }
    throw new Error(`HTTP ${res.status} ${res.statusText}${detail ? `: ${detail}` : ''}`);
  }

  if (!res.body) {
    throw new Error('Streaming not supported (no response body)');
  }

  const reader = res.body.getReader();
  const decoder = new TextDecoder();
  let buffer = '';
  let firstChunkAt = null;
  let sessionId = '';
  let reply = '';
  let streamError = null;
  let serverTimings = null;

  while (true) {
    const { done, value } = await reader.read();
    if (done) break;

    buffer += decoder.decode(value, { stream: true });
    const parts = buffer.split('\n\n');
    buffer = parts.pop() ?? '';

    for (const part of parts) {
      if (!part.trim()) continue;

      let event = 'message';
      let data = '';

      for (const line of part.split('\n')) {
        if (line.startsWith('event: ')) {
          event = line.slice(7);
        } else if (line.startsWith('data: ')) {
          data = line.slice(6);
        }
      }

      if (!data) continue;

      try {
        const parsed = JSON.parse(data);

        switch (event) {
          case 'session':
            if (parsed.session_id) sessionId = parsed.session_id;
            break;
          case 'chunk':
            // RN's chunk handler overwrites latestReply with each chunk's text
            // (data.text), so we mirror that: keep the latest text, not an append.
            if (parsed.text) {
              if (firstChunkAt === null) firstChunkAt = performance.now();
              reply = parsed.text;
            }
            break;
          case 'done':
            if (parsed.reply) reply = parsed.reply;
            if (parsed.session_id) sessionId = parsed.session_id;
            if (parsed.timings && typeof parsed.timings === 'object') {
              serverTimings = parsed.timings;
            }
            break;
          case 'error':
            streamError = parsed.message ?? 'Chat failed';
            break;
        }
      } catch {
        // ignore malformed SSE frames (matches RN client behavior)
      }
    }
  }

  if (streamError) {
    throw new Error(`SSE error event: ${streamError}`);
  }

  if (firstChunkAt === null) {
    throw new Error('No chunk event received before stream end');
  }

  return { ttft: firstChunkAt - t0, reply, sessionId, serverTimings };
}

function formatServerTimings(timings) {
  if (!timings) return '';
  const parts = [];
  for (const [label, key] of [
    ['pre-LLM', 'preLlmMs'],
    ['augment', 'augmentMs'],
    ['prefs', 'preferencesMs'],
    ['LLM-first', 'llmFirstTokenMs'],
  ]) {
    if (Number.isFinite(timings[key])) parts.push(`${label}=${timings[key]}ms`);
  }
  return parts.length ? `  server(${parts.join(', ')})` : '';
}

async function main() {
  if (!token && apiBase.includes('railway.app')) {
    console.error(
      'DONNA_AUTH_TOKEN is required to hit Railway prod (RequireAuth is on).',
    );
    console.error('Set DONNA_API_BASE=http://localhost:8787 for a local server with REQUIRE_AUTH=false.');
    process.exit(2);
  }

  console.log(`[rn]  target: ${apiBase}`);
  console.log(
    `[rn]  prompt: "${prompt}"  runs: ${runs}  model: ${model || '(server default)'}`,
  );
  console.log('');

  let originalModel = null;
  if (model) {
    originalModel = await getModel(token);
    console.log(`[rn]  switching model: ${originalModel} → ${model}`);
    await setModel(token, model);
  }

  let ttfts;
  let serverSamples;
  try {
    ttfts = [];
    serverSamples = {
      preLlmMs: [],
      augmentMs: [],
      preferencesMs: [],
      llmFirstTokenMs: [],
    };
    for (let i = 1; i <= runs; i++) {
      try {
        const { ttft, reply, serverTimings } = await runOnce();
        ttfts.push(ttft);
        for (const key of Object.keys(serverSamples)) {
          if (Number.isFinite(serverTimings?.[key])) {
            serverSamples[key].push(serverTimings[key]);
          }
        }
        console.log(
          `[rn]  run ${i}/${runs}  TTFT = ${Math.round(ttft)} ms` +
            formatServerTimings(serverTimings) +
            `  (reply: ${JSON.stringify(reply.slice(0, 60))}${reply.length > 60 ? '…' : ''})`,
        );
      } catch (err) {
        console.error(`[rn]  run ${i}/${runs} FAILED: ${err.message}`);
        throw err;
      }
    }
  } finally {
    if (originalModel !== null) {
      try {
        console.log(`[rn]  restoring model: ${model} → ${originalModel}`);
        await setModel(token, originalModel);
      } catch (err) {
        console.error(`[rn]  FAILED to restore model: ${err.message}`);
      }
    }
  }

  const s = summarize(ttfts);
  console.log('');
  console.log(
    `[rn]  summary  min=${Math.round(s.min)}  median=${Math.round(s.median)}  ` +
      `p95=${Math.round(s.p95)}  mean=${Math.round(s.mean)}  max=${Math.round(s.max)} ms`,
  );
  const serverSummary = Object.entries(serverSamples)
    .filter(([, values]) => values.length > 0)
    .map(([key, values]) => {
      const span = summarize(values);
      return `${key}: median=${Math.round(span.median)} p95=${Math.round(span.p95)}ms`;
    });
  if (serverSummary.length > 0) {
    console.log(`[rn]  server   ${serverSummary.join('  ')}`);
  }
}

main().catch((err) => {
  console.error(err.message ?? err);
  process.exit(1);
});
