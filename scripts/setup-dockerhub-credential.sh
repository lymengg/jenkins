#!/bin/bash
set -euo pipefail

# Docker Hub Credential Setup Script
# Creates a 'dockerhub' username/password credential in Jenkins for Docker Hub pushes.
#
# Usage:
#   ./scripts/setup-dockerhub-credential.sh
#   DOCKERHUB_USER=lymengouk DOCKERHUB_TOKEN=dhp_xxx ./scripts/setup-dockerhub-credential.sh
#
# Prerequisites:
#   - Jenkins running (docker compose up -d)
#   - JENKINS_USER and JENKINS_API_TOKEN set in .env

CREDENTIAL_ID="dockerhub"
CONTAINER_NAME="${CONTAINER_NAME:-jenkins}"

log() { echo "[setup-dockerhub] $*"; }
die() { echo "[setup-dockerHub] ERROR: $*" >&2; exit 1; }

# Load .env if present
if [[ -f .env ]]; then
    set -a
    # shellcheck disable=SC1091
    source .env
    set +a
fi

JENKINS_USER="${JENKINS_USER:-}"
JENKINS_API_TOKEN="${JENKINS_API_TOKEN:-}"

if [[ -z "${JENKINS_USER}" || -z "${JENKINS_API_TOKEN}" ]]; then
    die "JENKINS_USER and JENKINS_API_TOKEN must be set in .env"
fi

# Check container is running
if ! docker ps --format '{{.Names}}' | grep -q "^${CONTAINER_NAME}$"; then
    die "Container '${CONTAINER_NAME}' is not running"
fi

# Prompt for Docker Hub credentials if not in environment
DOCKERHUB_USER="${DOCKERHUB_USER:-}"
DOCKERHUB_TOKEN="${DOCKERHUB_TOKEN:-}"

if [[ -z "${DOCKERHUB_USER}" ]]; then
    read -r -p "Docker Hub username: " DOCKERHUB_USER
fi
if [[ -z "${DOCKERHUB_TOKEN}" ]]; then
    read -r -s -p "Docker Hub access token: " DOCKERHUB_TOKEN
    echo
fi

if [[ -z "${DOCKERHUB_USER}" || -z "${DOCKERHUB_TOKEN}" ]]; then
    die "Docker Hub username and token are required"
fi

log "Creating credential '${CREDENTIAL_ID}' in Jenkins..."

GROOVY_SCRIPT=$(cat <<'GROOVY'
import com.cloudbees.plugins.credentials.CredentialsScope
import com.cloudbees.plugins.credentials.domains.Domain
import com.cloudbees.plugins.credentials.impl.UsernamePasswordCredentialsImpl
import jenkins.model.Jenkins

def jenkins = Jenkins.instance
def store = jenkins.getExtensionList(
    com.cloudbees.plugins.credentials.CredentialsProvider.class
)[0].getStore()

def existing = com.cloudbees.plugins.credentials.CredentialsMatchers.firstOrNull(
    store.getCredentials(Domain.global()),
    com.cloudbees.plugins.credentials.CredentialsMatchers.withId("dockerhub")
)

if (existing != null) {
    println("Credential 'dockerhub' already exists. Updating...")
    store.updateCredentials(Domain.global(), existing, {
        it.username = DOCKERHUB_USER_VAR
        it.password = DOCKERHUB_TOKEN_VAR
        it.description = "Docker Hub push credentials"
    } as com.cloudbees.plugins.credentials.CredentialsUpdater)
} else {
    def cred = new UsernamePasswordCredentialsImpl(
        CredentialsScope.GLOBAL,
        "dockerhub",
        "Docker Hub push credentials",
        "DOCKERHUB_USER_VAR",
        "DOCKERHUB_TOKEN_VAR"
    )
    store.addCredentials(Domain.global(), cred)
    println("Credential 'dockerhub' created successfully.")
}

jenkins.save()
GROOVY
)

# Escape and substitute actual values
ESCAPED_USER=$(printf '%s' "${DOCKERHUB_USER}" | sed "s/'/\\\\'/g")
ESCAPED_TOKEN=$(printf '%s' "${DOCKERHUB_TOKEN}" | sed "s/'/\\\\'/g")
FINAL_SCRIPT=$(echo "${GROOVY_SCRIPT}" | sed "s/DOCKERHUB_USER_VAR/${ESCAPED_USER}/g; s/DOCKERHUB_TOKEN_VAR/${ESCAPED_TOKEN}/g")

# Execute via Jenkins Script Console
HTTP_CODE=$(docker exec "${CONTAINER_NAME}" \
    curl -s -o /tmp/jenkins-script-result.txt -w "%{http_code}" \
    -u "${JENKINS_USER}:${JENKINS_API_TOKEN}" \
    -X POST \
    -H "Content-Type: application/x-www-form-urlencoded" \
    --data-urlencode "script=${FINAL_SCRIPT}" \
    "http://localhost:8080/scriptText" 2>/dev/null) || true

if [[ "${HTTP_CODE}" == "200" ]]; then
    RESULT=$(docker exec "${CONTAINER_NAME}" cat /tmp/jenkins-script-result.txt 2>/dev/null || true)
    log "${RESULT}"
    log "Done. The 'dockerhub' credential is now available in Jenkins."
else
    die "Jenkins API returned HTTP ${HTTP_CODE}. Check JENKINS_USER and JENKINS_API_TOKEN in .env"
fi
