#!/usr/bin/env bash
# ==============================================================================
# build_and_publish_multiarch.sh
#
# Build and push all anpta Docker images (multi-arch where applicable) to
# Docker Hub, end-to-end, from a Linux amd64 host — including ATLAS HTC cluster
# nodes with rootless Docker.
#
# ------------------------------------------------------------------------------
# What this script builds (8 Dockerfile targets)
# ------------------------------------------------------------------------------
#
#   Target                  Platforms              Moving tag on Docker Hub
#   ----------------------  ---------------------  ---------------------------
#   cpu-singularity         linux/amd64, arm64     cpu-singularity
#   cpu                     linux/amd64, arm64     cpu
#   gpu-cuda124-singularity linux/amd64            gpu-cuda124-singularity
#   gpu-cuda124             linux/amd64            gpu-cuda124
#   gpu-cuda128-singularity linux/amd64            gpu-cuda128-singularity
#   gpu-cuda128             linux/amd64            gpu-cuda128
#   gpu-cuda13-singularity  linux/amd64            gpu-cuda13-singularity
#   gpu-cuda13              linux/amd64            gpu-cuda13
#
# Each variant also receives an immutable tag:
#   ${VERSION}-<variant>-<ubuntu-tag>   (e.g. v0.5.1-cpu-ubuntu24.04)
#
# VERSION is read from the VERSION file in the repository root.
#
# ------------------------------------------------------------------------------
# Cluster / rootless Docker (condor and similar)
# ------------------------------------------------------------------------------
#
# Rootless Docker cannot store images on NFS home (overlayfs/lchown fails).
# Use ZFS /local/user for Docker data-root (not NFS, not host /tmp tmpfs — dpkg fails
# there with "Invalid cross-device link"). This script can write
# ~/.config/docker/daemon.json when you pass --setup-rootless.
#
# One-time setup on a build node (as your user):
#
#   dockerd-rootless-setuptool.sh install
#   ./scripts/build_and_publish_multiarch.sh --setup-rootless
#   systemctl --user enable --now docker.service
#   loginctl enable-linger "$USER"    # optional; ask sysadmin — survives logout
#
# Add to ~/.bashrc:
#
#   export DOCKER_HOST=unix:///run/user/$(id -u)/docker.sock
#   export PATH=/usr/bin:$PATH
#
# Stay on the same node for a release build. Override storage if needed:
#   export ANPTA_DOCKER_DATA_ROOT=/local/user/$USER/docker
#
# ------------------------------------------------------------------------------
# Prerequisites
# ------------------------------------------------------------------------------
#
#   - Docker 24+ with buildx plugin
#   - docker login   (REQUIRED when pushing — not needed with --no-push)
#   - jq, curl       (for credential / registry checks)
#   - For linux/arm64 cross-builds on amd64: host qemu binfmt (usually preinstalled)
#   - Disk: tens of GB free under the Docker data-root (see --setup-rootless)
#   - Network access to Docker Hub and base image registries
#
# ------------------------------------------------------------------------------
# Usage
# ------------------------------------------------------------------------------
#
#   ./scripts/build_and_publish_multiarch.sh [OPTIONS]
#
# Options:
#   --setup-rootless     Configure data-root on node-local disk and show hints
#   --skip-env-check     Skip rootless / data-root / daemon checks
#   --dry-run            Print build commands without executing them
#   --no-cache           Do not import old registry cache (still exports cache)
#   --no-push            Build only; do not upload to Docker Hub (see below)
#   --variant NAME       Build only one variant (e.g. cpu, gpu-cuda128)
#   --help               Show this help
#
# --no-push (build / test mode):
#   Skips docker login and registry push. Images are tagged locally as
#   anpta:<moving-tag> (e.g. anpta:cpu). Single-platform variants are --load
#   ed into the local Docker store for docker run. Multi-arch CPU variants
#   are built for all platforms but not loaded (docker run needs --platform
#   or a separate amd64-only test build).
#
# Examples:
#
#   docker login
#   ./scripts/build_and_publish_multiarch.sh
#   ./scripts/build_and_publish_multiarch.sh --no-push --variant cpu
#   ./scripts/build_and_publish_multiarch.sh --variant cpu
#   ./scripts/build_and_publish_multiarch.sh --setup-rootless
#   ./scripts/build_and_publish_multiarch.sh --dry-run
#
# Runtime: many hours for all eight variants (CPU multi-arch is the slowest).
# Log to a file:
#
#   ./scripts/build_and_publish_multiarch.sh 2>&1 | tee ~/anpta-publish.log
#
# See also: docs/PUBLISHING_DOCKERHUB.md
# ==============================================================================

