#!/usr/bin/env bash
set -euo pipefail
cd "$(dirname "$0")/.."
for tool in aws terraform kubectl; do
  command -v "$tool" >/dev/null || { echo "Install $tool first"; exit 1; }
done
region="$(terraform -chdir=infra output -raw aws_region)"
cluster="$(terraform -chdir=infra output -raw cluster_name)"
aws sts get-caller-identity >/dev/null
aws eks wait cluster-active --name "$cluster" --region "$region"
aws eks update-kubeconfig --name "$cluster" --region "$region" --alias "$cluster"
[[ "$(kubectl config current-context)" = "$cluster" ]]
kubectl apply -f k8s/bootstrap/namespace.yaml
kubectl apply -f k8s/bootstrap/rbac.yaml
kubectl apply -f k8s/bootstrap/readers.yaml
kubectl apply -f k8s/bootstrap/api-serviceaccount.yaml
table_name="$(terraform -chdir=infra output -raw tasks_table_name)"
kubectl -n brain-tasks create configmap brain-tasks-api \
  --from-literal="table_name=$table_name" --from-literal="region=$region" \
  --dry-run=client -o yaml | kubectl apply -f -
if ! kubectl -n brain-tasks get secret brain-tasks-http-auth >/dev/null 2>&1; then
  auth_dir="$(mktemp -d)"
  trap 'rm -rf "$auth_dir"' EXIT
  bash scripts/create-auth-file.sh "$auth_dir/htpasswd"
  kubectl -n brain-tasks create secret generic brain-tasks-http-auth \
    --from-file="htpasswd=$auth_dir/htpasswd"
fi
kubectl get nodes -o wide
kubectl get nodepools
kubectl -n amazon-cloudwatch get pods
echo 'Bootstrap complete. Finish the AWS GitHub connection, then enable the pipeline.'
