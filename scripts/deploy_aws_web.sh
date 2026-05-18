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
  local attempt=1
  local max_attempts="${AWS_DEPLOY_MAX_ATTEMPTS:-5}"
  local delay=2

  while true; do
    if [[ -n "${AWS_REGION:-}" ]]; then
      aws --region "$AWS_REGION" "$@" && return 0
    else
      aws "$@" && return 0
    fi

    if (( attempt >= max_attempts )); then
      return 1
    fi

    echo "AWS command failed; retrying in ${delay}s (${attempt}/${max_attempts})..." >&2
    sleep "$delay"
    attempt=$((attempt + 1))
    delay=$((delay * 2))
  done
}

require_command flutter
require_command aws
require_env AWS_S3_BUCKET

export AWS_RETRY_MODE="${AWS_RETRY_MODE:-adaptive}"
export AWS_MAX_ATTEMPTS="${AWS_MAX_ATTEMPTS:-10}"

WEB_RENDERER="${WEB_RENDERER:-html}"
DART2JS_OPTIMIZATION="${DART2JS_OPTIMIZATION:-O4}"

BUILD_ARGS=(
  build web
  --release
  --pwa-strategy=none
  --web-renderer "$WEB_RENDERER"
  --dart2js-optimization "$DART2JS_OPTIMIZATION"
)

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

BUILD_STAMP="${SELFX_BUILD_STAMP:-$(date -u +%Y%m%d%H%M%S)}"
BUILD_ARGS+=("--dart-define=SELFX_BUILD_STAMP=${BUILD_STAMP}")

echo "🚀 Building Flutter web..."
echo "Build stamp: ${BUILD_STAMP}"
rm -rf build/web
flutter "${BUILD_ARGS[@]}"

NO_CACHE_FILES=(
  "index.html"
  "main.dart.js"
  "flutter.js"
  "flutter_bootstrap.js"
  "flutter_service_worker.js"
  "version.json"
  "manifest.json"
  "assets/AssetManifest.json"
  "assets/AssetManifest.bin"
  "assets/AssetManifest.bin.json"
  "assets/FontManifest.json"
  "assets/NOTICES"
)

echo "☁️ Uploading cacheable assets to S3..."
aws_cmd s3 sync build/web "s3://${AWS_S3_BUCKET}" \
  --delete \
  --exclude "index.html" \
  --exclude "main.dart.js" \
  --exclude "flutter.js" \
  --exclude "flutter_bootstrap.js" \
  --exclude "flutter_service_worker.js" \
  --exclude "version.json" \
  --exclude "manifest.json" \
  --exclude "assets/AssetManifest.json" \
  --exclude "assets/AssetManifest.bin" \
  --exclude "assets/AssetManifest.bin.json" \
  --exclude "assets/FontManifest.json" \
  --exclude "assets/NOTICES" \
  --cache-control "public,max-age=31536000,immutable"

echo "📄 Uploading runtime entry files (no cache)..."
aws_cmd s3 cp build/web/index.html "s3://${AWS_S3_BUCKET}/index.html" \
  --content-type "text/html; charset=utf-8" \
  --cache-control "public,max-age=0,no-cache,no-store,must-revalidate"

for file in "${NO_CACHE_FILES[@]}"; do
  if [[ "$file" == "index.html" ]]; then
    continue
  fi
  if [[ -f "build/web/${file}" ]]; then
    case "$file" in
      *.js)
        aws_cmd s3 cp \
          "build/web/${file}" \
          "s3://${AWS_S3_BUCKET}/${file}" \
          --content-type "application/javascript; charset=utf-8" \
          --cache-control "public,max-age=0,no-cache,no-store,must-revalidate"
        ;;
      *.json)
        aws_cmd s3 cp \
          "build/web/${file}" \
          "s3://${AWS_S3_BUCKET}/${file}" \
          --content-type "application/json; charset=utf-8" \
          --cache-control "public,max-age=0,no-cache,no-store,must-revalidate"
        ;;
      *)
        aws_cmd s3 cp \
          "build/web/${file}" \
          "s3://${AWS_S3_BUCKET}/${file}" \
          --cache-control "public,max-age=0,no-cache,no-store,must-revalidate"
        ;;
    esac
  else
    # Remove stale runtime files when current build doesn't generate them
    # (for example flutter_service_worker.js with --pwa-strategy=none).
    aws_cmd s3 rm "s3://${AWS_S3_BUCKET}/${file}" >/dev/null 2>&1 || true
  fi
done

if [[ -n "${CLOUDFRONT_DISTRIBUTION_ID:-}" ]]; then
  echo "⚡ Invalidating CloudFront..."
  invalidation_id="$(
    aws_cmd cloudfront create-invalidation \
      --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
      --paths "/*" \
      --query 'Invalidation.Id' \
      --output text
  )"

  echo "⏳ Waiting for CloudFront invalidation ${invalidation_id} to complete..."
  aws_cmd cloudfront wait invalidation-completed \
    --distribution-id "$CLOUDFRONT_DISTRIBUTION_ID" \
    --id "$invalidation_id"
  echo "✅ CloudFront invalidation completed."
fi

echo "✅ Deployment completed successfully!"
