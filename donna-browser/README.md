# donna-browser

Playwright Chromium sidecar for Donna’s `browse_page` chat tool.

## Run locally

```bash
cd donna-browser
npm install
npm run install-browsers
npm start
```

Listens on `http://127.0.0.1:9229` by default.

Point the Go server at it:

```bash
export DONNA_BROWSER_URL=http://127.0.0.1:9229
```

Without `DONNA_BROWSER_URL`, Donna still exposes `fetch_url` (HTTP + HTML→text) but not `browse_page`.

## API

- `GET /health` → `{ ok, service, active }`
- `POST /browse` `{ url, wait_ms?, max_chars? }` → `{ url, title, text, status }`