set -euo pipefail

# ------------------------------------------------------------------------------
# Configuration (override via environment)
# ------------------------------------------------------------------------------

readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"
readonly DOCKERFILE="${REPO_ROOT}/Dockerfile"

readonly DOCKERHUB_USER="${DOCKERHUB_USER:-vhaasteren}"
readonly IMAGE_REPO="${IMAGE_REPO:-docker.io/${DOCKERHUB_USER}/anpta}"

# Buildx builder name and driver. On rootless cluster nodes, "docker" (embedded
# BuildKit in rootless dockerd) is reliable; only one "docker" driver builder
# is allowed — ensure_buildx_builder reuses default/rootless if needed.
BUILDX_BUILDER="${ANPTA_BUILDX_BUILDER:-anpta-builder}"
readonly BUILDX_DRIVER="${ANPTA_BUILDX_DRIVER:-docker}"

# Docker storage (not NFS). Default: tmpfs when >=100 GiB free, else /local/user.
LOCAL_DOCKER_ROOT=""

# Flags set by CLI
SETUP_ROOTLESS=false
SKIP_ENV_CHECK=false
DRY_RUN=false
NO_CACHE=false
PUSH_TO_HUB=true
FILTER_VARIANT=""

# Local image name prefix when --no-push (docker load / docker run)
readonly LOCAL_IMAGE_PREFIX="${LOCAL_IMAGE_PREFIX:-anpta}"

# ------------------------------------------------------------------------------
# Logging
# ------------------------------------------------------------------------------

if [[ -t 1 ]]; then
  COLOR_INFO=$'\033[0;32m'
  COLOR_WARN=$'\033[1;33m'
  COLOR_ERR=$'\033[0;31m'
  COLOR_OFF=$'\033[0m'
else
  COLOR_INFO="" COLOR_WARN="" COLOR_ERR="" COLOR_OFF=""
fi

log_info()  { printf '%s[INFO]%s %s\n'  "$COLOR_INFO"  "$COLOR_OFF" "$*"; }
log_warn()  { printf '%s[WARN]%s %s\n'  "$COLOR_WARN"  "$COLOR_OFF" "$*"; }
log_error() { printf '%s[ERROR]%s %s\n' "$COLOR_ERR"   "$COLOR_OFF" "$*" >&2; }
die()       { log_error "$*"; exit 1; }

# ------------------------------------------------------------------------------
# Help
# ------------------------------------------------------------------------------

usage() {
  awk '/^# =/{f=1} f && /^set -euo pipefail$/{exit} f' "$0" | sed 's/^# \{0,1\}//'
  exit 0
}

# ------------------------------------------------------------------------------
# Version
# ------------------------------------------------------------------------------

read_version() {
  local version_file="${REPO_ROOT}/VERSION"
  [[ -f "$version_file" ]] || die "Missing VERSION file at ${version_file}"
  VERSION="$(tr -d '[:space:]' < "$version_file")"
  [[ -n "$VERSION" ]] || die "VERSION file is empty"
}

# ------------------------------------------------------------------------------
# Rootless / cluster environment
# ------------------------------------------------------------------------------

is_rootless_docker() {
  docker info 2>/dev/null | grep -qi 'rootless'
}

ensure_docker_cli() {
  command -v docker >/dev/null 2>&1 || die "docker not found in PATH"
  docker buildx version >/dev/null 2>&1 || die "docker buildx plugin not available"
  command -v jq >/dev/null 2>&1 || die "jq is required (install jq or use a node that has it)"
  command -v curl >/dev/null 2>&1 || die "curl is required"
}

