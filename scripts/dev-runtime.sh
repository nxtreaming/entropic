#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
DEFAULT_COLIMA_HOME="$HOME/.entropic/colima-dev"
LEGACY_DEFAULT_COLIMA_HOME="$HOME/.nova/colima-dev"
COLIMA_HOME="${ENTROPIC_COLIMA_HOME:-$DEFAULT_COLIMA_HOME}"
ACTIVE_DOCKER_HOST=""
SCRIPT_BIN_DIRS="${PROJECT_ROOT}/src-tauri/target/debug/resources/bin:${PROJECT_ROOT}/src-tauri/resources/bin"

usage() {
  local default_colima_home="${ENTROPIC_COLIMA_HOME:-$DEFAULT_COLIMA_HOME}"

  cat <<USAGE
Usage: ./scripts/dev-runtime.sh <command>

By default, this script uses the isolated runtime home:
  ${default_colima_home}
Set ENTROPIC_COLIMA_HOME to override.

Commands:
  status       Print current Docker/Colima and Entropic container status
  start        Start Colima (if available), then confirm Docker is ready
  up           Run \`pnpm tauri:dev\` after prep for Colima/Docker
  stop         Stop Entropic containers (gateway + scanner)
  prune        Remove Entropic containers and entropic-net
  logs [name]  Tail logs for entropic-openclaw or entropic-skill-scanner
  help         Show this help
USAGE
}

find_docker_binary() {
  local candidates=()

  if command -v docker >/dev/null 2>&1; then
    candidates+=("$(command -v docker)")
  fi

  local bundled="${PROJECT_ROOT}/src-tauri/resources/bin/docker"
  if [ -x "$bundled" ]; then
    candidates+=("$bundled")
  fi

  local target_debug="${PROJECT_ROOT}/src-tauri/target/debug/resources/bin/docker"
  if [ -x "$target_debug" ]; then
    candidates+=("$target_debug")
  fi

  for path in "${candidates[@]}"; do
    if "$path" --version >/dev/null 2>&1; then
      echo "$path"
      return 0
    fi
  done

  echo "docker"
}

find_colima_binary() {
  local target_debug="${PROJECT_ROOT}/src-tauri/target/debug/resources/bin/colima"
  if [ -x "$target_debug" ]; then
    echo "$target_debug"
    return 0
  fi

  local bundled="${PROJECT_ROOT}/src-tauri/resources/bin/colima"
  if [ -x "$bundled" ]; then
    echo "$bundled"
    return 0
  fi

  if command -v colima >/dev/null 2>&1; then
    echo "$(command -v colima)"
    return 0
  fi

  return 1
}

DOCKER_BIN="$(find_docker_binary)"
COLIMA_BIN="$(find_colima_binary || true)"

run_colima() {
  if [ -z "${COLIMA_BIN:-}" ]; then
    return 1
  fi

  COLIMA_HOME="$COLIMA_HOME" \
  LIMA_HOME="$COLIMA_HOME/_lima" \
  PATH="${SCRIPT_BIN_DIRS}:$PATH" \
  "$COLIMA_BIN" "$@"
}

colima_profiles=(entropic-vz entropic-qemu)
legacy_colima_profiles=(nova-vz nova-qemu)
all_colima_profiles=("${colima_profiles[@]}" "${legacy_colima_profiles[@]}")
colima_vm_types=(vz qemu)

resolve_docker_host() {
  local profile=$1
  local candidate_homes=(
    "$COLIMA_HOME"
    "$DEFAULT_COLIMA_HOME"
    "$LEGACY_DEFAULT_COLIMA_HOME"
    "$HOME/.entropic/colima"
    "$HOME/.nova/colima"
  )
  local home
  local sock
  local candidate
  for home in "${candidate_homes[@]}"; do
    sock="$home/$profile/docker.sock"
    if [ -S "$sock" ]; then
      candidate="unix://$sock"
      if docker_host_is_available "$candidate"; then
        echo "$candidate"
        return 0
      fi
    fi
  done
  return 1
}

docker_host_is_available() {
  local candidate="$1"
  if [ -z "$candidate" ]; then
    return 1
  fi

  DOCKER_HOST="$candidate" "$DOCKER_BIN" info >/dev/null 2>&1
}

resolve_working_docker_host() {
  if docker_host_is_available "${ACTIVE_DOCKER_HOST:-}"; then
    return 0
  fi

  # Re-scan known Colima homes in case environment changed across sessions.
  local profile home sock candidate
  for profile in "${all_colima_profiles[@]}"; do
    for home in \
      "$COLIMA_HOME" \
      "$DEFAULT_COLIMA_HOME" \
      "$LEGACY_DEFAULT_COLIMA_HOME" \
      "$HOME/.entropic/colima" \
      "$HOME/.nova/colima" \
      "$HOME/.colima"; do
      [ -d "$home" ] || continue
      sock="$home/$profile/docker.sock"
      candidate="unix://$sock"
      if [ -S "$sock" ] && docker_host_is_available "$candidate"; then
        ACTIVE_DOCKER_HOST="$candidate"
        return 0
      fi
    done
  done

  if [ -n "${DOCKER_HOST:-}" ] && docker_host_is_available "${DOCKER_HOST}"; then
    ACTIVE_DOCKER_HOST="${DOCKER_HOST}"
    return 0
  fi

  ACTIVE_DOCKER_HOST=""
  return 1
}

run_docker() {
  if ! resolve_working_docker_host; then
    echo "[dev] Docker socket unavailable; using default Docker context" >&2
  fi
  local docker_host="${ACTIVE_DOCKER_HOST:-}"
  DOCKER_HOST="$docker_host" "$DOCKER_BIN" "$@"
}

is_docker_running() {
  resolve_working_docker_host >/dev/null 2>&1 && run_docker info >/dev/null 2>&1
}

wait_for_docker() {
  local attempts=20
  local delay=1
  while [ "$attempts" -gt 0 ]; do
    if is_docker_running; then
      return 0
    fi
    attempts=$((attempts - 1))
    if [ "$attempts" -eq 0 ]; then
      break
    fi
    sleep "$delay"
  done
  return 1
}

colima_running_profile() {
  local profile=$1
  local sock
  local home
  local candidate
  local candidate_homes=(
    "$COLIMA_HOME"
    "$DEFAULT_COLIMA_HOME"
    "$LEGACY_DEFAULT_COLIMA_HOME"
    "$HOME/.entropic/colima"
    "$HOME/.nova/colima"
  )
  for home in "${candidate_homes[@]}"; do
    sock="$home/$profile/docker.sock"
    if [ -S "$sock" ]; then
      candidate="unix://$sock"
      if docker_host_is_available "$candidate"; then
        ACTIVE_DOCKER_HOST="$candidate"
        return 0
      fi
      echo "[dev] Found $profile socket at $sock but Docker API is not reachable yet." >&2
    fi
  done

  if [ -n "${COLIMA_BIN:-}" ] && run_colima status --profile "$profile" 2>/dev/null | grep -qi "running"; then
    # Colima can report "running" while the docker.sock is stale/missing.
    # Treat that as not-running so caller can restart the profile.
    echo "[dev] Colima reports $profile running but no docker socket was found." >&2
    return 1
  fi

  return 1
}

resolve_runtime_host() {
  for profile in "${all_colima_profiles[@]}"; do
    if active="$(resolve_docker_host "$profile")"; then
      ACTIVE_DOCKER_HOST="$active"
      return 0
    fi
  done
  return 1
}

# Returns 0 if the daemon log for a profile contains a `signal: killed` marker.
colima_has_crash_marker() {
  local profile=$1
  local home log
  for home in "$COLIMA_HOME" "$DEFAULT_COLIMA_HOME" "$LEGACY_DEFAULT_COLIMA_HOME" "$HOME/.entropic/colima" "$HOME/.nova/colima"; do
    log="$home/$profile/daemon/daemon.log"
    if [ -f "$log" ] && grep -q "signal: killed" "$log" 2>/dev/null; then
      return 0
    fi
  done
  return 1
}

# Delete all Colima + Lima state for a profile so it can start fresh.
# NOTE: Lima stores its instance at $COLIMA_HOME/_lima/colima-<profile>
#       (with the "colima-" prefix), NOT at $COLIMA_HOME/_lima/<profile>.
reset_colima_profile() {
  local profile=$1
  echo "[dev] Resetting Colima + Lima state for profile $profile..."
  run_colima --profile "$profile" stop --force 2>/dev/null || true
  run_colima --profile "$profile" delete --force 2>/dev/null || true
  # Remove the Lima instance directory (colima- prefix is required)
  rm -rf "$COLIMA_HOME/_lima/colima-$profile" 2>/dev/null || true
  # Also wipe the Colima profile directory itself so no stale sockets remain
  rm -rf "$COLIMA_HOME/$profile" 2>/dev/null || true
  mkdir -p "$COLIMA_HOME/_lima"
}

_try_start_colima_profiles() {
  for i in "${!colima_profiles[@]}"; do
    local profile="${colima_profiles[$i]}"
    local vm_type="${colima_vm_types[$i]}"
    local socket_wait=20

    if colima_running_profile "$profile"; then
      ACTIVE_DOCKER_HOST="$(resolve_docker_host "$profile")"
      echo "[dev] Colima already running: $profile"
      return 0
    fi

    # If Colima says profile is running but we couldn't resolve docker.sock,
    # force-stop before attempting start so socket gets recreated cleanly.
    if [ -n "${COLIMA_BIN:-}" ] && run_colima status --profile "$profile" 2>/dev/null | grep -qi "running"; then
      echo "[dev] Forcing restart for $profile to recover missing docker socket..."
      run_colima --profile "$profile" stop --force 2>/dev/null || true
      sleep 1
    fi

    # Proactively reset if the daemon log shows the VM was OOM-killed.
    if colima_has_crash_marker "$profile"; then
      echo "[dev] Crash marker (signal: killed) detected for $profile; resetting before start."
      reset_colima_profile "$profile"
      sleep 1
    fi

    echo "[dev] Starting Colima profile $profile ($vm_type)..."
    local attempts=2
    while [ "$attempts" -gt 0 ]; do
      if start_output=$(run_colima --profile "$profile" start --vm-type "$vm_type" 2>&1); then
        while [ "$socket_wait" -gt 0 ]; do
          if active="$(resolve_docker_host "$profile")"; then
            ACTIVE_DOCKER_HOST="$active"
            echo "[dev] Colima started: $profile"
            return 0
          fi
          sleep 1
          socket_wait=$((socket_wait - 1))
        done
        echo "[dev] Colima started profile $profile but docker socket not ready yet."
        break
      fi

      attempts=$((attempts - 1))
      if [ "$attempts" -gt 0 ] && echo "${start_output:-}" | grep -qi "lima\|signal.*killed\|compatibility"; then
        # Lima state is corrupt or stale — reset and retry the same profile.
        echo "[dev] Lima init error detected for $profile; resetting state and retrying..."
        reset_colima_profile "$profile"
        sleep 1
      else
        echo "[dev] Colima failed to start profile $profile (vm: $vm_type)."
        if [ -n "${start_output:-}" ]; then
          echo "[dev] start output: ${start_output}"
        fi
        break
      fi
    done

    if [ "$vm_type" = "vz" ] && [ -z "${ACTIVE_DOCKER_HOST:-}" ]; then
      echo "[dev] VZ profile unavailable; trying qemu fallback."
      continue
    fi
  done

  return 1
}

ensure_colima() {
  if [ -z "${COLIMA_BIN:-}" ]; then
    echo "[dev] Colima binary not available. Using existing Docker context."
    return 0
  fi

  # Ensure Colima/Lima home directories exist.  The clean-for-user-test
  # script (and first-time runs) wipe COLIMA_HOME entirely; Lima crashes
  # with "signal: killed" if its home dir is missing.
  mkdir -p "$COLIMA_HOME/_lima"

  if _try_start_colima_profiles; then
    return 0
  fi

  # All profiles failed on the first pass.  Do a one-time hard reset of
  # all Lima/Colima state and retry — this heals corrupted disk images or
  # leftover PID files from a previous OOM kill.
  echo "[dev] All Colima profiles failed; performing a full clean reset and retrying..."
  for i in "${!colima_profiles[@]}"; do
    reset_colima_profile "${colima_profiles[$i]}"
  done
  rm -rf "$COLIMA_HOME/_lima" 2>/dev/null || true
  mkdir -p "$COLIMA_HOME/_lima"
  sleep 2

  if _try_start_colima_profiles; then
    return 0
  fi

  echo "[dev] WARNING: Colima did not auto-start. Continuing with Docker context if available."
  return 0
}

start_stack() {
  ensure_colima

  if [ -z "${ACTIVE_DOCKER_HOST}" ] && [ -n "${COLIMA_BIN:-}" ]; then
    for profile in "${colima_profiles[@]}"; do
      if active="$(resolve_docker_host "$profile")"; then
        ACTIVE_DOCKER_HOST="$active"
        break
      fi
    done
  fi

  if ! wait_for_docker; then
    echo "[dev] ERROR: Docker socket not available yet."
    echo "       Open Docker Desktop or start Colima manually and retry."
    return 1
  fi

  if [ -n "${ACTIVE_DOCKER_HOST}" ]; then
    echo "[dev] Using Docker host: $ACTIVE_DOCKER_HOST"
  else
    echo "[dev] Using default Docker context."
  fi

  echo "[dev] Docker ready: $(run_docker version --format '{{.Client.Version}}')"
  echo "[dev] Collected runtime status:"
  status
}

bundle_runtime_tar_if_available() {
  local tar_path="$PROJECT_ROOT/src-tauri/resources/openclaw-runtime.tar.gz"

  if [ -f "$tar_path" ]; then
    return 0
  fi

  if ! run_docker image inspect openclaw-runtime:latest >/dev/null 2>&1; then
    echo "[dev] openclaw-runtime:latest not found in active Docker daemon; skipping runtime tar bundle."
    return 0
  fi

  echo "[dev] Bundling OpenClaw runtime tar for Tauri resources..."
  if [ -n "${ACTIVE_DOCKER_HOST:-}" ]; then
    if ! DOCKER_HOST="$ACTIVE_DOCKER_HOST" "$PROJECT_ROOT/scripts/bundle-runtime-image.sh"; then
      echo "[dev] WARNING: Failed to bundle runtime tar; continuing."
      return 0
    fi
  else
    if ! "$PROJECT_ROOT/scripts/bundle-runtime-image.sh"; then
      echo "[dev] WARNING: Failed to bundle runtime tar; continuing."
      return 0
    fi
  fi
}

stop_stack() {
  echo "[dev] Stopping Entropic gateway containers..."
  run_docker stop \
    entropic-openclaw entropic-skill-scanner \
    nova-openclaw nova-skill-scanner \
    2>/dev/null || true
  echo "[dev] Entropic gateway containers stopped."
}

prune_stack() {
  echo "[dev] Removing Entropic gateway containers and network artifacts..."
  run_docker rm -f \
    entropic-openclaw entropic-skill-scanner \
    nova-openclaw nova-skill-scanner \
    2>/dev/null || true
  run_docker network rm entropic-net nova-net 2>/dev/null || true
  echo "[dev] Cleanup complete."
}

status() {
  if [ -z "${ACTIVE_DOCKER_HOST:-}" ]; then
    resolve_runtime_host || true
  fi

  if [ -n "${ACTIVE_DOCKER_HOST:-}" ]; then
    echo "[dev] Using Docker host: $ACTIVE_DOCKER_HOST"
  else
    echo "[dev] Using default Docker context."
  fi

  echo "[dev] Host OS: $(uname -s)"
  echo "[dev] Docker: $(run_docker --version | head -n 1)"
  if is_docker_running; then
    echo "[dev] Docker socket: ready"
  else
    echo "[dev] Docker socket: unavailable"
  fi

  if [ -n "${COLIMA_BIN:-}" ]; then
    for profile in "${all_colima_profiles[@]}"; do
      if colima_running_profile "$profile"; then
        echo "[dev] Colima profile: $profile (running)"
      else
        echo "[dev] Colima profile: $profile (stopped)"
      fi
    done
  else
    echo "[dev] Colima: not configured"
  fi

  echo "[dev] Containers:"
  local container_rows
  container_rows="$(run_docker ps -a --format "{{.Names}}\t{{.Status}}\t{{.Ports}}" || true)"
  if [ -n "$container_rows" ]; then
    echo "NAMES	STATUS	PORTS"
    echo "$container_rows" | awk -F '\t' '$1 ~ /^(entropic|nova)-/ { print }'
  else
    echo "[dev] (no containers)"
  fi

  echo "[dev] Network:"
  local found_network=0
  for network in entropic-net nova-net; do
    if run_docker network inspect "$network" >/dev/null 2>&1; then
      echo "[dev] ${network} exists"
      found_network=1
    fi
  done
  if [ "$found_network" -eq 0 ]; then
    echo "[dev] entropic-net/nova-net missing"
  fi
}

up_stack() {
  start_stack
  bundle_runtime_tar_if_available

  # Remove stale stopped gateway containers before launching a new one.
  # This avoids the Docker "name already in use" retry path.
  for container in entropic-openclaw nova-openclaw; do
    STOPPED_CONTAINER_IDS="$(run_docker ps -aq -f "name=$container" -f "status=exited" || true)"
    if [ -n "$STOPPED_CONTAINER_IDS" ]; then
      run_docker rm -f "$container" >/dev/null 2>&1 || true
    fi
  done

  echo "[dev] Starting Entropic app with runtime prepared..."
  if [ -n "${ACTIVE_DOCKER_HOST}" ]; then
    echo "[dev] Launching with ENTROPIC_COLIMA_HOME=$COLIMA_HOME and DOCKER_HOST=$ACTIVE_DOCKER_HOST"
    ENTROPIC_COLIMA_HOME="$COLIMA_HOME" DOCKER_HOST="$ACTIVE_DOCKER_HOST" pnpm tauri:dev
  else
    echo "[dev] Launching with ENTROPIC_COLIMA_HOME=$COLIMA_HOME"
    ENTROPIC_COLIMA_HOME="$COLIMA_HOME" pnpm tauri:dev
  fi
}

tail_logs() {
  local target="${1:-}"
  if [ -z "$target" ]; then
    local candidate
    for candidate in entropic-openclaw nova-openclaw; do
      if run_docker ps -a --format "{{.Names}}" | grep -qx "$candidate"; then
        target="$candidate"
        break
      fi
    done
    if [ -z "$target" ]; then
      target="entropic-openclaw"
    fi
  fi
  run_docker logs --tail 200 -f "$target"
}

case "${1:-help}" in
  status)
    status
    ;;
  start)
    start_stack
    ;;
  up)
    up_stack
    ;;
  stop)
    stop_stack
    ;;
  prune)
    prune_stack
    ;;
  logs)
    tail_logs "${2:-}"
    ;;
  help|--help|-h)
    usage
    ;;
  *)
    echo "Unknown command: ${1:-}"
    usage
    exit 1
    ;;
esac
