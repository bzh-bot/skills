#!/usr/bin/env bash
# demo-tools.sh — the REAL tools a backend/schema demo must be filmed in, self-hosted
# inside the cage's own Docker daemon.
#
# Why this exists: a pretty-printed `curl` or a hand-rolled "rows" table is not
# evidence. It says nothing about what a reviewer would actually see in the product's
# own tooling, and it cannot be trusted (the presenter chose the formatting). So:
#   HTTP / API request demos        → Hoppscotch        (self-hosted, fixed port)
#   database rows / table state     → CloudBeaver       (self-hosted, fixed port)
#   spreadsheets / tabular export   → Google Sheets     (browser, login gate — see docs)
# The evidence gate FAILS a beat that shows a custom UI while these are up.
#
# Usage (inside the cage — it drives the cage's DinD daemon):
#   demo-tools.sh up      [--force-connection]   bring both up, wait, record URLs
#   demo-tools.sh status                          what is running + health + URLs
#   demo-tools.sh require                         exit 1 unless both are healthy (a gate)
#   demo-tools.sh down    [--purge]               stop/remove containers (keep data)
#
# Fixed ports (override with env if the run's app owns one):
#   CloudBeaver   127.0.0.1:8978      DEMO_CB_PORT=8978
#   Hoppscotch    127.0.0.1:3300      DEMO_HOPP_PORT=3300      (webapp)
#   Hoppscotch    127.0.0.1:3170      DEMO_HOPP_API_PORT=3170  (GraphQL/API backend)
#
# The run's own database is pre-configured as a CloudBeaver connection, reaching it on
# the cage's loopback (CloudBeaver runs with --network host, so 127.0.0.1 is the run's
# 127.0.0.1). Never point this at a real/production database: the dev password is stored
# in the CloudBeaver workspace volume.
#
# Images and cost (pre-pull these into the cage image for offline runs):
#   dbeaver/cloudbeaver:latest      705 MB   ~0.7-1.2 GB RAM
#   hoppscotch/hoppscotch:latest    832 MB   ~0.5-0.8 GB RAM  (AIO: webapp + backend)
#   postgres:16                     451 MB   ~50 MB RAM
#   → budget ~2 GB RAM and ~2 GB disk per cage; first `up` pulls (~2-4 min).
set -uo pipefail

DEMO_NET="${DEMO_NET:-workflow-demo}"
CB_NAME="${DEMO_CB_NAME:-workflow-demo-cloudbeaver}"
CB_VOL="${DEMO_CB_VOLUME:-workflow-demo-cloudbeaver-ws}"
CB_IMG="${DEMO_CB_IMAGE:-dbeaver/cloudbeaver:latest}"
CB_PORT="${DEMO_CB_PORT:-8978}"
HOPP_NAME="${DEMO_HOPP_NAME:-workflow-demo-hoppscotch}"
HOPP_PG="${DEMO_HOPP_PG_NAME:-workflow-demo-hoppscotch-pg}"
HOPP_PG_VOL="${DEMO_HOPP_PG_VOLUME:-workflow-demo-hoppscotch-pg-data}"
HOPP_IMG="${DEMO_HOPP_IMAGE:-hoppscotch/hoppscotch:latest}"
PG_IMG="${DEMO_PG_IMAGE:-postgres:16}"
HOPP_PORT="${DEMO_HOPP_PORT:-3300}"
HOPP_API_PORT="${DEMO_HOPP_API_PORT:-3170}"
CB_WAIT="${DEMO_CB_WAIT:-180}"
HOPP_WAIT="${DEMO_HOPP_WAIT:-240}"

VIDEO_DIR="${VIDEO_DIR:-$PWD/.workflow-video}"
RUN_ENV="${DEMO_RUN_ENV:-/tmp/workflow-run.env}"
STATE_JSON="$VIDEO_DIR/demo-tools.json"
COLLECTION="$VIDEO_DIR/demo-tools/hoppscotch-collection.json"

