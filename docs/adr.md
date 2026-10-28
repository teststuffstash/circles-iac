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
**Status:** Accepted (2026-09-05). Ratifies circles ⚖-R1 (`specs/process/phases.md`
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
