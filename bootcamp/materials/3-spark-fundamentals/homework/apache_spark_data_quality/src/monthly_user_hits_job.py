# src/jobs/monthly_user_hits_job.py
from pyspark.sql import SparkSession, DataFrame
from pyspark.sql.functions import (
    col, date_trunc, count, coalesce, array, when,
    expr, date_add, to_date, lit, array_repeat, datediff
)
from pyspark.sql.types import ArrayType, LongType
from typing import Optional


def process_monthly_user_hits(
        spark: SparkSession,
        date: str,
        events_table: Optional[str] = "events",
        hits_table: Optional[str] = "monthly_user_site_hits"
) -> DataFrame:
    """
    Process monthly user hits for a given date.

    Args:
        spark: SparkSession object
        date: Target date in format 'YYYY-MM-DD'
        events_table: Name of events table (optional, for testing)
        hits_table: Name of hits table (optional, for testing)

    Returns:
        DataFrame with processed monthly user hits

    Raises:
        ValueError: If date format is invalid
    """
    try:
        target_date = to_date(lit(date))
        if target_date is None:
            raise ValueError(f"Invalid date format: {date}")

        # Get yesterday's date and month start
        yesterday = date_add(target_date, -1)
        month_start = date_trunc("month", target_date)

        # Calculate array size needed
        days_since_month_start = expr(f"datediff('{date}', '{month_start}')")

        # Read yesterday's data
        yesterday_df = spark.table(hits_table) \
            .filter(col("date_partition") == yesterday)

        # Process today's events
        today_df = spark.table(events_table) \
            .filter(
            (date_trunc("day", col("event_time")) == target_date) &
            (col("user_id").isNotNull())
        ) \
            .groupBy(
            col("user_id"),
            date_trunc("day", col("event_time")).alias("today_date")
        ) \
            .agg(count(lit(1)).alias("num_hits"))

        # Ensure hit_array is properly sized and padded
        result_df = yesterday_df.join(
            today_df,
            yesterday_df.user_id == today_df.user_id,
            "fullouter"
        ).select(
            coalesce(yesterday_df.user_id, today_df.user_id).alias("user_id"),
            expr("""
                CASE 
                    WHEN hit_array IS NULL THEN 
                        array_repeat(cast(null as bigint), datediff(date_partition, month_start))
                    WHEN size(hit_array) < datediff(date_partition, month_start) THEN
                        array_union(
                            hit_array,
                            array_repeat(
                                cast(null as bigint),
                                datediff(date_partition, month_start) - size(hit_array)
                            )
                        )
                    ELSE hit_array
                END
            """).alias("base_array"),
            month_start.alias("month_start"),
            when(
                (col("y.first_found_date").isNotNull()) &
                (col("t.today_date").isNotNull()) &
                (col("y.first_found_date") < col("t.today_date")),
                col("y.first_found_date")
            ).otherwise(
                coalesce(col("t.today_date"), col("y.first_found_date"))
            ).alias("first_found_date"),
            target_date.alias("date_partition")
        )

        # Add today's hits
        final_df = result_df.select(
            col("user_id"),
            expr("""
                array_union(
                    base_array,
                    array(coalesce(t.num_hits, cast(null as bigint)))
                )
            """).alias("hits_array"),
            col("month_start"),
            col("first_found_date"),
            col("date_partition")
        )

        return final_df

    except Exception as e:
        raise RuntimeError(f"Error processing monthly user hits: {str(e)}")


# src/jobs/user_cumulated_job.py
from pyspark.sql import SparkSession, DataFrame
from pyspark.sql.functions import (
    col, date_trunc, count, coalesce, array, when,
    expr, date_add, to_date, lit
)
from pyspark.sql.types import ArrayType, DateType
from typing import Optional


def process_user_cumulated(
        spark: SparkSession,
        date: str,
        events_table: Optional[str] = "events",
        users_table: Optional[str] = "users_cumulated"
) -> DataFrame:
    """
    Process user cumulated data for a given date.

    Args:
        spark: SparkSession object
        date: Target date in format 'YYYY-MM-DD'
        events_table: Name of events table (optional, for testing)
        users_table: Name of users table (optional, for testing)

    Returns:
        DataFrame with processed user cumulated data

    Raises:
        ValueError: If date format is invalid
    """
    try:
        target_date = to_date(lit(date))
        if target_date is None:
            raise ValueError(f"Invalid date format: {date}")

        # Get yesterday's date
        yesterday = date_add(target_date, -1)

        # Read yesterday's data
        yesterday_df = spark.table(users_table) \
            .filter(col("date") == yesterday)

        # Process today's events
        today_df = spark.table(events_table) \
            .filter(
            (date_trunc("day", col("event_time")) == target_date) &
            (col("user_id").isNotNull())
        ) \
            .groupBy(
            col("user_id"),
            date_trunc("day", col("event_time")).alias("today_date")
        ) \
            .agg(count(lit(1)).alias("num_events"))

        # Combine data using full outer join with proper date list handling
        result_df = yesterday_df.join(
            today_df,
            yesterday_df.user_id == today_df.user_id,
            "fullouter"
        ).select(
            coalesce(today_df.user_id, yesterday_df.user_id).alias("user_id"),
            expr("""
                array_distinct(
                    array_union(
                        coalesce(dates_active, array()),
                        case when t.user_id is not null 
                        then array(t.today_date)
                        else array()
                        end
                    )
                )
            """).alias("date_list"),
            coalesce(
                today_df.today_date,
                date_add(yesterday_df.date, 1)
            ).alias("date")
        )

        return result_df

    except Exception as e:
        raise RuntimeError(f"Error processing user cumulated data: {str(e)}")

