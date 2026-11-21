# circles/auth — the LAN passkey gate (ADR-004)

Target path of the `circles-auth` ArgoCD Application (`apps/circles-auth.yaml`), kept apart from
`circles-infra` so a failing seed hook cannot hold up the specs-pr routes. Flat directory only.

- `auth-secrets-workspace.yaml` — every secret minted in-cluster → Secret `circles-auth`
  (rotation procedure and the encryption-key backup step are in its header).
- `pocket-id.yaml` — the passkey-only OIDC provider (SQLite on a PVC, settings from env) and the
  CiliumNetworkPolicy that admits only the gateway, oauth2-proxy and the seed.
- `httproute-id.yaml` — `id.circles.teststuff.net` → Pocket ID; blocks the first-run admin
  signup paths permanently.
- `pocket-id-seed.yaml` — Sync hook: the `operator` user, the oauth2-proxy client and its secret,
  through the API. Nothing is clicked.
- `oauth2-proxy.yaml` — the gate itself; `circles/infra/httproute-page.yaml` routes
  `app.circles.teststuff.net` to it.

Enroll a passkey: `scripts/passkey-login-link.sh` (one-time link, open it on the device).

Log out (both sessions): `https://app.circles.teststuff.net/oauth2/sign_out?rd=https://id.circles.teststuff.net/logout`
— oauth2-proxy drops its cookie, then Pocket ID's logout page ends its own session. Signing out at
`/oauth2/sign_out` alone is not a logout: Pocket ID's 24 h session lets you straight back in.
