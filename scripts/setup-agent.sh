#!/bin/bash
set -euo pipefail

# Jenkins Agent Host Setup Script (SSH launch method)
#
# Prepares a Linux host to act as a Jenkins build agent that the controller
# connects to over SSH. This is the recommended, most secure agent method:
#   - Key-based authentication (no shared JNLP secret)
#   - No inbound port required on the Jenkins controller
#   - Per-agent key rotation and revocation
#
# This script is idempotent and safe to re-run. It does NOT generate, accept,
# or store SSH keys, and it does NOT modify sshd configuration (SSH hardening
# is the responsibility of your infra/security team - see the printed notes).
#
# What this script does:
#   1. Creates a dedicated, low-privilege `jenkins` user (no sudo, no password)
#   2. Installs Java 21 (Jenkins 2.568+ requires JDK 21), idempotently
#   3. Creates ~jenkins/.ssh with correct ownership and permissions
#   4. Verifies Java, the user, and the .ssh directory
#   5. Prints step-by-step instructions for key generation, Jenkins credential
#      setup, node registration in the Jenkins UI, and verification
#
# Usage:
#   sudo ./scripts/setup-agent.sh
#   sudo ./scripts/setup-agent.sh --java-package openjdk-21-jre-headless
#   sudo ./scripts/setup-agent.sh --remote-root /home/jenkins
#   sudo ./scripts/setup-agent.sh --help
#
# Requirements:
#   - Run as root (or with sudo) to create users and install packages
#   - One of: apt-get, dnf, or yum package manager
#   - systemd-based Linux (for sshd status check)

set -euo pipefail

# ---------------------------------------------------------------------------
# Defaults
# ---------------------------------------------------------------------------
AGENT_USER="${AGENT_USER:-jenkins}"
REMOTE_ROOT="${REMOTE_ROOT:-/home/${AGENT_USER}}"
JAVA_PACKAGE_APT="${JAVA_PACKAGE_APT:-openjdk-21-jre-headless}"
JAVA_PACKAGE_DNF="${JAVA_PACKAGE_DNF:-java-21-openjdk-headless}"
JAVA_MIN_VERSION="${JAVA_MIN_VERSION:-21}"

# ---------------------------------------------------------------------------
# Helpers
# ---------------------------------------------------------------------------
log()   { echo "[setup-agent] $*"; }
warn()  { echo "[setup-agent] WARN: $*" >&2; }
die()   { echo "[setup-agent] ERROR: $*" >&2; exit 1; }

print_help() {
    cat <<'EOF'
Jenkins Agent Host Setup Script (SSH launch method)

Prepares a Linux host to be a Jenkins build agent connected via SSH.

Usage:
  sudo ./scripts/setup-agent.sh [options]

Options:
  --java-package <pkg>   Override the Java package name to install
  --remote-root <dir>    Agent home directory (default: /home/jenkins)
  --user <name>          Agent system user (default: jenkins)
  --help                 Show this help and exit

Environment variables (override defaults):
  AGENT_USER             Agent system user (default: jenkins)
  REMOTE_ROOT            Agent home directory (default: /home/jenkins)
  JAVA_PACKAGE_APT       apt package name (default: openjdk-21-jre-headless)
  JAVA_PACKAGE_DNF       dnf/yum package name (default: java-21-openjdk-headless)
  JAVA_MIN_VERSION       Minimum Java major version required (default: 21)

Notes:
  - This script does NOT generate or store SSH keys. It prints instructions
    for generating an ed25519 keypair on your admin machine and configuring
    authorized_keys on the agent.
  - This script does NOT modify sshd config. SSH hardening (disabling
    password auth, disabling root login, firewall rules) is the
    responsibility of your infra/security team. Recommendations are printed
    at the end.
  - Idempotent: safe to re-run.

Examples:
  sudo ./scripts/setup-agent.sh
  sudo ./scripts/setup-agent.sh --remote-root /opt/jenkins
EOF
}

