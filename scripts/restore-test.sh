#!/bin/bash
set -euo pipefail

# Jenkins Restore Test Script
# Tests backup restoration in an isolated environment.
# Does NOT touch the production Jenkins volume.

TEST_ID=$(date +%s)
TEST_CONTAINER="jenkins-restore-test-${TEST_ID}"
TEST_VOLUME="jenkins_test_home_${TEST_ID}"
TEST_PORT=8081
TEST_AGENT_PORT=50001
JENKINS_IMAGE_TAG="${JENKINS_IMAGE_TAG:-2.462.1-jdk17}"
NO_WAIT=false

usage() {
    echo "Usage: $0 -f <backup-file> [--no-wait]"
    echo ""
    echo "Options:"
    echo "  -f <backup-file>    Path to the backup tar.gz file (required)"
    echo "  --no-wait           Skip the 5-minute manual verification wait (for CI/automation)"
    echo "  -h                  Show this help message"
    exit 1
}

# Parse arguments
BACKUP_FILE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        -f) BACKUP_FILE="$2"; shift 2 ;;
        --no-wait) NO_WAIT=true; shift ;;
        -h) usage ;;
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

# Verify backup file is a valid tar.gz
echo "Verifying backup file integrity..."
if ! tar tzf "${BACKUP_FILE}" >/dev/null 2>&1; then
    echo "ERROR: Backup file is not a valid tar.gz archive"
    exit 1
fi
echo "Integrity check: PASS"

# Check if test ports are available
check_port() {
    if command -v ss >/dev/null 2>&1; then
        ss -tlnp 2>/dev/null | grep -q ":${1} " && return 1 || return 0
    elif command -v netstat >/dev/null 2>&1; then
        netstat -tlnp 2>/dev/null | grep -q ":${1} " && return 1 || return 0
    fi
    return 0  # Can't check - assume available
}

if ! check_port ${TEST_PORT}; then
    echo "ERROR: Port ${TEST_PORT} is already in use. Free it or modify TEST_PORT in the script."
    exit 1
fi
if ! check_port ${TEST_AGENT_PORT}; then
    echo "ERROR: Port ${TEST_AGENT_PORT} is already in use."
    exit 1
fi

# Cleanup function
cleanup() {
    echo "Cleaning up test environment..."
    docker stop "${TEST_CONTAINER}" 2>/dev/null || true
    docker rm "${TEST_CONTAINER}" 2>/dev/null || true
    docker volume rm "${TEST_VOLUME}" 2>/dev/null || true
}

trap cleanup EXIT

echo ""
echo "=== Jenkins Restore Test ==="
echo "Testing backup: ${BACKUP_FILE}"
echo "Jenkins image tag: ${JENKINS_IMAGE_TAG}"
echo "Test container: ${TEST_CONTAINER}"
echo "Test volume: ${TEST_VOLUME}"
echo ""

# Clean up any existing test environment with the same ID
cleanup

# Create test volume
echo "Creating test volume..."
docker volume create "${TEST_VOLUME}"

# Restore backup to test volume
echo "Restoring backup to test volume..."
docker run --rm \
    -v "${TEST_VOLUME}:/var/jenkins_home" \
    -v "$(realpath "${BACKUP_FILE}"):/backup/restore.tar.gz:ro" \
    alpine:latest \
    sh -c "tar xzf /backup/restore.tar.gz -C /var/jenkins_home"

# Fix permissions (Jenkins runs as UID 1000)
echo "Fixing permissions..."
docker run --rm \
    -v "${TEST_VOLUME}:/var/jenkins_home" \
    alpine:latest \
    chown -R 1000:1000 /var/jenkins_home

# Start Jenkins test instance
echo "Starting test Jenkins instance..."
docker run -d \
    --name "${TEST_CONTAINER}" \
    -p "${TEST_PORT}:8080" \
    -p "${TEST_AGENT_PORT}:50000" \
    -v "${TEST_VOLUME}:/var/jenkins_home" \
    -e "JAVA_OPTS=-Djava.awt.headless=true -Xmx1024m" \
    jenkins/jenkins:${JENKINS_IMAGE_TAG}

# Wait for Jenkins to start
echo "Waiting for Jenkins to start..."
MAX_WAIT=120
WAIT_INTERVAL=5
ELAPSED=0
JENKINS_STARTED=false

while [ ${ELAPSED} -lt ${MAX_WAIT} ]; do
    if curl -sf "http://localhost:${TEST_PORT}/login" > /dev/null 2>&1; then
        echo "Jenkins is responding after ${ELAPSED} seconds"
        JENKINS_STARTED=true
        break
    fi
    sleep ${WAIT_INTERVAL}
    ELAPSED=$((ELAPSED + WAIT_INTERVAL))
    echo "Waiting... (${ELAPSED}/${MAX_WAIT}s)"
done

if [ "${JENKINS_STARTED}" = false ]; then
    echo "ERROR: Jenkins did not start within ${MAX_WAIT}s"
    echo "Container logs:"
    docker logs "${TEST_CONTAINER}" --tail=30
    exit 1
fi

# Verify Jenkins is running
echo ""
echo "=== Verification ==="

# Check 1: HTTP health check
echo -n "1. HTTP health check: "
if curl -sf "http://localhost:${TEST_PORT}/login" > /dev/null 2>&1; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Check 2: Jenkins home directory exists and is readable
echo -n "2. Jenkins home readable: "
if docker exec "${TEST_CONTAINER}" test -d /var/jenkins_home; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Check 3: Configuration files present
echo -n "3. Configuration present: "
if docker exec "${TEST_CONTAINER}" test -f /var/jenkins_home/config.xml; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Check 4: Plugins directory exists
echo -n "4. Plugins directory: "
if docker exec "${TEST_CONTAINER}" test -d /var/jenkins_home/plugins; then
    echo "PASS"
else
    echo "FAIL"
    exit 1
fi

# Check 5: Jobs directory exists (if any jobs were in backup)
echo -n "5. Jobs directory: "
if docker exec "${TEST_CONTAINER}" test -d /var/jenkins_home/jobs; then
    echo "PASS"
else
    echo "PASS (no jobs in backup)"
fi

# Check 6: Jenkins API accessible
echo -n "6. Jenkins API: "
if docker exec "${TEST_CONTAINER}" curl -sf "http://localhost:8080/api/json" > /dev/null 2>&1; then
    echo "PASS"
else
    echo "WARN (API may not be fully initialized)"
fi

echo ""
echo "=== Restore Test Complete ==="
echo "All critical checks passed."
echo "Test Jenkins is running on port ${TEST_PORT}"

if [ "${NO_WAIT}" = true ]; then
    echo "--no-wait specified, cleaning up immediately."
else
    echo ""
    echo "To manually verify, open: http://localhost:${TEST_PORT}"
    echo "Press Ctrl+C to stop and clean up, or wait for automatic cleanup..."
    sleep 300
    echo "Test period ended. Cleaning up..."
fi
