#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
GLANCE_DIR="$REPO_ROOT/glance"
ENV_FILE="$GLANCE_DIR/asgard.env"
LOCAL_TAG="glance-dashboard:local"
CONTAINER="glance-asgard-test"
PORT=8081
BASE="http://127.0.0.1:$PORT"

keep=1
login=1

usage() {
  cat <<EOF
Usage: $(basename "$0") [--no-keep] [--no-login]

Build the image and run it locally with the Asgard config (glance-asgard.yml)
and glance/asgard.env, then check that the login is enforced.

Options:
  --no-keep   Stop the container after the checks (default: leave it running
              at $BASE for a browser login)
  --no-login  Skip the check that logs in with your password
  -h, --help  Show this message
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --no-keep) keep=0 ;;
    --no-login) login=0 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "Unknown option: $1" >&2; usage >&2; exit 2 ;;
  esac
  shift
done

if [[ ! -f "$ENV_FILE" ]]; then
  echo "$ENV_FILE not found. Run: scripts/auth-secrets.sh --write" >&2
  exit 1
fi

# The file is single-quoted for Compose. `docker run --env-file` would keep the
# quotes as part of the values, so load it here and pass the variables through.
set -a
# shellcheck source=/dev/null
. "$ENV_FILE"
set +a
for var in STEAM_API_KEY STEAM_USER WEATHER_LOCATION GLANCE_SECRET_KEY GLANCE_PASSWORD_HASH; do
  if [[ -z "${!var:-}" ]]; then
    echo "$var is empty in $ENV_FILE" >&2
    exit 1
  fi
done

echo "Building $LOCAL_TAG from $GLANCE_DIR ..."
docker build -q -t "$LOCAL_TAG" "$GLANCE_DIR" > /dev/null

docker rm -f "$CONTAINER" > /dev/null 2>&1 || true
# MSYS_NO_PATHCONV: Git Bash would rewrite /app/... into a Windows path. Scoped
# to this command because docker build needs the host path translated.
MSYS_NO_PATHCONV=1 docker run -d --name "$CONTAINER" -p "127.0.0.1:$PORT:8080" \
  -e STEAM_API_KEY -e STEAM_USER -e WEATHER_LOCATION \
  -e GLANCE_SECRET_KEY -e GLANCE_PASSWORD_HASH \
  --entrypoint /app/glance "$LOCAL_TAG" --config /app/config/glance-asgard.yml > /dev/null

for _ in $(seq 1 30); do
  curl -fs -o /dev/null "$BASE/api/healthz" && break
  if [[ "$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null)" != true ]]; then
    echo "FAIL: container exited during startup" >&2
    docker logs "$CONTAINER" >&2
    docker rm -f "$CONTAINER" > /dev/null 2>&1 || true
    exit 1
  fi
  sleep 1
done

fails=0
check() {
  if [[ "$2" == "$3" ]]; then
    echo "PASS  $1"
  else
    echo "FAIL  $1 (expected $3, got $2)"
    fails=$((fails + 1))
  fi
}

check "GET /api/healthz is public" \
  "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/healthz")" 200

redirect="$(curl -s -o /dev/null -w '%{http_code} %{redirect_url}' "$BASE/")"
check "GET / redirects to the login page" "${redirect%% *} ${redirect##*/}" "303 login"

check "Page content needs a session" \
  "$(curl -s -o /dev/null -w '%{http_code}' "$BASE/api/pages/home/content/")" 401

if [[ $login -eq 1 ]]; then
  read -r -s -p "Password for 'piotr' (checks the hash survived the env file): " password; echo
  jar="$(mktemp)"
  password="${password//\\/\\\\}"
  password="${password//\"/\\\"}"
  body="$(printf '{"username":"piotr","password":"%s"}' "$password")"
  unset password
  check "Login with the right password" \
    "$(curl -s -o /dev/null -w '%{http_code}' -c "$jar" -H 'Content-Type: application/json' \
        --data-binary "$body" "$BASE/api/authenticate")" 200
  unset body
  check "Page content with the session cookie" \
    "$(curl -s -o /dev/null -w '%{http_code}' -b "$jar" "$BASE/api/pages/home/content/")" 200
  rm -f "$jar"
fi

echo
if [[ $keep -eq 1 ]]; then
  echo "Running at $BASE. Stop it with: docker rm -f $CONTAINER"
else
  docker rm -f "$CONTAINER" > /dev/null
fi

if [[ $fails -gt 0 ]]; then
  echo "$fails check(s) failed" >&2
  exit 1
fi
echo "All checks passed"
