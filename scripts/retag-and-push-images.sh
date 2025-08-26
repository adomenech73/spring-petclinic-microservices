#!/bin/bash
set -e

# Configuration
VERSION=${VERSION:-3.2.7}
REPOSITORY_PREFIX=${REPOSITORY_PREFIX:-localhost:5001}
SOURCE_PREFIX="localhost/springcommunity"
LOG_FILE="podman-retag-push.log"

# Services array
services=(
    "spring-petclinic-config-server"
    "spring-petclinic-discovery-server"
    "spring-petclinic-api-gateway"
    "spring-petclinic-visits-service"
    "spring-petclinic-vets-service"
    "spring-petclinic-customers-service"
    "spring-petclinic-admin-server"
    "spring-petclinic-genai-service"
)

# Log function
log() {
    echo "$(date '+%Y-%m-%d %H:%M:%S') - $1" | tee -a "$LOG_FILE"
}

# Validate environment
validate_env() {
    if [[ -z "$REPOSITORY_PREFIX" ]]; then
        log "ERROR: REPOSITORY_PREFIX is not set"
        exit 1
    fi
}

# Check if Podman is available
check_podman() {
    if ! command -v podman &> /dev/null; then
        log "ERROR: Podman is not installed or not in PATH"
        exit 1
    fi
}

# Check if source images exist
check_source_images() {
    log "Checking source images..."
    local missing_count=0

    for service in "${services[@]}"; do
        local source_image="${SOURCE_PREFIX}/${service}"

        if ! podman image inspect "$source_image" &> /dev/null; then
            log "ERROR: Source image $source_image not found locally"
            ((missing_count++))
        else
            log "OK: Found source image $source_image"
        fi
    done

    if [[ $missing_count -gt 0 ]]; then
        log "ERROR: $missing_count source images missing. Please build the images first."
        exit 1
    fi
}

# Retag images from source to destination
retag_images() {
    log "=== Retagging Images ==="
    local success_count=0
    local fail_count=0

    for service in "${services[@]}"; do
        local source_image="${SOURCE_PREFIX}/${service}"
        local target_image="${REPOSITORY_PREFIX}/${service}:${VERSION}"

        log "Retagging $source_image to $target_image..."

        if podman tag "$source_image" "$target_image"; then
            log "SUCCESS: Retagged $service"
            ((success_count++))
        else
            log "ERROR: Failed to retag $service"
            ((fail_count++))
        fi
    done

    log "Retagging completed: $success_count successful, $fail_count failed"

    if [[ $fail_count -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Push images with retry logic
push_images() {
    log "=== Pushing Images ==="
    local max_retries=3
    local retry_delay=5
    local success_count=0
    local fail_count=0

    for service in "${services[@]}"; do
        local image="${REPOSITORY_PREFIX}/${service}:${VERSION}"
        local attempt=1

        while [[ $attempt -le $max_retries ]]; do
            log "Attempt $attempt: Pushing $image..."

            if podman push --tls-verify=false "$image"; then
                log "SUCCESS: Pushed $image"
                ((success_count++))
                break
            else
                if [[ $attempt -eq $max_retries ]]; then
                    log "ERROR: Failed to push $image after $max_retries attempts"
                    ((fail_count++))
                else
                    log "WARNING: Push attempt $attempt failed, retrying in ${retry_delay}s..."
                    sleep $retry_delay
                fi
            fi
            ((attempt++))
        done
    done

    log "Push process completed: $success_count successful, $fail_count failed"

    if [[ $fail_count -gt 0 ]]; then
        return 1
    fi
    return 0
}

# Clean up retagged images (optional)
cleanup_images() {
    local cleanup_source=${1:-false}  # Default: don't clean source images
    log "=== Cleaning Up Images ==="
    log "Cleanup source images: $cleanup_source"

    local removed_count=0
    local skip_count=0

    for service in "${services[@]}"; do
        local src_image="${SOURCE_PREFIX}/${service}:latest"
        local dst_image="${REPOSITORY_PREFIX}/${service}:${VERSION}"

        # Remove destination image
        if podman image inspect "$dst_image" &> /dev/null; then
            log "Removing destination image: $dst_image..."
            if podman rmi "$dst_image" 2>/dev/null; then
                log "SUCCESS: Removed $dst_image"
                ((removed_count++))
            else
                log "WARNING: Could not remove $dst_image"
                ((skip_count++))
            fi
        fi

        # Conditionally remove source image
        if [[ "$cleanup_source" == "true" ]] && podman image inspect "$src_image" &> /dev/null; then
            log "Removing source image: $src_image..."
            if podman rmi "$src_image" 2>/dev/null; then
                log "SUCCESS: Removed $src_image"
                ((removed_count++))
            else
                log "WARNING: Could not remove $src_image (might be base for other images)"
                ((skip_count++))
            fi
        fi
    done

    log "Cleanup completed: $removed_count images removed, $skip_count skipped"
}

# Main execution
main() {
    validate_env
    check_podman
    check_source_images
    retag_images
    push_images
    # Uncomment the next line if you want to clean up after pushing
    cleanup_images true
}

main "$@"