# Point DOCKER_HOST at the user’s rootless socket when the system socket is absent.
ensure_docker_host() {
  if [[ -n "${DOCKER_HOST:-}" ]]; then
    log_info "Using DOCKER_HOST=${DOCKER_HOST}"
    return 0
  fi
  local uid sock
  uid="$(id -u)"
  sock="/run/user/${uid}/docker.sock"
  if [[ -S "$sock" ]]; then
    export DOCKER_HOST="unix://${sock}"
    log_info "Set DOCKER_HOST=${DOCKER_HOST} (rootless socket)"
    return 0
  fi
  if [[ -S /var/run/docker.sock ]] && docker info >/dev/null 2>&1; then
    log_info "Using default system Docker socket"
    return 0
  fi
  die "No Docker socket found. Start rootless Docker: systemctl --user start docker.service"
}

docker_data_root() {
  docker info 2>/dev/null | awk -F': ' '/^ Docker Root Dir/{print $2; exit}'
}

path_on_nfs() {
  local path="$1"
  local fstype
  fstype="$(df -T "$path" 2>/dev/null | awk 'NR==2 {print $2}')"
  [[ "$fstype" == "nfs" || "$fstype" == "nfs4" ]]
}

path_fs_type() {
  df -T "$1" 2>/dev/null | awk 'NR==2 {print $2}'
}

path_mount_point() {
  df "$1" 2>/dev/null | awk 'NR==2 {print $NF}'
}

# Prefer ZFS /local/user for rootless builds (apt/dpkg works). Tmpfs docker root breaks dpkg.
pick_docker_data_root() {
  if [[ -n "${ANPTA_DOCKER_DATA_ROOT:-}" ]]; then
    echo "${ANPTA_DOCKER_DATA_ROOT}"
    return 0
  fi
  echo "/local/user/${USER}/docker"
}

init_docker_data_root() {
  LOCAL_DOCKER_ROOT="$(pick_docker_data_root)"
  log_info "Recommended Docker data-root: ${LOCAL_DOCKER_ROOT}"
}

# Warn or fix: Docker data must not live on NFS for rootless builds.
check_docker_data_root() {
  local root fstype mount_pt
  root="$(docker_data_root)"
  [[ -n "$root" ]] || die "Could not determine Docker Root Dir (is the daemon running?)"

  fstype="$(path_fs_type "$root")"
  mount_pt="$(path_mount_point "$root")"
  log_info "Docker Root Dir: ${root} (fstype=${fstype}, mount=${mount_pt})"

  if path_on_nfs "$root"; then
    log_warn "Docker data is on NFS — image builds will fail (overlayfs/lchown)."
    log_warn "Re-run with --setup-rootless or: export ANPTA_DOCKER_DATA_ROOT=${LOCAL_DOCKER_ROOT}"
    die "Move Docker data off NFS before building."
  fi

  if [[ "$fstype" == "tmpfs" ]]; then
    log_warn "Docker data on tmpfs — apt/dpkg often fails (Invalid cross-device link)."
    log_warn "Use: export ANPTA_DOCKER_DATA_ROOT=/local/user/\$USER/docker && --setup-rootless"
  elif [[ "$fstype" == "zfs" && "$mount_pt" == /local/user ]]; then
    log_info "Docker data on ZFS /local/user — recommended for rootless builds on this cluster."
  fi

  local avail_kb avail_gb
  avail_kb="$(df -k "$root" | awk 'NR==2 {print $4}')"
  avail_gb=$((avail_kb / 1024 / 1024))
  if (( avail_gb < 80 )); then
    log_warn "Low disk space at Docker root (~${avail_gb} GiB free). Full release needs ~80+ GiB."
  else
    log_info "Disk space at Docker root: ~${avail_gb} GiB free"
  fi
}

