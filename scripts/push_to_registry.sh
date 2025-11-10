#!/bin/bash
#
# Build and push all anpta container variants to registry (local or Docker Hub)
#
# Usage:
#   ./scripts/push_to_registry.sh [REGISTRY]
#
# Examples:
#   ./scripts/push_to_registry.sh                          # Local registry (default: vhaasteren.com)
#   ./scripts/push_to_registry.sh dockerhub                # Docker Hub
#   ./scripts/push_to_registry.sh vhaasteren.com            # Local registry with custom domain
#
# Version is ALWAYS read from VERSION file in repo root (must exist).

set -euo pipefail

# Get script directory and repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Read version from VERSION file (must exist)
if [ ! -f "${REPO_ROOT}/VERSION" ]; then
    error "VERSION file not found at ${REPO_ROOT}/VERSION"
    exit 1
fi
VERSION=$(cat "${REPO_ROOT}/VERSION" | tr -d '[:space:]')
if [ -z "${VERSION}" ]; then
    error "VERSION file is empty"
    exit 1
fi
REGISTRY_ARG="${1:-vhaasteren.com}"
DOCKERHUB_USER="vhaasteren"

# Registry configuration
if [ "${REGISTRY_ARG}" = "dockerhub" ]; then
    USE_DOCKERHUB=true
    LOCAL_REPO="${DOCKERHUB_USER}/anpta"
    REGISTRY_HOST="index.docker.io"
    REGISTRY_URL="https://hub.docker.com/r/${DOCKERHUB_USER}/anpta"
else
    USE_DOCKERHUB=false
    DOMAIN="${REGISTRY_ARG}"
    REGISTRY_HOST="registry-api.${DOMAIN}"
    LOCAL_REPO="${REGISTRY_HOST}/anpta"
    REGISTRY_URL="https://registry.${DOMAIN}"
fi

# Shared cache refs (one per family)
CPU_CACHE_REF="${LOCAL_REPO}:cache-cpu"
GPU_CU124_CACHE_REF="${LOCAL_REPO}:cache-gpu-cuda124"
GPU_CU128_CACHE_REF="${LOCAL_REPO}:cache-gpu-cuda128"
GPU_CU13_CACHE_REF="${LOCAL_REPO}:cache-gpu-cuda13"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Logging functions
info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1" >&2
}

# Check prerequisites
check_prerequisites() {
    info "Checking prerequisites..."
    
    # Check if docker buildx is available
    if ! docker buildx version &>/dev/null; then
        error "docker buildx is not available"
        exit 1
    fi
    
    # Check if buildx builder exists with multi-platform support
    local builder_name="anpta-builder"
    
    # Check if builder exists (skip header line)
    if docker buildx ls 2>/dev/null | tail -n +2 | awk '{print $1}' | grep -q "^${builder_name}$"; then
        info "Found existing buildx builder: ${builder_name}"
        
        # Check if it has the correct driver
        local driver=$(docker buildx inspect "${builder_name}" 2>/dev/null | grep "Driver:" | awk '{print $2}' || echo "")
        
        if [ "${driver}" != "docker-container" ]; then
            warn "Existing builder has unsupported driver (${driver}), removing..."
            docker buildx rm "${builder_name}" 2>/dev/null || true
            info "Creating new buildx builder with docker-container driver..."
            docker buildx create --name "${builder_name}" --driver docker-container --use
        else
            info "Using existing buildx builder with docker-container driver"
            # Switch to it - don't try to create again
            docker buildx use "${builder_name}" 2>/dev/null || true
        fi
    else
        info "Creating new buildx builder with docker-container driver (supports multi-platform)..."
        docker buildx create --name "${builder_name}" --driver docker-container --use
    fi
    
    # Bootstrap the builder to ensure it's ready
    info "Bootstrapping builder..."
    if ! docker buildx inspect --bootstrap "${builder_name}" 2>/dev/null; then
        warn "Bootstrap failed, trying to recreate builder..."
        docker buildx rm "${builder_name}" 2>/dev/null || true
        docker buildx create --name "${builder_name}" --driver docker-container --use
        docker buildx inspect --bootstrap "${builder_name}"
    fi
    
    # Check if we can reach the registry
    if [ "${USE_DOCKERHUB}" = "true" ]; then
        # Check Docker Hub login
        if ! docker info 2>/dev/null | grep -q "Username"; then
            warn "Not logged into Docker Hub. Run 'docker login' first."
            warn "Continuing anyway - the push will fail if not logged in"
        else
            info "Docker Hub login detected"
        fi
        # Check Docker Hub reachability
        if ! curl -s "https://index.docker.io/v2/" > /dev/null 2>&1; then
            warn "Cannot reach Docker Hub"
            warn "Continuing anyway - the push will fail if registry is unreachable"
        else
            info "Docker Hub is reachable"
        fi
    else
        # Check local registry reachability
        if ! curl -k -s "https://${REGISTRY_HOST}/v2/" > /dev/null 2>&1; then
            warn "Cannot reach registry at ${REGISTRY_HOST}"
            warn "Continuing anyway - the push will fail if registry is unreachable"
        else
            info "Registry ${REGISTRY_HOST} is reachable"
        fi
    fi
}

