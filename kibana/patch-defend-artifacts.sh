#!/bin/sh
# After Kibana is up:
#  1. Ensure Fleet package policies exist (kibana.yml preconfig often skips them).
#  2. Point Fleet agent-binary downloads at the local nginx mirror.
#  3. Set Elastic Defend artifact base_url on Endpoint Policy.
# kibana.yml cannot hold Defend inputs.config on 9.5 (config validation rejects it).
set -eu

CA_CERT_PATH="${CA_CERT_PATH:-/usr/share/kibana/config/ca.crt}"
KIBANA_URL="${KIBANA_URL:-https://kibana:5601}"
ELASTIC_PASSWORD="${ELASTIC_PASSWORD:-}"
ARTIFACTS_PORT="${ARTIFACTS_PORT:-9080}"
host="${FLEET_EXTERNAL_HOST:-localhost}"
# Strip host:port bind prefix if someone set ARTIFACTS_PORT=127.0.0.1:9080
port="${ARTIFACTS_PORT##*:}"
ARTIFACTS_URL="http://${host}:${port}"
DOWNLOADS_URL="${ARTIFACTS_URL}/downloads/"

NODE_BIN=$(find /usr/share/kibana/node -name node -type f 2>/dev/null | head -1)
NODE_BIN="${NODE_BIN:-node}"

echo "Waiting for Kibana…"
i=0
while [ "$i" -lt 60 ]; do
  if curl -sf --cacert "$CA_CERT_PATH" "${KIBANA_URL}/api/status" | grep -qE '"level"\s*:\s*"(available|degraded)"'; then
    break
  fi
  i=$((i + 1))
  sleep 5
done

echo "Ensuring Fleet package policies + download source ${DOWNLOADS_URL}"
export CA_CERT_PATH KIBANA_URL ELASTIC_PASSWORD ARTIFACTS_URL DOWNLOADS_URL
"${NODE_BIN}" <<'EOF'
const https = require('https');
const fs = require('fs');
const { URL } = require('url');

const kibana = process.env.KIBANA_URL;
const password = process.env.ELASTIC_PASSWORD;
const artifactsUrl = process.env.ARTIFACTS_URL;
const downloadsUrl = process.env.DOWNLOADS_URL;
const ca = fs.readFileSync(process.env.CA_CERT_PATH);

function request(method, path, body) {
  return new Promise((resolve, reject) => {
    const u = new URL(path, kibana);
    const payload = body ? JSON.stringify(body) : null;
    const req = https.request(
      {
        hostname: u.hostname,
        port: u.port || 443,
        path: u.pathname + u.search,
        method,
        ca,
        servername: u.hostname,
        auth: 'elastic:' + password,
        headers: {
          'kbn-xsrf': 'true',
          'Content-Type': 'application/json',
          ...(payload ? { 'Content-Length': Buffer.byteLength(payload) } : {}),
        },
      },
      (res) => {
        let data = '';
        res.on('data', (c) => (data += c));
        res.on('end', () => {
          if (res.statusCode === 409) {
            resolve({ conflict: true, status: 409 });
            return;
          }
          if (res.statusCode >= 400) {
            reject(new Error(method + ' ' + path + ' → ' + res.statusCode + ' ' + data.slice(0, 500)));
            return;
          }
          resolve(data ? JSON.parse(data) : {});
        });
      }
    );
    req.setTimeout(120000);
    req.on('error', reject);
    if (payload) req.write(payload);
    req.end();
  });
}

function sleep(ms) {
  return new Promise((r) => setTimeout(r, ms));
}

function ensure(obj, keys) {
  let cur = obj;
  for (const k of keys) {
    if (!cur[k] || typeof cur[k] !== 'object') cur[k] = {};
    cur = cur[k];
  }
  return cur;
}

async function waitPackageVersion(name) {
  for (let i = 0; i < 36; i++) {
    const d = await request('GET', '/api/fleet/epm/packages/' + name);
    const item = d.item || {};
    if (item.status === 'installed' && (item.version || item.latestVersion)) {
      return item.version || item.latestVersion;
    }
    await sleep(5000);
  }
  throw new Error('package not installed: ' + name);
}

