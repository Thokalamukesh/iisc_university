#!/usr/bin/env bash

set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

require_command() {
  if ! command -v "$1" >/dev/null 2>&1; then
    echo "Missing required command: $1" >&2
    exit 1
  fi
}

require_env() {
  local var_name="$1"
  if [[ -z "${!var_name:-}" ]]; then
    echo "Missing required environment variable: $var_name" >&2
    exit 1
  fi
}

aws_cmd() {
  if [[ -n "${AWS_REGION:-}" ]]; then
    aws --region "$AWS_REGION" "$@"
  else
    aws "$@"
  fi
}

require_command flutter
require_command aws
require_env AWS_S3_BUCKET

BUILD_ARGS=(build web --release)

if [[ -n "${FLUTTER_BASE_HREF:-}" ]]; then
  BUILD_ARGS+=(--base-href "$FLUTTER_BASE_HREF")
fi

if [[ -n "${SELFX_WEB_API_BASE_URL:-}" ]]; then
  BUILD_ARGS+=(
    "--dart-define=SELFX_WEB_API_BASE_URL=${SELFX_WEB_API_BASE_URL}"
  )
fi

if [[ -n "${SELFX_WEB_RESTAURANTS_URL:-}" ]]; then
  BUILD_ARGS+=(
    "--dart-define=SELFX_WEB_RESTAURANTS_URL=${SELFX_WEB_RESTAURANTS_URL}"
  )
fi

echo "🚀 Building Flutter web..."
flutter "${BUILD_ARGS[@]}"

echo "☁️ Uploading assets to S3..."
aws_cmd s3 sync build/web "s3://${AWS_S3_BUCKET}" \
  --delete \
  --exclude "index.html" \
  --cache-control "public,max-age=31536000,immutable"

echo "📄 Uploading index.html (no cache)..."
aws_cmd s3 cp build/web/index.html "s3://${AWS_S3_BUCKET}/index.html" \
  --content-type "text/html; charset=utf-8" \
  --cache-control "public,max-age=0,no-cache,no-store,must-revalidate"

if [[ -f "build/web/flutter_service_worker.js" ]]; then
  echo "🔄 Uploading service worker..."
  aws_cmd s3 cp \
    build/web/flutter_service_worker.js \
    "s3://${AWS_S3_BUCKET}/flutter_service_worker.js" \
    --content-type "application/javascript; charset=utf-8" \
    --cache-control "public,max-age=0,no-cache,no-store,must-revalidate"
fi

if [[ -n "${CLOUDFRONT_DISTRIBUTION_ID:-}" ]]; then
  echo "⚡ Invalidating CloudFront..."
  aws_cmd cloudfront create-invalidation \
    --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
    --paths "/*"
fi

echo "✅ Deployment completed successfully!"
