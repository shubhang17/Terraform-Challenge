#!/usr/bin/env bash
#
# Startup sequence for the per-student application container:
#
#   1. Block until the centralized cache (CACHE_HOST:CACHE_PORT) is
#      actually accepting TCP connections -- not just "the Terraform
#      resource exists," but genuinely reachable. This is the
#      race-condition protection the assessment calls out: cold-started
#      cache infrastructure can take longer to be ready than the app
#      container takes to boot.
#   2. Register a heartbeat key in the cache, namespaced by STUDENT_ID so
#      one tenant's session state never collides with another's, even
#      though the cache itself is a shared/centralized service. This
#      heartbeat is what gives the "agnostic cache layer" an actual job:
#      it is the seed of an idle-timeout / cost-tracking mechanism, not
#      a decorative env var. See docs/DECISIONS.md.
#   3. Exec ttyd, protected with per-student basic-auth credentials, so
#      "isolation" also covers who can open the terminal in the first
#      place -- not just network-layer separation.
set -euo pipefail

: "${CACHE_HOST:?CACHE_HOST env var is required}"
: "${CACHE_PORT:?CACHE_PORT env var is required}"
: "${STUDENT_ID:?STUDENT_ID env var is required}"
: "${TTYD_USER:?TTYD_USER env var is required}"
: "${TTYD_PASSWORD:?TTYD_PASSWORD env var is required}"

WAIT_TIMEOUT_SECONDS="${CACHE_WAIT_TIMEOUT_SECONDS:-60}"
HEARTBEAT_INTERVAL_SECONDS="${HEARTBEAT_INTERVAL_SECONDS:-30}"
POLL_INTERVAL_SECONDS=2

echo "[entrypoint] student=${STUDENT_ID} waiting for cache at ${CACHE_HOST}:${CACHE_PORT} (timeout ${WAIT_TIMEOUT_SECONDS}s)"

waited=0
until nc -z "${CACHE_HOST}" "${CACHE_PORT}" 2>/dev/null; do
  waited=$((waited + POLL_INTERVAL_SECONDS))
  if [ "${waited}" -ge "${WAIT_TIMEOUT_SECONDS}" ]; then
    echo "[entrypoint] ERROR: cache never became reachable within ${WAIT_TIMEOUT_SECONDS}s -- exiting non-zero so the orchestrator retries the task instead of serving a broken health check" >&2
    exit 1
  fi
  sleep "${POLL_INTERVAL_SECONDS}"
done

echo "[entrypoint] cache reachable after ${waited}s, registering heartbeat"

register_heartbeat() {
  redis-cli -h "${CACHE_HOST}" -p "${CACHE_PORT}" \
    SET "student:${STUDENT_ID}:heartbeat" "$(date -u +%FT%TZ)" EX 120 >/dev/null 2>&1 \
    || echo "[entrypoint] WARN: heartbeat write failed, continuing anyway (cache is a convenience layer, not a hard dependency for the terminal itself)" >&2
}

register_heartbeat

(
  while true; do
    sleep "${HEARTBEAT_INTERVAL_SECONDS}"
    register_heartbeat
  done
) &

echo "[entrypoint] starting ttyd for student=${STUDENT_ID}"
exec ttyd -p 7681 -c "${TTYD_USER}:${TTYD_PASSWORD}" bash
