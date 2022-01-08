-- This script is ran only once, to set up a table on the Redshift `public` schema
-- in the database specified with Terraform
DROP TABLE IF EXISTS public.malware_file;

CREATE TABLE public.malware_file (
    TimeReceived TIMESTAMP,
    DownloadSource TEXT,
    TopLevelDomain TEXT,
    DownloadSpeed TEXT,
    PingTimeToServer INT,
    FileSizeBytes NUMERIC,
    HowManyTimesFileSeen INT,
    ExecutableCodeMaybePresentInHeaders TEXT,
    CallsToLowLevelSystemLibraries NUMERIC,
    EvidenceOfCodeObfuscation TEXT,
    ThreadsStarted INT,
    MeanWordLengthOfExtractedStrings NUMERIC,
    SimilarityScore NUMERIC,
    CharactersInUrl INT,
    ActuallyMalicious TEXT,
    InitialStatisticalAnalysis TEXT
);