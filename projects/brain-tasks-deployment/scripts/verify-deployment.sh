#!/usr/bin/env bash
set -euo pipefail
: "${EKS_CLUSTER_NAME:?Set the EKS cluster name}"
release_dir="${RELEASE_ARTIFACT_DIR:-${CODEBUILD_SRC_DIR_BuildArtifact:-out}}"
mkdir -p submission-evidence
aws eks describe-cluster --name "$EKS_CLUSTER_NAME" \
  --query 'cluster.{name:name,status:status,version:version,arn:arn}' \
  > submission-evidence/cluster.json
aws eks update-kubeconfig --name "$EKS_CLUSTER_NAME"
kubectl -n brain-tasks rollout status deployment/brain-tasks-api --timeout=300s
kubectl -n brain-tasks rollout status deployment/brain-tasks --timeout=300s
kubectl -n brain-tasks wait --for=condition=Ready pod \
  -l app.kubernetes.io/name=brain-tasks --timeout=300s
kubectl -n brain-tasks get deployment brain-tasks -o json > submission-evidence/deployment.json
kubectl -n brain-tasks get deployment brain-tasks-api -o json > submission-evidence/api-deployment.json
kubectl -n brain-tasks get pods -o wide > submission-evidence/pods.txt
kubectl -n brain-tasks get hpa > submission-evidence/hpa.txt
python3 - "$release_dir/release.json" <<'PY'
import json, sys
release = json.load(open(sys.argv[1]))
expected = release['image']
deploy = json.load(open('submission-evidence/deployment.json'))
actual = deploy['spec']['template']['spec']['containers'][0]['image']
assert actual == expected, f'Wrong release: expected {expected}, got {actual}'
assert deploy['status'].get('availableReplicas', 0) >= 2, 'Fewer than two replicas available'
api = json.load(open('submission-evidence/api-deployment.json'))
assert api['spec']['template']['spec']['containers'][0]['image'] == release['api_image'], 'Wrong API release'
assert api['status'].get('availableReplicas', 0) >= 2, 'Fewer than two API replicas available'
print('PASS: both desired release digests are running with at least two available replicas each')
PY
hostname=""
for _attempt in {1..120}; do
  hostname="$(kubectl -n brain-tasks get service brain-tasks \
    -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
  if [[ -n "$hostname" ]]; then break; fi
  sleep 5
done
[[ "$hostname" =~ ^[a-zA-Z0-9.-]+\.elb\.[a-zA-Z0-9.-]+$ ]] || { echo 'NLB hostname is not ready'; exit 1; }
url="http://${hostname}:3000"
healthy=false
for _attempt in {1..60}; do
  if curl --fail --silent --connect-timeout 5 --max-time 10 "$url/healthz" | grep -qx ok; then
    healthy=true
    break
  fi
  sleep 5
done
[[ "$healthy" = true ]] || { echo 'NLB health endpoint did not become healthy'; exit 1; }
[[ "$(curl --silent --connect-timeout 5 --max-time 10 -o /dev/null -w '%{http_code}' "$url/")" = 401 ]]
[[ "$(curl --silent --connect-timeout 5 --max-time 10 -o /dev/null -w '%{http_code}' "$url/api/v1/tasks")" = 401 ]]
kubectl -n brain-tasks get service brain-tasks -o yaml > submission-evidence/service.yaml
aws elbv2 describe-load-balancers > submission-evidence/load-balancers.json
python3 - "$hostname" "$url" "$release_dir/release.json" <<'PY'
import datetime,json,pathlib,sys
hostname, url, release_path = sys.argv[1:]
lbs=json.load(open('submission-evidence/load-balancers.json'))['LoadBalancers']
matches=[lb for lb in lbs if lb['DNSName'] == hostname]
assert len(matches) == 1, 'Could not identify the actual load balancer ARN'
lb=matches[0]
assert lb['State']['Code'] == 'active', 'Load balancer is not active'
result={'application_url':url,'load_balancer_arn':lb['LoadBalancerArn'],
        'verified_at':datetime.datetime.now(datetime.timezone.utc).isoformat(),
        'release':json.load(open(release_path))}
pathlib.Path('submission-evidence/submission.json').write_text(json.dumps(result,indent=2)+'\n')
print(json.dumps(result,indent=2))
PY
# Preserve only the selected load balancer in the submission report.
rm submission-evidence/load-balancers.json
echo 'PASS: both rollouts, release digests, two replicas each, health endpoint, authentication and active NLB'
