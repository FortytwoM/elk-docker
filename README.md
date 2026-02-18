# docker-elk

[![Elastic Stack version](https://img.shields.io/badge/Elastic%20Stack-9.3.0-00bfb3?style=flat&logo=elastic-stack)](https://www.elastic.co/blog/category/releases)

Production-ready single-node Elastic stack (ELK) on Docker Compose.

**What's included:**

- **Elasticsearch** — full-text search and analytics
- **Kibana** — visualization (HTTPS enabled by default)
- **Logstash** — log ingestion pipeline
- **Fleet Server** — Elastic Agent management
- **Elastic Package Registry** — local (air-gapped) integration repository

**Security by default:**

- TLS everywhere: Elasticsearch HTTP/Transport, Kibana browser TLS, Fleet Server TLS
- Kibana encryption keys generated automatically on first start
- All certificates generated on first start via `elasticsearch-certutil`

---

## Quick start

```sh
cp .env.example .env
# Edit .env: change passwords and optionally set DATA_PATH
docker compose up -d --build
```

Open **<https://localhost:5601>** (accept the self-signed certificate).
Default credentials: `elastic` / `changeme` (change before use — see [Initial setup](#initial-setup)).

---

## How it works

On first `docker compose up`:

1. **tls** — generates X.509 certificates under `tls/certs/` (skipped if already present)
2. **kibana-init** — generates Kibana encryption keys and writes them to `kibana/config/kibana.yml` (idempotent)
3. **elasticsearch** — starts; setup waits until it is healthy
4. **setup** — creates Elasticsearch users and roles from `.env` passwords
5. **kibana**, **logstash**, **package-registry**, **fleet-server** — start in correct order

No manual steps required.

---

## Requirements

- [Docker Engine](https://docs.docker.com/get-started/get-docker/) 20.10+
- [Docker Compose](https://docs.docker.com/compose/install/) v2.0+
- 4 GB RAM recommended (2 GB minimum)

### Linux: required system setting

```sh
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.d/99-elasticsearch.conf
sudo sysctl --system
```

### Docker Desktop (Windows / macOS): data on external drive

By default data is stored in `./data/`. To use another drive, set `DATA_PATH` in `.env`:

```env
DATA_PATH=E:\docker-elk-data
```

Make sure the drive is shared: Docker Desktop → Settings → Resources → File sharing.

To move build cache and images to another drive: Docker Desktop → Settings → Resources → Advanced → **Disk image location**.

---

## Ports

| Port  | Service                       |
|-------|-------------------------------|
| 5601  | Kibana (HTTPS)                |
| 9200  | Elasticsearch HTTP (TLS)      |
| 9300  | Elasticsearch transport (TLS) |
| 8220  | Fleet Server                  |
| 8080  | Elastic Package Registry      |
| 5044  | Logstash Beats input          |
| 50000 | Logstash TCP input            |
| 9600  | Logstash monitoring API       |

---

## Configuration

All config files are mounted read-only from the host — edit locally and restart the service.

| Component     | Config file                              |
|---------------|------------------------------------------|
| Elasticsearch | `elasticsearch/config/elasticsearch.yml` |
| Kibana        | `kibana/config/kibana.yml`               |
| Logstash      | `logstash/config/logstash.yml`           |
| Pipeline      | `logstash/pipeline/logstash.conf`        |
| TLS instances | `tls/instances.yml`                      |

Environment overrides can also be set directly in `docker-compose.yml`:

```yml
elasticsearch:
  environment:
    cluster.name: my-cluster
```

### Fleet and Package Registry

Fleet Server and the local Elastic Package Registry start automatically. Kibana is configured with:

```yaml
xpack.fleet.isAirGapped: true
xpack.fleet.registryUrl: "http://package-registry:8080"
```

To disable air-gapped mode or use a remote registry, edit `kibana/config/kibana.yml` and restart Kibana.

---

## Initial setup

### 1. Change passwords

Before or right after the first run, reset the default `changeme` passwords:

```sh
docker compose exec elasticsearch \
  bin/elasticsearch-reset-password --batch --user elastic --url https://localhost:9200

docker compose exec elasticsearch \
  bin/elasticsearch-reset-password --batch --user logstash_internal --url https://localhost:9200

docker compose exec elasticsearch \
  bin/elasticsearch-reset-password --batch --user kibana_system --url https://localhost:9200
```

Update the new passwords in `.env`, then restart Logstash and Kibana:

```sh
docker compose up -d logstash kibana
```

### 2. Inject data

Send data to Logstash over TCP port 50000:

```sh
cat /path/to/logfile.log | nc --send-only localhost 50000
```

Or load the sample data from the Kibana home page.

---

## Operations

### Stop the stack

```sh
docker compose down
```

### Remove all data

```sh
docker compose down
rm -rf data   # or the folder set in DATA_PATH
```

### Rebuild images (after version change or Dockerfile edit)

```sh
docker compose build
docker compose up -d
```

### Change the Elastic Stack version

Set `ELASTIC_VERSION` in `.env` and rebuild:

```sh
docker compose build
docker compose up -d
```

### Re-generate TLS certificates

Remove existing certs and restart the `tls` service:

```sh
find tls/certs -mindepth 1 -name ca -prune -o -type d -exec rm -rfv {} +
docker compose up tls
docker compose up -d
```

To add a hostname or IP to certificates, edit `tls/instances.yml` first.

### Re-run user setup

```sh
docker compose up setup
```

### Regenerate Kibana encryption keys

```sh
docker compose run --rm kibana-init
docker compose restart kibana
```

> **Warning:** regenerating keys invalidates previously encrypted saved objects (alerts, reports, connectors).

### Reset a password via API

```sh
curl -XPOST 'https://localhost:9200/_security/user/elastic/_password' \
  --cacert tls/certs/ca/ca.crt \
  -H 'Content-Type: application/json' \
  -u elastic:<current-password> \
  -d '{"password":"<new-password>"}'
```

---

## JVM tuning

Default heap sizes are kept low for development. Increase in `docker-compose.yml`:

| Service       | Variable      | Default |
|---------------|---------------|---------|
| Elasticsearch | `ES_JAVA_OPTS`| 512 MB  |
| Logstash      | `LS_JAVA_OPTS`| 256 MB  |

Example — set Elasticsearch to 2 GB:

```yml
elasticsearch:
  environment:
    ES_JAVA_OPTS: -Xms2g -Xmx2g
```

---

## Optional: x-pack license patch

A tool to build a patched `x-pack-core` JAR that bypasses license validation is included in `elasticsearch/crack/`.

```sh
# Linux/macOS
bash elasticsearch/crack/crack_linux.sh 9.3.0

# Windows
.\elasticsearch\crack\crack_windows.ps1 -Version 9.3.0
```

After building, uncomment the `CRACK_JAR` volume and environment variable in `docker-compose.yml`, then restart Elasticsearch. See [`elasticsearch/crack/README.md`](elasticsearch/crack/README.md) for details.

---

## Disable paid features (revert to Basic license)

In Kibana: **Stack Management → License Management → Revert to Basic**.

Or via API:

```sh
curl -XPOST 'https://localhost:9200/_license/start_basic?acknowledge=true' \
  --cacert tls/certs/ca/ca.crt \
  -u elastic:<password>
```

---

## Extensions

Optional extensions are available in the [`extensions/`](extensions/) directory (Metricbeat, Filebeat, Heartbeat, Curator). Each has its own `README.md` with usage instructions.

---

## Adding plugins

1. Add a `RUN` statement to the relevant `Dockerfile`:
   ```dockerfile
   RUN elasticsearch-plugin install analysis-icu
   ```
2. Rebuild: `docker compose build`

---

[elk-stack]: https://www.elastic.co/elastic-stack/
[elastic-docker]: https://www.docker.elastic.co/
