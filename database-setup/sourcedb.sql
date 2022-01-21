CREATE SCHEMA IF NOT EXISTS threats;

DROP TABLE IF EXISTS threats.malware_file;

CREATE TABLE threats.malware_file (
  time_received TIMESTAMP,
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

COPY threats.malware_file
FROM
  '/source-data/dated_malware_detection.csv' CSV DELIMITER ',' HEADER;