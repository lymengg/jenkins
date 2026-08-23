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
    echo "  -t <target>         Target container name (default: jenkins-controller)"
    echo "  -y                  Skip confirmation prompt (DANGEROUS)"
    echo "  -h                  Show this help message"
    exit 1
}

# Default values
TARGET_CONTAINER="jenkins-controller"
FORCE_RESTORE=false
BACKUP_FILE=""

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

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${TARGET_CONTAINER}$"; then
    echo "ERROR: Container '${TARGET_CONTAINER}' is not running"
    exit 1
fi

# Confirmation prompt
if [ "${FORCE_RESTORE}" = false ]; then
    echo "WARNING: This will OVERWRITE the Jenkins home directory in container '${TARGET_CONTAINER}'"
    echo "Backup file: ${BACKUP_FILE}"
    echo ""
    echo "This action is IRREVERSIBLE and may cause data loss."
    read -p "Are you sure you want to proceed? (yes/no): " CONFIRM
    if [ "${CONFIRM}" != "yes" ]; then
        echo "Restore cancelled"
        exit 0
    fi
fi

echo "Starting Jenkins restore at $(date)"
echo "Restoring from: ${BACKUP_FILE}"
echo "Target container: ${TARGET_CONTAINER}"

# Stop Jenkins gracefully
echo "Stopping Jenkins..."
docker exec "${TARGET_CONTAINER}" jenkins-cli safe-shutdown 2>/dev/null || true
sleep 10

# Force stop if still running
if docker ps --format '{{.Names}}' | grep -q "^${TARGET_CONTAINER}$"; then
    echo "Force stopping container..."
    docker stop "${TARGET_CONTAINER}"
fi

# Backup current state before restore
echo "Creating safety backup of current state..."
SAFETY_BACKUP="jenkins-pre-restore-$(date +%Y-%m-%d-%H%M%S).tar.gz"
docker exec "${TARGET_CONTAINER}" tar czf - -C /var/jenkins_home . > "./backup/${SAFETY_BACKUP}" 2>/dev/null || true

# Restore the backup
echo "Restoring backup..."
docker run --rm \
    -v "${TARGET_CONTAINER}_jenkins_home:/var/jenkins_home" \
    -v "$(realpath "${BACKUP_FILE}"):/backup/restore.tar.gz:ro" \
    alpine:latest \
    sh -c "rm -rf /var/jenkins_home/* && tar xzf /backup/restore.tar.gz -C /var/jenkins_home"

# Fix permissions
echo "Fixing permissions..."
docker run --rm \
    -v "${TARGET_CONTAINER}_jenkins_home:/var/jenkins_home" \
    alpine:latest \
    chown -R 1000:1000 /var/jenkins_home

# Start Jenkins
echo "Starting Jenkins..."
docker start "${TARGET_CONTAINER}"

echo "Restore completed at $(date)"
echo "Please verify Jenkins is working correctly"
echo "Safety backup saved to: ./backup/${SAFETY_BACKUP}"
