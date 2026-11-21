#!/usr/bin/env bash
# passkey-login-link.sh — mint a one-time Pocket ID login link for a gate user (ADR-004), so a
# passkey can be enrolled without any admin clicking: open the printed link ON THE DEVICE that will
# hold the passkey, then add the passkey on the account page Pocket ID lands on. Valid 1 hour,
# single use. Re-run it to enroll another device or after losing one.
#
# Reads STATIC_API_KEY from the connection Secret circles-auth (needs `get secret` in ns circles)
# and calls the API over the LAN hostname. Prints the link to stdout — it is a credential;
# don't paste it anywhere shared.
#
#   KUBECTL="devbox run -- kubectl --kubeconfig tofu/kubeconfig" bash scripts/passkey-login-link.sh
set -euo pipefail

USER_ID="${1:-6f1c2a3e-8b4d-4c7e-9a10-2d5e7f8a9b01}"   # the seed's `operator` (pocket-id-seed.yaml)
BASE="${POCKET_ID_URL:-https://id.circles.teststuff.net}"
KUBECTL="${KUBECTL:-kubectl}"

key=$($KUBECTL -n circles get secret circles-auth -o jsonpath='{.data.static_api_key}' | base64 -d)
[ -n "$key" ] || { echo "circles-auth has no static_api_key" >&2; exit 1; }

resp=$(curl -fsS -X POST -H "X-API-Key: $key" -H 'Content-Type: application/json' \
  --data '{}' "$BASE/api/users/$USER_ID/one-time-access-token")
token=$(printf '%s' "$resp" | sed -nE 's/.*"token":"([^"]+)".*/\1/p')
[ -n "$token" ] || { echo "no token in response: $resp" >&2; exit 1; }

echo "$BASE/lc/$token"
