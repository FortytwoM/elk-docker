# Heartbeat

Monitors the availability of Elasticsearch and other services via HTTP and ICMP checks.

## Usage

Heartbeat is activated via the `monitoring` profile:

```sh
docker compose --profile monitoring up -d --build
```

Or with Make:

```sh
make up-mon
```

**Required passwords** in `.env`: `HEARTBEAT_INTERNAL_PASSWORD`, `BEATS_SYSTEM_PASSWORD`.

## Configuration

Edit `extensions/heartbeat/config/heartbeat.yml`, then restart:

```sh
docker compose restart heartbeat
```

## See also

- [Heartbeat Reference](https://www.elastic.co/docs/reference/beats/heartbeat)
- [Run on Docker](https://www.elastic.co/docs/reference/beats/heartbeat/running-on-docker)
