# circles-iac — Architecture Decision Record

The decision log for the **circles stack's deployment truth** — what this repo, the circles
chart, and the platform each own when a real person's page is deployed. Same format and rules
as homelab `docs/adr.md` (one decision per block, ≤~20 lines, design goes to a doc under
`docs/` and the block links to it; accepted blocks are immutable in substance — a moved decision
is a new block with `Superseded-by`). Numbering is local to this repo: cite as
**circles-iac ADR-nnn** outside it (homelab has its own ADR-nnn series).

Product decisions (what the page is, what the bake computes) live in the circles repo's spec
tree (`specs/open-questions.md`, the ⚖ register) — never here. This log holds only what the
spec explicitly defers "next door": deploy-time mechanism, exposure, credentials.

---

### ADR-001 — The deploy seam: an in-cluster bake CronJob publishes a real person's page to a volume the page pod serves
**Status:** Accepted (2026-09-05). **Input source superseded by ADR-003** (2026-11-14): the
CronJob no longer clones the notes repo; everything else below stands. Ratifies circles ⚖-R1 (`specs/process/phases.md`
§CIR-PROC-DEPLOY-SEAM), which recommends this shape and defers the decision here.
**Decision:** real content enters at deploy time through **three chart values and two secrets**:
the circles chart grows a `content.mode: image|volume` seam (a PVC mounted read-only over the
nginx root when `volume`) and a `bake.*` block (a CronJob in the `circles` namespace running the
same `python -m bake --evaluate` code path as the image build, from a `circles-bake` image
published at the same tag). The CronJob clones the operator's **private notes repo** (an
ESO-delivered token; the repo lives on the platform's Forgejo, never on GitHub, never named in
public YAML) and publishes `data.json` + `index.html` with per-file atomic renames onto a 1 Gi
`longhorn` RWO PVC that the page pod mounts; a `podAffinity` pins the job to the page pod's node.
circles-iac holds ONLY the values overlay and the ExternalSecrets — references, never values.
Design, resource list, rollout order and gaps: [`deploy-seam.md`](deploy-seam.md).
**Considered:** (b) bake commits the artifact back to git and the deploy pipeline redeploys —
couples a data refresh to a full deploy and puts a git-write token in the nightly path; (c) bake
to object storage, page fetches — breaks the single-origin rule (⚖-R4, `CIR-RENDER-NO-EGRESS`);
a bake **sidecar** with an emptyDir — loses the last-good artifact on every pod restart, so a
failed bake at restart would serve the fixture (the dangerous placeholder), while a PVC keeps
`CIR-BAKE-ATOMIC-WRITE#failed-bake-keeps-last-good` true across restarts; RWX storage — Longhorn
RWX is not enabled on the platform (SERVICES.md lists no RWX class), and node affinity costs
nothing for a single-replica static page.
**Consequences:** the chart is still the deployable unit (the seam is `values.schema.json`-
authoritative, `CIR-PROC-DEPLOY-SEAM#chart-declares-the-seam`); the image is NEVER rebuilt with
real data; a data refresh is a CronJob run, not an image tag (`#publish-without-rebuild-is-
testable`); the page stays LAN-only until exposure is decided separately (ADR-002, Open).

### ADR-002 — Exposure: who may see `app.circles.teststuff.net`
**Status:** Open (2026-09-05). Today the hostname resolves only on the LAN (HAProxy wildcard →
the stack gateway VIP, homelab ADR-092). Going public is a homelab **PublicRoute** claim
(`docs/cloudflare.md`, ADR-124) and, because the page carries real personal status, must ride
the **mTLS-enforced** shape `ha.teststuff.net` proved (client certificate in the handshake, WAF
rule blocks without it) — never an open consumer-profile route. **This block must be Accepted
before `content.mode: volume` is enabled in `values/circles.yaml`**; until then the deployment
serves the fixture person only.

### ADR-003 — Real content is pushed: the notes repo publishes a whitelisted export; the cluster never reads the repo
**Status:** Accepted (2026-11-14, operator). Supersedes ADR-001's input source only (the clone).
**Decision:** the operator's private notes repo (Forgejo) **publishes** what circles needs: its own
Forgejo Actions workflow copies an explicit file whitelist (the person's `circles.yaml` + exactly
the notes it references, relative paths preserved) and `rclone sync`s it into the Garage bucket
`circles-source` (`circles/infra/source-workspace.yaml`). The bake CronJob reads that bucket with
a read-only key instead of cloning. The notes repo holds the writer key; the cluster holds no
credential for the notes repo at all. Output side (PVC, atomic writes, page pod) is ADR-001
unchanged.
**Considered:** the ADR-001 clone with a read-only Forgejo token — the repo also holds medical
and other documents unrelated to circles, and a read token exposes all of it to a pod in this
namespace; a separate small data repo still cloned — splits the operator's notes for a
transport concern and keeps a cluster-side repo credential; publishing the rendered page from
the notes repo's CI — puts the bake (and `command:` adapters that need cluster reach) outside
the released, tested image.
**Consequences:** the whitelist in the notes repo is the privacy boundary and the bucket is its
audit point (`rclone ls circles-source:`); the circles chart's bake init container moves from
git clone to an S3 copy (reader key from Secret `circles-source-s3`); a publish that breaks the
config fails the bake, which keeps the last good page (ADR-001). `docs/deploy-seam.md` follows.

