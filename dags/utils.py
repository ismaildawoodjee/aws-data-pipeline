"""Utility functions to connect with AWS infrastructure and/or transfer local files 
to resources such as S3, EMR, Redshift, etc. Also includes a Python function to process 
file locally (attach datetime column weekly) before sending it off to the cloud."""

import os
import numpy as np
import pandas as pd
from datetime import datetime, timedelta
from airflow.hooks.S3_hook import S3Hook


def _attach_datetime(filename: str, destination: str):
    """Attach 7-day randomly spaced timestamps (sampled from a Gaussian distribution)
    to each row in the malware_file_detection.csv file. The file has N = 165053 rows,
    so each day will have N/7 +/- N/70 rows (mean = N/7 and standard deviation = N/70).
    Purpose of doing this is to introduce some variability, so that there is more data
    on some days than on others, and also to demonstrate a daily batch process.

    If today is Monday (todays_day == 0), then generate random timestamps
    and attach them to the dataset. Otherwise, do nothing.

    Args:
        filename (str): absolute path to file, on the Docker container
        destination (str): absolute destination where processed file is to be written
    """
    now = datetime.utcnow()
    todays_day = now.weekday()

    if todays_day:
        return

    df = pd.read_csv(filename)
    N = len(df)
    MEAN = N / 7
    STD = MEAN / 10

    six_day_sizes: list[int] = [round(n) for n in np.random.normal(MEAN, STD, size=6)]
    one_week_sizes = six_day_sizes + [N - sum(six_day_sizes)]

    # sanity check to ensure that all week's data adds up to the expected total
    assert sum(one_week_sizes) == N
    days = range(-1, 6)

    all_timestamps = []

    for size, d in zip(one_week_sizes, days):
        today = datetime(now.year, now.month, now.day, 0, 0, 0)
        start_day = today + timedelta(days=d) - timedelta(days=todays_day)

        mean_interval = 86400 / size
        std_interval = mean_interval / 10

        sampling_intervals = np.random.normal(mean_interval, std_interval, size)
        total = sum(sampling_intervals)
        sampling_intervals = [s * 86400 / total for s in sampling_intervals]

        interval_offsets = np.cumsum(sampling_intervals)
        interval_offsets[-1] -= 1e-6

        start_timestamp = start_day.timestamp()
        all_timestamps += [start_timestamp + offs for offs in interval_offsets]

    df.insert(0, "TimeReceived", all_timestamps)
    df["TimeReceived"] = [datetime.fromtimestamp(time) for time in df["TimeReceived"]]
    df.to_csv(destination, index=False)


def _local_to_s3(bucket_name: str, key: str, filename: str, remove_local: bool):
    """Loads file from local system to S3 bucket. If the file needs to be removed
    locally after transferring it to S3, specify `remove_local=True`.

    Args:
        bucket_name (str): S3 bucket name
        key (str): directory on S3 where file is going to be loaded
        file_name (str): directory on local system where file is located
        remove_local (bool): to delete local file
    """
    s3_hook = S3Hook()
    s3_hook.load_file(filename=filename, bucket_name=bucket_name, replace=True, key=key)

    if remove_local:
        if os.path.isfile(filename):
            os.remove(filename)
