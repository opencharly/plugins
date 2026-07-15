---
name: airflow-layer
description: |
  Apache Airflow 3.x with LocalExecutor + SQLite (single-node, dev-friendly), 4 supervisord services (init, scheduler, dag-processor, webserver). Layer is service-only — its Python deps live in /charly-versa:marimo-layer's pixi env. No MCP wrapper (no upstream v2 release exists; consumers drive Airflow via direct REST /api/v2 calls).
  Use when working with the airflow layer, Airflow 3.x compatibility findings, the SimpleAuthManager auth-fix pattern, the dag-processor split-from-scheduler architecture change, or the JWT-issuance + REST API trigger flow used by self-authoring notebooks.
---

# airflow — Apache Airflow 3.x layer

LocalExecutor + SQLite — zero external services. Suitable for
single-node dev / R10 verification. For multi-node production swap
in CeleryExecutor + Postgres + Valkey (those layers stayed available
under `candy/postgresql/` + `candy/valkey/`).

This layer is **service-only**: it ships no `pixi.toml`. Its Python
deps (`apache-airflow`) live in `/charly-versa:marimo-layer`'s pixi env,
so airflow runs alongside marimo in the same pod with one combined
Python environment.

## Layer properties

| Property | Value |
|----------|-------|
| Dependencies | `marimo` (for the pixi env), `supervisord` |
| Ports | `8080` (api-server, host-mapped to **28080**) |
| Services | `airflow-init` (one-shot) + `airflow-scheduler` + `airflow-dag-processor` + `airflow-webserver` |
| Volumes | `airflow-data` at `~/airflow` |
| Secrets | `airflow-fernet-key`, `airflow-webserver-secret`, `airflow-admin-password` |
| MCP provides | none (no Airflow-3 / `/api/v2` release of the upstream `mcp-server-apache-airflow` package exists; consumers drive the REST API directly via JWT + `/api/v2/`) |
| DAG folder | `/workspace/dags` (`AIRFLOW__CORE__DAGS_FOLDER`) |

## Airflow 3.x compatibility — 8 RCA findings

The layer was hardened across multiple RCA cycles to handle Airflow
3.x's architectural changes. Each finding is encoded in either the
init script, env vars, or supervisord service list:

### 1. SimpleAuthManager replaced FAB

Airflow 3.x removed `airflow users create`. The new SimpleAuthManager
generates a **random** admin password on first boot and writes it to
`${AIRFLOW_HOME}/simple_auth_manager_passwords.json.generated` —
that random value bears no relation to the `AIRFLOW_ADMIN_PASSWORD`
secret we inject, so JWT auth via `/auth/token` rejects every request
with 401.

**Fix in `airflow-init.sh`**: overwrite the passwords file from
`${AIRFLOW_ADMIN_PASSWORD}` on every boot. Idempotent; tolerant of
secret rotation.

```bash
mkdir -p "${HOME}/airflow"
printf '{"admin": "%s"}\n' "${AIRFLOW_ADMIN_PASSWORD}" \
  > "${HOME}/airflow/simple_auth_manager_passwords.json.generated"
chmod 0600 "${HOME}/airflow/simple_auth_manager_passwords.json.generated"
```

### 2. dag_dir_list_interval moved to dag_processor section

The Airflow-2 key path `[scheduler] dag_dir_list_interval` is
deprecated in 3.x; the canonical key is now
`[dag_processor] refresh_interval`. Layer env block sets:

```yaml
env:
  AIRFLOW__DAG_PROCESSOR__REFRESH_INTERVAL: "10"
```

Default is 300 seconds — far too slow for the runtime-DAG-write
pattern (notebook drops a `.py` and triggers it within seconds). 10s
makes the scan effectively interactive at negligible CPU cost on a
single-user dev pod.

### 3. DAG processor split from scheduler

Airflow 3.x splits the DAG processor out of the scheduler — without a
separate `airflow dag-processor` daemon, the dags folder is **never
scanned** (notebooks waiting on registration deadlock forever).