write_rootless_daemon_json() {
  local cfg_dir="${HOME}/.config/docker"
  local cfg_file="${cfg_dir}/daemon.json"
  local desired_root current_root

  init_docker_data_root
  desired_root="${LOCAL_DOCKER_ROOT}"
  mkdir -p "${desired_root}"
  mkdir -p "$cfg_dir"

  if [[ -f "$cfg_file" ]] && command -v jq >/dev/null 2>&1; then
    current_root="$(jq -r '."data-root" // empty' "$cfg_file" 2>/dev/null || true)"
    if [[ "$current_root" == "$desired_root" ]]; then
      log_info "${cfg_file} already has data-root=${desired_root}"
      return 0
    fi
    if [[ -n "$current_root" ]]; then
      log_warn "Updating data-root: ${current_root} -> ${desired_root}"
    fi
    jq --arg root "$desired_root" '."data-root" = $root' "$cfg_file" > "${cfg_file}.tmp" \
      && mv "${cfg_file}.tmp" "$cfg_file"
  else
    log_info "Writing ${cfg_file} with data-root=${desired_root}"
    cat > "$cfg_file" <<EOF
{
  "data-root": "${desired_root}"
}
EOF
  fi
  log_warn "Restart rootless Docker: systemctl --user restart docker.service"
}

setup_rootless() {
  log_info "=== Rootless Docker setup hints ==="
  if ! command -v dockerd-rootless-setuptool.sh >/dev/null 2>&1; then
    die "dockerd-rootless-setuptool.sh not found — ask sysadmin to install rootless Docker"
  fi
  if [[ ! -f "${HOME}/.config/systemd/user/docker.service" ]]; then
    log_warn "User docker.service not installed yet. Run:"
    log_warn "  dockerd-rootless-setuptool.sh install"
  fi
  write_rootless_daemon_json
  cat <<EOF

Next steps:
  1. systemctl --user enable --now docker.service
  2. Add to ~/.bashrc:
       export DOCKER_HOST=unix:///run/user/\$(id -u)/docker.sock
       export PATH=/usr/bin:\$PATH
  3. Optional: loginctl enable-linger ${USER}
  4. docker login
  5. Re-run this script without --setup-rootless

EOF
}

ensure_rootless_daemon() {
  ensure_docker_host
  if ! docker info >/dev/null 2>&1; then
    die "Cannot connect to Docker. Try: systemctl --user start docker.service"
  fi
  if is_rootless_docker; then
    log_info "Rootless Docker daemon is running"
  else
    log_info "Privileged Docker daemon is running (not rootless)"
  fi
}

check_binfmt_arm64() {
  if [[ -f /proc/sys/fs/binfmt_misc/qemu-aarch64 ]]; then
    if grep -q '^enabled' /proc/sys/fs/binfmt_misc/qemu-aarch64 2>/dev/null; then
      log_info "qemu-aarch64 binfmt is enabled (arm64 cross-builds OK)"
      return 0
    fi
  fi
  log_warn "qemu-aarch64 binfmt not enabled — arm64 layers may fail on amd64 hosts"
  log_warn "Sysadmin may need: tonistiigi/binfmt or qemu-user-static on the host"
}

# ------------------------------------------------------------------------------
# Docker Hub login (strict — must succeed before any build)
# ------------------------------------------------------------------------------

docker_config_file() {
  if [[ -n "${DOCKER_CONFIG:-}" ]]; then
    echo "${DOCKER_CONFIG}/config.json"
  else
    echo "${HOME}/.docker/config.json"
  fi
}

