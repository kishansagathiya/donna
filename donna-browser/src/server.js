import http from "node:http";
import { chromium } from "playwright";

// Prefer platform PORT (Railway/Heroku); DONNA_BROWSER_PORT for local overrides.
const PORT = Number(process.env.PORT || process.env.DONNA_BROWSER_PORT || 9229);
const HOST = process.env.DONNA_BROWSER_HOST || (process.env.PORT ? "0.0.0.0" : "127.0.0.1");
const MAX_CONCURRENCY = Number(process.env.DONNA_BROWSER_CONCURRENCY || 2);
const NAV_TIMEOUT_MS = Number(process.env.DONNA_BROWSER_NAV_TIMEOUT_MS || 20_000);

let browserPromise = null;
let active = 0;

async function getBrowser() {
  if (!browserPromise) {
    browserPromise = chromium.launch({
      headless: true,
      args: ["--disable-dev-shm-usage", "--no-sandbox"],
    });
  }
  return browserPromise;
}

function clampText(text, maxChars) {
  const trimmed = String(text || "").trim();
  if (!maxChars || trimmed.length <= maxChars) return trimmed;
  return `${trimmed.slice(0, maxChars)}\n\n[truncated]`;
}

async function browsePage({ url, wait_ms: waitMs = 0, max_chars: maxChars = 16_000 }) {
  if (active >= MAX_CONCURRENCY) {
    const err = new Error("browser concurrency limit reached");
    err.status = 429;
    throw err;
  }
  active += 1;
  const browser = await getBrowser();
  const context = await browser.newContext({
    userAgent: "DonnaBrowser/1.0 (+https://github.com/kishansagathiya/donna)",
    javaScriptEnabled: true,
  });
  const page = await context.newPage();
  try {
    const response = await page.goto(url, {
      waitUntil: "domcontentloaded",
      timeout: NAV_TIMEOUT_MS,
    });
    const pauseMs = waitMs > 0 ? Math.min(waitMs, 10_000) : 500;
    await new Promise((resolve) => setTimeout(resolve, pauseMs));

    const extracted = await page.evaluate(() => {
      const article =
        document.querySelector("article") ||
        document.querySelector("main") ||
        document.body;
      const text = (article?.innerText || "").replace(/\n{3,}/g, "\n\n").trim();
      return {
        title: document.title || "",
        text,
      };
    });

    return {
      url: page.url(),
      title: extracted.title,
      text: clampText(extracted.text, maxChars),
      status: response?.status() ?? 0,
    };
  } finally {
    await context.close().catch(() => {});
    active -= 1;
  }
}

function sendJSON(res, status, body) {
  const payload = JSON.stringify(body);
  res.writeHead(status, {
    "Content-Type": "application/json",
    "Content-Length": Buffer.byteLength(payload),
  });
  res.end(payload);
}

const server = http.createServer(async (req, res) => {
  if (req.method === "GET" && req.url === "/health") {
    sendJSON(res, 200, { ok: true, service: "donna-browser", active });
    return;
  }

  if (req.method === "POST" && req.url === "/browse") {
    let raw = "";
    for await (const chunk of req) {
      raw += chunk;
      if (raw.length > 100_000) {
        sendJSON(res, 413, { error: "request too large" });
        return;
      }
    }
    let body;
    try {
      body = JSON.parse(raw || "{}");
    } catch {
      sendJSON(res, 400, { error: "invalid json" });
      return;
    }
    if (!body.url || typeof body.url !== "string") {
      sendJSON(res, 400, { error: "url is required" });
      return;
    }
    try {
      const result = await browsePage(body);
      sendJSON(res, 200, result);
    } catch (err) {
      const status = err?.status || 500;
      sendJSON(res, status, { error: err?.message || "browse failed" });
    }
    return;
  }

  sendJSON(res, 404, { error: "not found" });
});

server.listen(PORT, HOST, () => {
  console.log(`[donna-browser] listening on http://${HOST}:${PORT}`);
});

async function shutdown() {
  try {
    if (browserPromise) {
      const browser = await browserPromise;
      await browser.close();
    }
  } finally {
    process.exit(0);
  }
}

process.on("SIGINT", shutdown);
process.on("SIGTERM", shutdown);
