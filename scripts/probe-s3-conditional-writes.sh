#!/usr/bin/env bash
# Probe whether the S3 endpoint supports `If-None-Match: *` on PutObject.
# Hetzner Object Storage's docs are silent on this; the answer determines
# whether tofu's `use_lockfile = true` works or we fall back to CI concurrency.
#
# Required env:
#   S3_ENDPOINT             e.g. https://fsn1.your-objectstorage.com
#   S3_BUCKET               e.g. luuk-infra-state
#   AWS_ACCESS_KEY_ID
#   AWS_SECRET_ACCESS_KEY
# Optional:
#   S3_REGION               default: fsn1
#
# Exit codes:
#   0 = supported (second PUT was rejected with 412 PreconditionFailed)
#   1 = NOT supported (second PUT silently overwrote the first)
#   2 = test inconclusive (couldn't reach endpoint, credentials wrong, etc.)

set -euo pipefail

: "${S3_ENDPOINT:?Set S3_ENDPOINT}"
: "${S3_BUCKET:?Set S3_BUCKET}"
: "${AWS_ACCESS_KEY_ID:?Set AWS_ACCESS_KEY_ID}"
: "${AWS_SECRET_ACCESS_KEY:?Set AWS_SECRET_ACCESS_KEY}"
S3_REGION="${S3_REGION:-fsn1}"

KEY="_cond_write_probe_$$_$RANDOM"
EMPTY="$(mktemp)"

s3() {
  command aws --endpoint-url "$S3_ENDPOINT" --region "$S3_REGION" "$@"
}

cleanup() {
  s3 s3api delete-object --bucket "$S3_BUCKET" --key "$KEY" >/dev/null 2>&1 || true
  rm -f "$EMPTY"
  # DEBUG_LOG intentionally kept — small, useful for follow-up if rc != 0/1.
}
trap cleanup EXIT

echo "==> probe bucket=$S3_BUCKET endpoint=$S3_ENDPOINT key=$KEY"

echo "==> first PUT with If-None-Match: *  (must succeed: object doesn't exist)"
if ! s3 s3api put-object \
       --bucket "$S3_BUCKET" --key "$KEY" \
       --if-none-match '*' \
       --body "$EMPTY" >/dev/null 2>err; then
  echo "    FAIL: first PUT rejected — not a conditional-write outcome, fix prereqs first"
  cat err
  exit 2
fi
echo "    OK"

echo "==> second PUT with If-None-Match: *  (should fail 412 iff supported)"
DEBUG_LOG="$(mktemp)"
set +e
s3 --debug s3api put-object \
   --bucket "$S3_BUCKET" --key "$KEY" \
   --if-none-match '*' \
   --body "$EMPTY" >"$DEBUG_LOG" 2>&1
rc=$?

# aws-cli's --debug log includes a botocore line like
#   '... botocore.httpsession - DEBUG - Response code: 412'
# but real-world output varies a bit; fall back to grepping for any obvious
# HTTP status pattern. set -e stays off so a missing match doesn't kill us.
status=$(grep -oE "[Rr]esponse code: '?[0-9]+" "$DEBUG_LOG" \
           | head -1 | grep -oE "[0-9]+")
if [ -z "$status" ]; then
  # urllib3's connectionpool log line: '... "PUT /path HTTP/1.1" 412 262'
  status=$(grep -oE 'HTTP/[12]\.[01]" [0-9]+' "$DEBUG_LOG" \
             | head -1 | awk '{print $2}')
fi
if [ -z "$status" ] && grep -q "PreconditionFailed" "$DEBUG_LOG"; then
  status=412
fi
status=${status:-unknown}
set -e

case "$status" in
  412)
    cat <<EOF
    HTTP 412 PreconditionFailed

  result: SUPPORTED
    Flip use_lockfile = true in tofu/host/backend.tf and
    tofu/netbird-account/backend.tf. The CI concurrency group can stay as
    belt-and-suspenders or be dropped.
EOF
    exit 0
    ;;
  200)
    cat <<EOF
    HTTP 200 — endpoint overwrote without checking the condition

  result: NOT SUPPORTED
    Leave use_lockfile off; keep the GitHub Actions concurrency group as the
    apply-serialization mechanism. Same setup as Garage.
EOF
    exit 1
    ;;
  unknown)
    echo "    couldn't parse HTTP status from aws --debug output"
    echo "    full debug log saved to: $DEBUG_LOG"
    echo "    (search for 'Response code', 'StatusCode', or '412' / '200' in it)"
    exit 2
    ;;
  *)
    echo "    HTTP $status — unexpected, neither 412 nor 200"
    echo "    full debug log saved to: $DEBUG_LOG"
    exit 2
    ;;
esac
