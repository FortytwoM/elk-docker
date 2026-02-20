# Filebeat

Collects and forwards Docker container logs to Elasticsearch.

## Usage

Filebeat is activated via the `monitoring` profile:

```sh
docker compose --profile monitoring up -d --build
```

Or with Make:

```sh
make up-mon
```

**Required passwords** in `.env`: `FILEBEAT_INTERNAL_PASSWORD`, `BEATS_SYSTEM_PASSWORD`.

## Configuration

Edit `extensions/filebeat/config/filebeat.yml`, then restart:

```sh
docker compose restart filebeat
```

## See also

- [Filebeat Reference](https://www.elastic.co/docs/reference/beats/filebeat)
- [Run on Docker](https://www.elastic.co/docs/reference/beats/filebeat/running-on-docker)
