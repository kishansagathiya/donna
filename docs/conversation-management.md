# Conversation management

Donna conversations support search, rename, archive, pin, tags, LLM titles, and public share links.

## Deletion model

- **Archive** (`PATCH` with `archived: true`) is soft-hide: archived chats leave the default list and appear under the Archived filter. Unarchive restores them.
- **Delete** (`DELETE /conversations/{id}`) is **hard delete**: the conversation row is removed; turns, tags, and share links cascade. This cannot be undone.

## Title provenance (`title_source`)

| Value | Meaning |
|-------|---------|
| `auto` | Truncated first-turn placeholder |
| `llm` | Async LLM-generated title after the first turn |
| `user` | Manual rename — never overwritten by LLM generation |

## Sharing

- `POST /conversations/{id}/share` creates (or returns) an active share link. Response: `{ url, token, created_at }`.
- `GET /conversations/{id}/share` returns the active share if one exists (404 otherwise).
- `DELETE /conversations/{id}/share` revokes the active share.
- `GET /share/{token}` is **public** (no JWT) and returns a safe snapshot: title, channel, and turns (user/assistant text + attachments). Grounded transcripts and session IDs are omitted.
- Share URLs point at `{DONNA_WEB_APP_BASE}/share/{token}` (default `https://donnadoesit.com`).
- At most one active share per conversation; revoke then create again for a new token.

## API surface

- `GET /conversations?q=&tag=&include_archived=&archived_only=&limit=`
- `GET /conversations/tags`
- `GET /conversations/{id}`
- `PATCH /conversations/{id}` — `{ title?, archived?, pinned?, tags? }`
- `DELETE /conversations/{id}` — hard delete
- `POST /conversations/{id}/share` / `GET` / `DELETE`
- `GET /share/{token}` — public read
