# Metricbeat

Collects metrics from the host OS, Docker containers, and stack components (Elasticsearch, Logstash, Kibana).

## Usage

Metricbeat is activated via the `monitoring` profile:

```sh
docker compose --profile monitoring up -d --build
```

Or with Make:

```sh
make up-mon
```

**Required passwords** in `.env`: `METRICBEAT_INTERNAL_PASSWORD`, `MONITORING_INTERNAL_PASSWORD`, `BEATS_SYSTEM_PASSWORD`.

## Configuration

Edit `extensions/metricbeat/config/metricbeat.yml`, then restart:

```sh
docker compose restart metricbeat
```

## See also

- [Metricbeat Reference](https://www.elastic.co/docs/reference/beats/metricbeat)
- [Run on Docker](https://www.elastic.co/docs/reference/beats/metricbeat/running-on-docker)