# ---------------------------------------------------------------------------
# Parse args
# ---------------------------------------------------------------------------
while [[ $# -gt 0 ]]; do
    case "$1" in
        --help|-h) print_help; exit 0 ;;
        --java-package)
            [[ $# -ge 2 ]] || die "--java-package requires a value"
            JAVA_PACKAGE_APT="$2"; JAVA_PACKAGE_DNF="$2"; shift 2 ;;
        --remote-root) [[ $# -ge 2 ]] || die "--remote-root requires a value"; REMOTE_ROOT="$2"; shift 2 ;;
        --user)        [[ $# -ge 2 ]] || die "--user requires a value"; AGENT_USER="$2"; shift 2 ;;
        *) die "Unknown option: $1 (try --help)" ;;
    esac
done

# ---------------------------------------------------------------------------
# Preflight checks
# ---------------------------------------------------------------------------
[[ "$(id -u)" -eq 0 ]] || die "Must run as root (use sudo). This script creates a user and installs packages."

if command -v apt-get >/dev/null 2>&1; then
    PM="apt"
elif command -v dnf >/dev/null 2>&1; then
    PM="dnf"
elif command -v yum >/dev/null 2>&1; then
    PM="yum"
else
    die "No supported package manager found (apt-get, dnf, yum). Install Java 21 manually and re-run with --skip-java (not yet implemented)."
fi
log "Detected package manager: ${PM}"

# ---------------------------------------------------------------------------
# 1. Create dedicated agent user (idempotent)
# ---------------------------------------------------------------------------
log "Ensuring agent user '${AGENT_USER}' exists..."
if id "${AGENT_USER}" >/dev/null 2>&1; then
    log "User '${AGENT_USER}' already exists."
else
    useradd --create-home --home-dir "${REMOTE_ROOT}" --shell /bin/bash "${AGENT_USER}"
    # Lock password login (key-only). Operator can unlock if needed.
    passwd --lock "${AGENT_USER}" >/dev/null
    log "Created user '${AGENT_USER}' with home '${REMOTE_ROOT}' (password locked)."
fi

# Ensure home dir exists and is owned by the agent user
mkdir -p "${REMOTE_ROOT}"
chown "${AGENT_USER}:${AGENT_USER}" "${REMOTE_ROOT}"
chmod 755 "${REMOTE_ROOT}"

# ---------------------------------------------------------------------------
# 2. Install Java (idempotent)
# ---------------------------------------------------------------------------
java_major() {
    # Print the major version of the default java, or empty if not installed
    if command -v java >/dev/null 2>&1; then
        java -version 2>&1 | awk -F\" '/version/ {print $2}' | head -1 \
            | sed -E 's/^([0-9]+)\..*/\1/' | sed -E 's/^1\.([0-9]+)$/\1/'
    fi
}

CURRENT_JAVA_MAJOR="$(java_major || true)"
if [[ -n "${CURRENT_JAVA_MAJOR}" && "${CURRENT_JAVA_MAJOR}" -ge "${JAVA_MIN_VERSION}" ]]; then
    log "Java ${CURRENT_JAVA_MAJOR} already installed (>= ${JAVA_MIN_VERSION}). Skipping install."
else
    if [[ -n "${CURRENT_JAVA_MAJOR}" ]]; then
        log "Installed Java ${CURRENT_JAVA_MAJOR} is older than required ${JAVA_MIN_VERSION}. Installing Java ${JAVA_MIN_VERSION}..."
    else
        log "Java not found. Installing Java ${JAVA_MIN_VERSION}..."
    fi
    case "${PM}" in
        apt)
            apt-get update -y
            DEBIAN_FRONTEND=noninteractive apt-get install -y "${JAVA_PACKAGE_APT}"
            ;;
        dnf)
            dnf install -y "${JAVA_PACKAGE_DNF}"
            ;;
        yum)
            yum install -y "${JAVA_PACKAGE_DNF}"
            ;;
    esac
fi

# Re-check after install
CURRENT_JAVA_MAJOR="$(java_major || true)"
[[ -n "${CURRENT_JAVA_MAJOR}" && "${CURRENT_JAVA_MAJOR}" -ge "${JAVA_MIN_VERSION}" ]] \
    || die "Java >= ${JAVA_MIN_VERSION} is required but could not be verified (got: '${CURRENT_JAVA_MAJOR}'). Install Java ${JAVA_MIN_VERSION} manually and re-run."
log "Java verified: version ${CURRENT_JAVA_MAJOR} (java -version follows)"
java -version

# ---------------------------------------------------------------------------
# 3. Create .ssh directory with correct permissions (idempotent)
# ---------------------------------------------------------------------------
SSH_DIR="${REMOTE_ROOT}/.ssh"
AUTH_KEYS="${SSH_DIR}/authorized_keys"

log "Ensuring ${SSH_DIR} exists with correct ownership and permissions..."
sudo -u "${AGENT_USER}" mkdir -p "${SSH_DIR}"
chown -R "${AGENT_USER}:${AGENT_USER}" "${SSH_DIR}"
chmod 700 "${SSH_DIR}"

# Create an empty authorized_keys file if missing (operator will populate it)
if [[ ! -f "${AUTH_KEYS}" ]]; then
    sudo -u "${AGENT_USER}" touch "${AUTH_KEYS}"
fi
chown "${AGENT_USER}:${AGENT_USER}" "${AUTH_KEYS}"
chmod 600 "${AUTH_KEYS}"

# ---------------------------------------------------------------------------
# 4. Verify sshd is running (informational; not modified)
# ---------------------------------------------------------------------------
if command -v systemctl >/dev/null 2>&1; then
    if systemctl is-active --quiet sshd 2>/dev/null || systemctl is-active --quiet ssh 2>/dev/null; then
        log "sshd service is running."
    else
        warn "sshd/ssh service does not appear to be running. Start it with: systemctl start sshd (or 'ssh' on Debian/Ubuntu)."
    fi
