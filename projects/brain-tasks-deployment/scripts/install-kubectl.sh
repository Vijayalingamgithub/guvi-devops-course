#!/usr/bin/env bash
set -euo pipefail
: "${EKS_CLUSTER_NAME:?Set the EKS cluster name}"
version="$(aws eks describe-cluster --name "$EKS_CLUSTER_NAME" --query cluster.version --output text)"
[[ "$version" =~ ^1\.[0-9]+$ ]] || { echo 'Unexpected Kubernetes version'; exit 1; }
work_dir="$(mktemp -d)"
trap 'rm -rf "$work_dir"' EXIT
curl --fail --silent --show-error --location \
  "https://dl.k8s.io/release/v${version}.0/bin/linux/amd64/kubectl" -o "$work_dir/kubectl"
curl --fail --silent --show-error --location \
  "https://dl.k8s.io/release/v${version}.0/bin/linux/amd64/kubectl.sha256" -o "$work_dir/kubectl.sha256"
expected="$(cat "$work_dir/kubectl.sha256")"
printf '%s  %s\n' "$expected" "$work_dir/kubectl" | sha256sum --check
install -m 0755 "$work_dir/kubectl" /usr/local/bin/kubectl
kubectl version --client
