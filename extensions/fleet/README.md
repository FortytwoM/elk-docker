# Fleet Server

**Fleet Server and the Elastic Package Registry are started with the main stack** (`docker compose up`). You do not need to use a separate Compose file unless you want to run the stack without Fleet.

> [!WARNING]
> This extension currently exists for preview purposes and should be considered **EXPERIMENTAL**. Expect regular changes
> to the default Fleet settings, both in the Elastic Agent and Kibana.
>
> See [Known Issues](#known-issues) for a list of issues that need to be addressed before this extension can be
> considered functional.

Fleet provides central management capabilities for [Elastic Agents][fleet-doc] via an API and web UI served by Kibana,
with Elasticsearch acting as the communication layer.
Fleet Server is the central component which allows connecting Elastic Agents to the Fleet.

## Requirements

The Fleet Server exposes the TCP port `8220` for Agent to Server communications.

## Usage

### CA Certificate Fingerprint

Before starting Fleet Server, take note of the CA certificate's SHA256 fingerprint printed by the `docker compose up
tls` command (it is safe to run it multiple times), and use it as the value of the commented `ca_trusted_fingerprint`
setting inside the [`kibana/config/kibana.yml`][config-kbn] file.

The fingerprint appears on a line similar to the one below, in the output of the aforementioned command:

```none
⠿ SHA256 fingerprint: 846637d1bb82209640d31b79869a370c8e47c2dc15c7eafd4f3d615e51e3d503
```

This fingerprint is required for Fleet Server (and other Elastic Agents) to be able to verify the authenticity of the CA
certificate presented by Elasticsearch during TLS handshakes.

Restart Kibana with `docker compose restart kibana` if it is already running.

### Agent install parameters

When installing Fleet Server or Elastic Agent on another host (e.g. from Fleet UI "Add Fleet Server" or "Add agent"),
use the following so the agent trusts the stack’s TLS certificates. Paths below are for the **Docker host**; copy the
referenced files from the project to the target host (e.g. `tls/certs/ca/ca.crt` → `/etc/kibana/certs/ca.crt`).

**Fleet Server / agent (Fleet Server host):**

```text
--certificate-authorities=/path/to/ca.crt
--fleet-server-es-ca=/path/to/http_ca.crt
--fleet-server-cert=/path/to/fleet-server.crt
--fleet-server-cert-key=/path/to/fleet-server.key
```

Use `tls/certs/ca/ca.crt` for `--certificate-authorities`. For Elasticsearch HTTP CA use the same CA cert or the
fingerprint via `ca_trusted_fingerprint` in Kibana (see [CA Certificate Fingerprint](#ca-certificate-fingerprint)).
Fleet Server cert and key are in `tls/certs/fleet-server/`.

**Elastic Agent (other hosts):**

```text
--certificate-authorities=/path/to/ca.crt
```

Copy `tls/certs/ca/ca.crt` to the agent host and point `--certificate-authorities` to it.

### Startup

Fleet Server is included in the main `docker compose up`. To run only the core stack without Fleet and the package registry, omit the `fleet-server` and `package-registry` services (e.g. by using a profile or a custom override). To run with the standalone Fleet Compose file instead (e.g. for testing), use:

```console
$ docker compose -f docker-compose.yml -f extensions/fleet/fleet-compose.yml up
```

## Configuring Fleet Server

Fleet Server — like any Elastic Agent — is configured via [Agent Policies][fleet-pol] which can be either managed
through the Fleet management UI in Kibana, or statically pre-configured inside the Kibana configuration file.

To ease the enrollment of Fleet Server in this extension, elk-docker comes with a pre-configured Agent Policy for Fleet
Server defined inside [`kibana/config/kibana.yml`][config-kbn].

Please refer to the following documentation page for more details about configuring Fleet Server through the Fleet
management UI: [Fleet UI Settings][fleet-cfg].

## Known Issues

- The Elastic Agent auto-enrolls using the `elastic` super-user. With this approach, you do not need to generate a
  service token — either using the Fleet management UI or [CLI utility][es-svc-token] — prior to starting this
  extension. However convenient that is, this approach _does not follow security best practices_, and we recommend
  generating a service token for Fleet Server instead.

## See also

[Fleet and Elastic Agent Guide][fleet-doc]

## Screenshots

![fleet-agents](https://user-images.githubusercontent.com/3299086/202701399-27518fe4-17b7-49d1-aefb-868dffeaa68a.png
"Fleet Agents")
![elastic-agent-dashboard](https://user-images.githubusercontent.com/3299086/202701404-958f8d80-a7a0-4044-bbf9-bf73f3bdd17a.png
"Elastic Agent Dashboard")

[fleet-doc]: https://www.elastic.co/docs/reference/fleet
[fleet-pol]: https://www.elastic.co/docs/reference/fleet/agent-policy
[fleet-cfg]: https://www.elastic.co/docs/reference/fleet/fleet-settings

[config-kbn]: ../../kibana/config/kibana.yml

[es-svc-token]: https://www.elastic.co/docs/reference/elasticsearch/command-line-tools/service-tokens-command
