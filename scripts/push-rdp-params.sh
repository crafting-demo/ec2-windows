#!/bin/bash
# Points the web RDP tunnel at the Windows VM.
#
# Reads the `windows` resource state that Terraform saved (hostname and the
# decrypted Administrator password) and pushes it into the tunnel's config API.
#
# Usage:
#   push-rdp-params.sh            push once and exit
#   push-rdp-params.sh --watch    push, then re-push whenever the VM's address
#                                 changes (this is how it runs as a daemon)
#
# The watch mode exists because suspend destroys the instance and resume creates
# a new one with a different public address. Running this as a daemon means the
# push happens again on every resume, and a tunnel is never left pointing at an
# address that no longer exists.

set -euo pipefail

STATE_FILE="${STATE_FILE:-/run/sandbox/fs/resources/windows/state}"
PARAMS_URL="${PARAMS_URL:-http://localhost:8081/params}"
RDP_USER="${RDP_USER:-Administrator}"
TIMEOUT="${TIMEOUT:-600}"
WATCH_INTERVAL="${WATCH_INTERVAL:-30}"

WATCH=0
[[ "${1:-}" == "--watch" ]] && WATCH=1

log() { echo "[push-rdp-params] $*"; }

urlencode() { jq -rn --arg v "$1" '$v|@uri'; }

# Blocks until the resource state carries a usable address. The state file is
# absent until the `windows` resource finishes provisioning.
wait_for_state() {
  local deadline=$(( SECONDS + TIMEOUT ))
  while (( SECONDS < deadline )); do
    if [[ -s "$STATE_FILE" ]] &&
       jq -e '(.public_dns // .public_ip) != null' "$STATE_FILE" >/dev/null 2>&1; then
      return 0
    fi
    log "waiting for $STATE_FILE ..."
    sleep 5
  done
  log "ERROR: resource state never became usable at $STATE_FILE"
  return 1
}

wait_for_tunnel() {
  local deadline=$(( SECONDS + TIMEOUT ))
  until curl -sf -m 5 "$PARAMS_URL" >/dev/null 2>&1; do
    if (( SECONDS >= deadline )); then
      log "ERROR: RDP tunnel did not come up at $PARAMS_URL"
      return 1
    fi
    log "waiting for the RDP tunnel ..."
    sleep 5
  done
}

push() {
  # Prefer the DNS name; it is what an RDP client would normally be handed.
  local host password query response
  host="$(jq -r '.public_dns // .public_ip' "$STATE_FILE")"
  password="$(jq -r '.password // empty' "$STATE_FILE")"

  if [[ -z "$host" || "$host" == "null" ]]; then
    log "no hostname in resource state; is the VM suspended?"
    return 1
  fi

  # The servlet reads request parameters. For a PUT only the query string is
  # parsed as parameters, so these cannot be sent as a form body. Values are
  # URL-encoded because generated Windows passwords routinely contain
  # characters that are significant in a query string.
  query="protocol=rdp"
  query+="&hostname=$(urlencode "$host")"
  query+="&username=$(urlencode "$RDP_USER")"
  [[ -n "$password" ]] && query+="&password=$(urlencode "$password")"

  log "pointing the RDP tunnel at $host as $RDP_USER"

  # The response echoes the active config with the password masked, so it is
  # safe to log and confirms the push landed.
  response="$(curl -sf -m 10 -X PUT "$PARAMS_URL?$query")"
  log "tunnel configured: $response"

  LAST_HOST="$host"
}

wait_for_state
wait_for_tunnel
push

if (( WATCH )); then
  log "reconciling the tunnel against $STATE_FILE every ${WATCH_INTERVAL}s"

  # Compare against what the tunnel actually reports rather than against the
  # last value pushed. That catches the address changing across a resume and
  # also the container restarting and losing its configuration, which would
  # otherwise leave the tunnel pointing at its default of localhost.
  while sleep "$WATCH_INTERVAL"; do
    desired="$(jq -r '.public_dns // .public_ip // empty' "$STATE_FILE" 2>/dev/null || true)"
    [[ -n "$desired" ]] || continue

    # The tunnel echoes its config as form-encoded key=value pairs. A hostname
    # contains no characters that URLEncoder would escape, so read it directly.
    actual="$(curl -sf -m 5 "$PARAMS_URL" 2>/dev/null |
                tr '&' '\n' | sed -n 's/^hostname=//p' | head -1 || true)"

    if [[ -z "$actual" ]]; then
      log "tunnel unreachable; waiting for it to come back"
      wait_for_tunnel && push || log "re-push failed; will retry"
    elif [[ "$actual" != "$desired" ]]; then
      log "tunnel points at '$actual' but should be '$desired'; re-pushing"
      push || log "re-push failed; will retry"
    fi
  done
fi
