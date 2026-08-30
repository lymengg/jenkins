#!/usr/bin/env bash

set -euo pipefail

DEPLOY_USER="deploy"
APP_NAME="spring-boilerplate"
APP_DIR="/opt/${APP_NAME}"

echo "Creating deployment user..."

if ! id "${DEPLOY_USER}" &>/dev/null; then
    sudo useradd \
        --create-home \
        --shell /bin/bash \
        "${DEPLOY_USER}"
fi

echo "Configuring SSH directory..."

sudo install -d \
    -m 700 \
    -o "${DEPLOY_USER}" \
    -g "${DEPLOY_USER}" \
    "/home/${DEPLOY_USER}/.ssh"

sudo touch "/home/${DEPLOY_USER}/.ssh/authorized_keys"

sudo chown "${DEPLOY_USER}:${DEPLOY_USER}" \
    "/home/${DEPLOY_USER}/.ssh/authorized_keys"

sudo chmod 600 \
    "/home/${DEPLOY_USER}/.ssh/authorized_keys"

echo
echo "Paste the Jenkins deployment PUBLIC key."
echo "Example:"
echo "ssh-ed25519 AAAAC3... jenkins-production-deploy"
echo

read -r -p "Public key: " SSH_PUBLIC_KEY

if [[ -z "${SSH_PUBLIC_KEY}" ]]; then
    echo "ERROR: Public key cannot be empty."
    exit 1
fi

if ! grep -qxF "${SSH_PUBLIC_KEY}" \
    "/home/${DEPLOY_USER}/.ssh/authorized_keys"; then

    echo "${SSH_PUBLIC_KEY}" | sudo tee -a \
        "/home/${DEPLOY_USER}/.ssh/authorized_keys" >/dev/null
fi

sudo chown "${DEPLOY_USER}:${DEPLOY_USER}" \
    "/home/${DEPLOY_USER}/.ssh/authorized_keys"

sudo chmod 600 \
    "/home/${DEPLOY_USER}/.ssh/authorized_keys"

echo "Creating application directory..."

sudo mkdir -p "${APP_DIR}"

sudo chown "${DEPLOY_USER}:${DEPLOY_USER}" "${APP_DIR}"

sudo chmod 755 "${APP_DIR}"

echo "Configuring Docker access..."

if command -v docker >/dev/null 2>&1; then
    if getent group docker >/dev/null 2>&1; then
        sudo usermod -aG docker "${DEPLOY_USER}"
    fi
else
    echo "WARNING: Docker is not installed."
    echo "Install Docker before using the deployment user."
fi

echo "Configuring SSH daemon..."

SSHD_CONFIG="/etc/ssh/sshd_config"

sudo sed -i \
    's/^[#[:space:]]*PubkeyAuthentication.*/PubkeyAuthentication yes/' \
    "${SSHD_CONFIG}"

if ! sudo grep -qE '^[[:space:]]*PubkeyAuthentication[[:space:]]+yes' "${SSHD_CONFIG}"; then
    echo "PubkeyAuthentication yes" | sudo tee -a "${SSHD_CONFIG}" >/dev/null
fi

sudo systemctl restart sshd

echo
echo "======================================"
echo "Deployment user setup complete"
echo "======================================"
echo
echo "User:       ${DEPLOY_USER}"
echo "App dir:    ${APP_DIR}"
echo
echo "Test with:"
echo "ssh deploy@<SERVER_IP>"
echo
echo "IMPORTANT:"
echo "The deploy user must log in using the Jenkins SSH private key."
echo