# The run's own Postgres. Defaults match the most common local dev stack.
DB_HOST="${DEMO_DB_HOST:-127.0.0.1}"
DB_PORT="${DEMO_DB_PORT:-5432}"
DB_NAME="${DEMO_DB_NAME:-postgres}"
DB_USER="${DEMO_DB_USER:-postgres}"
DB_PASSWORD="${DEMO_DB_PASSWORD:-postgres}"
DB_URL="${DEMO_DB_URL:-}"
if [ -n "$DB_URL" ]; then
  # postgresql://user:pass@host:port/db → the CloudBeaver connection wants the parts
  DB_USER="${DB_URL#*://}"; DB_USER="${DB_USER%%:*}"
  DB_PASSWORD="${DB_URL#*://*:}"; DB_PASSWORD="${DB_PASSWORD%%@*}"
  DB_HOST="${DB_URL#*@}"; DB_HOST="${DB_HOST%%:*}"
  DB_PORT="${DB_URL#*@*:}"; DB_PORT="${DB_PORT%%/*}"
  DB_NAME="${DB_URL##*/}"; DB_NAME="${DB_NAME%%\?*}"
fi
DB_JDBC="${DEMO_DB_JDBC:-jdbc:postgresql://$DB_HOST:$DB_PORT/$DB_NAME}"
API_BASE="${DEMO_API_BASE:-http://127.0.0.1:8080}"

log()  { printf '  %s\n' "$*"; }
die()  { printf 'FAIL: %s\n' "$*" >&2; exit 1; }
need() { command -v "$1" >/dev/null 2>&1 || die "$1 is not on PATH"; }

docker_ok() { docker info >/dev/null 2>&1; }
exists()    { docker container inspect "$1" >/dev/null 2>&1; }
running()   { [ "$(docker container inspect -f '{{.State.Running}}' "$1" 2>/dev/null)" = "true" ]; }
pg_ready()  { docker exec "$HOPP_PG" pg_isready -U postgres -d hoppscotch >/dev/null 2>&1; }
http_ok()   { [ "$(curl -s -o /dev/null -w '%{http_code}' --max-time 4 "$1" 2>/dev/null)" = "200" ]; }

wait_for() { # wait_for <label> <timeout-s> <command...>
  local label="$1" timeout="$2"; shift 2
  local i=0
  while [ "$i" -lt "$timeout" ]; do
    if "$@" >/dev/null 2>&1; then log "$label ready after ~${i}s"; return 0; fi
    sleep 2; i=$((i + 2))
  done
  return 1
}

ensure_network() {
  docker network inspect "$DEMO_NET" >/dev/null 2>&1 || docker network create "$DEMO_NET" >/dev/null
}