**Fix**: new `airflow-dag-processor` supervisord service alongside
`airflow-scheduler`. Without this service, `dag_processor.refresh_interval`
has no effect because nothing honors it.

### 4. POST /dagRuns requires logical_date

Airflow 2.x auto-generated `logical_date` if omitted; 3.x rejects with
422. Notebook trigger code must include:

```python
from datetime import datetime, timezone
requests.post(f"{api}/api/v2/dags/{dag_id}/dagRuns",
              headers=auth,
              json={"conf": {}, "logical_date": datetime.now(timezone.utc).isoformat()},
              timeout=10)
```

### 5. webserver renamed to api-server

Airflow 3.x dropped `airflow webserver` in favor of `airflow api-server`
(FastAPI-based). The `airflow-webserver.sh` wrapper was updated:

```bash
exec "${HOME}/.pixi/envs/default/bin/airflow" api-server
```

### 6. Auth backend defaults to JWT

The api-server uses JWT issued by SimpleAuthManager. Clients fetch
a token via `POST /auth/token` (admin/password JSON body), then pass
`Authorization: Bearer <token>` on subsequent calls. Basic auth is
rejected on `/api/v2/` endpoints by default.

### 7. airflow-init must NOT block boot

`airflow-init` is a one-shot supervisord program (`restart: "no"`,
`exit_codes: "0"`) that runs `airflow db migrate` + writes the
passwords file. It exits cleanly on success; the long-running daemons
start at higher priority numbers (30+) once init has finished.

## Service list (4 entries)

| Name | Priority | Restart | Purpose |
|---|---:|---|---|
| `airflow-init` | 25 | no | `airflow db migrate` + write SimpleAuthManager passwords file |
| `airflow-scheduler` | 30 | always | Schedule DAG runs from the metadata DB |
| `airflow-dag-processor` | 31 | always | Scan dags folder + serialise DAGs into the DB |
| `airflow-webserver` | 31 | always | `airflow api-server` (FastAPI on :8080) |

## Check probes (8 — proves the auth + REST paths work)

Build-scope (4):
- `airflow-init-script` `/usr/local/bin/airflow-init.sh` exists + executable
- `airflow-webserver-script` ditto
- `airflow-scheduler-script` ditto
- `airflow-dag-processor-script` ditto (added with #3 above)

Deploy-scope (4):
- `airflow-init-db-created` — `~/airflow/airflow.db` exists (SQLite metadata)
- `airflow-scheduler-running`, `airflow-dag-processor-running`, `airflow-webserver-running` — supervisord program states
- `airflow-port-reachable` — TCP 8080 reachable
- `airflow-http-version` — `GET /api/v2/version` returns 200
- `airflow-jwt-issuance` — `POST /auth/token` with admin creds returns body containing `access_token` (THE notebook auth path; locks in finding #1)

## Notebook self-author DAG pattern

The marimo notebook in `/charly-versa:notebook-osm` writes its own DAG
file into `/workspace/dags/` and triggers it via the REST API:

1. POST `/auth/token` (admin / `$AIRFLOW_ADMIN_PASSWORD`) → JWT
2. Wait for the DAG to register: poll `GET /api/v2/dags/<id>`
   (typically <30 s with `REFRESH_INTERVAL=10`)
3. Unpause: PATCH `/api/v2/dags/<id>` with `{"is_paused": false}`
4. Trigger: POST `/api/v2/dags/<id>/dagRuns` with `logical_date`
5. Poll: GET `/api/v2/dags/<id>/dagRuns/<run_id>` until `state in
   ("success", "failed")`

The notebook uses this pattern to fire BOTH `notebook_osm_pipeline`
and `notebook_gtfs_pipeline` in parallel.

## Cross-references

- `/charly-versa:marimo-layer` — pixi env that owns the airflow Python deps
- `/charly-versa:notebook-osm` — canonical user of the REST trigger pattern
- `/charly-versa:versa` — the image composing this layer
- `/charly-infrastructure:supervisord` — service mgmt
- `/charly-build:secrets` — the 3 airflow secrets injected via this layer
