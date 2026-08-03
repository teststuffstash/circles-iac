# circles/infra — app-owned infra CRs (ADR-076)

Currently empty on purpose: the agent plumbing (standing OpenRouter key, git tokens, egress
policy) is rendered by the AgentStack claim in `../agent/agentstack.yaml`, and no product infra
exists yet. This directory is the target path of the `circles` ArgoCD Application
(`apps/circles.yaml`), so it must exist even while empty.

Rules (inherited from the oracle/sleep stacks):

- **Flat directory only** — the platform's argocd-cm ignores `directory.recurse` on Application
  objects, so subdirectories here would silently not sync.
- **References, never values** — this repo is public; secrets arrive via ESO/Infisical
  references only.
