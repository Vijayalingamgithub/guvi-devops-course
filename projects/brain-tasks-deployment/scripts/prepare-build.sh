#!/usr/bin/env bash
set -euo pipefail
: "${ECR_REPOSITORY_URI:?Set the ECR repository URI}"
: "${ECR_REPOSITORY_NAME:?Set the ECR repository name}"
: "${API_REPOSITORY_URI:?Set the API ECR repository URI}"
: "${API_REPOSITORY_NAME:?Set the API ECR repository name}"
: "${AWS_DEFAULT_REGION:?Set the AWS region}"
: "${CODEBUILD_RESOLVED_SOURCE_VERSION:?Source commit is required}"
: "${CODEBUILD_BUILD_ID:?CodeBuild build identifier is required}"
revision="$CODEBUILD_RESOLVED_SOURCE_VERSION"
[[ "$revision" =~ ^[0-9a-fA-F]{40}$ ]] || { echo 'Expected a Git commit SHA'; exit 1; }
build_uuid="${CODEBUILD_BUILD_ID##*:}"
[[ "$build_uuid" =~ ^[a-zA-Z0-9-]+$ ]] || { echo 'Invalid build UUID'; exit 1; }
image_tag="${revision:0:12}-${build_uuid}"
registry="${ECR_REPOSITORY_URI%%/*}"
mkdir -p out
printf '%s\n' "$image_tag" > out/image-tag.txt
aws ecr get-login-password --region "$AWS_DEFAULT_REGION" |
  docker login --username AWS --password-stdin "$registry"
aws ecr describe-repositories --repository-names "$ECR_REPOSITORY_NAME" >/dev/null
aws ecr describe-repositories --repository-names "$API_REPOSITORY_NAME" >/dev/null
