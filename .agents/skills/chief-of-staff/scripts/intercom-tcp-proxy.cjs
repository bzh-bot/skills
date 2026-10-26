#!/usr/bin/env node
// TCP :9458 -> unix broker.sock bridge for cages (fallback when socat is absent).
// Linux hosts have no socat here, but cages still dial host.docker.internal:9458.
const net = require("net");
const path = require("path");
const os = require("os");
const fs = require("fs");

const PORT = Number(process.env.INTERCOM_BRIDGE_PORT || 9458);
const SOCK =
  process.env.INTERCOM_SOCK ||
  path.join(process.env.PI_CODING_AGENT_DIR || path.join(os.homedir(), ".pi/agent"), "intercom", "broker.sock");

if (!fs.existsSync(SOCK)) {
  console.error(`intercom-tcp-proxy: broker socket missing at ${SOCK}`);
  process.exit(1);
}

const server = net.createServer((client) => {
  client.setNoDelay(true);
  const upstream = net.connect(SOCK);
  const kill = () => {
    client.destroy();
    upstream.destroy();
  };
  client.on("error", kill);
  upstream.on("error", kill);
  client.on("close", () => upstream.destroy());
  upstream.on("close", () => client.destroy());
  client.pipe(upstream).pipe(client);
});

server.on("error", (e) => {
  console.error(`intercom-tcp-proxy: ${e.message}`);
  process.exit(1);
});

server.listen(PORT, "0.0.0.0", () => {
  console.log(`intercom-tcp-proxy: 0.0.0.0:${PORT} -> ${SOCK}`);
});