# Resolve Docker Hub username and password/token from config.json or credential helper.
# Prints "user<TAB>pass" on success; returns 1 on failure (safe for subshells).
dockerhub_credentials() {
  local cfg
  cfg="$(docker_config_file)"
  if [[ ! -f "$cfg" ]]; then
    log_error "No ${cfg} — run: docker login"
    return 1
  fi

  local registry="https://index.docker.io/v1/"
  local store helper user pass auth

  store="$(jq -r '.credsStore // empty' "$cfg")"
  helper="$(jq -r '.credHelpers["https://index.docker.io/v1/"] // empty' "$cfg")"

  if [[ -n "$store" && "$store" != "null" ]]; then
    helper="$store"
  fi

  if [[ -n "$helper" && "$helper" != "null" ]]; then
    local bin="docker-credential-${helper}"
    if ! command -v "$bin" >/dev/null 2>&1; then
      log_error "Credential helper ${bin} not found"
      return 1
    fi
    user="$(echo "$registry" | "$bin" get 2>/dev/null | jq -r '.Username // empty')"
    pass="$(echo "$registry" | "$bin" get 2>/dev/null | jq -r '.Secret // empty')"
  fi

  if [[ -z "${user:-}" ]]; then
    auth="$(jq -r '.auths["https://index.docker.io/v1/"].auth // empty' "$cfg")"
    if [[ -z "$auth" ]]; then
      log_error "Not logged into Docker Hub — run: docker login"
      return 1
    fi
    user="$(printf '%s' "$auth" | base64 -d 2>/dev/null | cut -d: -f1)"
    pass="$(printf '%s' "$auth" | base64 -d 2>/dev/null | cut -d: -f2-)"
  fi

  if [[ -z "$user" || -z "$pass" ]]; then
    log_error "Could not read Docker Hub credentials — run: docker login"
    return 1
  fi
  printf '%s\t%s' "$user" "$pass"
}

# Request a registry token with push scope; proves login works before multi-hour builds.
ensure_dockerhub_login() {
  local creds user pass response token
  creds="$(dockerhub_credentials)" || die "Docker Hub login required — run: docker login"
  user="${creds%%$'\t'*}"
  pass="${creds#*$'\t'}"

  log_info "Verifying Docker Hub credentials for user: ${user}"

  response="$(
    curl -fsS -u "${user}:${pass}" \
      "https://auth.docker.io/token?service=registry.docker.io&scope=repository:${DOCKERHUB_USER}/anpta:pull,push" \
      2>/dev/null
  )" || die "Docker Hub authentication failed — run: docker login (check username, token, or PAT)"

  token="$(echo "$response" | jq -r '.token // empty')"
  [[ -n "$token" && "$token" != "null" ]] || die "Docker Hub did not return a push token — check repository permissions for ${DOCKERHUB_USER}/anpta"

  # Second check: registry API accepts the token
  if ! curl -fsS -o /dev/null \
      -H "Authorization: Bearer ${token}" \
      "https://index.docker.io/v2/" 2>/dev/null; then
    die "Docker Hub registry rejected the token"
  fi

  log_info "Docker Hub login OK (push scope verified for ${DOCKERHUB_USER}/anpta)"
}

# ------------------------------------------------------------------------------
# Buildx
# ------------------------------------------------------------------------------

buildx_builder_exists() {
  docker buildx inspect "$1" >/dev/null 2>&1
}

buildx_builder_driver() {
  docker buildx inspect "$1" 2>/dev/null | awk -F': ' '/^Driver:/{gsub(/ /,"",$2); print $2; exit}'
}

# Rootless dockerd only permits one buildx builder with driver=docker.
find_docker_driver_builder() {
  local name
  for name in "${BUILDX_BUILDER}" default rootless; do
    [[ -n "$name" ]] || continue
    if buildx_builder_exists "$name" && [[ "$(buildx_builder_driver "$name")" == "docker" ]]; then
      echo "$name"
      return 0
    fi
  done
  return 1
}

ensure_buildx_builder() {
  local builder="$BUILDX_BUILDER"
  local driver="$BUILDX_DRIVER"

  log_info "Ensuring buildx builder '${builder}' (driver=${driver})"

  if buildx_builder_exists "${builder}"; then
    local current_driver
    current_driver="$(buildx_builder_driver "${builder}")"
    if [[ "$current_driver" != "$driver" ]]; then
      log_warn "Removing builder ${builder} (driver was ${current_driver}, want ${driver})"
      docker buildx rm "${builder}" 2>/dev/null || true
    fi
  fi

  if ! buildx_builder_exists "${builder}"; then
    if [[ "$driver" == "docker" ]]; then
      local existing
      if existing="$(find_docker_driver_builder)"; then
        log_warn "Reusing buildx builder '${existing}' (rootless Docker allows only one driver=docker builder)"
        builder="$existing"
      elif ! docker buildx create --name "${builder}" --driver docker --use 2>/dev/null; then
        existing="$(find_docker_driver_builder)" || die "Could not create or find a buildx builder with driver=docker"
        log_warn "Reusing buildx builder '${existing}' after create failed"
        builder="$existing"
        docker buildx use "${builder}"
      fi
    else
      docker buildx create --name "${builder}" --driver "${driver}" --use
    fi
  else
    docker buildx use "${builder}"
  fi

  BUILDX_BUILDER="$builder"
  docker buildx inspect --bootstrap "${BUILDX_BUILDER}" >/dev/null

  if ! docker buildx inspect "${BUILDX_BUILDER}" 2>/dev/null | grep -q 'linux/arm64'; then
    log_warn "Builder may not list linux/arm64 — CPU multi-arch builds could fail"
  fi

  log_info "Buildx builder ready: ${BUILDX_BUILDER}"
}

