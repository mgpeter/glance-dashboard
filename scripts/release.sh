#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
VERSION_FILE="$REPO_ROOT/VERSION"
IMAGE_NAME="mgpeter/glance-dashboard"
LOCAL_TAG="glance-dashboard:local"
BUILD_CONTEXT="$REPO_ROOT/glance"

bump=patch
no_push=0
dry_run=0
bump_set=0

usage() {
  cat <<EOF
Usage: $(basename "$0") [--patch | --minor | --major] [--no-push] [--dry-run]

Bump VERSION, build the docker image, tag :latest and :<version>, push.

Options:
  --patch    Bump patch (default)
  --minor    Bump minor (resets patch)
  --major    Bump major (resets minor and patch)
  --no-push  Build and tag locally; skip 'docker push'
  --dry-run  Print the version bump and exit without writing/building/pushing
  -h, --help Show this message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --patch) bump=patch; bump_set=$((bump_set + 1)) ;;
    --minor) bump=minor; bump_set=$((bump_set + 1)) ;;
    --major) bump=major; bump_set=$((bump_set + 1)) ;;
    --no-push) no_push=1 ;;
    --dry-run) dry_run=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [[ $bump_set -gt 1 ]]; then
  echo "Pass at most one of --patch / --minor / --major" >&2
  exit 2
fi

if [[ ! -f "$VERSION_FILE" ]]; then
  echo "VERSION file not found at $VERSION_FILE" >&2
  exit 1
fi

current="$(tr -d '[:space:]' < "$VERSION_FILE")"
if [[ ! "$current" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "VERSION file does not contain a valid semver: '$current'" >&2
  exit 1
fi

IFS='.' read -r major minor patch <<<"$current"

case "$bump" in
  patch) patch=$((patch + 1)) ;;
  minor) minor=$((minor + 1)); patch=0 ;;
  major) major=$((major + 1)); minor=0; patch=0 ;;
esac

new="${major}.${minor}.${patch}"

echo "glance-dashboard: ${current} -> ${new} (${bump})"

if [[ $dry_run -eq 1 ]]; then
  echo "(dry-run) no changes made"
  exit 0
fi

printf '%s\n' "$new" > "$VERSION_FILE"

echo "Building $LOCAL_TAG from $BUILD_CONTEXT ..."
docker build -t "$LOCAL_TAG" "$BUILD_CONTEXT"

echo "Tagging $IMAGE_NAME:latest and $IMAGE_NAME:$new ..."
docker tag "$LOCAL_TAG" "$IMAGE_NAME:latest"
docker tag "$LOCAL_TAG" "$IMAGE_NAME:$new"

if [[ $no_push -eq 1 ]]; then
  echo "Built (push skipped): $IMAGE_NAME:$new"
  exit 0
fi

echo "Pushing $IMAGE_NAME (all tags) ..."
docker push --all-tags "$IMAGE_NAME"

echo "Released $IMAGE_NAME:$new"
