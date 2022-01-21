-- Only ran once. Putting column names in double-quotes allow Postgres to capitalize them.
DROP TABLE IF EXISTS public.malware_file;

-- TimeReceived is made unique to make use of Postgres' upsert capabilities
CREATE TABLE public.malware_file (
    "TimeReceived" TIMESTAMP UNIQUE,
    "DownloadSource" TEXT,
    "TopLevelDomain" TEXT,
    "PingTimeToServer" INT,
    "FileSizeBytes" NUMERIC,
    "ExecutableCodeMaybePresentInHeaders" TEXT,
    "CallsToLowLevelSystemLibraries" NUMERIC,
    "EvidenceOfCodeObfuscation" TEXT,
    "ThreadsStarted" INT,
    "CharactersInUrl" INT,
    "ActuallyMalicious" TEXT,
    "InitialStatisticalAnalysis" TEXT
);

-- The following code creates a `dblink` function in order to load data from
-- Redshift into a Postgres database running on EC2. Also ran only once.
-- This will ensure that daily data from Redshift is available in an always-online
-- database, even when Redshift is paused.
CREATE EXTENSION postgres_fdw;

CREATE EXTENSION dblink;

CREATE SERVER foreign_server FOREIGN DATA WRAPPER postgres_fdw OPTIONS (
    host 'MY_REDSHIFT_ENDPOINT',
    port '5439',
    dbname 'malwaredb',
    sslmode 'require'
);

CREATE USER MAPPING FOR postgres SERVER foreign_server OPTIONS (
    user 'MY_REDSHIFT_CLUSTER_USERNAME',
    password 'MY_REDSHIFT_CLUSTER_PASSWORD'
);