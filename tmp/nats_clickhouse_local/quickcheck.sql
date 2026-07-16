DROP TABLE IF EXISTS nats_local_mv;
DROP TABLE IF EXISTS nats_local_dst;
DROP TABLE IF EXISTS nats_local_src;

CREATE TABLE nats_local_src
(
    key UInt64,
    value String
)
ENGINE = NATS
SETTINGS
    nats_url = 'nats:4222',
    nats_subjects = 'events.local',
    nats_format = 'JSONEachRow',
    nats_username = 'clickhouse',
    nats_password = 'ClickHouse_NATS_P@ssw0rd';

CREATE TABLE nats_local_dst
(
    key UInt64,
    value String
)
ENGINE = MergeTree
ORDER BY key;

CREATE MATERIALIZED VIEW nats_local_mv TO nats_local_dst
AS SELECT key, value FROM nats_local_src;

SELECT 'setup ok' AS status;
