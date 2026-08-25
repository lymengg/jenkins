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
    ↓
Reverse Proxy (recommended for production)
    ↓
Jenkins :8080 (HTTP)
    ↓
Jenkins Agent Port :50000 (JNLP)
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

- Minimal exposed ports (8080 for HTTP, 50000 for agents)
- Reverse proxy recommended for TLS termination
- Firewall rules should restrict access to Jenkins ports

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
- Multi-node Jenkins cluster
- Monitoring and alerting (Prometheus/Grafana)
- Log aggregation (ELK/Loki)
- TLS termination via reverse proxy (nginx/traefik)
- Automated scheduled backups via cron/systemd timer
