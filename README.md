# elk-docker

[![Elastic Stack version](https://img.shields.io/badge/Elastic%20Stack-9.3.0-00bfb3?style=flat&logo=elastic-stack)](https://www.elastic.co/blog/category/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Single-node Elastic Stack on Docker Compose — fully automated, TLS everywhere, x-pack license patch included.

**Includes:** Elasticsearch · Kibana · Logstash · Fleet Server · Elastic Package Registry

**Optional (via profiles):** Metricbeat · Filebeat · Heartbeat

---

## Quick start

```sh
git clone https://github.com/FortyTwoM/elk-docker.git
cd elk-docker
cp .env.example .env   # set passwords
docker compose up -d --build
```

Open **<https://localhost:5601>** (accept the self-signed certificate).
Default credentials: `elastic` / `changeme`.

### With monitoring (Metricbeat, Filebeat, Heartbeat)

```sh
docker compose --profile monitoring up -d --build
```

### Using Make

```sh
make up          # core stack
make up-mon      # core + monitoring
make down        # stop all
make clean       # stop + remove volumes and images
make logs        # tail logs
make status      # show service health
```

Run `make` to see all available commands.

---

## How it works

On first `docker compose up --build`:

1. **tls** — generates X.509 certificates under `tls/certs/` via `elasticsearch-certutil`
2. **kibana-init** — generates Kibana encryption keys, injects the CA fingerprint for Fleet
3. **elasticsearch** — starts with the patched x-pack JAR (baked into the image at build time)
4. **setup** — creates Elasticsearch users and roles from passwords in `.env`
5. **kibana · logstash · package-registry · fleet-server** — start in dependency order

No manual steps required.

---

## Requirements

- [Docker Engine](https://docs.docker.com/get-started/get-docker/) 20.10+
- [Docker Compose](https://docs.docker.com/compose/install/) v2.0+
- 4 GB RAM recommended (2 GB minimum)

### Linux: vm.max_map_count

```sh
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.d/99-elasticsearch.conf
sudo sysctl --system
```

### Docker Desktop (Windows / macOS): data on an external drive

All persistent data lives in Docker **named volumes** inside Docker Desktop's virtual disk image.

To move everything to an external drive:

1. Docker Desktop → **Settings → Resources → Advanced → Disk image location**
2. Set the path, e.g. `E:\DockerDesktop`
3. **Apply & Restart**

> Bind-mounting external NTFS drives doesn't work for Elasticsearch — WSL2's NTFS layer lacks Unix file locking. Named volumes use ext4 inside the VM and work correctly.

---

## Ports

| Port  | Service                       | Bind        |
|-------|-------------------------------|-------------|
| 5601  | Kibana (HTTPS)                | 127.0.0.1   |
| 9200  | Elasticsearch HTTP (TLS)      | 127.0.0.1   |
| 9300  | Elasticsearch transport (TLS) | 127.0.0.1   |
| 8220  | Fleet Server                  | 0.0.0.0     |
| 8080  | Elastic Package Registry      | 127.0.0.1   |
| 5044  | Logstash Beats input          | 0.0.0.0     |
| 50000 | Logstash TCP input            | 0.0.0.0     |
| 9600  | Logstash monitoring API       | 0.0.0.0     |

Elasticsearch, Kibana, and Package Registry bind to `127.0.0.1` by default to prevent accidental exposure. To allow remote access, change the bind address in `docker-compose.yml` (e.g. `0.0.0.0:9200:9200`).

---

## Configuration

Config files are mounted read-only — edit locally, then restart the service.

| Component     | File                                     |
|---------------|------------------------------------------|
| Elasticsearch | `elasticsearch/config/elasticsearch.yml` |
| Kibana        | `kibana/config/kibana.yml`               |
| Logstash      | `logstash/config/logstash.yml`           |
| Pipeline      | `logstash/pipeline/logstash.conf`        |
| TLS instances | `tls/instances.yml`                      |

### Fleet and Package Registry

Fleet Server and the local Elastic Package Registry start automatically.
The CA fingerprint is injected by `kibana-init`, so Fleet appears healthy out of the box.

To use the public Elastic registry instead of the local one, remove `xpack.fleet.isAirGapped` and `xpack.fleet.registryUrl` from `kibana/config/kibana.yml`.

### Monitoring profile

The `monitoring` profile starts Metricbeat, Filebeat, and Heartbeat. Their configs are in `extensions/*/config/`. Passwords must be set in `.env`:

```ini
METRICBEAT_INTERNAL_PASSWORD='changeme'
FILEBEAT_INTERNAL_PASSWORD='changeme'
HEARTBEAT_INTERNAL_PASSWORD='changeme'
MONITORING_INTERNAL_PASSWORD='changeme'
BEATS_SYSTEM_PASSWORD='changeme'
```

---

## Initial setup

### Change passwords

Edit `.env` before the first run, or reset afterwards:

```sh
docker compose exec elasticsearch \
  bin/elasticsearch-reset-password --batch --user elastic
```

Update `.env`, then restart affected services:

```sh
docker compose up -d logstash kibana
```

### Send data to Logstash

```sh
cat /path/to/logfile.log | nc --send-only localhost 50000
```

Or load sample data from the Kibana home page.

---

## Operations

```sh
# Stop
docker compose down

# Remove all data (volumes)
docker compose down -v

# Rebuild after version change
docker compose build && docker compose up -d

# Regenerate TLS certificates
rm -rf tls/certs/*/
docker compose up tls && docker compose up -d

# Re-run user setup
docker compose up setup

# Regenerate Kibana encryption keys
docker compose run --rm kibana-init
docker compose restart kibana

# Reset password via API
curl -XPOST 'https://localhost:9200/_security/user/elastic/_password' \
  --cacert tls/certs/ca/ca.crt \
  -H 'Content-Type: application/json' \
  -u elastic:<current-password> \
  -d '{"password":"<new-password>"}'
```

> **Warning:** regenerating Kibana encryption keys invalidates previously encrypted saved objects.

---

## JVM tuning

| Service       | Variable       | Default |
|---------------|----------------|---------|
| Elasticsearch | `ES_JAVA_OPTS` | 512 MB  |
| Logstash      | `LS_JAVA_OPTS` | 256 MB  |

Example — 2 GB heap:

```yml
elasticsearch:
  environment:
    ES_JAVA_OPTS: -Xms2g -Xmx2g
```

---

## x-pack license patch

The patched `x-pack-core` JAR is compiled and baked into the Elasticsearch image at build time via a multi-stage `Dockerfile`. No runtime hacks.

After changing `ELASTIC_VERSION`:

```sh
docker compose build elasticsearch
docker compose up -d elasticsearch
```

See [`elasticsearch/crack/README.md`](elasticsearch/crack/README.md) for details.

---

## Troubleshooting

**Fleet Server shows "Unhealthy" / "Message Signing Key" error**

```sh
docker compose down
docker volume rm elk-docker_fleet-server-state
docker compose up -d
```

**Elasticsearch won't start on Linux** — check `vm.max_map_count` (see [Requirements](#linux-vmmax_map_count)).

**Revert to Basic license**

```sh
curl -XPOST 'https://localhost:9200/_license/start_basic?acknowledge=true' \
  --cacert tls/certs/ca/ca.crt \
  -u elastic:<password>
```

---

## Project structure

```
├── docker-compose.yml          Main stack definition
├── .env.example                Environment template
├── Makefile                    Shortcuts (make up, make clean, ...)
├── elasticsearch/
│   ├── Dockerfile              Multi-stage build with x-pack patch
│   ├── config/elasticsearch.yml
│   └── crack/                  License patch sources
├── kibana/
│   ├── Dockerfile
│   ├── config/kibana.yml
│   └── init-keys.sh            Encryption keys + CA fingerprint injection
├── logstash/
│   ├── Dockerfile
│   ├── config/logstash.yml
│   └── pipeline/logstash.conf
├── setup/                      User and role provisioning
├── tls/                        Certificate generation
│   └── instances.yml           Hostnames/IPs for certificates
└── extensions/
    ├── fleet/                  Fleet Server (always on)
    ├── metricbeat/             Stack & host monitoring   (profile: monitoring)
    ├── filebeat/               Docker log collection     (profile: monitoring)
    └── heartbeat/              Uptime checks             (profile: monitoring)
```

---

## License

[MIT](LICENSE)
