"""Utility functions to connect with AWS infrastructure and/or transfer local
files to resources such as S3, and to pause/resume the Redshift cluster. Also 
includes a Python function to process file locally (attach datetime column weekly) 
before sending it off to the cloud."""

import os
import time
import logging
import numpy as np
import pandas as pd
from datetime import datetime, timedelta
from airflow.hooks.S3_hook import S3Hook
from airflow.exceptions import AirflowException
from airflow.providers.amazon.aws.hooks.redshift import RedshiftHook


def _attach_datetime(filename: str, destination: str):
    """Attach 7-day randomly spaced timestamps (sampled from a Gaussian distribution)
    to each row in the malware_detection.csv file. The file has N = 165053 rows,
    so each day will have N/7 +/- N/70 rows (mean = N/7 and standard deviation = N/70).
    Purpose of doing this is to introduce some variability, so that there is more data
    on some days than on others, and also to demonstrate a daily batch process.

    If today is Monday (todays_day == 0), then generate random timestamps
    and attach them to the dataset. Otherwise, do nothing.

    Args:
        filename (str): absolute path to file, on the Docker container
        destination (str): absolute path where processed file is to be written
    """
    now = datetime.utcnow()
    todays_day = now.weekday()

    if todays_day != 0:
        return

    df = pd.read_csv(filename)
    N = len(df)
    MEAN = N / 7
    STD = MEAN / 10

    six_day_sizes: list[int] = [round(n) for n in np.random.normal(MEAN, STD, size=6)]
    one_week_sizes = six_day_sizes + [N - sum(six_day_sizes)]

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

    # sanity check to ensure that all week's data adds up to the expected total
    assert sum(one_week_sizes) == len(all_timestamps) == N

    df.insert(0, "TimeReceived", all_timestamps)
    df["TimeReceived"] = [datetime.fromtimestamp(time) for time in df["TimeReceived"]]
    df.to_csv(destination, index=False)


def _local_file_to_s3(bucket_name: str, key: str, filename: str, remove_local: bool):
    """Uploads file from local system to S3 bucket. If the file needs to be removed
    locally after transferring it to S3, specify `remove_local=True`.

    Args:
        bucket_name (str): S3 bucket name
        key (str): directory on S3 where file is going to be loaded
        filename (str): directory on local system where file is located
        remove_local (bool): to delete local file
    """
    s3_hook = S3Hook()
    s3_hook.load_file(filename=filename, bucket_name=bucket_name, replace=True, key=key)

    if remove_local:
        if os.path.isfile(filename):
            os.remove(filename)


def _resume_redshift_cluster(cluster_identifier: str):
    """Resume a Redshift cluster when it is paused. Only resume the cluster when
    queries need to be run or data has to be retrieved from somewhere (mainly from S3).

    Args:
        cluster_identifier (str): the name of the Redshift cluster

    Raises:
        AirflowException: if Redshift cannot be resumed, downstream tasks
            should not proceed.
    """
    redshift_hook = RedshiftHook()
    cluster_state = redshift_hook.cluster_status(cluster_identifier=cluster_identifier)

    try:
        if cluster_state == "available":
            return

        redshift_hook.get_conn().resume_cluster(ClusterIdentifier=cluster_identifier)
        while cluster_state != "available":
            time.sleep(1)
            cluster_state = redshift_hook.cluster_status(
                cluster_identifier=cluster_identifier
            )
    except Exception as ex:
        logging.warning(
            f"Can't resume! Cluster {cluster_identifier} is in state: {cluster_state}."
        )
        raise AirflowException(ex)


def _pause_redshift_cluster(cluster_identifier: str):
    """Pause a Redshift cluster when it is in an active/available state. This is
    to optimize costs - only pay for storage when paused and not for compute/running
    the cluster.

    Args:
        cluster_identifier (str): the name of the Redshift cluster

    Raises:
        AirflowException: should fail the pipeline, and (possibly?) send an
            alert to notify that your money is leaking.
    """
    redshift_hook = RedshiftHook()
    cluster_state = redshift_hook.cluster_status(cluster_identifier=cluster_identifier)

    try:
        if cluster_state == "paused":
            return

        redshift_hook.get_conn().pause_cluster(ClusterIdentifier=cluster_identifier)
        while cluster_state != "paused":
            time.sleep(1)
            cluster_state = redshift_hook.cluster_status(
                cluster_identifier=cluster_identifier
            )
    except Exception as ex:
        logging.warning(
            f"Can't pause! Cluster {cluster_identifier} is in state: {cluster_state}."
        )
        raise AirflowException(ex)
