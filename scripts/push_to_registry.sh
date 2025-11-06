#!/bin/bash
#
# Build and push all anpta container variants to registry (local or Docker Hub)
#
# Usage:
#   ./scripts/push_to_registry.sh [VERSION] [DOMAIN|dockerhub]
#
# Examples:
#   ./scripts/push_to_registry.sh                          # Local registry (default), reads VERSION from repo
#   ./scripts/push_to_registry.sh v0.1.0                   # Override version, local registry
#   ./scripts/push_to_registry.sh v0.1.0 vhaasteren.com    # Override version, local registry with custom domain
#   ./scripts/push_to_registry.sh v0.1.0 dockerhub        # Override version, Docker Hub
#
# Version is read from VERSION file in repo root, or can be overridden as first argument.

set -euo pipefail

# Get script directory and repo root
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Read version from VERSION file
DEFAULT_VERSION=$(cat "${REPO_ROOT}/VERSION" | tr -d '[:space:]')
VERSION="${1:-${DEFAULT_VERSION}}"
REGISTRY_ARG="${2:-vhaasteren.com}"
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
    
    # Check if builder exists
    if docker buildx ls | grep -q "${builder_name}"; then
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
            # Just switch to it - don't try to create again
            docker buildx use "${builder_name}" 2>/dev/null || {
                warn "Failed to use existing builder, trying to bootstrap..."
                docker buildx inspect "${builder_name}" --bootstrap
            }
        fi
    else
        info "Creating new buildx builder with docker-container driver (supports multi-platform)..."
        docker buildx create --name "${builder_name}" --driver docker-container --use
    fi
    
    # Bootstrap the builder to ensure it's ready
    info "Bootstrapping builder..."
    docker buildx inspect --bootstrap "${builder_name}" || {
        warn "Bootstrap failed, trying to recreate builder..."
        docker buildx rm "${builder_name}" 2>/dev/null || true
        docker buildx create --name "${builder_name}" --driver docker-container --use
        docker buildx inspect --bootstrap "${builder_name}"
    }
    
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

# Build and push a variant
build_and_push() {
    local target=$1
    local platforms=$2
    local base_image=$3
    local tag_suffix=$4
    local alias_tag=$5
    
    info "Building ${target} for platforms: ${platforms}"
    
    # Full tag with version
    local full_tag="${LOCAL_REPO}:${VERSION}-${tag_suffix}"
    
    # Build and push (will abort on error due to set -e)
    info "Starting build and push for ${full_tag}..."
    
    # Also create Dockerfile target name alias for convenience
    local target_alias="${LOCAL_REPO}:${target}"
    
    docker buildx build \
        --platform "${platforms}" \
        --target "${target}" \
        -t "${full_tag}" \
        -t "${target_alias}" \
        --build-arg BASE_IMAGE="${base_image}" \
        --push \
        .
    
    info "Successfully pushed ${full_tag}"
    info "Successfully pushed ${target_alias}"
    
    # Wait a moment to ensure push completes
    sleep 2
    
    # Create moving alias (wait for previous push to fully complete)
    if [ -n "${alias_tag}" ]; then
        info "Waiting for registry to index the image..."
        sleep 3
        
        info "Creating moving alias: ${alias_tag}"
        docker buildx imagetools create \
            -t "${LOCAL_REPO}:${alias_tag}" \
            "${full_tag}"
        info "Successfully created alias ${LOCAL_REPO}:${alias_tag}"
    fi
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
    info "Note: Built as Docker image, but not converted to .sif (Singularity doesn't run on ARM64)"
    build_and_push \
        "cpu-singularity" \
        "linux/amd64,linux/arm64" \
        "ubuntu:24.04" \
        "cpu-singularity-ubuntu24.04" \
        "cpu-singularity"
    echo ""
    
    info "=== Building CPU (Docker) variant ==="
    build_and_push \
        "cpu" \
        "linux/amd64,linux/arm64" \
        "ubuntu:24.04" \
        "cpu-ubuntu24.04" \
        "cpu"
    echo ""
    
    info "=== Building GPU CUDA 12.4 (Singularity) variant ==="
    build_and_push \
        "gpu-cuda124-singularity" \
        "linux/amd64" \
        "nvidia/cuda:12.4.0-devel-ubuntu22.04" \
        "gpu-cu124-singularity-ubuntu22.04" \
        "gpu-cu124-singularity"
    echo ""
    
    info "=== Building GPU CUDA 12.4 (Docker) variant ==="
    build_and_push \
        "gpu-cuda124" \
        "linux/amd64" \
        "nvidia/cuda:12.4.0-devel-ubuntu22.04" \
        "gpu-cu124-ubuntu22.04" \
        "gpu-cu124"
    echo ""
    
    info "=== Building GPU CUDA 12.8 (Singularity) variant ==="
    build_and_push \
        "gpu-cuda128-singularity" \
        "linux/amd64" \
        "nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04" \
        "gpu-cu128-singularity-ubuntu24.04" \
        "gpu-cu128-singularity"
    echo ""
    
    info "=== Building GPU CUDA 12.8 (Docker) variant ==="
    build_and_push \
        "gpu-cuda128" \
        "linux/amd64" \
        "nvidia/cuda:12.8.1-cudnn-devel-ubuntu24.04" \
        "gpu-cu128-ubuntu24.04" \
        "gpu-cu128"
    echo ""
    
    info "=== Building GPU CUDA 13 (Singularity) variant ==="
    build_and_push \
        "gpu-cuda13-singularity" \
        "linux/amd64" \
        "nvidia/cuda:13.0.1-cudnn-devel-ubuntu24.04" \
        "gpu-cu13-singularity-ubuntu24.04" \
        "gpu-cu13-singularity"
    echo ""
    
    info "=== Building GPU CUDA 13 (Docker) variant ==="
    build_and_push \
        "gpu-cuda13" \
        "linux/amd64" \
        "nvidia/cuda:13.0.1-cudnn-devel-ubuntu24.04" \
        "gpu-cu13-ubuntu24.04" \
        "gpu-cu13"
    echo ""
    
    # Success summary
    info "=== All variants built and pushed successfully! ==="
    info ""
    info "Pushed tags:"
    info "  - ${LOCAL_REPO}:${VERSION}-cpu-singularity-ubuntu24.04 → ${LOCAL_REPO}:cpu-singularity"
    info "  - ${LOCAL_REPO}:${VERSION}-cpu-ubuntu24.04 → ${LOCAL_REPO}:cpu"
    info "  - ${LOCAL_REPO}:${VERSION}-gpu-cu124-singularity-ubuntu22.04 → ${LOCAL_REPO}:gpu-cu124-singularity"
    info "  - ${LOCAL_REPO}:${VERSION}-gpu-cu124-ubuntu22.04 → ${LOCAL_REPO}:gpu-cu124"
    info "  - ${LOCAL_REPO}:${VERSION}-gpu-cu128-singularity-ubuntu24.04 → ${LOCAL_REPO}:gpu-cu128-singularity"
    info "  - ${LOCAL_REPO}:${VERSION}-gpu-cu128-ubuntu24.04 → ${LOCAL_REPO}:gpu-cu128"
    info "  - ${LOCAL_REPO}:${VERSION}-gpu-cu13-singularity-ubuntu24.04 → ${LOCAL_REPO}:gpu-cu13-singularity"
    info "  - ${LOCAL_REPO}:${VERSION}-gpu-cu13-ubuntu24.04 → ${LOCAL_REPO}:gpu-cu13"
    info ""
    info "View at: ${REGISTRY_URL}"
}

# Run main function
main "$@"