# ------------------------------------------------------------------------------
# Build matrix
# ------------------------------------------------------------------------------

# Cache refs (registry-backed, one per family)
readonly CACHE_CPU="${IMAGE_REPO}:cache-cpu"
readonly CACHE_GPU124="${IMAGE_REPO}:cache-gpu-cuda124"
readonly CACHE_GPU128="${IMAGE_REPO}:cache-gpu-cuda128"
readonly CACHE_GPU13="${IMAGE_REPO}:cache-gpu-cuda13"

# variant_key | dockerfile_target | platforms | base_image | tag_suffix | moving_tag | cache_ref | extra_cache_tag
VARIANT_MATRIX=(
  'cpu-singularity|cpu-singularity|linux/amd64,linux/arm64|ubuntu:24.04|cpu-singularity-ubuntu24.04|cpu-singularity|'"${CACHE_CPU}"'|'
  'cpu|cpu|linux/amd64,linux/arm64|ubuntu:24.04|cpu-ubuntu24.04|cpu|'"${CACHE_CPU}"'|cpu-singularity'
  'gpu-cuda124-singularity|gpu-cuda124-singularity|linux/amd64|nvidia/cuda:12.4.0-devel-ubuntu22.04|gpu-cuda124-singularity-ubuntu22.04|gpu-cuda124-singularity|'"${CACHE_GPU124}"'|'
  'gpu-cuda124|gpu-cuda124|linux/amd64|nvidia/cuda:12.4.0-devel-ubuntu22.04|gpu-cuda124-ubuntu22.04|gpu-cuda124|'"${CACHE_GPU124}"'|gpu-cuda124-singularity'
  'gpu-cuda128-singularity|gpu-cuda128-singularity|linux/amd64|nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04|gpu-cuda128-singularity-ubuntu24.04|gpu-cuda128-singularity|'"${CACHE_GPU128}"'|'
  'gpu-cuda128|gpu-cuda128|linux/amd64|nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04|gpu-cuda128-ubuntu24.04|gpu-cuda128|'"${CACHE_GPU128}"'|gpu-cuda128-singularity'
  'gpu-cuda13-singularity|gpu-cuda13-singularity|linux/amd64|nvidia/cuda:13.0.1-cudnn-devel-ubuntu24.04|gpu-cuda13-singularity-ubuntu24.04|gpu-cuda13-singularity|'"${CACHE_GPU13}"'|'
  'gpu-cuda13|gpu-cuda13|linux/amd64|nvidia/cuda:13.0.1-cudnn-devel-ubuntu24.04|gpu-cuda13-ubuntu24.04|gpu-cuda13|'"${CACHE_GPU13}"'|gpu-cuda13-singularity'
)

should_build_variant() {
  local key="$1"
  [[ -z "$FILTER_VARIANT" || "$FILTER_VARIANT" == "$key" ]]
}

# True when platforms string lists exactly one platform (no comma).
is_single_platform() {
  [[ "$1" != *","* ]]
}

image_tags_for_variant() {
  local tag_suffix="$1"
  local moving_tag="$2"
  if [[ "$PUSH_TO_HUB" == "true" ]]; then
    printf '%s\n' \
      "${IMAGE_REPO}:${VERSION}-${tag_suffix}" \
      "${IMAGE_REPO}:${moving_tag}"
  else
    printf '%s\n' \
      "${LOCAL_IMAGE_PREFIX}:${VERSION}-${tag_suffix}" \
      "${LOCAL_IMAGE_PREFIX}:${moving_tag}"
  fi
}

