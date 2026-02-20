# Extensions

Optional components activated via Docker Compose profiles.

| Extension  | Profile      | Description                              |
|------------|--------------|------------------------------------------|
| Metricbeat | `monitoring` | Host, Docker, and stack metrics          |
| Filebeat   | `monitoring` | Docker container log collection          |
| Heartbeat  | `monitoring` | Uptime monitoring (HTTP, ICMP)           |

Fleet Server and the Elastic Package Registry are part of the core stack and always start.

## Usage

```sh
docker compose --profile monitoring up -d --build
```

See each extension's `README.md` for configuration details.
