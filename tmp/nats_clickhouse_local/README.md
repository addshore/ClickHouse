# Quick local NATS + ClickHouse validation

This is a minimal local stack to validate the NATS table engine quickly.

## What it starts
- `nats` on `localhost:4222`
- `clickhouse` on `localhost:8123` / `localhost:9000`
- `nats-box` helper container (for `nats pub`)

## Run
From this directory (`tmp/nats_clickhouse_local`):

- Start stack: `docker compose up -d`
- Create objects: `docker compose exec clickhouse clickhouse-client -n < /workspace/quickcheck.sql`

If `/workspace/quickcheck.sql` path does not exist in your image, use:
`docker compose cp quickcheck.sql clickhouse:/tmp/quickcheck.sql`
then:
`docker compose exec clickhouse clickhouse-client -n < /tmp/quickcheck.sql`

## Publish a test message
`docker compose exec nats-box nats --server nats://clickhouse:ClickHouse_NATS_P@ssw0rd@nats:4222 pub events.local '{"key":1,"value":"hello"}'`

## Verify in ClickHouse
`docker compose exec clickhouse clickhouse-client -q "SELECT * FROM nats_local_dst ORDER BY key"`

## Validate your new inline credentials setting (`nats_credentials`)
This stack uses user/password for simplicity. To validate `nats_credentials`, point ClickHouse at a NATS server configured for JWT/NKey auth and create a table like:

`SETTINGS nats_credentials = '-----BEGIN NATS USER JWT-----\\n...\\n------END NATS USER JWT------\\n\\n************************* IMPORTANT *************************\\nNKEY Seed printed below can be used to sign and prove identity.\\nNKEYs are sensitive and should be treated as secrets.\\n\\n-----BEGIN USER NKEY SEED-----\\nSU...\\n------END USER NKEY SEED------\\n'`

In other words, the setting takes the same payload as a `.creds` file, in-memory.

## Stop
`docker compose down -v`
