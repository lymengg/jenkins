#!/bin/bash
set -euo pipefail

# Jenkins Health Check Script
# Verifies Jenkins is running and responding properly.
# Exits with non-zero if critical checks fail.

CONTAINER_NAME="${CONTAINER_NAME:-jenkins}"
JENKINS_PORT="${JENKINS_PORT:-8080}"
JENKINS_URL="${JENKINS_URL:-http://localhost:${JENKINS_PORT}}"
TIMEOUT=10
WARNINGS=0

echo "=== Jenkins Health Check ==="
echo "Container: ${CONTAINER_NAME}"
echo "URL: ${JENKINS_URL}"
echo ""

# Check 1: Docker container is running
echo -n "1. Container status: "
if docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    echo "RUNNING"
else
    echo "NOT RUNNING"
    exit 1
fi

# Check 2: HTTP health endpoint responds
echo -n "2. HTTP health check: "
if curl -sf --max-time ${TIMEOUT} "${JENKINS_URL}/login" > /dev/null 2>&1; then
    echo "RESPONDING"
else
    echo "NOT RESPONDING"
    exit 1
fi

# Check 3: Jenkins API accessible
echo -n "3. Jenkins API: "
if curl -sf --max-time ${TIMEOUT} "${JENKINS_URL}/api/json" > /dev/null 2>&1; then
    echo "ACCESSIBLE"
else
    echo "NOT ACCESSIBLE"
    exit 1
fi

# Check 4: Jenkins is not in quiet down (safe mode)
# The API returns "quietingDown":true when Jenkins is in quiet mode
echo -n "4. Quiet down check: "
QUIET_DOWN=$(curl -sf --max-time ${TIMEOUT} "${JENKINS_URL}/api/json" 2>/dev/null | grep -o '"quietingDown":[a-z]*' | head -1 || echo "")
if echo "${QUIET_DOWN}" | grep -q '"quietingDown":true'; then
    echo "WARNING - Jenkins is in quiet down mode"
    WARNINGS=$((WARNINGS + 1))
else
    echo "OK"
fi

# Check 5: Disk space
echo -n "5. Disk space: "
DISK_USAGE=$(docker exec "${CONTAINER_NAME}" df -h /var/jenkins_home 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%' || echo "")
if [ -z "${DISK_USAGE}" ] || ! echo "${DISK_USAGE}" | grep -qE '^[0-9]+$'; then
    echo "UNABLE TO CHECK (docker exec failed)"
    WARNINGS=$((WARNINGS + 1))
elif [ "${DISK_USAGE}" -lt 90 ]; then
    echo "OK (${DISK_USAGE}% used)"
else
    echo "WARNING - High disk usage (${DISK_USAGE}%)"
    WARNINGS=$((WARNINGS + 1))
fi

# Check 6: Memory usage
echo -n "6. Memory usage: "
MEM_USAGE=$(docker stats "${CONTAINER_NAME}" --no-stream --format "{{.MemPerc}}" 2>/dev/null | tr -d ' %' || echo "")
if [ -z "${MEM_USAGE}" ] || ! echo "${MEM_USAGE}" | grep -qE '^[0-9.]+$'; then
    echo "UNAVAILABLE"
    WARNINGS=$((WARNINGS + 1))
else
    echo "OK (${MEM_USAGE}% used)"
fi

echo ""
echo "=== Health Check Complete ==="
if [ ${WARNINGS} -eq 0 ]; then
    echo "Jenkins is healthy and operational"
    exit 0
else
    echo "Jenkins is operational with ${WARNINGS} warning(s)"
    exit 0
fi