# Build and push a variant (with registry-backed cache import/export)
build_and_push() {
    local target="$1"               # Dockerfile target name
    local platforms="$2"            # e.g. "linux/amd64,linux/arm64"
    local base_image="$3"           # e.g. "ubuntu:24.04"
    local tag_suffix="$4"           # e.g. "cpu-ubuntu24.04"
    local moving_tag="$5"           # the ONE canonical moving tag, e.g. "cpu" or "gpu-cuda124"
    local family_cache_ref="$6"     # e.g. "$CPU_CACHE_REF"
    local extra_cache_from="${7:-}" # optional: another image tag to use as cache source

    info "Building ${target} for platforms: ${platforms}"

    local full_tag="${LOCAL_REPO}:${VERSION}-${tag_suffix}"
    local moving_ref="${LOCAL_REPO}:${moving_tag}"
    info "Tags: ${full_tag} (versioned), ${moving_ref} (moving)"

    # cache-from: shared family cache, prior target alias, optional extra
    local cache_from_flags=(
        "--cache-from=type=registry,ref=${family_cache_ref}"
        "--cache-from=type=registry,ref=${moving_ref}"
    )
    if [ -n "${extra_cache_from}" ]; then
        cache_from_flags+=("--cache-from=type=registry,ref=${LOCAL_REPO}:${extra_cache_from}")
    fi

    # cache-to: export to the shared family cache
    local cache_to_flags=(
        "--cache-to=type=registry,ref=${family_cache_ref},mode=max"
    )

    # Build with arrays (no eval), include inline cache metadata
    local args=(
        buildx build
        --builder anpta-builder
        --platform "${platforms}"
        --target "${target}"
        -t "${full_tag}"
        -t "${moving_ref}"
        --build-arg "BASE_IMAGE=${base_image}"
        --build-arg "BUILDKIT_INLINE_CACHE=1"
        "${cache_from_flags[@]}"
        "${cache_to_flags[@]}"
        --push
        .
    )

    info "Starting build and push for ${full_tag} ..."
    docker "${args[@]}"
    info "Successfully pushed ${full_tag} and ${moving_ref}"
}