# write the run's DB into the CloudBeaver workspace as a preconfigured connection.
# CloudBeaver reads ${WORKSPACE}/GlobalConfiguration/.dbeaver/data-sources.json at boot;
# writing it from a throwaway container avoids host/container uid ownership problems.
seed_cloudbeaver() {
  local force="${1:-}"
  # CloudBeaver reads this file at boot. Writing it from a throwaway container avoids
  # host/container uid ownership problems on the workspace volume.
  if [ -z "$force" ] && docker run --rm -v "$CB_VOL:/ws" --entrypoint sh "$CB_IMG" \
       -c "test -s /ws/GlobalConfiguration/.dbeaver/data-sources.json" >/dev/null 2>&1; then
    log "CloudBeaver connection already seeded (--force-connection rewrites it)"
    return 0
  fi
  DB_HOST="$DB_HOST" DB_PORT="$DB_PORT" DB_NAME="$DB_NAME" DB_USER="$DB_USER" \
  DB_PASSWORD="$DB_PASSWORD" DB_JDBC="$DB_JDBC" python3 - <<'PY' \
    | docker run --rm -i -v "$CB_VOL:/ws" --entrypoint sh "$CB_IMG" \
        -c 'mkdir -p /ws/GlobalConfiguration/.dbeaver && cat > /ws/GlobalConfiguration/.dbeaver/data-sources.json'
import json, os
cfg = {
  "folders": {},
  "connections": {
    "workflowRunDb": {
      "provider": "postgresql",
      "driver": "postgres-jdbc",
      "name": "Run DB (workflow)",
      "description": "The database this run actually uses - query it, do not mock it",
      "save-password": True,
      "read-only": False,
      "configuration": {
        "host": os.environ["DB_HOST"],
        "port": os.environ["DB_PORT"],
        "database": os.environ["DB_NAME"],
        "url": os.environ["DB_JDBC"],
        "configurationType": "MANUAL",
        "type": "dev",
        "auth-model": "native",
        "auth-properties": {"user": os.environ["DB_USER"], "password": os.environ["DB_PASSWORD"]},
      },
    }
  },
}
print(json.dumps(cfg, indent=2))
PY
  log "seeded CloudBeaver connection -> $DB_JDBC ($DB_USER)"
}

start_cb() {
  if exists "$CB_NAME"; then
    running "$CB_NAME" || { docker start "$CB_NAME" >/dev/null; log "started existing $CB_NAME"; }
  else
    docker run -d --name "$CB_NAME" --restart unless-stopped --network host \
      -v "$CB_VOL:/opt/cloudbeaver/workspace" "$CB_IMG" >/dev/null
    log "created $CB_NAME (host network, port $CB_PORT)"
  fi
}

start_hoppscotch() {
  if ! exists "$HOPP_PG"; then
    docker run -d --name "$HOPP_PG" --restart unless-stopped --network "$DEMO_NET" \
      -v "$HOPP_PG_VOL:/var/lib/postgresql/data" \
      -e POSTGRES_USER=postgres -e POSTGRES_PASSWORD=testpass -e POSTGRES_DB=hoppscotch \
      "$PG_IMG" >/dev/null
    log "created Hoppscotch's Postgres ($HOPP_PG)"
  else
    running "$HOPP_PG" || docker start "$HOPP_PG" >/dev/null
  fi
  wait_for "hoppscotch-db" 60 pg_ready || die "Hoppscotch's Postgres never became ready (docker logs $HOPP_PG)"

  # The AIO image does NOT auto-migrate: without this the backend exits with
  # "Database migration not found". `prisma migrate deploy` is idempotent.
  local dsn="postgresql://postgres:testpass@$HOPP_PG:5432/hoppscotch?connect_timeout=300"
  log "applying Hoppscotch migrations (idempotent)"
  docker run --rm --network "$DEMO_NET" -e DATABASE_URL="$dsn" -w /dist/backend --entrypoint sh "$HOPP_IMG" \
    -c './node_modules/.bin/prisma migrate deploy' >/tmp/demo-tools-migrate.log 2>&1 \
    || { tail -5 /tmp/demo-tools-migrate.log >&2; die "Hoppscotch migrations failed"; }

  if exists "$HOPP_NAME"; then
    running "$HOPP_NAME" || { docker start "$HOPP_NAME" >/dev/null; log "started existing $HOPP_NAME"; }
  else
    docker run -d --name "$HOPP_NAME" --restart unless-stopped --network "$DEMO_NET" \
      -e DATABASE_URL="$dsn" \
      -e DATA_ENCRYPTION_KEY="${DEMO_DATA_ENCRYPTION_KEY:-0123456789abcdef0123456789abcdef}" \
      -e VITE_BASE_URL="http://127.0.0.1:$HOPP_PORT" \
      -e VITE_SHORTCODE_BASE_URL="http://127.0.0.1:$HOPP_PORT" \
      -e VITE_ADMIN_URL="http://127.0.0.1:3100" \
      -e VITE_BACKEND_GQL_URL="http://127.0.0.1:$HOPP_API_PORT/graphql" \
      -e VITE_BACKEND_WS_URL="ws://127.0.0.1:$HOPP_API_PORT/graphql" \
      -e VITE_BACKEND_API_URL="http://127.0.0.1:$HOPP_API_PORT/v1" \
      -e WHITELISTED_ORIGINS="http://127.0.0.1:$HOPP_PORT,http://localhost:$HOPP_PORT,http://127.0.0.1:$HOPP_API_PORT,http://localhost:$HOPP_API_PORT" \
      -e PROXY_APP_URL="" \
      -p "127.0.0.1:$HOPP_PORT:3000" -p "127.0.0.1:$HOPP_API_PORT:3170" \
      "$HOPP_IMG" >/dev/null
    log "created $HOPP_NAME (webapp :$HOPP_PORT, backend :$HOPP_API_PORT)"
  fi
}

