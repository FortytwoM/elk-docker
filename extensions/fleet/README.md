# Fleet Server

Fleet Server is part of the core stack and starts automatically with `docker compose up`.

Fleet provides central management for [Elastic Agents][fleet-doc] via Kibana, with Elasticsearch as the communication layer.

## Ports

| Port | Protocol |
|------|----------|
| 8220 | HTTPS    |

## Configuration

Fleet Server is configured via [Agent Policies][fleet-pol] in Kibana. A default policy (`fleet-server-policy`) is pre-configured in `kibana/config/kibana.yml`.

The CA fingerprint is injected automatically by the `kibana-init` service.

## Enrolling external agents

When installing Elastic Agent on another host, copy the CA certificate so the agent trusts the stack's TLS:

```text
--certificate-authorities=/path/to/ca.crt
```

The CA certificate is at `tls/certs/ca/ca.crt`.

Fleet Server certificate and key are at `tls/certs/fleet-server/`.

## Known issues

- Fleet Server auto-enrolls using the `elastic` superuser. For production, generate a dedicated service token instead.

## See also

- [Fleet and Elastic Agent Guide][fleet-doc]
- [Agent Policies][fleet-pol]
- [Fleet Settings][fleet-cfg]

[fleet-doc]: https://www.elastic.co/docs/reference/fleet
[fleet-pol]: https://www.elastic.co/docs/reference/fleet/agent-policy
[fleet-cfg]: https://www.elastic.co/docs/reference/fleet/fleet-settings
