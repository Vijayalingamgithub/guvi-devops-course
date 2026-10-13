#!/usr/bin/env bash
set -euo pipefail
: "${ECR_REPOSITORY_URI:?Set the ECR repository URI}"
: "${ECR_REPOSITORY_NAME:?Set the ECR repository name}"
: "${API_REPOSITORY_URI:?Set the API ECR repository URI}"
: "${API_REPOSITORY_NAME:?Set the API ECR repository name}"
: "${CODEBUILD_RESOLVED_SOURCE_VERSION:?Source commit is required}"
image_tag="$(cat out/image-tag.txt)"
docker push "${ECR_REPOSITORY_URI}:${image_tag}"
digest="$(aws ecr describe-images --repository-name "$ECR_REPOSITORY_NAME" \
  --image-ids "imageTag=$image_tag" --query 'imageDetails[0].imageDigest' --output text)"
[[ "$digest" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo 'ECR did not return an image digest'; exit 1; }
image_uri="${ECR_REPOSITORY_URI}@${digest}"
docker push "${API_REPOSITORY_URI}:${image_tag}"
api_digest="$(aws ecr describe-images --repository-name "$API_REPOSITORY_NAME" \
  --image-ids "imageTag=$image_tag" --query 'imageDetails[0].imageDigest' --output text)"
[[ "$api_digest" =~ ^sha256:[0-9a-f]{64}$ ]] || { echo 'ECR did not return an API image digest'; exit 1; }
api_image_uri="${API_REPOSITORY_URI}@${api_digest}"
render_args=(--image "$image_uri" --api-image "$api_image_uri" --output out/manifests.yaml \
  --source-cidrs "${LOAD_BALANCER_SOURCE_CIDRS:?Set the permitted load balancer source CIDRs}")
if [[ -n "${ACM_CERTIFICATE_ARN:-}" ]]; then
  render_args+=(--certificate "$ACM_CERTIFICATE_ARN")
fi
python3 scripts/render-manifests.py "${render_args[@]}"
python3 - "$image_uri" "$image_tag" "$CODEBUILD_RESOLVED_SOURCE_VERSION" "$api_image_uri" <<'PY'
import json, pathlib, sys
image, tag, revision, api_image = sys.argv[1:]
pathlib.Path('out/image.json').write_text(json.dumps({'image': image, 'api_image': api_image, 'tag': tag}, indent=2) + '\n')
pathlib.Path('out/release.json').write_text(json.dumps({'revision': revision, 'image': image, 'api_image': api_image}, indent=2) + '\n')
PY
