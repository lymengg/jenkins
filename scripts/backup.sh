#!/bin/bash
set -euo pipefail

# Jenkins Backup Script
# Creates a consistent backup of JENKINS_HOME

BACKUP_DIR="${BACKUP_DIR:-./backup}"
TIMESTAMP=$(date +%Y-%m-%d-%H%M%S)
BACKUP_FILE="jenkins-${TIMESTAMP}.tar.gz"
CONTAINER_NAME="${CONTAINER_NAME:-jenkins-controller}"

# Ensure backup directory exists
mkdir -p "${BACKUP_DIR}"

echo "Starting Jenkins backup at $(date)"
echo "Backup file: ${BACKUP_DIR}/${BACKUP_FILE}"

# Check if container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "ERROR: Container '${CONTAINER_NAME}' is not running"
    exit 1
fi

# Create backup using docker exec to ensure consistency
# This creates a tarball of the entire jenkins_home directory
if docker exec "${CONTAINER_NAME}" tar czf - -C /var/jenkins_home . > "${BACKUP_DIR}/${BACKUP_FILE}"; then
    BACKUP_SIZE=$(du -h "${BACKUP_DIR}/${BACKUP_FILE}" | cut -f1)
    echo "Backup completed successfully"
    echo "File: ${BACKUP_DIR}/${BACKUP_FILE}"
    echo "Size: ${BACKUP_SIZE}"
else
    echo "ERROR: Backup failed"
    rm -f "${BACKUP_DIR}/${BACKUP_FILE}"
    exit 1
fi

# Clean up old backups based on retention policy
RETENTION_DAYS="${BACKUP_RETENTION_DAYS:-30}"
echo "Cleaning up backups older than ${RETENTION_DAYS} days..."
find "${BACKUP_DIR}" -name "jenkins-*.tar.gz" -mtime +${RETENTION_DAYS} -delete 2>/dev/null || true

echo "Backup process completed at $(date)"
