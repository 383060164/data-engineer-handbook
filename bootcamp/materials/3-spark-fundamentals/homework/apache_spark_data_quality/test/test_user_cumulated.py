# src/tests/test_user_cumulated.py
from pyspark.sql import SparkSession
from pyspark.sql.types import (
    StructType, StructField, StringType,
    ArrayType, DateType, IntegerType
)
from datetime import datetime, date
from jobs.user_cumulated_job import process_user_cumulated
from typing import List, Dict


def test_user_cumulated(spark: SparkSession):
    """
    Test suite for user_cumulated_job with multiple scenarios.
    """
    # Create test schemas
    users_schema = StructType([
        StructField("user_id", StringType(), True),
        StructField("dates_active", ArrayType(DateType()), True),
        StructField("date", DateType(), True)
    ])

    events_schema = StructType([
        StructField("user_id", StringType(), True),
        StructField("event_time", DateType(), True)
    ])

    # Define test scenarios
    test_scenarios = [
        {
            "name": "normal_case",
            "yesterday_data": [
                ("user1", [date(2023, 3, 29)], date(2023, 3, 30)),
                ("user2", [date(2023, 3, 29), date(2023, 3, 30)], date(2023, 3, 30))
            ],
            "events_data": [
                ("user1", datetime(2023, 3, 31, 10, 0)),
                ("user1", datetime(2023, 3, 31, 11, 0)),
                ("user3", datetime(2023, 3, 31, 12, 0))
            ],
            "expected_data": [
                ("user1", [date(2023, 3, 29), date(2023, 3, 31)], date(2023, 3, 31)),
                ("user2", [date(2023, 3, 29), date(2023, 3, 30)], date(2023, 3, 31)),
                ("user3", [date(2023, 3, 31)], date(2023, 3, 31))
            ]
        },
        {
            "name": "duplicate_dates",
            "yesterday_data": [
                ("user1", [date(2023, 3, 29), date(2023, 3, 29)], date(2023, 3, 30))
            ],
            "events_data": [
                ("user1", datetime(2023, 3, 31, 10, 0)),
                ("user1", datetime(2023, 3, 31, 10, 0))
            ],
            "expected_data": [
                ("user1", [date(2023, 3, 29), date(2023, 3, 31)], date(2023, 3, 31))
            ]
        },
        {
            "name": "no_yesterday_data",
            "yesterday_data": [],
            "events_data": [
                ("user1", datetime(2023, 3, 31, 10, 0))
            ],
            "expected_data": [
                ("user1", [date(2023, 3, 31)], date(2023, 3, 31))
            ]
        },
        {
            "name": "no_events_today",
            "yesterday_data": [
                ("user1", [date(2023, 3, 29), date(2023, 3, 30)], date(2023, 3, 30))
            ],
            "events_data": [],
            "expected_data": [
                ("user1", [date(2023, 3, 29), date(2023, 3, 30)], date(2023, 3, 31))
            ]
        },
        {
            "name": "null_dates_active",
            "yesterday_data": [
                ("user1", None, date(2023, 3, 30))
            ],
            "events_data": [
                ("user1", datetime(2023, 3, 31, 10, 0))
            ],
            "expected_data": [
                ("user1", [date(2023, 3, 31)], date(2023, 3, 31))
            ]
        }
    ]

    # Run all test scenarios
    for scenario in test_scenarios:
        print(f"Running test scenario: {scenario['name']}")

        # Create test DataFrames
        yesterday_df = spark.createDataFrame(
            scenario["yesterday_data"],
            users_schema
        )
        events_df = spark.createDataFrame(
            scenario["events_data"],
            events_schema
        )

        # Register temporary views with unique names for parallel testing
        yesterday_df.createOrReplaceTempView(f"users_cumulated_{scenario['name']}")
        events_df.createOrReplaceTempView(f"events_{scenario['name']}")

        # Create expected DataFrame
        expected_df = spark.createDataFrame(
            scenario["expected_data"],
            users_schema
        )

        # Process data
        result_df = process_user_cumulated(
            spark,
            "2023-03-31",
            f"events_{scenario['name']}",
            f"users_cumulated_{scenario['name']}"
        )

        # Compare results
        assert_dataframe_equality(result_df, expected_df, scenario['name'])


def assert_dataframe_equality(df1, df2, scenario_name: str):
    """
    Compare two DataFrames in detail with meaningful error messages.

    Args:
        df1: First DataFrame to compare
        df2: Second DataFrame to compare
        scenario_name: Name of the test scenario for error reporting
    """
    # Check schema equality
    assert df1.schema == df2.schema, f"Schema mismatch in scenario {scenario_name}"

    # Convert to lists for detailed comparison
    rows1 = df1.collect()
    rows2 = df2.collect()

    assert len(rows1) == len(rows2), \
        f"Row count mismatch in scenario {scenario_name}: {len(rows1)} vs {len(rows2)}"

    # Sort both sets of rows by user_id for comparison
    rows1.sort(key=lambda x: x.user_id)
    rows2.sort(key=lambda x: x.user_id)

    for row1, row2 in zip(rows1, rows2):
        for field in df1.schema.fields:
            val1 = row1[field.name]
            val2 = row2[field.name]

            if isinstance(val1, list) and isinstance(val2, list):
                # For date arrays, sort before comparison
                val1.sort()
                val2.sort()

            assert val1 == val2, \
                f"Mismatch in {scenario_name}, field {field.name}: {val1} vs {val2}"


def test_invalid_date_handling(spark: SparkSession):
    """Test handling of invalid date input"""
    with pytest.raises(ValueError) as exc_info:
        process_user_cumulated(spark, "invalid-date")
    assert "Invalid date format" in str(exc_info.value)