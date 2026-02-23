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

1. **tls** — generates X.509 certificates under `tls/certs/` via `elasticsearch-certutil`; if `FLEET_EXTERNAL_HOST` is set, automatically adds it to the certificate SANs
2. **kibana-init** — copies `kibana.yml` template into a Docker volume, generates encryption keys, injects CA fingerprint, and adds external URLs if `FLEET_EXTERNAL_HOST` is set
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

| Port  | Service                       | Bind      |
|-------|-------------------------------|-----------|
| 9200  | Elasticsearch HTTP (TLS)      | 0.0.0.0   |
| 9300  | Elasticsearch transport (TLS) | 127.0.0.1 |
| 5601  | Kibana (HTTPS)                | 0.0.0.0   |
| 8220  | Fleet Server (HTTPS)          | 0.0.0.0   |
| 8080  | Elastic Package Registry      | 127.0.0.1 |
| 5044  | Logstash Beats input          | 0.0.0.0   |
| 50000 | Logstash TCP input            | 0.0.0.0   |
| 9600  | Logstash monitoring API       | 127.0.0.1 |

Package Registry and Logstash monitoring API bind to `127.0.0.1` (local-only). To restrict other services, prefix the port with `127.0.0.1:` in `docker-compose.yml` (e.g. `127.0.0.1:9200:9200`).

---

## Configuration

Config files are mounted read-only — edit locally, then restart the service.

| Component     | File                                     | Notes                                                |
|---------------|------------------------------------------|------------------------------------------------------|
| Elasticsearch | `elasticsearch/config/elasticsearch.yml` |                                                      |
| Kibana        | `kibana/config/kibana.yml`               | Template — `kibana-init` generates the working copy  |
| Logstash      | `logstash/config/logstash.yml`           |                                                      |
| Pipeline      | `logstash/pipeline/logstash.conf`        |                                                      |
| TLS instances | `tls/instances.yml`                      | External IP added automatically from `FLEET_EXTERNAL_HOST` |

### Fleet and Package Registry

Fleet Server and the local Elastic Package Registry start automatically.
The CA fingerprint is injected by `kibana-init`, so Fleet appears healthy out of the box.

To use the public Elastic registry instead of the local one, remove `xpack.fleet.isAirGapped` and `xpack.fleet.registryUrl` from `kibana/config/kibana.yml`.

### Connecting external Elastic Agents

By default Fleet Server and Elasticsearch URLs use Docker-internal names (`fleet-server:8220`, `elasticsearch:9200`). External agents can't resolve them.

**Step 1.** Set your Docker host's IP (or hostname) in `.env`:

```ini
FLEET_EXTERNAL_HOST=192.168.1.100
```

**Step 2.** Regenerate certs and restart:

```sh
make certs
docker compose up -d --build
```

Everything happens automatically:
- **tls** adds the IP to the Elasticsearch and Fleet Server certificates (SAN)
- **kibana-init** replaces internal Docker hostnames with external URLs, injects the CA fingerprint and embeds the full CA certificate into the Fleet output
- Kibana UI will show the external URL in the enrollment command

**Step 3.** Copy `tls/certs/ca/ca.crt` to the agent host and run the enrollment script.

Get the enrollment token from Kibana: **Fleet → Add agent → select policy → copy token**.

**Linux / macOS:**

```sh
sudo ./scripts/install-agent.sh \
  --url https://192.168.1.100:8220 \
  --token <TOKEN_FROM_KIBANA> \
  --ca /path/to/ca.crt
```

**Windows** (elevated PowerShell):

```powershell
.\scripts\install-agent.ps1 `
  -FleetUrl "https://192.168.1.100:8220" `
  -Token "<TOKEN_FROM_KIBANA>" `
  -CaCertPath "C:\path\to\ca.crt"
```

The scripts automatically install the CA into the OS trust store — this is **required** for Elastic Defend (endpoint-security) to work with self-signed certificates.

### Monitoring profile

The `monitoring` profile starts Metricbeat, Filebeat, and Heartbeat. Their configs are in `extensions/*/config/`. Passwords must be set in `.env`:

```ini
METRICBEAT_INTERNAL_PASSWORD=changeme
FILEBEAT_INTERNAL_PASSWORD=changeme
HEARTBEAT_INTERNAL_PASSWORD=changeme
MONITORING_INTERNAL_PASSWORD=changeme
BEATS_SYSTEM_PASSWORD=changeme
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

# Regenerate TLS certificates (also resets Kibana config to pick up new CA fingerprint)
make certs
docker compose up -d --build

# Re-run user setup
docker compose up setup

# Regenerate Kibana encryption keys (deletes the working config so init re-seeds from template)
docker volume rm $(docker compose config --volumes | grep kibana-config | head -1)
docker compose up -d

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
docker volume ls -q --filter name=fleet-server-state | xargs -r docker volume rm
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
├── docker-compose.yml            Main stack definition
├── .env.example                  Environment template
├── Makefile                      Shortcuts (make up, make clean, ...)
├── scripts/
│   ├── install-agent.sh          Agent enrollment helper (Linux/macOS)
│   └── install-agent.ps1         Agent enrollment helper (Windows)
├── elasticsearch/
│   ├── Dockerfile                Multi-stage build with x-pack patch
│   ├── config/elasticsearch.yml
│   └── crack/                    License patch sources
├── kibana/
│   ├── Dockerfile
│   ├── config/kibana.yml         Template (kibana-init generates the working copy)
│   └── init-keys.sh              Encryption keys + CA fingerprint + external URLs
├── logstash/
│   ├── Dockerfile
│   ├── config/logstash.yml
│   └── pipeline/logstash.conf
├── setup/                        User and role provisioning
├── tls/                          Certificate generation
│   ├── instances.yml             Hostnames/IPs for certificates
│   └── certs/                    Generated certs (gitignored)
└── extensions/
    ├── fleet/                    Fleet Server (always on)
    ├── metricbeat/               Stack & host monitoring   (profile: monitoring)
    ├── filebeat/                 Docker log collection     (profile: monitoring)
    └── heartbeat/                Uptime checks             (profile: monitoring)
```

---

## License

[MIT](LICENSE)
