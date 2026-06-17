#!/usr/bin/env bash
# external data source: read the FirstInstance bootstrap PAT off the Tier-0 box.
# Auth is via the operator's ssh-agent — the same key that ran the host deploy.
# DNS for the Zitadel host points at the box, so we SSH straight to the domain.
set -euo pipefail

# The external data source passes the query as one JSON object on stdin; read it
# once (a second `jq` would see EOF and yield an empty value).
input="$(cat)"
host="$(jq -r '.host' <<<"$input")"
user="$(jq -r '.user' <<<"$input")"

pat="$(ssh \
  -o StrictHostKeyChecking=accept-new \
  -o BatchMode=yes \
  -o ConnectTimeout=20 \
  -o ServerAliveInterval=5 \
  -o ServerAliveCountMax=3 \
  "${user}@${host}" \
  'cat /var/lib/zitadel/bootstrap-pat')"

jq -n --arg pat "$pat" '{pat: $pat}'
