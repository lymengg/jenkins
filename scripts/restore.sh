#!/bin/bash
set -euo pipefail

# Jenkins Restore Script
# Restores Jenkins from a backup file
# WARNING: This is a destructive operation that will overwrite the current Jenkins home

usage() {
    echo "Usage: $0 -f <backup-file> [-t <target-container>] [-y]"
    echo ""
    echo "Options:"
    echo "  -f <backup-file>    Path to the backup tar.gz file (required)"
    echo "  -t <target>         Target container name (default: jenkins)"
    echo "  -y                  Skip confirmation prompt (DANGEROUS)"
    echo "  -h                  Show this help message"
    exit 1
}

# Default values
TARGET_CONTAINER="jenkins"
FORCE_RESTORE=false
BACKUP_FILE=""
JENKINS_USER="${JENKINS_USER:-}"
JENKINS_API_TOKEN="${JENKINS_API_TOKEN:-}"

# Parse arguments
while getopts "f:t:yh" opt; do
    case $opt in
        f) BACKUP_FILE="$OPTARG" ;;
        t) TARGET_CONTAINER="$OPTARG" ;;
        y) FORCE_RESTORE=true ;;
        h) usage ;;
        *) usage ;;
    esac
done

# Validate required arguments
if [ -z "${BACKUP_FILE}" ]; then
    echo "ERROR: Backup file is required"
    usage
fi

# Check if backup file exists
if [ ! -f "${BACKUP_FILE}" ]; then
    echo "ERROR: Backup file not found: ${BACKUP_FILE}"
    exit 1
fi

# Verify backup file is a valid tar.gz before doing anything destructive
echo "Verifying backup file integrity..."
if ! tar tzf "${BACKUP_FILE}" >/dev/null 2>&1; then
    echo "ERROR: Backup file is not a valid tar.gz archive"
    exit 1
fi
echo "Integrity check: PASS"

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${TARGET_CONTAINER}$"; then
    echo "ERROR: Container '${TARGET_CONTAINER}' is not running"
    exit 1
fi

# Resolve the actual Docker volume name (compose prefixes with project name)
VOLUME_NAME=$(docker volume ls --format '{{.Name}}' | grep "jenkins_home$" | head -1)
if [ -z "${VOLUME_NAME}" ]; then
    echo "ERROR: Could not find jenkins_home volume"
    echo "Available volumes:"
    docker volume ls
    exit 1
fi

# Confirmation prompt
if [ "${FORCE_RESTORE}" = false ]; then
    echo ""
    echo "WARNING: This will OVERWRITE the Jenkins home directory in container '${TARGET_CONTAINER}'"
    echo "Backup file: ${BACKUP_FILE}"
    echo "Target volume: ${VOLUME_NAME}"
    echo ""
    echo "This action is IRREVERSIBLE and may cause data loss."
    read -p "Are you sure you want to proceed? (yes/no): " CONFIRM
    if [ "${CONFIRM}" != "yes" ]; then
        echo "Restore cancelled"
        exit 0
    fi
fi

echo ""
echo "Starting Jenkins restore at $(date)"
echo "Restoring from: ${BACKUP_FILE}"
echo "Target container: ${TARGET_CONTAINER}"
echo "Target volume: ${VOLUME_NAME}"

# Ensure backup directory exists for safety backup
mkdir -p ./backup

# Backup current state before stopping (container must be running for docker exec)
echo "Creating safety backup of current state..."
SAFETY_BACKUP="jenkins-pre-restore-$(date +%Y-%m-%d-%H%M%S).tar.gz"
if docker exec "${TARGET_CONTAINER}" tar czf - -C /var/jenkins_home . > "./backup/${SAFETY_BACKUP}" 2>/dev/null; then
    SAFETY_SIZE=$(du -h "./backup/${SAFETY_BACKUP}" | cut -f1)
    echo "Safety backup created: ./backup/${SAFETY_BACKUP} (${SAFETY_SIZE})"
else
    echo "ERROR: Could not create safety backup. Aborting restore to prevent data loss."
    echo "If you want to proceed without a safety backup, remove this check or fix the container."
    exit 1
fi

# Stop Jenkins gracefully using the HTTP API (not jenkins-cli which isn't in the image)
echo "Stopping Jenkins gracefully..."
SAFE_EXIT_ARGS=(-X POST "http://localhost:8080/safeExit")
if [ -n "${JENKINS_USER}" ] && [ -n "${JENKINS_API_TOKEN}" ]; then
    SAFE_EXIT_ARGS=(-u "${JENKINS_USER}:${JENKINS_API_TOKEN}" "${SAFE_EXIT_ARGS[@]}")
fi
docker exec "${TARGET_CONTAINER}" curl -fsS "${SAFE_EXIT_ARGS[@]}" >/dev/null 2>&1 || true

# Wait for Jenkins to stop (up to 30 seconds)
echo "Waiting for Jenkins to stop..."
STOP_WAIT=0
while [ ${STOP_WAIT} -lt 30 ]; do
    if ! docker ps --format '{{.Names}}' | grep -q "^${TARGET_CONTAINER}$"; then
        echo "Jenkins stopped gracefully after ${STOP_WAIT}s"
        break
    fi
    sleep 2
    STOP_WAIT=$((STOP_WAIT + 2))
done

# Force stop if still running
if docker ps --format '{{.Names}}' | grep -q "^${TARGET_CONTAINER}$"; then
    echo "Force stopping container (Jenkins did not stop within 30s)..."
    docker stop "${TARGET_CONTAINER}"
fi

# Restore the backup
echo "Restoring backup..."
docker run --rm \
    -v "${VOLUME_NAME}:/var/jenkins_home" \
    -v "$(realpath "${BACKUP_FILE}"):/backup/restore.tar.gz:ro" \
    alpine:latest \
    sh -c "rm -rf /var/jenkins_home/* /var/jenkins_home/.[!.]* 2>/dev/null; tar xzf /backup/restore.tar.gz -C /var/jenkins_home"

# Fix permissions (Jenkins runs as UID 1000 in the official image)
echo "Fixing permissions..."
docker run --rm \
    -v "${VOLUME_NAME}:/var/jenkins_home" \
    alpine:latest \
    chown -R 1000:1000 /var/jenkins_home

# Start Jenkins
echo "Starting Jenkins..."
docker start "${TARGET_CONTAINER}"

# Wait for Jenkins to respond
echo "Waiting for Jenkins to start..."
MAX_WAIT=120
ELAPSED=0
while [ ${ELAPSED} -lt ${MAX_WAIT} ]; do
    if docker exec "${TARGET_CONTAINER}" curl -sf "http://localhost:8080/login" >/dev/null 2>&1; then
        echo "Jenkins is responding after ${ELAPSED}s"
        break
    fi
    sleep 5
    ELAPSED=$((ELAPSED + 5))
    echo "Waiting... (${ELAPSED}/${MAX_WAIT}s)"
done

if [ ${ELAPSED} -ge ${MAX_WAIT} ]; then
    echo "ERROR: Jenkins did not respond within ${MAX_WAIT}s"
    echo "Check logs: docker logs ${TARGET_CONTAINER}"
    echo "Safety backup: ./backup/${SAFETY_BACKUP}"
    exit 1
fi

echo ""
echo "Restore completed at $(date)"
echo "Jenkins is running and responding"
echo "Safety backup saved to: ./backup/${SAFETY_BACKUP}"
echo "Please verify jobs and plugins are working correctly."
