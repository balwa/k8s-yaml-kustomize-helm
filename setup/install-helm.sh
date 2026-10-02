#!/usr/bin/env bash
# Installs the Helm CLI on the control-plane node if it is not already present.
# kubectl already ships with Kustomize (`kubectl kustomize`, `kubectl apply -k`),
# so there is nothing else to install.
set -euo pipefail

if command -v helm >/dev/null 2>&1; then
  echo "helm is already installed: $(helm version --short)"
  exit 0
fi

echo "Installing helm using the official install script..."
curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash

helm version --short