async function ensureDownloadSource() {
  const res = await request('GET', '/api/fleet/agent_download_sources');
  const items = res.items || [];
  const body = { name: 'Local artifacts', host: downloadsUrl, is_default: true };
  const existing =
    items.find((s) => s.id === 'local-artifacts') ||
    items.find((s) => s.host === downloadsUrl) ||
    items.find((s) => s.is_default);
  if (existing) {
    if (existing.host === downloadsUrl && existing.is_default) {
      console.log('Download source already', downloadsUrl);
      return;
    }
    await request('PUT', '/api/fleet/agent_download_sources/' + existing.id, body);
    console.log('Updated download source', existing.id, '→', downloadsUrl);
    return;
  }
  await request('POST', '/api/fleet/agent_download_sources', { id: 'local-artifacts', ...body });
  console.log('Created download source', downloadsUrl);
}

async function ensurePackagePolicies() {
  const wanted = [
    { name: 'fleet_server-1', policy_id: 'fleet-server-policy', pkg: 'fleet_server' },
    { name: 'system-1', policy_id: 'fleet-server-policy', pkg: 'system' },
    { name: 'elastic_agent-1', policy_id: 'fleet-server-policy', pkg: 'elastic_agent' },
    { name: 'endpoint-system-1', policy_id: 'endpoint-policy', pkg: 'system' },
    { name: 'endpoint-windows-1', policy_id: 'endpoint-policy', pkg: 'windows' },
    { name: 'endpoint-elastic_agent-1', policy_id: 'endpoint-policy', pkg: 'elastic_agent' },
    { name: 'endpoint-defend-1', policy_id: 'endpoint-policy', pkg: 'endpoint' },
  ];
  const versions = {};
  for (const pkg of [...new Set(wanted.map((w) => w.pkg))]) {
    versions[pkg] = await waitPackageVersion(pkg);
    console.log('Package', pkg, versions[pkg]);
  }
  const existing = await request('GET', '/api/fleet/package_policies?perPage=100');
  const names = new Set((existing.items || []).map((p) => p.name));
  for (const w of wanted) {
    if (names.has(w.name)) {
      console.log('Package policy exists', w.name);
      continue;
    }
    const res = await request('POST', '/api/fleet/package_policies', {
      name: w.name,
      description: '',
      namespace: 'default',
      policy_id: w.policy_id,
      package: { name: w.pkg, version: versions[w.pkg] },
      inputs: {},
    });
    if (res.conflict) console.log('Package policy already present', w.name);
    else console.log('Created package policy', w.name);
  }
}

async function patchDefend() {
  const res = await request('GET', '/api/fleet/package_policies?perPage=100');
  const items = (res.items || []).filter((p) => p.package && p.package.name === 'endpoint');
  if (!items.length) {
    console.log('No endpoint package policy — skip Defend artifact URL');
    return;
  }

  for (const policy of items) {
    let changed = false;
    for (const input of policy.inputs || []) {
      const value =
        (input.config && input.config.policy && input.config.policy.value) ||
        (input.config && input.config._config && input.config._config.value);
      if (!value || typeof value !== 'object') continue;
      const root = input.config.policy && input.config.policy.value ? input.config.policy.value : value;
      for (const os of ['linux', 'mac', 'windows']) {
        const leaf = ensure(root, [os, 'advanced', 'artifacts', 'global']);
        if (leaf.base_url !== artifactsUrl) {
          leaf.base_url = artifactsUrl;
          changed = true;
        }
      }
    }
    if (!changed) {
      console.log('Defend artifact URL already set on', policy.name);
      continue;
    }
    const body = {
      name: policy.name,
      description: policy.description,
      namespace: policy.namespace,
      policy_id: policy.policy_id,
      policy_ids: policy.policy_ids,
      package: policy.package,
      inputs: policy.inputs,
      vars: policy.vars,
    };
    await request('PUT', '/api/fleet/package_policies/' + policy.id, body);
    console.log('Updated Defend artifacts on', policy.name);
  }
}

(async () => {
  await ensureDownloadSource();
  await ensurePackagePolicies();
  await patchDefend();
})().catch((err) => {
  console.error(err.message || err);
  process.exit(1);
});
EOF
