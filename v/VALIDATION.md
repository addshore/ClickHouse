# Validation proof

This records the local Docker validation of the NATS inline-credentials change.

## Build

- Command: `python -m ci.praktika run "Build (amd_debug)"`
- Result: `OK`
- Built executable: `ci/tmp/build/programs/clickhouse`

### Build log excerpt

```text
=== Run script [Build (amd_debug)], workflow [PR] ===
...
-- Building sub-tree with 12 compile jobs and 6 linker jobs
...
-- Building ClickHouse: OK
```

## Runtime smoke test

- Local stack: `tmp/nats_clickhouse_local/docker-compose.yml`
- Baseline NATS table creation with `nats_username` / `nats_password`: passed
- Message publish to `events.local`: passed
- ClickHouse server started from the patched binary inside Docker: passed

### Runtime log excerpt

```text
NAME                                 IMAGE                                 COMMAND
nats_clickhouse_local-clickhouse-1   clickhouse/clickhouse-server:latest   "/entrypoint.sh"
...
26.7.1.0        B8B3FC6FADE029AAAF0D8CBD477569B78493A37C
```

### Smoke-test shell transcript

```text
setup ok
17:32:12 Published 37 bytes to "events.local"
```

### Fresh end-to-end rerun

I re-ran the smoke test from scratch on the same setup and waited for the consumer to process the message before checking the destination table.

```text
18:50:38 Published 35 bytes to "events.local"
1       8       8
8       proof-row-delay
```

That is the clearest proof in this validation run that the NATS source table consumed a published message and the materialized view wrote it into `nats_local_dst`.

## Inline credentials proof

The following runtime checks were observed on the patched server:

- Creating a table with both `nats_credentials` and `nats_credential_file` fails with:
  - `You can specify only one of nats_credential_file and nats_credentials.`
- Creating a table with only `nats_credentials` reaches the NATS auth path and fails on the intentionally invalid creds payload with:
  - `Cannot connect to Nats last error: (nkeys.c:83): invalid checksum.`

### Error-path excerpt

```text
Received exception from server (version 26.7.1):
Code: 36. DB::Exception: ... You can specify only one of `nats_credential_file` and `nats_credentials`. (BAD_ARGUMENTS)

Received exception from server (version 26.7.1):
Code: 665. DB::Exception: ... Cannot connect to Nats last error: (nkeys.c:83): invalid checksum. (CANNOT_CONNECT_NATS)
```

### Inline-creds command transcript

```text
cd /home/adam/dev/github/ClickHouse/ClickHouse/tmp/nats_clickhouse_local
docker compose exec -T clickhouse clickhouse-client -q "DROP TABLE IF EXISTS nats_inline_only"
docker compose exec -T clickhouse clickhouse-client -q "CREATE TABLE nats_inline_only (key UInt64, value String) ENGINE = NATS SETTINGS nats_url='nats:4222', nats_subjects='events.local', nats_format='JSONEachRow', nats_credentials='-----BEGIN NATS USER JWT-----\ninvalid\n------END NATS USER JWT------\n\n-----BEGIN USER NKEY SEED-----\nSUAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA\n------END USER NKEY SEED------\n'"
Received exception from server (version 26.7.1):
Code: 665. DB::Exception: Received from localhost:9000. DB::Exception: Cannot connect to Nats last error: (nkeys.c:83): invalid checksum. (CANNOT_CONNECT_NATS)
```

### Mutually-exclusive credentials transcript

```text
cd /home/adam/dev/github/ClickHouse/ClickHouse/tmp/nats_clickhouse_local
docker compose exec -T clickhouse clickhouse-client -q "DROP TABLE IF EXISTS nats_conflict"
docker compose exec -T clickhouse clickhouse-client -q "CREATE TABLE nats_conflict (key UInt64, value String) ENGINE = NATS SETTINGS nats_url='nats:4222', nats_subjects='events.local', nats_format='JSONEachRow', nats_credentials='dummy-creds', nats_credential_file='/tmp/dummy.creds'"
Received exception from server (version 26.7.1):
Code: 36. DB::Exception: Received from localhost:9000. DB::Exception: You can specify only one of `nats_credential_file` and `nats_credentials`. (BAD_ARGUMENTS)
```

### File-based credentials transcript

```text
cd /home/adam/dev/github/ClickHouse/ClickHouse/tmp/nats_clickhouse_local
cat > creds.creds <<'EOF'
-----BEGIN NATS USER JWT-----
invalid
------END NATS USER JWT------

-----BEGIN USER NKEY SEED-----
SUAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA
------END USER NKEY SEED------
EOF
docker compose down -v
docker compose up -d
docker compose exec -T clickhouse sh -lc 'ls -l /workspace && ls -l /workspace/creds.creds'
total 16
-rw-r--r-- 1 1000 1000  186 Jul 16 18:58 creds.creds
... /workspace/creds.creds
docker compose exec -T clickhouse clickhouse-client -q "DROP TABLE IF EXISTS nats_file_only"
docker compose exec -T clickhouse clickhouse-client -q "CREATE TABLE nats_file_only (key UInt64, value String) ENGINE = NATS SETTINGS nats_url='nats:4222', nats_subjects='events.local', nats_format='JSONEachRow', nats_credential_file='/workspace/creds.creds'"
Received exception from server (version 26.7.1):
Code: 665. DB::Exception: Received from localhost:9000. DB::Exception: Cannot connect to Nats last error: (nkeys.c:83): invalid checksum. (CANNOT_CONNECT_NATS)
```

## Working credentials proof

After bootstrapping a local operator/account/user with `nsc init`, I generated a real `.creds` payload and used it both from disk and inline.

### File-based happy path

```text
docker compose exec -T clickhouse sh -lc 'clickhouse-client --multiquery < /workspace/file_auth.sql'
file auth setup ok
/home/adam/go/bin/nats --server nats://localhost:4222 --creds good.creds pub events.creds.file '{"key":2,"value":"file-2"}'
20:03:15 Published 26 bytes to "events.creds.file"
docker compose exec -T clickhouse clickhouse-client -q "SELECT count(), groupArray((key, value)) FROM nats_file_dst"
1       [(2,'file-2')]
```

### Inline happy path

```text
docker compose exec -T clickhouse sh -lc 'clickhouse-client --multiquery < /workspace/inline_auth.sql'
inline auth setup ok
/home/adam/go/bin/nats --server nats://localhost:4222 --creds good.creds pub events.creds.inline '{"key":4,"value":"inline-2"}'
20:03:36 Published 28 bytes to "events.creds.inline"
docker compose exec -T clickhouse clickhouse-client -q "SELECT count(), groupArray((key, value)) FROM nats_inline_dst"
1       [(4,'inline-2')]
```

That confirms both `nats_credential_file` and `nats_credentials` can use a real JWT / seed pair successfully, not just the invalid-checksum rejection path.