# Main execution
main() {
    if [ "${USE_DOCKERHUB}" = "true" ]; then
        info "Starting build and push to Docker Hub"
    else
        info "Starting build and push to local registry"
    fi
    info "Version: ${VERSION}"
    info "Registry: ${LOCAL_REPO}"
    echo ""
    
    check_prerequisites
    echo ""
    
    # Build and push all variants (aborts on first error due to set -e)
    info "=== Building CPU (Singularity) variant ==="
    info "Note: Built as Docker image, but not converted to .sif (Apptainer doesn't run on macOS)"
    build_and_push \
        "cpu-singularity" \
        "linux/amd64,linux/arm64" \
        "ubuntu:24.04" \
        "cpu-singularity-ubuntu24.04" \
        "cpu-singularity" \
        "${CPU_CACHE_REF}"
    echo ""
    
    info "=== Building CPU (unified for Docker & Devcontainer) variant ==="
    build_and_push \
        "cpu" \
        "linux/amd64,linux/arm64" \
        "ubuntu:24.04" \
        "cpu-ubuntu24.04" \
        "cpu" \
        "${CPU_CACHE_REF}" \
        "cpu-singularity"
    echo ""
    
    info "=== Building GPU CUDA 12.4 (Singularity) variant ==="
    build_and_push \
        "gpu-cuda124-singularity" \
        "linux/amd64" \
        "nvidia/cuda:12.4.0-devel-ubuntu22.04" \
        "gpu-cuda124-singularity-ubuntu22.04" \
        "gpu-cuda124-singularity" \
        "${GPU_CU124_CACHE_REF}"
    echo ""
    
    info "=== Building GPU CUDA 12.4 (unified for Docker & Devcontainer) variant ==="
    build_and_push \
        "gpu-cuda124" \
        "linux/amd64" \
        "nvidia/cuda:12.4.0-devel-ubuntu22.04" \
        "gpu-cuda124-ubuntu22.04" \
        "gpu-cuda124" \
        "${GPU_CU124_CACHE_REF}" \
        "gpu-cuda124-singularity"
    echo ""
    
    info "=== Building GPU CUDA 12.8 (Singularity) variant ==="
    build_and_push \
        "gpu-cuda128-singularity" \
        "linux/amd64" \
        "nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04" \
        "gpu-cuda128-singularity-ubuntu24.04" \
        "gpu-cuda128-singularity" \
        "${GPU_CU128_CACHE_REF}"
    echo ""
    
    info "=== Building GPU CUDA 12.8 (unified for Docker & Devcontainer) variant ==="
    build_and_push \
        "gpu-cuda128" \
        "linux/amd64" \
        "nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04" \
        "gpu-cuda128-ubuntu24.04" \
        "gpu-cuda128" \
        "${GPU_CU128_CACHE_REF}" \
        "gpu-cuda128-singularity"
    echo ""
    
    info "=== Building GPU CUDA 13 (Singularity) variant ==="
    build_and_push \
        "gpu-cuda13-singularity" \
        "linux/amd64" \
        "nvidia/cuda:13.0.1-cudnn-devel-ubuntu24.04" \
        "gpu-cuda13-singularity-ubuntu24.04" \
        "gpu-cuda13-singularity" \
        "${GPU_CU13_CACHE_REF}"
    echo ""
    
    info "=== Building GPU CUDA 13 (unified for Docker & Devcontainer) variant ==="
    build_and_push \
        "gpu-cuda13" \
        "linux/amd64" \
        "nvidia/cuda:13.0.1-cudnn-devel-ubuntu24.04" \
        "gpu-cuda13-ubuntu24.04" \
        "gpu-cuda13" \
        "${GPU_CU13_CACHE_REF}" \
        "gpu-cuda13-singularity"
    echo ""
    
    # Success summary
    info "=== All variants built and pushed successfully! ==="
    info ""
    info "Pushed tags:"
    info "  - ${LOCAL_REPO}:${VERSION}-cpu-singularity-ubuntu24.04 → ${LOCAL_REPO}:cpu-singularity"
    info "  - ${LOCAL_REPO}:${VERSION}-cpu-ubuntu24.04 → ${LOCAL_REPO}:cpu"
    info "  - ${LOCAL_REPO}:${VERSION}-gpu-cuda124-singularity-ubuntu22.04 → ${LOCAL_REPO}:gpu-cuda124-singularity"
    info "  - ${LOCAL_REPO}:${VERSION}-gpu-cuda124-ubuntu22.04 → ${LOCAL_REPO}:gpu-cuda124"
    info "  - ${LOCAL_REPO}:${VERSION}-gpu-cuda128-singularity-ubuntu24.04 → ${LOCAL_REPO}:gpu-cuda128-singularity"
    info "  - ${LOCAL_REPO}:${VERSION}-gpu-cuda128-ubuntu24.04 → ${LOCAL_REPO}:gpu-cuda128"
    info "  - ${LOCAL_REPO}:${VERSION}-gpu-cuda13-singularity-ubuntu24.04 → ${LOCAL_REPO}:gpu-cuda13-singularity"
    info "  - ${LOCAL_REPO}:${VERSION}-gpu-cuda13-ubuntu24.04 → ${LOCAL_REPO}:gpu-cuda13"
    info ""
    info "View at: ${REGISTRY_URL}"
}

# Run main function
main "$@"

