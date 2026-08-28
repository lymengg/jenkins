# Jenkins Agents

This guide covers setting up Jenkins build agents using the recommended, most secure method (**SSH launch**), with fallback options for network-restricted environments.

## Recommended method: SSH launch

The Jenkins controller connects **outbound** to the agent over SSH (port 22). This is the best-practice approach for modern Jenkins deployments.

**Why SSH is preferred:**

- **Key-based authentication** — strong, standard, revocable per-agent
- **No inbound port on the controller** — reduces attack surface (no JNLP port 50000 needed)
- **Per-agent key rotation** — one keypair per agent, easy to revoke individually
- **Integrates with existing SSH/bastion infrastructure** — familiar to ops teams
- **Works across Linux and Windows** (Windows agents via OpenSSH server)

## Prerequisites

- A running Jenkins controller (see [README](../README.md))
- A separate Linux machine (VM/container/bare metal) to act as the agent
- Network reachability from the controller → agent on port 22
- Root/sudo access on the agent host (to create the user and install Java)

## Setup overview

1. **Prepare the agent host** — run `scripts/setup-agent.sh` on the agent
2. **Generate an SSH keypair** — on your admin machine (not the agent)
3. **Install the public key** on the agent
4. **Add the private key** as a Jenkins credential
5. **Register the node** in the Jenkins UI
6. **Verify** the agent connects and runs a build

## Step 1 — Prepare the agent host

Run the provided setup script on the agent host (as root/sudo). It is idempotent and safe to re-run.

```bash
# Copy the script to the agent host, then:
sudo ./scripts/setup-agent.sh
```

The script:
- Creates a dedicated, low-privilege `jenkins` user (password locked, key-only login)
- Installs Java 21 (Jenkins 2.568+ requires JDK 21), idempotently
- Creates `~jenkins/.ssh` with correct ownership (`jenkins`) and permissions (700 dir, 600 `authorized_keys`)
- Verifies Java, the user, and the `.ssh` directory
- Prints the remaining steps (key generation, Jenkins UI registration)

Options:

```bash
sudo ./scripts/setup-agent.sh --remote-root /opt/jenkins
sudo ./scripts/setup-agent.sh --user jenkins
sudo ./scripts/setup-agent.sh --java-package openjdk-21-jre-headless
sudo ./scripts/setup-agent.sh --help
```

