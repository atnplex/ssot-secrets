#!/usr/bin/env bash
# bws_client.sh — Unified BWS secret access with multi-tier fallback
# SSOT: ssot-secrets
# Usage: source bws_client.sh; bws_get "SECRET_NAME"
#    or: ./bws_client.sh get SECRET_NAME
#    or: ./bws_client.sh health

set -euo pipefail

# ── Configuration ────────────────────────────────────────────────────────
NAMESPACE="${NAMESPACE:-/atn}"
SECRETS_DIR="${NAMESPACE}/.config/secrets"
AGE_KEY="${SECRETS_DIR}/age.key"
AGE_FILE="${SECRETS_DIR}/secrets.age"

# Endpoints (priority order)
BWS_LAN_URL="${BWS_LAN_URL:-http://unraid.local:5000}"
BWS_TAILSCALE_URL="${BWS_TAILSCALE_URL:-http://100.76.168.116:5000}"
BWS_OCI_URL="${BWS_OCI_URL:-https://bws.atnplex.cloud:5000}"

# Timeouts
CONNECT_TIMEOUT=2
REQUEST_TIMEOUT=5

# ── Logging ──────────────────────────────────────────────────────────────
_log()  { printf '[bws-client] %s\n' "$*" >&2; }
_ok()   { printf '[bws-client] ✓ %s\n' "$*" >&2; }
_warn() { printf '[bws-client] ! %s\n' "$*" >&2; }

# ── Tier 1: Environment variable (already set) ──────────────────────────
_try_env() {
  local key="$1"
  local val="${!key:-}"
  if [[ -n "$val" ]]; then
    _ok "Resolved '$key' from environment"
    echo "$val"
    return 0
  fi
  return 1
}

# ── Tier 2: Age-encrypted local cache ────────────────────────────────────
_try_age() {
  local key="$1"

  if [[ ! -f "$AGE_FILE" ]] || [[ ! -f "$AGE_KEY" ]]; then
    return 1
  fi

  if ! command -v age &>/dev/null; then
    _warn "age binary not found"
    return 1
  fi

  local json
  json=$(timeout 5 age -d -i "$AGE_KEY" "$AGE_FILE" 2>/dev/null) || return 1

  local val
  val=$(echo "$json" | jq -r --arg k "$key" '.[$k] // empty' 2>/dev/null)

  if [[ -n "$val" ]]; then
    _ok "Resolved '$key' from age cache"
    echo "$val"
    return 0
  fi
  return 1
}

# ── Tier 3-5: HTTP endpoints (LAN → Tailscale → OCI) ────────────────────
_try_http() {
  local key="$1"
  local url="$2"
  local label="$3"

  if ! command -v curl &>/dev/null; then
    return 1
  fi

  local response
  response=$(curl -sf \
    --connect-timeout "$CONNECT_TIMEOUT" \
    --max-time "$REQUEST_TIMEOUT" \
    -H "Content-Type: application/json" \
    "${url}/secret/${key}" 2>/dev/null) || return 1

  local val
  val=$(echo "$response" | jq -r '.value // empty' 2>/dev/null)

  if [[ -n "$val" ]]; then
    _ok "Resolved '$key' from $label ($url)"
    echo "$val"
    return 0
  fi
  return 1
}

# ── Tier 6: BWS CLI (last resort) ───────────────────────────────────────
_try_cli() {
  local key="$1"

  if ! command -v bws &>/dev/null; then
    _warn "bws CLI not found"
    return 1
  fi

  if [[ -z "${BWS_ACCESS_TOKEN:-}" ]]; then
    _warn "BWS_ACCESS_TOKEN not set, cannot use CLI"
    return 1
  fi

  # List secrets and find by key name
  local val
  val=$(bws secret list 2>/dev/null \
    | jq -r --arg k "$key" '.[] | select(.key == $k) | .value // empty' 2>/dev/null)

  if [[ -n "$val" ]]; then
    _ok "Resolved '$key' from BWS CLI"
    echo "$val"
    return 0
  fi
  return 1
}

# ── Public API ───────────────────────────────────────────────────────────

# Get a secret value using the full fallback chain
bws_get() {
  local key="${1:?Usage: bws_get SECRET_NAME}"

  # Tier 1: Environment
  _try_env "$key" && return 0

  # Tier 2: Age cache
  _try_age "$key" && return 0

  # Tier 3: LAN
  _try_http "$key" "$BWS_LAN_URL" "LAN" && return 0

  # Tier 4: Tailscale
  _try_http "$key" "$BWS_TAILSCALE_URL" "Tailscale" && return 0

  # Tier 5: OCI remote
  _try_http "$key" "$BWS_OCI_URL" "OCI" && return 0

  # Tier 6: CLI
  _try_cli "$key" && return 0

  _warn "Failed to resolve '$key' from any source"
  return 1
}

# Export a secret as an environment variable
bws_export() {
  local key="${1:?Usage: bws_export SECRET_NAME}"
  local val
  val=$(bws_get "$key") || return 1
  export "$key=$val"
}

# Export multiple secrets
bws_export_all() {
  local failed=0
  for key in "$@"; do
    bws_export "$key" || { _warn "Could not export $key"; failed=1; }
  done
  return $failed
}

# Health check — which tiers are reachable
bws_health() {
  local status=0

  printf "%-20s %s\n" "TIER" "STATUS"
  printf "%-20s %s\n" "----" "------"

  # Age cache
  if [[ -f "$AGE_FILE" ]] && [[ -f "$AGE_KEY" ]]; then
    printf "%-20s %s\n" "Age Cache" "✓ available"
  else
    printf "%-20s %s\n" "Age Cache" "✗ missing"
  fi

  # LAN
  if curl -sf --connect-timeout 1 "${BWS_LAN_URL}/health" &>/dev/null; then
    printf "%-20s %s\n" "LAN ($BWS_LAN_URL)" "✓ reachable"
  else
    printf "%-20s %s\n" "LAN ($BWS_LAN_URL)" "✗ unreachable"
  fi

  # Tailscale
  if curl -sf --connect-timeout 2 "${BWS_TAILSCALE_URL}/health" &>/dev/null; then
    printf "%-20s %s\n" "Tailscale" "✓ reachable"
  else
    printf "%-20s %s\n" "Tailscale" "✗ unreachable"
  fi

  # OCI
  if curl -sf --connect-timeout 3 "${BWS_OCI_URL}/health" &>/dev/null; then
    printf "%-20s %s\n" "OCI ($BWS_OCI_URL)" "✓ reachable"
  else
    printf "%-20s %s\n" "OCI ($BWS_OCI_URL)" "✗ unreachable"
  fi

  # CLI
  if command -v bws &>/dev/null && [[ -n "${BWS_ACCESS_TOKEN:-}" ]]; then
    printf "%-20s %s\n" "BWS CLI" "✓ available"
  else
    printf "%-20s %s\n" "BWS CLI" "✗ unavailable"
  fi
}

# ── CLI entrypoint ───────────────────────────────────────────────────────
if [[ "${BASH_SOURCE[0]}" == "$0" ]]; then
  case "${1:-}" in
    get)
      shift
      bws_get "$@"
      ;;
    export)
      shift
      bws_export "$@"
      ;;
    health)
      bws_health
      ;;
    *)
      echo "Usage: $0 {get|export|health} [SECRET_NAME]" >&2
      exit 1
      ;;
  esac
fi
