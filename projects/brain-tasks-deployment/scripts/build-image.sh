#!/usr/bin/env bash
set -euo pipefail
: "${ECR_REPOSITORY_URI:?Set the ECR repository URI}"
: "${API_REPOSITORY_URI:?Set the API ECR repository URI}"
: "${CODEBUILD_RESOLVED_SOURCE_VERSION:?Source commit is required}"
image_tag="$(cat out/image-tag.txt)"
image="${ECR_REPOSITORY_URI}:${image_tag}"
docker build --pull --platform linux/amd64 \
  --build-arg "SOURCE_REVISION=$CODEBUILD_RESOLVED_SOURCE_VERSION" \
  --tag "$image" .
bash scripts/smoke-test.sh "$image"
bash scripts/browser-test.sh "$image"
docker build --pull --platform linux/amd64 -f api/Dockerfile \
  --tag "${API_REPOSITORY_URI}:${image_tag}" .
