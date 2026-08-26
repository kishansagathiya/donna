#!/usr/bin/env bash
# Creates required Supabase storage buckets for Donna.
# Requires SUPABASE_URL and SUPABASE_SERVICE_ROLE_KEY in environment or repo-root .env.
#
# Note: ChatGPT export ZIPs are stored on Railway Buckets (S3), not Supabase.
# See CHATGPT_IMPORT_S3_* env vars on donna-server-go.
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
if [[ -f "$ROOT/.env" ]]; then
  set -a
  # shellcheck disable=SC1091
  source "$ROOT/.env"
  set +a
fi

: "${SUPABASE_URL:?SUPABASE_URL is required}"
: "${SUPABASE_SERVICE_ROLE_KEY:?SUPABASE_SERVICE_ROLE_KEY is required}"

create_bucket() {
  local id="$1"
  local status
  local payload="{\"id\":\"$id\",\"name\":\"$id\",\"public\":false}"
  status=$(curl -s -o /tmp/bucket_resp.json -w "%{http_code}" -X POST \
    -H "apikey: $SUPABASE_SERVICE_ROLE_KEY" \
    -H "Authorization: Bearer $SUPABASE_SERVICE_ROLE_KEY" \
    -H "Content-Type: application/json" \
    -d "$payload" \
    "$SUPABASE_URL/storage/v1/bucket")
  if [[ "$status" == "200" || "$status" == "201" ]]; then
    echo "Created bucket: $id"
  elif [[ "$status" == "409" ]] || grep -q '"error":"Duplicate\|already exists\|Duplicate"' /tmp/bucket_resp.json 2>/dev/null; then
    echo "Bucket already exists: $id"
  else
    echo "Failed to create bucket $id (HTTP $status):" >&2
    cat /tmp/bucket_resp.json >&2
    echo >&2
    exit 1
  fi
}

create_bucket "conversation-audio"
create_bucket "note-audio"
create_bucket "knowledge-assets"
create_bucket "chat-attachments"
create_bucket "note-attachments"
echo "Storage buckets ready."
echo "ChatGPT imports use Railway Buckets — configure CHATGPT_IMPORT_S3_* on the server."
