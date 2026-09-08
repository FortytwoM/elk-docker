# elk-docker

[![Elastic Stack version](https://img.shields.io/badge/Elastic%20Stack-9.5.3-00bfb3?style=flat&logo=elastic-stack)](https://www.elastic.co/blog/category/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Single-node Elastic Stack on Docker Compose — fully automated, TLS everywhere, x-pack license patch included.

**Includes:** Elasticsearch · Kibana · Logstash · Fleet Server · Elastic Package Registry · artifact mirror (agent binaries + Defend)

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
make kibana-reset  # re-seed Kibana config (new Fleet policies)
```

Run `make` to see all available commands.

---

## How it works

On first `docker compose up --build`:

1. **tls** — generates X.509 certificates under `tls/certs/` via `elasticsearch-certutil`; if `FLEET_EXTERNAL_HOST` is set, automatically adds it to the certificate SANs
2. **kibana-init** — copies `kibana.yml` template into a Docker volume, generates encryption keys, injects CA fingerprint, and adds external URLs if `FLEET_EXTERNAL_HOST` is set
3. **elasticsearch** — starts with the patched x-pack JAR (baked into the image at build time)
4. **setup** — creates Elasticsearch users and roles from passwords in `.env`, and applies ILM retention (`RETENTION_DAYS`)
5. **kibana · logstash · package-registry · endpoint-artifacts · fleet-server** — start in dependency order (Kibana and Logstash wait until `setup` has created users). Fleet ships a default **Endpoint Policy** with Elastic Defend pointed at the local artifact mirror.

No manual steps required.

---

## Requirements

- [Docker Engine](https://docs.docker.com/get-started/get-docker/) 20.10+
- [Docker Compose](https://docs.docker.com/compose/install/) v2.0+
- 10 GB RAM recommended for SIEM (Elasticsearch 2g heap + 6g cap). 4 GB is a tight minimum with heaps lowered in `.env`.

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

Published to the host by default. Override in `.env` (`ES_PORT`, `KIBANA_PORT`, `FLEET_PORT`, …). Prefix with `127.0.0.1:` to bind localhost-only.

| Port  | Service                       | Bind      | Why it is published |
|-------|-------------------------------|-----------|---------------------|
| 9200  | Elasticsearch HTTP (TLS)      | 0.0.0.0   | Elastic Agents ship data here (Fleet Server is control plane only) |
| 5601  | Kibana (HTTPS)                | 0.0.0.0   | UI |
| 8220  | Fleet Server (HTTPS)          | 0.0.0.0   | Agent enrollment and check-in |
| 9080  | Artifact mirror (nginx)       | 0.0.0.0   | Agent binaries + Defend malware models |
| 5044  | Logstash Beats input (TLS)    | 0.0.0.0   | Filebeat / Elastic Agent → Logstash |
| 50000 | Logstash TCP/UDP (plaintext)  | 0.0.0.0   | Quick ingest (`nc`, json_lines) |
| 9600  | Logstash monitoring API       | 127.0.0.1 | Local-only |

Not published:

- **9300** — Elasticsearch transport, single-node, Docker-internal
- **8080** — Elastic Package Registry, Docker-internal (`http://package-registry:8080`)

Elastic’s compose sample binds Elasticsearch to `127.0.0.1:9200` by default. That breaks remote agents. This stack keeps 9200 on all interfaces so a pocket SIEM can enroll hosts on the LAN. For a laptop-only lab:

```ini
ES_PORT=127.0.0.1:9200
KIBANA_PORT=127.0.0.1:5601
FLEET_PORT=127.0.0.1:8220
```

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

Fleet Server, a default **Endpoint Policy**, and the local Elastic Package Registry start automatically.
The CA fingerprint is injected by `kibana-init`, so Fleet appears healthy out of the box.

Preinstalled Fleet packages: `fleet_server`, `system`, `elastic_agent`, `endpoint` (Elastic Defend), `windows`.

Elastic Defend is attached to **Endpoint Policy** (package only — Kibana 9.5 cannot take Defend `inputs.config` in `kibana.yml`). After Kibana is healthy, `defend-init` sets:

- Fleet **Agent binary download** to `http://<FLEET_EXTERNAL_HOST>:9080/downloads/`
- Defend `advanced.artifacts.global.base_url` to `http://<FLEET_EXTERNAL_HOST>:9080`

That is the nginx mirror, not a Fleet **Settings → Proxies** entry. Proxies in that UI are corporate HTTP proxies (for agents that cannot reach the SIEM host directly). This stack does not add one: agents talk to Fleet, Elasticsearch, and `:9080` on `FLEET_EXTERNAL_HOST`.

Already running this stack? Re-seed Kibana so Defend and the artifact URL appear:

```sh
make kibana-reset
docker compose up -d
```

The local registry uses the **lite** image (`distribution:lite-9.5.3`) — common packages (including Defend), ~1 GB RAM. The full `distribution:9.5.3` image indexes every integration and will sit at 2 GB+ with CPU/network spikes. To switch back: set the image tag in `docker-compose.yml` and raise `REGISTRY_MEM_LIMIT` to 4g.

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

**Step 3.** On the SIEM host, warm the agent zip cache (once; Docker host needs internet):

```sh
make prefetch-agents
```

Endpoints then download **only from this host** (no `artifacts.elastic.co`):

| File | URL |
|------|-----|
| Windows agent | `http://192.168.1.108:9080/downloads/beats/elastic-agent/elastic-agent-9.5.3-windows-x86_64.zip` |
| Linux x86_64 | `http://192.168.1.108:9080/downloads/beats/elastic-agent/elastic-agent-9.5.3-linux-x86_64.tar.gz` |
| Stack CA | `http://192.168.1.108:9080/ca.crt` |

Get the enrollment token from Kibana: **Fleet → Add agent → Endpoint Policy**.

Copy `scripts/install-agent.ps1` (or `.sh`) to the endpoint — the script pulls the zip and CA from `:9080` itself.

**Windows** (elevated PowerShell):

```powershell
.\install-agent.ps1 `
  -FleetUrl "https://192.168.1.108:8220" `
  -Token "<TOKEN_FROM_KIBANA>"
```

**Linux:**

```sh
sudo ./install-agent.sh \
  --url https://192.168.1.108:8220 \
  --token <TOKEN_FROM_KIBANA>
```

After enrollment, Fleet upgrades also come from `:9080/downloads/` (set as the default Agent binary download source). The scripts install the CA into the OS trust store — required for Elastic Defend with this stack’s certificates.

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

Plaintext JSON lines (TCP or UDP):

```sh
cat /path/to/logfile.log | nc --send-only localhost 50000
```

Events land in the `logs-generic-default` data stream (ECS-compatible template).

Beats / Elastic Agent on **5044** must use TLS with this stack’s CA:

```yaml
output.logstash:
  hosts: ["HOST:5044"]
  ssl.enabled: true
  ssl.certificate_authorities: ["ca.crt"]
```

Or load sample data from the Kibana home page.

### Pocket SIEM checklist

After `docker compose up -d --build`:

1. Set `FLEET_EXTERNAL_HOST` and run `make certs` if agents are not on the Docker host (see above).
2. Enroll agents with the scripts in `scripts/` (installs the CA — required for Elastic Defend).
3. Confirm **Fleet → Endpoint Policy** has Elastic Defend and artifact URL `http://<your-ip>:9080`.
4. **Security → Rules → Detection rules** → install Elastic prebuilt rules. Large rule sets need the default 2g heap (or more) and matching `ES_MEM_LIMIT`.
5. Log retention is `RETENTION_DAYS` in `.env` (default 7). Set `0` to keep Elastic's built-in ILM (no auto-delete).

Existing volume from an older checkout: `make kibana-reset` then `docker compose up -d` (regenerates Kibana encryption keys).

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

# Regenerate Kibana encryption keys / pick up new Fleet preconfiguration
make kibana-reset
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

| Service       | Heap variable  | Default heap | Container `mem_limit` |
|---------------|----------------|--------------|------------------------|
| Elasticsearch | `ES_JAVA_OPTS` | 2 GB         | `ES_MEM_LIMIT` (6g)    |
| Logstash      | `LS_JAVA_OPTS` | 256 MB       | `LS_MEM_LIMIT` (768m)  |
| Kibana        | —              | —            | `KIBANA_MEM_LIMIT` (2g)|
| Fleet Server  | —              | —            | `FLEET_MEM_LIMIT` (1g) |
| Package Registry | —           | —            | `REGISTRY_MEM_LIMIT` (1g, lite image) |
| Artifact mirror | —            | —            | `ARTIFACTS_MEM_LIMIT` (64m) |

These are the SIEM defaults in `.env.example`. Give Docker **~8 GB**. Smaller box:

```ini
ES_JAVA_OPTS=-Xms512m -Xmx512m
ES_MEM_LIMIT=1g
KIBANA_MEM_LIMIT=1g
```

`mem_limit` is a hard cap (same idea as Elastic's sample compose). If the heap is larger than the cap, Docker kills Elasticsearch with OOM and it looks like a silent restart. Keep Elasticsearch `mem_limit` around **2× heap**.

The container also sets `bootstrap.memory_lock` and `xpack.ml.use_auto_machine_memory_percent` (official Elastic Docker Compose defaults). Heap should stay around half of the RAM you give Elasticsearch; leave the rest for Lucene page cache.

## Log retention

`setup` writes ILM policy `elk-retention` and attaches it through `logs@custom` / `metrics@custom` (Fleet does not overwrite those on package updates).

Default: rollover every **1 day** or **10 GB**, delete after **`RETENTION_DAYS`** (7). Applies to `logs-*` and `metrics-*`, including Logstash `logs-generic-default` and Elastic Agent data streams.

```ini
RETENTION_DAYS=7
```

`RETENTION_DAYS=0` skips the custom policy. Changing the value later: `docker compose up setup`.

## Artifact mirror (agent binaries + Defend)

Two different Elastic CDNs, one local nginx on port **9080**:

| Path | Upstream | Used for |
|------|----------|----------|
| `/downloads/beats/…` | `artifacts.elastic.co` | Elastic Agent installer + upgrades |
| `/ca.crt` | stack CA | Trust store on endpoints |
| `/downloads/endpoint/…` | `artifacts.security.elastic.co` | Defend malware models / blocklists |

The Docker host must reach Elastic once. Enrolled endpoints only need `http://<FLEET_EXTERNAL_HOST>:9080`. Agent binaries are cached on disk (volume `artifacts-cache`); the first download fills the cache, later agents are served locally.

`defend-init` points Fleet **Settings → Agent binary download** at `http://<FLEET_EXTERNAL_HOST>:9080/downloads/` and writes Defend `base_url` to `http://<FLEET_EXTERNAL_HOST>:9080`.

Warm the cache so endpoints never wait on the first pull (Windows zip is hundreds of MB):

```sh
make prefetch-agents
```

Check:

```sh
curl -sI http://127.0.0.1:9080/downloads/beats/elastic-agent/elastic-agent-9.5.3-windows-x86_64.zip
curl -sI http://127.0.0.1:9080/downloads/endpoint/manifest/artifacts-9.5.3.zip
```

The Defend response must include an `ETag` header. Agent binary responses include `X-Artifact-Cache: MISS` then `HIT`.

Fully air-gapped Docker host (no outbound HTTPS): replace the proxy with a static file tree as in [Elastic’s air-gapped artifact registry](https://www.elastic.co/docs/reference/fleet/air-gapped) and [offline endpoints](https://www.elastic.co/docs/solutions/security/configure-elastic-defend/configure-offline-endpoints-air-gapped-environments).

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
