-- Inserts today's batch from the Redshift DWH into an always-online
-- Postgres database on the EC2 instance named supersetdb
-- To ensure idempotency, use upsert method: https://www.postgresqltutorial.com/postgresql-upsert/
INSERT INTO
  public.malware_file (
    "TimeReceived",
    "DownloadSource",
    "TopLevelDomain",
    "PingTimeToServer",
    "FileSizeBytes",
    "ExecutableCodeMaybePresentInHeaders",
    "CallsToLowLevelSystemLibraries",
    "EvidenceOfCodeObfuscation",
    "ThreadsStarted",
    "CharactersInUrl",
    "ActuallyMalicious",
    "InitialStatisticalAnalysis"
  )
SELECT
  *
FROM
  dblink('foreign_server', $REDSHIFT$
    SELECT
      *
    FROM
      "malwaredb"."public"."malware_file"
    WHERE
      time_received < CURRENT_DATE
      AND time_received >= CURRENT_DATE - 1
    ORDER BY
      time_received ASC; --> this is the remote query ran on Redshift, using dblink
$REDSHIFT$) AS today_data (
  time_received TIMESTAMP,
  download_source TEXT,
  top_level_domain TEXT,
  ping_time_to_server INT,
  file_size_bytes NUMERIC,
  executable_code_maybe_present_in_headers TEXT,
  calls_to_low_level_system_libraries NUMERIC,
  evidence_of_code_obfuscation TEXT,
  threads_started INT,
  characters_in_url INT,
  actually_malicious TEXT,
  initial_statistical_analysis TEXT
)
ON CONFLICT ("TimeReceived") -- this clause ensures idempotency ("TimeReceived" has to be unique):
DO NOTHING; -- do not insert if the row with the same "TimeReceived" value already exists