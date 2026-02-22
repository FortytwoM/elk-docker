# TLS certificates

This directory stores the X.509 certificates and private keys used for securing communications between Elastic components over TLS.

They are generated automatically by `docker compose up tls` (or `make certs`), which materializes a file tree like this inside `certs/`:

```tree
certs/
├── ca/
│   ├── ca.crt
│   └── ca.key
├── elasticsearch/
│   ├── elasticsearch.crt
│   └── elasticsearch.key
├── fleet-server/
│   ├── fleet-server.crt
│   └── fleet-server.key
├── kibana/
│   ├── kibana.crt
│   └── kibana.key
└── logstash/
    ├── logstash.crt
    └── logstash.key
```

External IPs/hostnames are added automatically when `FLEET_EXTERNAL_HOST` is set in `.env`. To add extra entries manually, edit [`instances.yml`](./instances.yml) and run `make certs`.
