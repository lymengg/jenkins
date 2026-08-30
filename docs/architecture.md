# Architecture

## Overview

This repository provides a production-oriented Jenkins deployment using Docker Compose. Jenkins version and infrastructure are tracked in Git; plugins and configuration are managed via the Jenkins UI and persisted in a Docker volume.

## Components

### Jenkins Controller

- Official `jenkins/jenkins` LTS image (no custom build)
- Pinned version for reproducibility (overridable via `JENKINS_IMAGE_TAG`)
- Plugins and configuration managed via Jenkins UI (persisted in volume)

### Data Flow

```
Git Repository
    ↓
docker-compose.yml (image tag + infrastructure)
    ↓
Jenkins Container (official jenkins/jenkins image)
    ↓
Persistent Volume (jenkins_home: plugins, config, jobs, credentials)
```

### What is Tracked Where

| Artifact | Tracked In | Reason |
|----------|-----------|--------|
| Jenkins version + JDK | Git (`.env`, `docker-compose.yml`) | Reproducible upgrades/patches |
| Infrastructure (ports, limits, health) | Git (`docker-compose.yml`) | Reproducible deployments |
| Backup/restore/health scripts | Git (`scripts/`) | Operational reproducibility |
| Plugins | Docker volume + backups | UI-managed, Jenkins prompts for updates |
| Jobs, credentials, config | Docker volume + backups | UI-managed, captured by backup.sh |

### Persistent Storage

- Jenkins home directory is persisted in a Docker named volume
- Backups are stored in the `backup/` directory
- No Jenkins data is stored in the container filesystem

### Network Architecture

```
Internet
    ↓ (ports 80/443)
Caddy Reverse Proxy (automatic HTTPS via Let's Encrypt)
    ↓ (Docker network: jenkins)
Jenkins Controller :8080 (HTTP, internal only)

Build agents (recommended: SSH launch method)
    Controller ──SSH:22──> Agent host(s)
    (no inbound port required on the controller)

Fallback: WebSocket inbound (agent behind NAT)
    Agent ──HTTPS:443──> Controller (tunnels over existing TLS port)

Legacy (discouraged): JNLP/TCP :50000
    Agent ──TCP:50000──> Controller (opt-in, disabled by default)
```

## Security Model

### Container Security

- No Docker socket mounted (use dedicated build agents)
- Least privilege principle
- No unnecessary Linux capabilities
- Resource limits enforced via Docker Compose (`deploy.resources`)

### Access Control

- Admin user created via Jenkins setup wizard on first launch
- Authorization strategy configured via Jenkins UI
- API tokens for programmatic access

### Network Security

- Minimal exposed ports (Caddy publishes 80/443; Jenkins 8080 is internal to Docker network only)
- Caddy provides automatic TLS certificate management via Let's Encrypt
- Jenkins is not directly accessible from the public network
- Firewall rules should restrict access to SSH (22) only; 80/443 are handled by Caddy
- **Build agents**: prefer the SSH launch method (controller connects to agent on :22, no inbound port on controller). See [Agents](agents.md) for details.
- **WebSocket inbound** is the recommended fallback when the controller cannot reach the agent (tunnels over :443, no extra inbound port).
- **JNLP/TCP :50000** is legacy and discouraged; opt in via a `docker-compose.override.yml` (gitignored) that maps the port — see `docker-compose.yml` and [Agents](agents.md) for details.

## Build Agents

Build agents are separate hosts that execute Jenkins jobs. The controller dispatches builds to agents based on labels.

- **Recommended launch method**: SSH (controller → agent on :22, key-based auth, no inbound controller port). See [Agents](agents.md) for the full setup guide and `scripts/setup-agent.sh` for host preparation.
- **Fallback**: WebSocket inbound (for agents behind NAT; reuses :443, no extra controller port).
- **Legacy**: JNLP/TCP :50000 (discouraged; opt in via `docker-compose.override.yml`).
- Agents run as a dedicated low-privilege user (`jenkins`) created by `scripts/setup-agent.sh`.
- SSH hardening (disable password auth, restrict SSH to controller IP) is the responsibility of the infra/security team — see [Agents > Security hardening](agents.md#security-hardening).

## Deployment Environments

### Development

- Single Jenkins instance
- Local Docker environment
- Manual configuration via UI

### Staging

- Mirrors production configuration
- Used for testing upgrades
- Automated testing of backups

### Production

- Regular backups to external storage
- Health monitoring
- Documented upgrade procedures

## Disaster Recovery

### Backup Strategy

- Regular backups of entire Jenkins home (plugins, config, jobs, credentials)
- Timestamped backup files
- Retention policy for old backups
- External storage recommended

### Recovery Process

1. Provision new server
2. Install Docker and dependencies
3. Clone repository
4. Start Jenkins: `docker compose up -d`
5. Restore backup
6. Verify functionality

## Future Enhancements

- External secret management integration (Vault, AWS Secrets Manager)
- Monitoring and alerting (Prometheus/Grafana)
- Log aggregation (ELK/Loki)
- Automated scheduled backups via cron/systemd timer
