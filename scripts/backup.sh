#!/bin/bash
set -euo pipefail

# Jenkins Backup Script
# Creates a consistent backup of JENKINS_HOME.
#
# This script puts Jenkins into "quiet down" (prepare for shutdown) mode
# before backing up, which prevents new builds from starting and reduces
# the chance of capturing inconsistent state. Jenkins is resumed after.
#
# If JENKINS_USER and JENKINS_API_TOKEN are set, quietDown uses authenticated
# requests (required after the setup wizard enables security).
#
# For large/busy installations, consider using a volume snapshot or a
# dedicated backup plugin (e.g. thinBackup) instead of tar.

BACKUP_DIR="${BACKUP_DIR:-./backup}"
TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
BACKUP_FILE="jenkins-${TIMESTAMP}.tar.gz"
CONTAINER_NAME="${CONTAINER_NAME:-jenkins}"
JENKINS_USER="${JENKINS_USER:-}"
JENKINS_API_TOKEN="${JENKINS_API_TOKEN:-}"
LOCK_FILE="${LOCK_FILE:-/tmp/jenkins-backup.lock}"

# Acquire lock to prevent concurrent backups
exec 9>"${LOCK_FILE}"
if ! flock -n 9; then
    echo "ERROR: Another backup is already running (lock: ${LOCK_FILE})"
    exit 1
fi

# Ensure backup directory exists
mkdir -p "${BACKUP_DIR}"

echo "Starting Jenkins backup at $(date)"
echo "Backup file: ${BACKUP_DIR}/${BACKUP_FILE}"

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "ERROR: Container '${CONTAINER_NAME}' is not running"
    exit 1
fi

# Put Jenkins into quiet down mode to pause new builds for a consistent snapshot
echo "Putting Jenkins into quiet down mode..."
QUIET_DOWN_ARGS=(-X POST "http://localhost:8080/quietDown")
if [ -n "${JENKINS_USER}" ] && [ -n "${JENKINS_API_TOKEN}" ]; then
    QUIET_DOWN_ARGS=(-u "${JENKINS_USER}:${JENKINS_API_TOKEN}" "${QUIET_DOWN_ARGS[@]}")
fi
if ! docker exec "${CONTAINER_NAME}" curl -fsS "${QUIET_DOWN_ARGS[@]}" >/dev/null 2>&1; then
    echo "WARN: Could not enter quiet down mode (Jenkins may require auth)."
    echo "      Set JENKINS_USER and JENKINS_API_TOKEN in .env for authenticated quietDown."
    echo "      Continuing without quiet mode."
fi

# Give in-flight queue a moment to settle
sleep 2

# Create backup using docker exec to ensure consistency
# This creates a tarball of the entire jenkins_home directory
CLEANUP_EXIT=0
if docker exec "${CONTAINER_NAME}" tar czf - -C /var/jenkins_home . > "${BACKUP_DIR}/${BACKUP_FILE}"; then
    BACKUP_SIZE=$(du -h "${BACKUP_DIR}/${BACKUP_FILE}" | cut -f1)
    echo "Backup completed successfully"
    echo "File: ${BACKUP_DIR}/${BACKUP_FILE}"
    echo "Size: ${BACKUP_SIZE}"

    # Verify backup integrity
    echo "Verifying backup integrity..."
    if docker exec "${CONTAINER_NAME}" tar tzf - < "${BACKUP_DIR}/${BACKUP_FILE}" >/dev/null 2>&1; then
        echo "Integrity check: PASS"
    else
        echo "ERROR: Backup file is corrupt - removing"
        rm -f "${BACKUP_DIR}/${BACKUP_FILE}"
        CLEANUP_EXIT=1
    fi
else
    echo "ERROR: Backup failed"
    CLEANUP_EXIT=1
fi

# Always resume Jenkins, even if the backup failed
echo "Resuming Jenkins (cancelling quiet down)..."
RESUME_ARGS=(-X POST "http://localhost:8080/cancelQuietDown")
if [ -n "${JENKINS_USER}" ] && [ -n "${JENKINS_API_TOKEN}" ]; then
    RESUME_ARGS=(-u "${JENKINS_USER}:${JENKINS_API_TOKEN}" "${RESUME_ARGS[@]}")
fi
docker exec "${CONTAINER_NAME}" curl -fsS "${RESUME_ARGS[@]}" >/dev/null 2>&1 || true

if [ "${CLEANUP_EXIT}" -ne 0 ]; then
    rm -f "${BACKUP_DIR}/${BACKUP_FILE}"
    exit "${CLEANUP_EXIT}"
fi

# Clean up old backups based on retention policy
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
echo "Cleaning up backups older than ${RETENTION_DAYS} days..."
find "${BACKUP_DIR}" -name "jenkins-*.tar.gz" -mtime "+${RETENTION_DAYS}" -delete 2>/dev/null || true

echo "Backup process completed at $(date)"
