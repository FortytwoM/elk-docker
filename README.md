# elk-docker

[![Elastic Stack version](https://img.shields.io/badge/Elastic%20Stack-9.3.0-00bfb3?style=flat&logo=elastic-stack)](https://www.elastic.co/blog/category/releases)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](LICENSE)

Single-node Elastic Stack on Docker Compose — fully automated, TLS everywhere, x-pack license patch included.

**Includes:** Elasticsearch · Kibana · Logstash · Fleet Server · Elastic Package Registry

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

---

## How it works

On first `docker compose up --build` the following happens automatically:

1. **tls** — generates X.509 certificates under `tls/certs/` via `elasticsearch-certutil`
2. **kibana-init** — generates Kibana encryption keys and injects the CA fingerprint for Fleet into `kibana/config/kibana.yml`
3. **elasticsearch** — starts with the patched x-pack JAR (baked into the image at build time)
4. **setup** — creates Elasticsearch users and roles from passwords in `.env`
5. **kibana · logstash · package-registry · fleet-server** — start in dependency order

No manual steps required after `docker compose up`.

---

## Requirements

- [Docker Engine](https://docs.docker.com/get-started/get-docker/) 20.10+
- [Docker Compose](https://docs.docker.com/compose/install/) v2.0+
- 4 GB RAM recommended (2 GB minimum)

### Linux: vm.max_map_count

Elasticsearch requires a higher virtual memory limit:

```sh
echo "vm.max_map_count=262144" | sudo tee -a /etc/sysctl.d/99-elasticsearch.conf
sudo sysctl --system
```

### Docker Desktop (Windows / macOS): data on an external drive

All persistent data lives in Docker **named volumes** (`elasticsearch-data`, `fleet-server-state`) inside Docker Desktop's virtual disk image.

To move everything to an external drive:

1. Docker Desktop → **Settings → Resources → Advanced → Disk image location**
2. Set the path, e.g. `E:\DockerDesktop`
3. **Apply & Restart**

> Bind-mounting external NTFS drives for Elasticsearch data doesn't work on Docker Desktop — WSL2's NTFS layer doesn't support the Unix file locks Lucene requires. Named volumes use ext4 inside the VM and work correctly.

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

All config files are mounted read-only — edit locally and restart the service.

| Component     | File                                     |
|---------------|------------------------------------------|
| Elasticsearch | `elasticsearch/config/elasticsearch.yml` |
| Kibana        | `kibana/config/kibana.yml`               |
| Logstash      | `logstash/config/logstash.yml`           |
| Pipeline      | `logstash/pipeline/logstash.conf`        |
| TLS instances | `tls/instances.yml`                      |

### Fleet and Package Registry

Fleet Server and the local Elastic Package Registry start automatically.  
The CA fingerprint for the Fleet output is injected by `kibana-init`, so Fleet appears healthy in Kibana out of the box.

Kibana uses the local registry by default:

```yaml
xpack.fleet.isAirGapped: true
xpack.fleet.registryUrl: "http://package-registry:8080"
```

To use the public Elastic registry, remove or comment these two lines and restart Kibana.

---

## Initial setup

### Change passwords

Edit passwords in `.env` before the first run, or reset them afterwards:

```sh
docker compose exec elasticsearch \
  bin/elasticsearch-reset-password --batch --user elastic
```

Update the new values in `.env`, then restart affected services:

```sh
docker compose up -d logstash kibana
```

### Send data to Logstash

```sh
cat /path/to/logfile.log | nc --send-only localhost 50000
```

Or load the built-in sample data from the Kibana home page.

---

## Operations

### Stop / start

```sh
docker compose down
docker compose up -d
```

### Remove all data

```sh
docker compose down -v   # removes named volumes (elasticsearch-data, fleet-server-state)
```

### Rebuild after version change

Edit `ELASTIC_VERSION` in `.env`, then:

```sh
docker compose build
docker compose up -d
```

### Re-generate TLS certificates

```sh
find tls/certs -mindepth 1 -delete
docker compose up tls
docker compose up -d
```

To add a hostname or IP, edit `tls/instances.yml` first.

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

| Service       | Variable       | Default |
|---------------|----------------|---------|
| Elasticsearch | `ES_JAVA_OPTS` | 512 MB  |
| Logstash      | `LS_JAVA_OPTS` | 256 MB  |

Example — 2 GB heap for Elasticsearch:

```yml
elasticsearch:
  environment:
    ES_JAVA_OPTS: -Xms2g -Xmx2g
```

---

## x-pack license patch

The patched `x-pack-core` JAR is compiled and baked into the Elasticsearch image during `docker compose build` via a multi-stage `Dockerfile`. No runtime hacks, no manual steps.

After changing `ELASTIC_VERSION`, rebuild:

```sh
docker compose build elasticsearch
docker compose up -d elasticsearch
```

See [`elasticsearch/crack/README.md`](elasticsearch/crack/README.md) for details and manual build options.

---

## Troubleshooting

**Fleet Server shows "Unhealthy" / "Message Signing Key" error**

Clear Fleet Server's state volume and restart:

```sh
docker compose down
docker volume rm elk-docker_fleet-server-state
docker compose up -d
```

**Elasticsearch won't start on Linux**

Check `vm.max_map_count` (see [Requirements](#linux-vmmax_map_count)).

---

## Revert to Basic license

In Kibana: **Stack Management → License Management → Revert to Basic**.

Or via API:

```sh
curl -XPOST 'https://localhost:9200/_license/start_basic?acknowledge=true' \
  --cacert tls/certs/ca/ca.crt \
  -u elastic:<password>
```

---

## Extensions

Optional extensions (Metricbeat, Filebeat, Heartbeat, Curator) are in [`extensions/`](extensions/). Each has its own `README.md`.

## Plugins

Add a `RUN` line to the relevant `Dockerfile`:

```dockerfile
RUN elasticsearch-plugin install analysis-icu
```

Then rebuild: `docker compose build`.

---

## License

[MIT](LICENSE)
