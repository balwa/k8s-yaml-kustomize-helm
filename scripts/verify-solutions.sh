#!/usr/bin/env bash
# Instructor check: every reference solution renders and passes server-side validation,
# and every Lab 0 "broken" file really is broken.
#
# Needs kubectl + helm and a reachable cluster. It creates (and deletes) one throwaway
# namespace, and every apply is --dry-run=server, so nothing else is changed.
set -uo pipefail

ROOT=$(cd "$(dirname "$0")/.." && pwd)
SOL=$ROOT/solutions
NS=workshop-verify
fail=0

pass() { printf '  [PASS] %s\n' "$1"; }
flunk() { printf '  [FAIL] %s\n' "$1"; fail=1; }

# Server-side dry run of YAML on stdin into $NS. Hard-coded namespaces and fixed nodePorts
# are removed first, because a dry run still fails when a nodePort is already in use, so
# without this the check would fail on a cluster where students already deployed the labs.
dry_run() { sed -E '/^  namespace: /d; /^ +nodePort: /d; s/^( *)- nodePort: [0-9]+$/\1-/' | kubectl apply --dry-run=server -n "$NS" -f - >/dev/null; }
# Join every YAML file in a directory into one multi-document stream.
cat_dir() { for f in "$1"/*.yaml; do echo '---'; cat "$f"; done; }

kubectl create namespace "$NS" >/dev/null 2>&1 || true
trap 'kubectl delete namespace "$NS" --wait=false >/dev/null 2>&1' EXIT

echo "Lab 0: broken files must FAIL, fixed files must PASS"
for f in "$ROOT"/lab-0-yaml-is-just-data/broken/*.yaml; do
  name=$(basename "$f")
  if kubectl apply --dry-run=server -n "$NS" -f "$f" >/dev/null 2>&1; then
    flunk "broken/$name was accepted (it should be rejected)"
  else
    pass "broken/$name is rejected"
  fi
  if kubectl apply --dry-run=server -n "$NS" -f "$SOL/lab-0/$name" >/dev/null 2>&1; then
    pass "solutions/lab-0/$name is accepted"
  else
    flunk "solutions/lab-0/$name was rejected"
  fi
done

echo "Lab 1 + Lab 2: plain manifests"
for d in lab-1 lab-2/dev lab-2/prod; do
  if cat_dir "$SOL/$d" | dry_run; then
    pass "solutions/$d"
  else
    flunk "solutions/$d"
  fi
done
if cat_dir "$ROOT/lab-2-the-copy-paste-problem/app" | dry_run; then
  pass "lab-2 starter app"
else
  flunk "lab-2 starter app"
fi

echo "Lab 3: kustomize overlays"
for o in dev prod; do
  if kubectl kustomize "$SOL/lab-3/kustomize/overlays/$o" | dry_run; then
    pass "overlays/$o renders and validates"
  else
    flunk "overlays/$o"
  fi
done

echo "Lab 4: helm chart"
CHART=$SOL/lab-4/web-chart
if helm lint "$CHART" >/dev/null && helm lint "$CHART" -f "$SOL/lab-4/values-prod.yaml" >/dev/null; then
  pass "helm lint"
else
  flunk "helm lint"
fi
for v in "" "-f $SOL/lab-4/values-dev.yaml" "-f $SOL/lab-4/values-prod.yaml"; do
  label=${v:-defaults}
  # shellcheck disable=SC2086
  if helm template verify "$CHART" $v | dry_run; then
    pass "helm template ($label)"
  else
    flunk "helm template ($label)"
  fi
done
if helm template verify "$CHART" --set replicaCount=null >/dev/null 2>&1; then
  flunk "required replicaCount did not fail"
else
  pass "required replicaCount fails when unset"
fi

echo
if [[ $fail -eq 0 ]]; then echo "All solutions verified."; else echo "Some checks FAILED."; exit 1; fi
