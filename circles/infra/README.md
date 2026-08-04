# circles/infra — app-owned infra CRs (ADR-076)

The agent plumbing (standing OpenRouter key, git tokens, egress policy) is rendered by the
AgentStack claim in `../agent/agentstack.yaml` — not carried here. This directory is the target
path of the `circles-infra` ArgoCD Application (`apps/circles.yaml`).

Current contents — the **spec-publishing lane** (ADR-092, sleep-iac#22 shape, oracle as
reference implementation):

- `gateway.yaml` — the stack's L7 gateway on LB VIP `192.168.40.28` (homelab wired the
  `*.circles.teststuff.net` wildcard → HAProxy `3.28` half on 2026-08-04).
- `httproute-specs.yaml` — `specs.circles.teststuff.net` → the `circles-specs` Garage bucket.
- `specs-workspace.yaml` — the bucket + writer/reader keys (connection Secret
  `circles-specs-s3`; the writer pair reaches circles CI as GitHub secrets, set by operator).
- `specs-pr-<N>.yaml` — MACHINE-MANAGED per-PR preview routes
  (`specs-<N>.circles.teststuff.net`), opened/removed by circles
  `.github/workflows/specs-pr-site.yaml` via `scripts/specs-pr-route.sh`. Don't hand-edit.

Rules (inherited from the oracle/sleep stacks):

- **Flat directory only** — the platform's argocd-cm ignores `directory.recurse` on Application
  objects, so subdirectories here would silently not sync.
- **References, never values** — this repo is public; secrets arrive via ESO/Infisical
  references only.
