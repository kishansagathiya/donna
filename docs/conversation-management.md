# Conversation management

Donna conversations support search, rename, archive, pin, tags, and LLM titles.

## Deletion model

- **Archive** (`PATCH` with `archived: true`) is soft-hide: archived chats leave the default list and appear under the Archived filter. Unarchive restores them.
- **Delete** (`DELETE /conversations/{id}`) is **hard delete**: the conversation row is removed; turns and tags cascade. This cannot be undone.

## Title provenance (`title_source`)

| Value | Meaning |
|-------|---------|
| `auto` | Truncated first-turn placeholder |
| `llm` | Async LLM-generated title after the first turn |
| `user` | Manual rename — never overwritten by LLM generation |

## API surface

- `GET /conversations?q=&tag=&include_archived=&archived_only=&limit=`
- `GET /conversations/tags`
- `GET /conversations/{id}`
- `PATCH /conversations/{id}` — `{ title?, archived?, pinned?, tags? }`
- `DELETE /conversations/{id}` — hard delete