# a Hoppscotch import file with the run's REAL base URL and the requests the beats use.
# Hoppscotch's own import UI is used (Collections → Import); the collection lands in the
# run's persistent Chrome profile, so it survives a re-capture.
write_collection() {
  mkdir -p "$(dirname "$COLLECTION")"
  API_BASE="$API_BASE" COLLECTION="$COLLECTION" python3 - <<'PY'
import json, os, re
base = os.environ["API_BASE"].rstrip("/")
path = os.environ["COLLECTION"]
requests = []
extra = os.environ.get("DEMO_REQUEST_SPEC", "")   # "METHOD path {json-body}" per line, ';'-separated
for spec in filter(None, (s.strip() for s in extra.split(";"))):
    m = re.match(r"^([A-Z]+)\s+(\S+)\s*(.*)$", spec)
    if not m:
        continue
    method, url, body = m.group(1), m.group(2), m.group(3).strip()
    req = {"v": "10", "name": f"{method} {url}", "method": method,
           "endpoint": f"{base}{url}", "params": [], "headers": [],
           "preRequestScript": "", "testScript": "", "auth": {"authType": "none", "authActive": True}}
    if body:
        req["body"] = {"contentType": "application/json", "body": body}
    requests.append(req)
if not requests:
    # a seed request that proves the tool is wired to the run, not to a mock
    requests = [{"v": "10", "name": "GET / (run API base)", "method": "GET",
                 "endpoint": f"{base}/", "params": [], "headers": [],
                 "preRequestScript": "", "testScript": "", "auth": {"authType": "none", "authActive": True}}]
coll = {"v": 1, "name": "Workflow run — real API", "folders": [], "requests": requests}
json.dump(coll, open(path, "w"), indent=2)
print(path)
PY
}

