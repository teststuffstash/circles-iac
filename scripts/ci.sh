#!/usr/bin/env bash
# ci.sh — the circles-iac gate. This repo is the circles stack's deployment truth (app-of-apps +
# infra CRs + version pins), so the gate is: lint the YAML and structurally validate the manifests.
# Thin seam — the workflow just calls `devbox run ci`, so logic + tool versions live here, not in
# CI YAML. Run it locally the same way: `devbox run ci`.
#
# Skeleton stage: no chart is pinned yet, so there is no helm-template step. When the first chart
# pin lands in apps/, add the pull-then-template gate from sleep-iac scripts/ci.sh (prove the
# pinned chart renders with our values) — that check is the whole point of a pin.
set -euo pipefail

DIRS="apps circles"

echo "==> yamllint"
yamllint $DIRS

echo "==> kubeconform (raw manifests; CRDs → catalog schemas, else ignore-missing)"
# Infra CRs are CRDs (Workspace, ExternalSecret, Workflow*) + ArgoCD Applications. The CRDs
# catalog supplies real schemas for argoproj.io & friends — this repo now carries deploy truth
# for Argo Workflows (issue #41), so a malformed WorkflowTemplate must fail here, not at sync.
# -ignore-missing-schemas still covers kinds the catalog lacks (tf.upbound.io Workspace, …).
kubeconform -summary -strict -ignore-missing-schemas \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  $DIRS

# No argo-lint step yet: this repo carries no Argo Workflow manifests. Re-add the oracle-iac
# `argo lint --offline` gate together with the FIRST circles/infra/workflow-*.yaml.

echo "✓ circles-iac validation passed"
