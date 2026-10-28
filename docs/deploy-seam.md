# The deploy seam — how a real person's page reaches nginx (design for ADR-001)

> Mechanism behind [`adr.md`](adr.md) ADR-001. The contract it satisfies is circles
> `specs/process/phases.md` §CIR-PROC-DEPLOY-SEAM (five testable rows) and §CIR-PROC-PHASE-P1
> (the nightly bake). Product behaviour (what the bake computes, what the page shows) is the
> circles spec tree — this page only says where things run and how bytes move.

**Precedent copied:** sleep-iac `snore-recorder/` — an in-cluster Job/CronJob with its inputs
from a ConfigMap and its credential from an ESO `ExternalSecret`, nothing baked into an image
(homelab ROADMAP "snore-recorder" row, built 2026-08-02). Secrets doctrine: homelab
`docs/secrets.md` §Day-2 (Infisical → ESO → a native Secret in the stack namespace).

## The picture

```
Forgejo (LAN)  private repo: <circles.yaml + notes/…>        Infisical (homelab/prod)
      │  clone, read-only token                                     │  ESO
      ▼                                                             ▼
CronJob circles-bake  (ns circles, nightly, podAffinity → page pod's node)
  init: alpine/git  clone → /src (emptyDir)          Secret circles-source-git (token)
  main: ghcr.io/teststuffstash/circles-bake:<tag>
        python -m bake --config /src/<path>/circles.yaml --out /content --evaluate \
                       --stale-after-hours 36
        (validates, evaluates freshness:/command:, writes data.json + index.html atomically)
      │  PVC circles-content (longhorn, RWO, 1 Gi) — mounted RW at /content
      ▼
Deployment circles-page (the chart)  — PVC mounted RO over /usr/share/nginx/html
      │  Service circles-page:80 → HTTPRoute app.circles.teststuff.net (LAN only, ADR-002)
      ▼
the page
```

Two files, two atomic renames: the bake writes `data.json` then `index.html`, each via
temp-file + `os.replace` in the target directory (`CIR-BAKE-ATOMIC-WRITE`). Between the two
renames a reader can observe a new `data.json` beside the old `index.html` for milliseconds;
the page inlines its data, so no served page is ever internally inconsistent. If that window
ever matters, the escape hatch is a release directory + symlink swap (needs the nginx root to
follow a symlink — a chart-owned nginx.conf, not a Dockerfile change).

## Who owns what