build_and_push_variant() {
  local key="$1"
  local target="$2"
  local platforms="$3"
  local base_image="$4"
  local tag_suffix="$5"
  local moving_tag="$6"
  local family_cache="$7"
  local extra_cache_tag="${8:-}"

  local versioned_tag moving_ref
  mapfile -t _tags < <(image_tags_for_variant "$tag_suffix" "$moving_tag")
  versioned_tag="${_tags[0]}"
  moving_ref="${_tags[1]}"

  log_info "========== ${key} =========="
  log_info "Target:    ${target}"
  log_info "Platforms: ${platforms}"
  log_info "Tags:      ${versioned_tag}"
  log_info "           ${moving_ref}"
  if [[ "$PUSH_TO_HUB" == "true" ]]; then
    log_info "Output:    push to Docker Hub"
  else
    log_info "Output:    local build only (--no-push)"
  fi

  local -a cmd=(
    docker buildx build
    --builder "${BUILDX_BUILDER}"
    --platform "${platforms}"
    --target "${target}"
    -t "${versioned_tag}"
    -t "${moving_ref}"
    --build-arg "BASE_IMAGE=${base_image}"
    --build-arg "BUILDKIT_INLINE_CACHE=1"
  )

  # Registry cache: import is optional; export uploads to Hub and requires push mode.
  if [[ "$PUSH_TO_HUB" == "true" ]]; then
    if [[ "$NO_CACHE" != "true" ]]; then
      cmd+=(--cache-from="type=registry,ref=${family_cache}")
      cmd+=(--cache-from="type=registry,ref=${moving_ref}")
      if [[ -n "$extra_cache_tag" ]]; then
        cmd+=(--cache-from="type=registry,ref=${IMAGE_REPO}:${extra_cache_tag}")
      fi
      cmd+=(--cache-to="type=registry,ref=${family_cache},mode=max")
    else
      log_info "Skipping registry cache import (--no-cache)"
      if [[ -n "$extra_cache_tag" ]]; then
        cmd+=(--cache-from="type=registry,ref=${IMAGE_REPO}:${extra_cache_tag}")
      fi
      cmd+=(--cache-to="type=registry,ref=${family_cache},mode=max")
    fi
    cmd+=(--push)
  else
    if [[ "$NO_CACHE" != "true" ]]; then
      log_info "Importing registry cache only (no cache export in --no-push mode)"
      cmd+=(--cache-from="type=registry,ref=${family_cache}")
      cmd+=(--cache-from="type=registry,ref=${IMAGE_REPO}:${moving_tag}")
      if [[ -n "$extra_cache_tag" ]]; then
        cmd+=(--cache-from="type=registry,ref=${IMAGE_REPO}:${extra_cache_tag}")
      fi
    fi
    if is_single_platform "$platforms"; then
      cmd+=(--load)
      log_info "Will load single-platform image into local Docker (${moving_ref})"
    else
      log_warn "Multi-arch build: images stay in buildx cache (not docker load). Test amd64 with:"
      log_warn "  docker run --platform linux/amd64 --rm ${moving_ref} uname -m"
    fi
  fi

  cmd+=("${REPO_ROOT}")

  if [[ "$DRY_RUN" == "true" ]]; then
    printf '[DRY-RUN]'; printf ' %q' "${cmd[@]}"; printf '\n'
    return 0
  fi

  local start_ts end_ts elapsed
  start_ts="$(date +%s)"
  "${cmd[@]}"
  end_ts="$(date +%s)"
  elapsed=$(( end_ts - start_ts ))
  log_info "Finished ${key} in $(( elapsed / 3600 ))h $(( (elapsed % 3600) / 60 ))m $(( elapsed % 60 ))s"
}