else
    warn "systemctl not found; cannot verify sshd status. Ensure SSH is running on port 22."
fi

# ---------------------------------------------------------------------------
# 5. Print next steps
# ---------------------------------------------------------------------------
AGENT_HOSTNAME="$(hostname -f 2>/dev/null || hostname || echo '<agent-host>')"
CONTROLLER_HINT="jenkins.example.com"  # placeholder; operator replaces

cat <<EOF

==============================================================================
 Jenkins Agent Setup - Next Steps (SSH launch method)
==============================================================================

The agent host is prepared. Complete the remaining steps below.

STEP 1: Generate an SSH keypair (on your ADMIN machine, NOT on the agent)
--------------------------------------------------------------------------
Run this on your admin/laptop machine (NOT on the agent host):

    ssh-keygen -t ed25519 -f ~/.ssh/jenkins-agent-key -C "jenkins-agent@${AGENT_HOSTNAME}"

This produces:
  - ~/.ssh/jenkins-agent-key       (PRIVATE - keep secret, goes into Jenkins)
  - ~/.ssh/jenkins-agent-key.pub   (PUBLIC  - goes onto the agent host)

Best practice: generate ONE keypair per agent so each can be revoked
independently. Use ed25519 (modern, fast, secure).

STEP 2: Install the public key on this agent host
-------------------------------------------------
From your admin machine, copy the public key to the agent:

    ssh-copy-id -i ~/.ssh/jenkins-agent-key.pub ${AGENT_USER}@${AGENT_HOSTNAME}

Or manually, append the public key to this file on the agent:

    ${AUTH_KEYS}

The file must be owned by ${AGENT_USER} with mode 600, and ${SSH_DIR}
must be mode 700 (this script already set those - re-run if needed).

STEP 3: Add the private key as a Jenkins credential
---------------------------------------------------
In the Jenkins UI:
  1. Manage Jenkins > Credentials > System > Global credentials > Add credentials
  2. Kind:       SSH Username with private key
  3. ID:         jenkins-agent-ssh
  4. Username:   ${AGENT_USER}
  5. Enter directly: paste the contents of ~/.ssh/jenkins-agent-key (PRIVATE key)
  6. Save

STEP 4: Register the agent node in Jenkins
------------------------------------------
In the Jenkins UI:
  1. Manage Jenkins > Nodes > New node
  2. Node name: e.g. linux-agent-01
  3. Type: Permanent Agent > Create
  4. Configure:
       Remote root directory:      ${REMOTE_ROOT}
       Labels:                      linux (add more, e.g. docker, python)
       Usage:                       Use this node as much as possible
       Launch method:               Launch agents via SSH
       Host:                        ${AGENT_HOSTNAME}
       Credentials:                 jenkins-agent-ssh (from STEP 3)
       Host Key Verification:       Known hosts file  (preferred)
                                    (or "Manually trusted" - NEVER "Non verifying")
  5. Save. Jenkins will connect over SSH and provision the agent.

STEP 5: Verify
--------------
- The node should show a green "Connected" icon in Manage Jenkins > Nodes.
- Test with a pipeline:

      pipeline {
          agent { label 'linux' }
          stages {
              stage('Agent check') {
                  steps {
                      sh 'echo "Running on \$(hostname) with \$(java -version 2>&1 | head -1)"'
                  }
              }
          }
      }

==============================================================================
 Security hardening (deferred to your infra/security team)
==============================================================================
This script did NOT modify sshd config. The following are recommendations
for your infra team to apply (out of scope for this script):

  - Disable SSH password authentication:
        PasswordAuthentication no
  - Disable root login over SSH:
        PermitRootLogin no
  - Restrict SSH (port 22) to the Jenkins controller IP only (firewall:
        ufw allow from <controller-ip> to any port 22
        # or firewalld/iptables equivalent)
  - Use Host Key Verification Strategy = "Known hosts file" in Jenkins
        (prevents man-in-the-middle attacks)
  - Rotate the agent SSH key if the agent is decommissioned or compromised
  - Run builds as the dedicated low-privilege '${AGENT_USER}' user (already set up)
  - Keep Java and the OS patched

==============================================================================
 Setup summary
==============================================================================
  Agent user:           ${AGENT_USER}
  Agent home:           ${REMOTE_ROOT}
  SSH directory:        ${SSH_DIR}  (mode 700, owned by ${AGENT_USER})
  Authorized keys file: ${AUTH_KEYS} (mode 600, owned by ${AGENT_USER})
  Java:                 version ${CURRENT_JAVA_MAJOR}
  Agent hostname:       ${AGENT_HOSTNAME}
==============================================================================
EOF

log "Done. Follow the printed next steps to complete agent registration in Jenkins."