record_state() {
  mkdir -p "$(dirname "$STATE_JSON")"
  cat > "$STATE_JSON" <<EOF
{
  "cloudbeaver_url": "http://127.0.0.1:$CB_PORT",
  "cloudbeaver_connection": "Run DB (workflow)",
  "cloudbeaver_jdbc": "$DB_JDBC",
  "cloudbeaver_user": "$DB_USER",
  "hoppscotch_url": "http://127.0.0.1:$HOPP_PORT",
  "hoppscotch_api_url": "http://127.0.0.1:$HOPP_API_PORT",
  "hoppscotch_graphql": "http://127.0.0.1:$HOPP_API_PORT/graphql",
  "hoppscotch_collection": "$COLLECTION",
  "api_base": "$API_BASE",
  "containers": ["$CB_NAME", "$HOPP_NAME", "$HOPP_PG"],
  "network": "$DEMO_NET",
  "state": "up"
}
EOF

  # record into the run env idempotently: replace our marker block, never duplicate it.
  mkdir -p "$(dirname "$RUN_ENV")"
  touch "$RUN_ENV"
  awk 'BEGIN{skip=0} /^# >>> workflow demo tools >>>$/{skip=1;next} /^# <<< workflow demo tools <<<$/{skip=0;next} skip==0{print}' \
    "$RUN_ENV" > "$RUN_ENV.tmp" && mv "$RUN_ENV.tmp" "$RUN_ENV"
  cat >> "$RUN_ENV" <<EOF
# >>> workflow demo tools >>>
export DEMO_CLOUDBEAVER_URL="http://127.0.0.1:$CB_PORT"
export DEMO_CLOUDBEAVER_CONNECTION="Run DB (workflow)"
export DEMO_CLOUDBEAVER_JDBC="$DB_JDBC"
export DEMO_CLOUDBEAVER_USER="$DB_USER"
export DEMO_HOPPSCOTCH_URL="http://127.0.0.1:$HOPP_PORT"
export DEMO_HOPPSCOTCH_API_URL="http://127.0.0.1:$HOPP_API_PORT"
export DEMO_HOPPSCOTCH_GRAPHQL="http://127.0.0.1:$HOPP_API_PORT/graphql"
export DEMO_HOPPSCOTCH_COLLECTION="$COLLECTION"
export DEMO_API_BASE="$API_BASE"
export DEMO_TOOLS_STATE="$STATE_JSON"
# <<< workflow demo tools <<<
EOF
}

cmd_up() {
  local force_conn=""
  [ "${1:-}" = "--force-connection" ] && force_conn=1
  need docker; need curl
  docker_ok || die "no Docker daemon: this helper runs INSIDE the cage (DinD). On the host it may work too, but the URLs are for the cage's browser."
  ensure_network
  seed_cloudbeaver "$force_conn"
  start_cb
  start_hoppscotch
  write_collection >/dev/null || die "could not write the Hoppscotch collection"

  wait_for "CloudBeaver" "$CB_WAIT" bash -c "curl -s -o /dev/null -w '%{http_code}' --max-time 4 http://127.0.0.1:$CB_PORT/status | grep -q 200" \
    || die "CloudBeaver did not answer http://127.0.0.1:$CB_PORT/status — docker logs $CB_NAME"
  wait_for "Hoppscotch webapp" "$HOPP_WAIT" bash -c "curl -s -o /dev/null -w '%{http_code}' --max-time 4 http://127.0.0.1:$HOPP_PORT/ | grep -q 200" \
    || die "Hoppscotch webapp did not answer — docker logs $HOPP_NAME"
  wait_for "Hoppscotch backend" 120 bash -c "curl -s --max-time 5 -X POST -H 'content-type: application/json' -d '{\"query\":\"{__typename}\"}' http://127.0.0.1:$HOPP_API_PORT/graphql | grep -q __typename" \
    || die "Hoppscotch backend did not answer /graphql — docker logs $HOPP_NAME"

  record_state
  cmd_status
  cat <<EOF

Next (this is the evidence gate — do not film a custom UI while these are up):
  1. HTTP/API beat   → Hoppscotch, import $COLLECTION (Collections → Import), base $API_BASE
  2. DB/schema beat  → CloudBeaver → Run DB (workflow) → SQL editor; real rows, real DDL
  3. tabular export  → Google Sheets in the browser (signed-in profile required; if the
                       account is not signed in, STOP and ask the user — never substitute
                       a hand-built table)

When the capture is done: demo-tools.sh down   (data is kept; --purge removes it)
EOF
}

