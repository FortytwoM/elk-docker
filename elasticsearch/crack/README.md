# x-pack-core patch (optional)

Builds a patched `x-pack-core-<version>.jar` that replaces license validation so the stack can run without a trial expiry.

This is **optional**. The stack runs normally without it; with it, Elasticsearch accepts the patched JAR before startup.

## Build the JAR

Use the same version as `ELASTIC_VERSION` in the repo root `.env` (e.g. `9.3.0`).

### Linux / macOS

```bash
bash elasticsearch/crack/crack_linux.sh 9.3.0
```

### Windows (PowerShell)

```powershell
.\elasticsearch\crack\crack_windows.ps1 -Version 9.3.0
```

Output: `elasticsearch/crack/output/x-pack-core-<version>.crack.jar`.

## Enable the patch in elk-docker

1. In `docker-compose.yml`, under the `elasticsearch` service, **uncomment** the crack volume and env:

   ```yaml
   volumes:
     # ...
     - ./elasticsearch/crack/output/x-pack-core-${ELASTIC_VERSION}.crack.jar:/crack/x-pack-core.crack.jar:ro
   environment:
     # ...
     CRACK_JAR: /crack/x-pack-core.crack.jar
   ```

2. Restart Elasticsearch:

   ```bash
   docker compose up -d elasticsearch
   ```

On startup, the entrypoint will replace `modules/x-pack-core/x-pack-core-<version>.jar` with the patched JAR before Elasticsearch starts.
