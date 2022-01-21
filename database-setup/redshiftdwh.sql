-- This script is ran only once, to set up a table on the Redshift `public` schema
-- in the database specified with Terraform
DROP TABLE IF EXISTS public.malware_file;

CREATE TABLE public.malware_file (
    time_received TIMESTAMP UNIQUE,
    download_source TEXT,
    top_level_domain TEXT,
    download_speed TEXT,
    ping_time_to_server INT,
    file_size_bytes NUMERIC,
    how_many_times_file_seen INT,
    executable_code_maybe_present_in_headers TEXT,
    calls_to_low_level_system_libraries NUMERIC,
    evidence_of_code_obfuscation TEXT,
    threads_started INT,
    mean_word_length_of_extracted_strings NUMERIC,
    similarity_score NUMERIC,
    characters_in_url INT,
    actually_malicious TEXT,
    initial_statistical_analysis TEXT
);