cmd_status() {
  echo "── demo tools ─────────────────────────────────────────────"
  for c in "$CB_NAME" "$HOPP_NAME" "$HOPP_PG"; do
    if exists "$c"; then
      printf '  %-34s %s\n' "$c" "$(docker container inspect -f '{{.State.Status}}' "$c")"
    else
      printf '  %-34s %s\n' "$c" "absent"
    fi
  done
  local cb="down" hopp="down" api="down"
  http_ok "http://127.0.0.1:$CB_PORT/status" && cb="ok"
  http_ok "http://127.0.0.1:$HOPP_PORT/" && hopp="ok"
  curl -s --max-time 5 -X POST -H 'content-type: application/json' -d '{"query":"{__typename}"}' \
    "http://127.0.0.1:$HOPP_API_PORT/graphql" 2>/dev/null | grep -q __typename && api="ok"
  printf '  %-34s %s\n' "CloudBeaver  :$CB_PORT" "$cb"
  printf '  %-34s %s\n' "Hoppscotch    :$HOPP_PORT" "$hopp"
  printf '  %-34s %s\n' "Hoppscotch API:$HOPP_API_PORT" "$api"
  [ -f "$STATE_JSON" ] && echo "  state    $STATE_JSON"
  [ -f "$COLLECTION" ] && echo "  collection $COLLECTION"
  # DinD reports 0B for MemUsage (no cgroup accounting inside the cage), so PIDs is the
  # honest liveness signal. Budget ~2 GB RAM for the three containers (see the header).
  echo "  pids     $(docker stats --no-stream --format '{{.Name}}={{.PIDs}}' "$CB_NAME" "$HOPP_NAME" "$HOPP_PG" 2>/dev/null | tr '\n' ' ')"
}

cmd_require() {
  need curl
  # Prefer the recorded state over recomputing: stages must not hardcode ports.
  if [ -f "$STATE_JSON" ]; then
    local state_url state_api
    state_url=$(python3 -c 'import json,sys;print(json.load(open(sys.argv[1])).get("cloudbeaver_url",""))' "$STATE_JSON" 2>/dev/null || true)
    state_api=$(python3 -c 'import json,sys;d=json.load(open(sys.argv[1]));print(d.get("api_base",""))' "$STATE_JSON" 2>/dev/null || true)
    [ -n "$state_url" ] && CB_PORT="${state_url##*:}"
    [ -n "$state_api" ] && API_BASE="$state_api"
  fi
  local bad=0
  http_ok "http://127.0.0.1:$CB_PORT/status" || { echo "CloudBeaver is not up at http://127.0.0.1:$CB_PORT" >&2; bad=1; }
  http_ok "http://127.0.0.1:$HOPP_PORT/" || { echo "Hoppscotch is not up at http://127.0.0.1:$HOPP_PORT" >&2; bad=1; }
  if [ "$bad" = "1" ]; then
    cat >&2 <<EOF

EVIDENCE GATE FAILED: the real tools are not available, so this beat cannot be filmed
in them. Run \`$(basename "$0") up\` first.
Do NOT substitute a custom table, a hand-rolled HTML page or pretty-printed curl output —
those are not evidence. If the tools genuinely cannot run here, stop and ask the user.
EOF
    exit 1
  fi
  echo "✅ demo tools are up: CloudBeaver http://127.0.0.1:$CB_PORT · Hoppscotch http://127.0.0.1:$HOPP_PORT (API base $API_BASE)"
}

cmd_down() {
  local purge=0
  [ "${1:-}" = "--purge" ] && purge=1
  docker rm -f "$HOPP_NAME" "$HOPP_PG" "$CB_NAME" >/dev/null 2>&1 || true
  if [ "$purge" = "1" ]; then
    docker volume rm "$CB_VOL" "$HOPP_PG_VOL" >/dev/null 2>&1 || true
    docker network rm "$DEMO_NET" >/dev/null 2>&1 || true
    rm -f "$STATE_JSON"
    log "purged containers, connection workspace and network"
  else
    log "containers removed; the CloudBeaver connection and Hoppscotch DB volumes are kept"
  fi
}

case "${1:-}" in
  up)      shift; cmd_up "${1:-}" ;;
  status)  cmd_status ;;
  require) cmd_require ;;
  down)    shift; cmd_down "${1:-}" ;;
  *) sed -n '2,40p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
esac
