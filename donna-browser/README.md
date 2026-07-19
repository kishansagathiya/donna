# donna-browser

Playwright Chromium sidecar for [Donna](https://github.com/kishansagathiya/donna)’s `browse_page` chat tool.

The Go server (`donna-server-go`) calls this service when `DONNA_BROWSER_URL` is set. Without it, Donna still has `fetch_url` (plain HTTP + HTML→text).

## Run locally

```bash
npm install
npm run install-browsers
npm start
```

Listens on `http://127.0.0.1:9229` by default (`DONNA_BROWSER_HOST` / `DONNA_BROWSER_PORT`).

Point Donna’s server at it:

```bash
export DONNA_BROWSER_URL=http://127.0.0.1:9229
```

## API

| Method | Path | Body / response |
|--------|------|-----------------|
| `GET` | `/health` | `{ ok, service, active }` |
| `POST` | `/browse` | `{ url, wait_ms?, max_chars? }` → `{ url, title, text, status }` |

## Railway / production

Deploy as its own service, then set on `donna-server-go`:

```bash
DONNA_BROWSER_URL=https://your-donna-browser.up.railway.app
```

Prefer private networking between Railway services when possible. Bind with `DONNA_BROWSER_HOST=0.0.0.0` and Railway’s `PORT`.

## Related

- Monorepo: https://github.com/kishansagathiya/donna
- Server: https://github.com/kishansagathiya/donna-server-go
- Plan: `docs/improvement-plans/02-chat-browser-tool.md` in the monorepo
