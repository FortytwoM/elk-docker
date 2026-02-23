# Fleet Server

Fleet Server is part of the core stack and starts automatically with `docker compose up`.

Fleet provides central management for [Elastic Agents][fleet-doc] via Kibana, with Elasticsearch as the communication layer.

## Ports

| Port | Protocol |
|------|----------|
| 8220 | HTTPS    |

## Configuration

Fleet Server is configured via [Agent Policies][fleet-pol] in Kibana. A default policy (`fleet-server-policy`) is pre-configured in `kibana/config/kibana.yml`.

The CA fingerprint and full CA certificate are injected automatically by the `kibana-init` service into the Fleet output. The fingerprint lets the Go agent verify the CA during TLS handshake; the embedded certificate is passed to sub-components like Elastic Defend.

## Enrolling external agents

1. Set `FLEET_EXTERNAL_HOST` in `.env` and run `make certs && docker compose up -d --build`.
2. Copy `tls/certs/ca/ca.crt` to the agent host.
3. Get the enrollment token from **Kibana → Fleet → Add agent**.
4. Run the appropriate enrollment script from `scripts/`:

**Linux / macOS:**

```sh
sudo ./scripts/install-agent.sh \
  --url https://<FLEET_EXTERNAL_HOST>:8220 \
  --token <TOKEN> \
  --ca /path/to/ca.crt
```

**Windows** (elevated PowerShell):

```powershell
.\scripts\install-agent.ps1 `
  -FleetUrl "https://<FLEET_EXTERNAL_HOST>:8220" `
  -Token "<TOKEN>" `
  -CaCertPath "C:\path\to\ca.crt"
```

The enrollment scripts automatically install the CA into the **OS trust store**. This is required for Elastic Defend — its C++ code uses the system trust store for `cloudServices` and `responseActions` configuration.

### Manual enrollment (without the helper scripts)

```sh
# 1. Install CA into trust store (pick your OS)
# Debian/Ubuntu:
sudo cp ca.crt /usr/local/share/ca-certificates/elk-ca.crt && sudo update-ca-certificates
# RHEL/CentOS:
sudo cp ca.crt /etc/pki/ca-trust/source/anchors/elk-ca.crt && sudo update-ca-trust
# Windows:
Import-Certificate -FilePath ca.crt -CertStoreLocation Cert:\LocalMachine\Root
# macOS:
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain ca.crt

# 2. Enroll agent
sudo elastic-agent install \
  --url=https://<FLEET_EXTERNAL_HOST>:8220 \
  --enrollment-token=<TOKEN> \
  --certificate-authorities=/path/to/ca.crt
```

## How TLS works for agents

| Component | How it trusts Elasticsearch |
|-----------|-----------------------------|
| Elastic Agent (Go) | `ca_trusted_fingerprint` — matches the CA during TLS handshake |
| Elastic Defend (C++) | Receives the CA from the Fleet policy (`ssl.certificate_authorities`); system trust store also required for `cloudServices` and `responseActions` |
| Cloud services (artifacts) | Public Elastic CAs — requires internet access or [offline endpoint setup][offline] |

The stack sets both `ca_trusted_fingerprint` and the full CA certificate (`ssl.certificate_authorities`) on the Fleet output. The Go agent uses the fingerprint for initial trust; the embedded certificate is distributed to all sub-components, including Elastic Defend.

## Known issues

- Fleet Server auto-enrolls using the `elastic` superuser. For production, generate a dedicated service token instead.

## See also

- [Fleet and Elastic Agent Guide][fleet-doc]
- [Agent Policies][fleet-pol]
- [Fleet Settings][fleet-cfg]
- [Offline Endpoints][offline]

[fleet-doc]: https://www.elastic.co/docs/reference/fleet
[fleet-pol]: https://www.elastic.co/docs/reference/fleet/agent-policy
[fleet-cfg]: https://www.elastic.co/docs/reference/fleet/fleet-settings
[offline]: https://www.elastic.co/docs/solutions/security/configure-elastic-defend/offline-endpoint