run_all_builds() {
  local row key target platforms base_image tag_suffix moving_tag cache_ref extra_cache
  for row in "${VARIANT_MATRIX[@]}"; do
    IFS='|' read -r key target platforms base_image tag_suffix moving_tag cache_ref extra_cache <<< "$row"
    if should_build_variant "$key"; then
      build_and_push_variant "$key" "$target" "$platforms" "$base_image" \
        "$tag_suffix" "$moving_tag" "$cache_ref" "$extra_cache"
      echo ""
    fi
  done
}

# ------------------------------------------------------------------------------
# CLI
# ------------------------------------------------------------------------------

parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --setup-rootless)   SETUP_ROOTLESS=true ;;
      --skip-env-check)   SKIP_ENV_CHECK=true ;;
      --dry-run)          DRY_RUN=true ;;
      --no-cache)         NO_CACHE=true ;;
      --no-push)          PUSH_TO_HUB=false ;;
      --variant)          FILTER_VARIANT="${2:?--variant requires a name}"; shift ;;
      --help|-h)          usage ;;
      *)
        die "Unknown option: $1 (use --help)"
        ;;
    esac
    shift
  done
}

# ------------------------------------------------------------------------------
# Main
# ------------------------------------------------------------------------------

main() {
  parse_args "$@"

  if [[ "$SETUP_ROOTLESS" == "true" ]]; then
    setup_rootless
  fi

  cd "$REPO_ROOT"
  [[ -f "$DOCKERFILE" ]] || die "Missing Dockerfile at ${DOCKERFILE}"

  read_version

  log_info "anpta multi-arch build"
  log_info "  Host:     $(hostname)"
  log_info "  Version:  ${VERSION}"
  if [[ "$PUSH_TO_HUB" == "true" ]]; then
    log_info "  Mode:     build and push to Docker Hub"
    log_info "  Image:    ${IMAGE_REPO}"
  else
    log_info "  Mode:     build only (--no-push)"
    log_info "  Image:    ${LOCAL_IMAGE_PREFIX}:<tag> (local)"
  fi
  log_info "  Repo:     ${REPO_ROOT}"
  echo ""

  ensure_docker_cli

  if [[ "$SETUP_ROOTLESS" == "true" && "$SKIP_ENV_CHECK" != "true" ]]; then
    write_rootless_daemon_json
  fi

  if [[ "$SKIP_ENV_CHECK" != "true" ]]; then
    init_docker_data_root
    ensure_rootless_daemon
    check_docker_data_root
    check_binfmt_arm64
  else
    ensure_docker_host
    docker info >/dev/null 2>&1 || die "Docker not reachable"
  fi

  if [[ "$PUSH_TO_HUB" == "true" ]]; then
    ensure_dockerhub_login
  else
    log_info "Skipping Docker Hub login check (--no-push)"
  fi

  if [[ "$DRY_RUN" != "true" ]]; then
    ensure_buildx_builder
  else
    log_info "[DRY-RUN] Skipping buildx bootstrap"
  fi

  echo ""
  if [[ "$PUSH_TO_HUB" == "true" ]]; then
    log_info "Starting builds and push to Docker Hub (many hours for all variants)..."
  else
    log_info "Starting local builds only (--no-push; many hours for all variants)..."
  fi
  echo ""

  run_all_builds

  if [[ "$PUSH_TO_HUB" == "true" ]]; then
    log_info "=== All requested variants published successfully ==="
    log_info "Images: https://hub.docker.com/r/${DOCKERHUB_USER}/anpta"
    log_info ""
    log_info "Verify multi-arch manifests, e.g.:"
    log_info "  docker buildx imagetools inspect ${IMAGE_REPO}:cpu"
  else
    log_info "=== All requested variants built successfully (not pushed) ==="
    log_info "Local tags: ${LOCAL_IMAGE_PREFIX}:<variant> (e.g. ${LOCAL_IMAGE_PREFIX}:cpu)"
    log_info ""
    log_info "Quick test (single-platform / amd64):"
    log_info "  docker run --rm ${LOCAL_IMAGE_PREFIX}:cpu uname -m"
    log_info ""
    log_info "When ready to publish: re-run without --no-push after docker login"
  fi
}

main "$@"
