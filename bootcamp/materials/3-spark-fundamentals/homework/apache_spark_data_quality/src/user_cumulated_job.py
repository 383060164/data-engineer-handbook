from pyspark.sql import SparkSession
from pyspark.sql.functions import (
    col, date_trunc, count, coalesce, array, when,
    expr, date_add, to_date, lit
)
from pyspark.sql.types import ArrayType, DateType


def process_user_cumulated(spark: SparkSession, date: str):
    """
    Process user cumulated data for a given date.

    Args:
        spark: SparkSession object
        date: Target date in format 'YYYY-MM-DD'
    """
    # Get yesterday's date
    yesterday = date_add(to_date(lit(date)), -1)

    # Read yesterday's data
    yesterday_df = spark.table("users_cumulated") \
        .filter(col("date") == yesterday)

    # Process today's events
    today_df = spark.table("events") \
        .filter(
        (date_trunc("day", col("event_time")) == to_date(lit(date))) &
        (col("user_id").isNotNull())
    ) \
        .groupBy(
        col("user_id"),
        date_trunc("day", col("event_time")).alias("today_date")
    ) \
        .agg(count(lit(1)).alias("num_events"))

    # Combine data using full outer join
    result_df = yesterday_df.join(
        today_df,
        yesterday_df.user_id == today_df.user_id,
        "fullouter"
    ).select(
        coalesce(today_df.user_id, yesterday_df.user_id).alias("user_id"),
        expr("""
            array_union(
                coalesce(dates_active, array()),
                case when t.user_id is not null 
                then array(t.today_date)
                else array()
                end
            )
        """).alias("date_list"),
        coalesce(
            today_df.today_date,
            date_add(yesterday_df.date, 1)
        ).alias("date")
    )

    return result_df