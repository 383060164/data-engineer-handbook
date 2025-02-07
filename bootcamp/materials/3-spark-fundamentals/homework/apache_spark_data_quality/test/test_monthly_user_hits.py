from pyspark.sql import SparkSession
from pyspark.sql.types import (
    StructType, StructField, StringType,
    ArrayType, DateType, LongType
)
from datetime import datetime, date
from jobs.monthly_user_hits_job import process_monthly_user_hits
from pyspark.sql.functions import col
from typing import List, Dict
import pytest


def test_monthly_user_hits(spark: SparkSession):
    # Create test schemas
    monthly_hits_schema = StructType([
        StructField("user_id", StringType(), True),
        StructField("hits_array", ArrayType(LongType()), True),
        StructField("month_start", DateType(), True),
        StructField("first_found_date", DateType(), True),
        StructField("date_partition", DateType(), True)
    ])

    events_schema = StructType([
        StructField("user_id", StringType(), True),
        StructField("event_time", DateType(), True)
    ])

    # Test scenarios
    test_scenarios = [
        {
            "name": "normal_case",
            "yesterday_data": [
                ("user1", [1, 2], date(2023, 3, 1), date(2023, 3, 2), date(2023, 3, 2)),
                ("user2", [0, 1], date(2023, 3, 1), date(2023, 3, 2), date(2023, 3, 2))
            ],
            "events_data": [
                ("user1", datetime(2023, 3, 3, 10, 0)),
                ("user1", datetime(2023, 3, 3, 11, 0)),
                ("user3", datetime(2023, 3, 3, 12, 0))
            ],
            "expected_data": [
                ("user1", [1, 2, 2], date(2023, 3, 1), date(2023, 3, 2), date(2023, 3, 3)),
                ("user2", [0, 1, None], date(2023, 3, 1), date(2023, 3, 2), date(2023, 3, 3)),
                ("user3", [None, None, 1], date(2023, 3, 1), date(2023, 3, 3), date(2023, 3, 3))
            ]
        },
        {
            "name": "missing_yesterday_data",
            "yesterday_data": [],
            "events_data": [
                ("user1", datetime(2023, 3, 3, 10, 0))
            ],
            "expected_data": [
                ("user1", [None, None, 1], date(2023, 3, 1), date(2023, 3, 3), date(2023, 3, 3))
            ]
        },
        {
            "name": "no_events_today",
            "yesterday_data": [
                ("user1", [1, 2], date(2023, 3, 1), date(2023, 3, 2), date(2023, 3, 2))
            ],
            "events_data": [],
            "expected_data": [
                ("user1", [1, 2, None], date(2023, 3, 1), date(2023, 3, 2), date(2023, 3, 3))
            ]
        }
    ]

    for scenario in test_scenarios:
        # Create test DataFrames
        yesterday_df = spark.createDataFrame(
            scenario["yesterday_data"],
            monthly_hits_schema
        )
        events_df = spark.createDataFrame(
            scenario["events_data"],
            events_schema
        )

        # Register temporary views with unique names for parallel testing
        yesterday_df.createOrReplaceTempView(f"monthly_user_site_hits_{scenario['name']}")
        events_df.createOrReplaceTempView(f"events_{scenario['name']}")

        # Create expected DataFrame
        expected_df = spark.createDataFrame(
            scenario["expected_data"],
            monthly_hits_schema
        )

        # Process data
        result_df = process_monthly_user_hits(
            spark,
            "2023-03-03",
            f"events_{scenario['name']}",
            f"monthly_user_site_hits_{scenario['name']}"
        )

        # Compare results
        assert_dataframe_equality(result_df, expected_df)


def assert_dataframe_equality(df1, df2):
    """Compare two DataFrames in detail with meaningful error messages"""
    # Check schema equality
    assert df1.schema == df2.schema, "Schema mismatch"

    # Convert to lists for detailed comparison
    rows1 = df1.collect()
    rows2 = df2.collect()

    assert len(rows1) == len(rows2), f"Row count mismatch: {len(rows1)} vs {len(rows2)}"

    # Sort both sets of rows by user_id for comparison
    rows1.sort(key=lambda x: x.user_id)
    rows2.sort(key=lambda x: x.user_id)

    for row1, row2 in zip(rows1, rows2):
        for field in df1.schema.fields:
            val1 = row1[field.name]
            val2 = row2[field.name]
            assert val1 == val2, f"Mismatch in {field.name}: {val1} vs {val2}"

