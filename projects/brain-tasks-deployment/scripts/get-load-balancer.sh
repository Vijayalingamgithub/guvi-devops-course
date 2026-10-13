#!/usr/bin/env bash
set -euo pipefail
hostname="$(kubectl -n brain-tasks get service brain-tasks -o jsonpath='{.status.loadBalancer.ingress[0].hostname}')"
[[ -n "$hostname" ]] || { echo 'The Kubernetes Service has no NLB hostname yet'; exit 1; }
aws elbv2 describe-load-balancers | python3 -c '
import json,sys
host=sys.argv[1]
matches=[lb for lb in json.load(sys.stdin)["LoadBalancers"] if lb["DNSName"]==host]
assert len(matches)==1, "No unique load balancer matched the Kubernetes Service"
print("Application URL: http://"+host+":3000")
print("Load balancer ARN: "+matches[0]["LoadBalancerArn"])
' "$hostname"
