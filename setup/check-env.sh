#!/usr/bin/env bash
# Preflight check for the workshop. Run on the control-plane node.
set -uo pipefail

fail=0
ok()   { printf '  [ OK ] %s\n' "$1"; }
bad()  { printf '  [FAIL] %s\n' "$1"; fail=1; }
warn() { printf '  [WARN] %s\n' "$1"; }

echo "Checking tools..."
if command -v kubectl >/dev/null 2>&1; then
  ok "kubectl: $(kubectl version --client 2>/dev/null | head -1)"
  kz=$(kubectl version --client 2>/dev/null | grep -i kustomize || true)
  if [[ -n "$kz" ]]; then ok "$kz (built into kubectl)"; else bad "kubectl has no built-in kustomize (kubectl too old?)"; fi
else
  bad "kubectl not found"
fi

if command -v helm >/dev/null 2>&1; then
  ok "helm: $(helm version --short)"
else
  bad "helm not found. Run ./setup/install-helm.sh"
fi

if command -v python3 >/dev/null 2>&1 && python3 -c 'import yaml' 2>/dev/null; then
  ok "python3 + PyYAML (used in Lab 0)"
else
  warn "python3 PyYAML missing. Lab 0 needs it: sudo apt-get install -y python3-yaml"
fi

if command -v envsubst >/dev/null 2>&1; then
  ok "envsubst (used in Lab 2)"
else
  warn "envsubst missing. Lab 2 needs it: sudo apt-get install -y gettext-base"
fi

echo
echo "Checking cluster..."
if ! kubectl cluster-info >/dev/null 2>&1; then
  bad "cannot reach the API server. Is ~/.kube/config set up?"
else
  ok "API server reachable"
  total=$(kubectl get nodes --no-headers 2>/dev/null | wc -l)
  ready=$(kubectl get nodes --no-headers 2>/dev/null | awk '$2=="Ready"' | wc -l)
  if [[ "$total" -ge 1 && "$total" -eq "$ready" ]]; then
    ok "$ready/$total nodes Ready"
  else
    bad "$ready/$total nodes Ready. Check your CNI and kubelets."
  fi
  workers=$(kubectl get nodes -l '!node-role.kubernetes.io/control-plane' --no-headers 2>/dev/null | wc -l)
  if [[ "$workers" -ge 1 ]]; then ok "$workers worker node(s)"; else warn "no worker nodes: pods will stay Pending unless the control-plane taint is removed"; fi
fi

echo
if [[ "$fail" -eq 0 ]]; then
  echo "All checks passed."
else
  echo "Some checks failed. Fix them before starting."
  exit 1
fi