| Piece | Owner | Where |
|---|---|---|
| `content.mode: image\|volume`, `content.claimName`, `content.storage`, `bake.*` values + schema | circles chart | `chart/values.schema.json`, `chart/templates/{pvc,cronjob,deployment}.yaml` |
| the `circles-bake` image (Dockerfile stage 1 published at the same tag as the page image) | circles `deploy.yaml` / `scripts/build-image.sh` (`--target bake`) | ghcr `teststuffstash/circles-bake:<calver-gsha>` |
| the bake flags `--evaluate`, `--stale-after-hours` | circles bake (issue #33) | `bake/__main__.py` |
| the values overlay that turns the seam on | **this repo** | `values/circles.yaml` |
| `ExternalSecret circles-source-git` (Forgejo read token for the private repo; repo URL is a secret value too — the repo is never named in public YAML) | **this repo** | `circles/infra/externalsecret-source-git.yaml` (flat dir rule — see `circles/infra/README.md`) |
| the Infisical values `CIRCLES_SOURCE_REPO_URL`, `CIRCLES_SOURCE_REPO_TOKEN` | operator, by hand (`devbox run infisical-secret` in homelab) | Infisical `homelab/prod` |
| the private repo itself (`circles.yaml` + `notes/`, ISO dates, trusted input — `CIR-ADAPT-COMMAND` says the config runs with the bake's identity) | operator | Forgejo, private |
| exposure beyond the LAN | ADR-002 (Open) | homelab PublicRoute claim, mTLS shape |

## Values the overlay will set (the shape, so the chart chunk and this repo agree)

```yaml
content:
  mode: volume            # image (default: the fixture page baked into the image) | volume
  claimName: circles-content
  storage: 1Gi            # storageClassName longhorn — the ns quota allows 5Gi (agentstack-storage)
bake:
  enabled: true           # renders the CronJob (+ the PVC when content.mode=volume)
  schedule: "17 1 * * *"  # 03:17/04:17 Europe/Tallinn — after the notes' usual last edit
  staleAfterHours: 36     # → data.json stale_after_hours (CIR-BAKE-STALE-SELF ⚖-R15)
  configPath: circles.yaml            # path inside the cloned repo
  sourceSecretName: circles-source-git  # keys: url, token (ESO-rendered)
  image: { repository: ghcr.io/teststuffstash/circles-bake }  # tag = chart appVersion
```

Pod shape the chart renders for the CronJob: `concurrencyPolicy: Forbid`, `backoffLimit: 2`,
`ttlSecondsAfterFinished: 3600`, history 1/3, `automountServiceAccountToken: false`,
`runAsUser: 101` + `fsGroup: 101` (nginx-unprivileged's uid, so the files it writes are the
page pod's own), `activeDeadlineSeconds: 600` (the spec's 5-minute bake budget plus the clone),
required `podAffinity` on `app.kubernetes.io/name=circles` with `topologyKey:
kubernetes.io/hostname` (RWO volume, one node), the ESO Secret mounted read-only, the PVC at
`/content`, an `alpine/git` init container cloning `--depth 1` with the token via
`GIT_ASKPASS`/netrc — never in the URL.

## Rollout order (each step is independently green)

1. **circles bake** — `--evaluate` (freshness: issue #33 slice A, in flight 2026-09-05; command:
   slice B) and `--stale-after-hours N` (writes `stale_after_hours` into the artifact).
2. **circles chart** — the `content.*` / `bake.*` seam: PVC + CronJob templates, deployment
   volume mount, `values.schema.json`, helm-unittest cases for both modes, `build-image.sh`
   publishing the bake stage. `devbox run test-system` must still pass in `content.mode: image`
   (the default) — the kind gate is the proof the seam changed nothing for the fixture path.
3. **this repo** — ADR-001 (this), `externalsecret-source-git.yaml`, the overlay above with
   `content.mode: image` and `bake.enabled: true` FIRST (the CronJob bakes onto the PVC while the
   page still serves the fixture — a dry run visible in the job log), then `content.mode: volume`
   once ADR-002 is accepted.
4. **e2e** — `CIR-PROC-PHASE-P1#p1-new-data-no-redeploy`: edit a note in the private repo, wait
   for the next run (or `kubectl create job --from=cronjob/circles-bake`), the served stamp and
   status move, the image tag does not.

## Gaps and verifications still open

- **Egress from the bake pod to Forgejo** — the `circles` namespace carries no NetworkPolicy
  today (checked 2026-09-05: `kubectl -n circles get networkpolicy` is empty), so the clone
  works; if the AgentStack claim later adds a default-deny, the CronJob needs an egress rule to
  `192.168.40.15:3000`/`:443`. Verify at step 3 with the job log, not by assumption.
- **`CIR-ADAPT-BUDGET#environment-not-inherited-wholesale`** — the CronJob's env holds nothing
  secret (the token is a mounted file the init container consumes), and the bake passes a
  minimal env to `command:` scripts; both halves must be true, the chart half is checked by a
  helm-unittest case asserting the bake container has no `env` referencing the Secret.
- **Longhorn RWO + podAffinity** is the one operational coupling: if the page pod moves nodes
  while a bake runs, the job fails (volume attached elsewhere) and retries on the next schedule —
  acceptable for a nightly; the stale banner (`stale_after_hours: 36`) is the belt.
- **The kind gate does not exercise `content.mode: volume`** — a second `helm upgrade` with
  `content.mode=volume` + a one-shot Job from the CronJob template inside `test-system.sh`
  would evidence `#real-content-enters-at-deploy-time` in the system tier. Deferred until the
  chart chunk lands; tracked on circles #33.
