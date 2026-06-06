# HomeServerLab

Command center for a Raspberry Pi 4 homelab. This stack does not run product
services such as a wiki, smart-home server, media server, or NAS. It provides a
Tailscale-only entry point, service navigation, and observability for services
that are deployed separately on the same Docker host.

## What Is Included

- Homepage as the main navigation and live status page.
- Caddy as the only HTTP entry point, bound to the Raspberry Pi Tailscale IP.
- Prometheus, node_exporter, cAdvisor, and Glances for host/container metrics.
- Grafana with a provisioned `Homelab Overview` dashboard.
- Textfile metrics for Raspberry Pi CPU temperature and Docker Compose project
  health.
- Optional Portainer admin UI behind the `admin` compose profile.

## Network Model

Caddy publishes only on `${TAILSCALE_IP}:${CADDY_HTTP_PORT}`. All other services
use `expose` and are reachable only from Docker networks.

External application stacks should stay in their own compose projects. To expose
one through the command center:

1. Attach the application's web container to the external Docker network
   `homelab_frontend`.
2. Add a `http://service.${BASE_DOMAIN}` route in `caddy/Caddyfile`.
3. Add a Homepage link in `homepage/services.yaml`.
4. Add the compose project name to `HOMELAB_EXPECTED_COMPOSE_PROJECTS` in `.env`
   if it should be treated as mandatory by the metrics script.

Example network block for a separate compose project:

```yaml
networks:
  homelab_frontend:
    external: true
```

Example service attachment:

```yaml
services:
  wiki:
    networks:
      - default
      - homelab_frontend
```

## First Run

```bash
cp .env.example .env
chmod +x scripts/*.sh
docker compose up -d
```

For the optional admin UI:

```bash
docker compose --profile admin up -d portainer
```

## Textfile Metrics

node_exporter reads `.prom` files from `node-exporter/textfile`. Install a host
timer or cron job that periodically runs:

```bash
/opt/homelab/scripts/update-node-exporter-textfiles.sh
```

If the repository lives somewhere else, set `HOMELAB_TEXTFILE_DIR` to the
absolute path of the mounted `node-exporter/textfile` directory.

Example cron entry:

```cron
* * * * * cd /opt/homelab && ./scripts/update-node-exporter-textfiles.sh
```

Or install the included systemd units:

```bash
sudo cp systemd/homelab-textfile-metrics.* /etc/systemd/system/
sudo systemctl daemon-reload
sudo systemctl enable --now homelab-textfile-metrics.timer
```

The compose exporter groups containers by Docker Compose labels:

- `homelab_compose_project_up{project="..."}` is `1` only when all known
  containers in the project are running and healthy.
- `homelab_compose_project_degraded{project="..."}` is `1` when a project has
  stopped, starting, unhealthy, or missing containers.
- `homelab_compose_service_up{project="...",service="..."}` tracks compose
  services inside a project.

## Useful Additions

- Tailscale SSH and ACL tags for controlled admin access without publishing SSH.
- Restic or BorgBackup for encrypted backups to another disk or remote storage.
- Watchtower or Renovate for image update visibility. Prefer manual rollout on
  a Raspberry Pi if uptime matters.
- Uptime Kuma as an external monitored service if you want user-facing checks
  and notifications. Keep it outside this command-center compose.
- Loki + Promtail or Alloy for logs if metrics are not enough.
- smartctl exporter if the Pi uses USB/SATA storage with SMART support.
- blackbox_exporter for HTTP/TCP checks of services exposed through Caddy.
- Netdata if you want a very detailed live hardware console, again as a separate
  optional service.
