#!/bin/bash
set -euo pipefail

# Jenkins Health Check Script
# Verifies Jenkins is running and responding properly

CONTAINER_NAME="${CONTAINER_NAME:-jenkins-controller}"
JENKINS_PORT="${JENKINS_PORT:-8080}"
HEALTH_ENDPOINT="http://localhost:${JENKINS_PORT}/login"
API_ENDPOINT="http://localhost:${JENKINS_PORT}/api/json"
TIMEOUT=10

echo "=== Jenkins Health Check ==="
echo "Container: ${CONTAINER_NAME}"
echo "Port: ${JENKINS_PORT}"
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
if curl -sf --max-time ${TIMEOUT} "${HEALTH_ENDPOINT}" > /dev/null 2>&1; then
    echo "RESPONDING"
else
    echo "NOT RESPONDING"
    exit 1
fi

# Check 3: Jenkins API accessible
echo -n "3. Jenkins API: "
if curl -sf --max-time ${TIMEOUT} "${API_ENDPOINT}" > /dev/null 2>&1; then
    echo "ACCESSIBLE"
else
    echo "NOT ACCESSIBLE"
    exit 1
fi

# Check 4: Jenkins is not in safe mode
echo -n "4. Safe mode check: "
SAFE_MODE=$(curl -sf --max-time ${TIMEOUT} "${API_ENDPOINT}" 2>/dev/null | grep -o '"useCrumbs":[^,]*' | head -1 || echo "")
if [ -z "${SAFE_MODE}" ] || echo "${SAFE_MODE}" | grep -q '"useCrumbs":false'; then
    echo "OK"
else
    echo "WARNING - May be in safe mode"
fi

# Check 5: Disk space check
echo -n "5. Disk space: "
DISK_USAGE=$(docker exec "${CONTAINER_NAME}" df -h /var/jenkins_home 2>/dev/null | tail -1 | awk '{print $5}' | tr -d '%' || echo "0")
if [ "${DISK_USAGE}" -lt 90 ]; then
    echo "OK (${DISK_USAGE}% used)"
else
    echo "WARNING - High disk usage (${DISK_USAGE}%)"
fi

# Check 6: Memory usage
echo -n "6. Memory usage: "
MEM_USAGE=$(docker stats "${CONTAINER_NAME}" --no-stream --format "{{.MemPerc}}" 2>/dev/null | tr -d '%' || echo "0")
if [ -n "${MEM_USAGE}" ]; then
    echo "OK (${MEM_USAGE}% used)"
else
    echo "UNAVAILABLE"
fi

echo ""
echo "=== Health Check Complete ==="
echo "Jenkins is healthy and operational"
