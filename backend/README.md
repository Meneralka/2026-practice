# document-service - local dev environment

This directory holds the `docker-compose.yml` that stands up the full local
environment for the `document-service` Spring Boot application: the app
itself, Postgres, Kafka (+ Kafka UI), object storage (+ its web console),
and ClamAV.

## Quick start

```bash
cd backend
cp .env.example .env      # first time only - edit if you need different ports/creds
docker compose up -d
docker compose ps          # wait until every service shows "healthy"
```

To stop everything (keeping data volumes):

```bash
docker compose down
```

To stop and wipe all data (Postgres tables, Kafka topics, uploaded objects,
virus DB):

```bash
docker compose down -v
```

## Services, ports, and default credentials

| Service   | Image                  | Host port(s)       | Credentials                              |
|-----------|------------------------|---------------------|-------------------------------------------|
| document-service app | built from `./document-service/Dockerfile` | `8080` | -                            |
| Postgres  | `postgres:16`          | `5433` (host) -> `5432` (container) | db `documentservice`, user/pass `postgres`/`postgres` |
| Kafka     | `apache/kafka:latest`  | `9092`               | none (PLAINTEXT)                          |
| Kafka UI  | `kafbat/kafka-ui:latest` | `8081`             | none                                       |
| Object storage | `rustfs/rustfs:latest` (default) or `minio/minio:latest` | `9000` (S3 API), `9001` (console) | user/pass `devadmin`/`devadmin123` |
| ClamAV    | `clamav/clamav:latest` | `3310` (clamd)        | none                                       |

Note: Postgres is remapped to host port `5433` (container-internal port is
still `5432`) because port `5432` was already taken by an unrelated
container on the dev machine this was set up on. The `app` service always
talks to `postgres:5432` over the internal Docker network regardless of the
host-side mapping.

All of the above are configurable in `.env` (copied from `.env.example`).
Nothing is hardcoded twice - both `docker-compose.yml` and any app config
should read from the same `.env` values.

### Object storage: RustFS vs MinIO

Backlog item 3 ("Проверка RustFS на три фичи") is an open, time-boxed
investigation into whether RustFS actually supports what document-service
needs: object versioning, presigned/temporary links, and immutability of
approved files (object lock / WORM). That investigation is not done yet.

This compose file defaults to **RustFS** (`rustfs/rustfs:latest`) because a
real, actively maintained image exists on Docker Hub and it is the
candidate under evaluation. A **MinIO** service is included side-by-side,
disabled by default, as the fallback if RustFS fails the evaluation.

Switch backends by changing one line in `.env`:

```bash
# use RustFS (default)
COMPOSE_PROFILES=rustfs

# or use MinIO instead
COMPOSE_PROFILES=minio
```

Then `docker compose up -d` again. Both services bind the same host ports
(9000/9001) and read the same `OBJECT_STORAGE_ROOT_USER` /
`OBJECT_STORAGE_ROOT_PASSWORD` / port variables, so no other config needs to
change when swapping.

Note: RustFS's own Docker Hub page currently states "RustFS is under rapid
development. Do NOT use in production environments!" - fine for local dev,
but a real signal for the pending decision.

See `backend/rustfs-evaluation.md` for the actual three-feature check
(versioning, presigned URLs, immutability of approved files). Summary as of
this writing: versioning works; presigned URLs and WORM/Object Lock
(Compliance mode) work with caveats - open bugs allow deletes to bypass a
Compliance-mode retention lock, which undermines the "can't touch an
approved file" requirement. Recommendation there is a hands-on spike before
committing to RustFS, with MinIO as the fallback - which is exactly what
the `COMPOSE_PROFILES` switch above is for.

## Kafka networking (KRaft mode, no Zookeeper)

Kafka runs as a single combined broker+controller node using KRaft (no
Zookeeper container needed). It exposes two listeners:

- `PLAINTEXT` on `kafka:29092` - for other containers on the
  `document-service-net` compose network.
- `PLAINTEXT_HOST` on `localhost:9092` - for the Spring Boot app running on
  the host.

Set `spring.kafka.bootstrap-servers=localhost:9092` in the app's local
config.

## Verifying health

```bash
docker compose ps
```

Every row should say `healthy` (Postgres and Kafka typically flip healthy
within ~30s; RustFS/MinIO within ~15-20s; ClamAV can take longer on first
boot while it downloads virus definitions - `start_period` is set to 2
minutes to account for this).

Per-service manual checks:

**Postgres**

```bash
docker exec document-service-postgres pg_isready -U postgres -d documentservice
psql -h localhost -p 5432 -U postgres -d documentservice   # password: postgres
```

**Kafka**

```bash
docker exec document-service-kafka /opt/kafka/bin/kafka-broker-api-versions.sh --bootstrap-server localhost:9092
```

**Kafka UI**

Web console at http://localhost:8081 - browse topics, messages, consumer
groups, and broker config without a CLI.

**Object storage (RustFS)**

```bash
curl http://localhost:9000/health
# -> {"status":"ok","ready":true,...}
```
Console UI: http://localhost:9001/rustfs/console (sign in with
`OBJECT_STORAGE_ROOT_USER` / `OBJECT_STORAGE_ROOT_PASSWORD` from `.env`).

**Object storage (MinIO, if that profile is active)**

```bash
curl http://localhost:9000/minio/health/live
```
Console UI: http://localhost:9001

**ClamAV**

```bash
docker exec document-service-clamav clamdscan --version
```

**document-service app**

```bash
curl http://localhost:8080/actuator/health
# -> {"status":"UP","groups":["liveness","readiness"]}
```
Swagger UI: http://localhost:8080/swagger-ui.html
