# x-pack-core patch

Builds a patched `x-pack-core-<version>.jar` that replaces license validation so the stack can run without a trial expiry.

## How it works

The patch is built automatically as part of the Elasticsearch Docker image (multi-stage build in `elasticsearch/Dockerfile`). During `docker compose build`, a temporary stage downloads the Elasticsearch source files from GitHub, patches `LicenseVerifier.java` and `License.java`, recompiles, and repacks the JAR. The patched JAR then replaces the original in the final image.

No manual steps are required — just `docker compose up -d --build`.

## Force rebuild after version change

When you change `ELASTIC_VERSION` in `.env`, rebuild the image:

```sh
docker compose build elasticsearch
docker compose up -d
```

## Manual build (optional)

If you want to build the JAR separately (e.g. for use outside Docker):

### Linux / macOS

```bash
bash elasticsearch/crack/crack_linux.sh 9.3.0
```

### Windows (PowerShell)

```powershell
.\elasticsearch\crack\crack_windows.ps1 -Version 9.3.0
```

Output: `elasticsearch/crack/output/x-pack-core-<version>.crack.jar`.