> **Note:** The script does **not** generate, accept, or store SSH keys, and does **not** modify `sshd` configuration. SSH hardening is the responsibility of your infra/security team (see [Security hardening](#security-hardening)).

## Step 2 — Generate an SSH keypair

Run this on your **admin/laptop machine** (NOT on the agent host):

```bash
ssh-keygen -t ed25519 -f ~/.ssh/jenkins-agent-key -C "jenkins-agent@<agent-hostname>"
```

This produces:
- `~/.ssh/jenkins-agent-key` — **private key** (keep secret; goes into Jenkins)
- `~/.ssh/jenkins-agent-key.pub` — **public key** (goes onto the agent)

Best practice: generate **one keypair per agent** so each can be revoked independently. Use **ed25519** (modern, fast, secure).

## Step 3 — Install the public key on the agent

From your admin machine:

```bash
ssh-copy-id -i ~/.ssh/jenkins-agent-key.pub jenkins@<agent-hostname>
```

Or manually, append the public key to this file on the agent:

```
/home/jenkins/.ssh/authorized_keys
```

The file must be owned by `jenkins` with mode `600`, and `/home/jenkins/.ssh` must be mode `700` (the setup script already sets these — re-run it if needed).

## Step 4 — Add the private key as a Jenkins credential

1. Go to **Manage Jenkins → Credentials → System → Global credentials → Add credentials**
2. Configure:

| Field | Value |
|---|---|
| Kind | SSH Username with private key |
| ID | `jenkins-agent-ssh` |
| Username | `jenkins` |
| Enter directly | Paste contents of `~/.ssh/jenkins-agent-key` (private key) |

3. Save

## Step 5 — Register the agent node in Jenkins

1. Go to **Manage Jenkins → Nodes → New node**
2. Node name: e.g. `linux-agent-01`
3. Type: **Permanent Agent** → Create
4. Configure:

| Field | Value |
|---|---|
| Remote root directory | `/home/jenkins` |
| Labels | `linux` (add more, e.g. `docker`, `python`) |
| Usage | Use this node as much as possible |
| Launch method | **Launch agents via SSH** |
| Host | `<agent-hostname-or-ip>` |
| Credentials | `jenkins-agent-ssh` (from Step 4) |
| Host Key Verification Strategy | **Known hosts file** (preferred) or **Manually trusted** (never "Non verifying") |

5. Save. Jenkins will connect over SSH and provision the agent.

## Step 6 — Verify

- The node should show a green **"Connected"** icon in **Manage Jenkins → Nodes**.
- Test with a pipeline:

```groovy
pipeline {
    agent { label 'linux' }
    stages {
        stage('Agent check') {
            steps {
                sh 'echo "Running on $(hostname) with $(java -version 2>&1 | head -1)"'
            }
        }
    }
}
```

## Security hardening

The setup script intentionally does **not** modify `sshd` configuration — that is the responsibility of your infra/security team. Recommended hardening (apply via your standard config management):

- **Disable SSH password authentication**: `PasswordAuthentication no`
- **Disable root login over SSH**: `PermitRootLogin no`
- **Restrict SSH (port 22) to the Jenkins controller IP only** (firewall):
  ```bash
  # ufw example
  ufw allow from <controller-ip> to any port 22
  # firewalld example
  firewall-cmd --permanent --add-rich-rule='rule family="ipv4" source address="<controller-ip>" port port=22 protocol=tcp accept'
  firewall-cmd --reload
  ```
- **Use Host Key Verification Strategy = "Known hosts file"** in Jenkins (prevents man-in-the-middle attacks)
- **Rotate the agent SSH key** if the agent is decommissioned or compromised
- **Run builds as the dedicated low-privilege `jenkins` user** (set up by the script)
- **Keep Java and the OS patched**

## Fallback: WebSocket inbound (agent behind NAT)

Use this when the controller **cannot** reach the agent over SSH (e.g. agent is behind NAT/firewall). The WebSocket method tunnels over the existing HTTPS port (443), so **no extra inbound port is needed on the controller**.

### Controller configuration

1. Go to **Manage Jenkins → Global Security → Agents**
2. Set **TCP port for JNLP agents** to **Disable** (use WebSocket instead)
3. Save

### Register the node

1. **Manage Jenkins → Nodes → New node**
2. Type: **Permanent Agent** → Create
3. Launch method: **Launch agent by connecting it to the controller**
4. Save (note the agent secret shown on the node page)

### Start the agent

On the agent host:

```bash
curl -sO https://<controller-host>/jnlp/jnlp-cli/agent.jar
java -jar agent.jar \
  -url https://<controller-host> \
  -secret <agent-secret> \
  -name <node-name> \
  -webSocket
```

The `-webSocket` flag tunnels over HTTPS/443. For production, run the agent as a systemd service so it restarts automatically.

## Legacy: JNLP/TCP (port 50000) — discouraged

The classic JNLP/TCP method (agent connects to controller port 50000) is **discouraged**:

- Auth uses a shared **agent secret** stored on the controller (harder to rotate per-agent)
- Requires an **inbound port (50000)** on the controller (extra attack surface)
- Weakest of the three methods

If you have a legacy reason to use it, the port mapping in `docker-compose.yml` is **disabled by default**. Re-enable it by setting `JENKINS_AGENT_PORT_ENABLED=true` in your `.env` file (see `.env.example`).

## Method comparison

| Method | Direction | Auth | Inbound port on controller | Security | When to use |
|---|---|---|---|---|---|
| **SSH** | controller → agent (22) | SSH key | none | **best** | Default — controller can reach agent |
| **WebSocket** | agent → controller (443) | agent secret | none (reuses 443) | good | Agent behind NAT, controller can't reach it |
| JNLP/TCP | agent → controller (50000) | agent secret | yes (50000) | weakest | Legacy only — avoid |

## Troubleshooting

### Agent shows "Offline" / not connecting

- Verify the controller can reach the agent on port 22: `ssh jenkins@<agent-host>` from the controller host
- Check the agent's `authorized_keys` contains the public key (Step 3)
- Verify file permissions: `.ssh` = 700, `authorized_keys` = 600, both owned by `jenkins`
- Check the Jenkins node log: **Manage Jenkins → Nodes → <node> → Logs**
- Ensure `Host Key Verification Strategy` is not "Non verifying" and the host key is in the controller's known_hosts

### "Java not found" / wrong Java version

- Jenkins 2.568+ requires Java 21. Re-run `sudo ./scripts/setup-agent.sh` to install it
- Verify: `java -version` on the agent (run as the `jenkins` user)

### Permission denied on agent home

- Ensure the agent home is owned by `jenkins`: `chown -R jenkins:jenkins /home/jenkins`
- Re-run the setup script to fix `.ssh` permissions

### SSH key rejected

- Confirm you added the **public** key (`.pub`) to the agent, not the private key
- Confirm you pasted the **private** key into Jenkins credentials, not the public key
- Generate a new keypair if the key may have been exposed

## Related

- [Architecture](architecture.md) — network and security model
- [Operations](operations.md) — daily operations and environment variables
- `scripts/setup-agent.sh` — agent host preparation script
