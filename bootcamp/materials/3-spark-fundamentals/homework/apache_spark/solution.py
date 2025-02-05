from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.window import Window


def create_spark_session():
    return (SparkSession.builder
            .appName("ActorsSCD")
            .config("spark.sql.autoBroadcastJoinThreshold", "-1")
            .getOrCreate())


def load_current_actors(spark):
    return spark.read.table("actors")


def load_actors_history(spark):
    return spark.read.table("actors_history_scd")


def process_scd_updates(current_actors_df, history_df):
    # Window for ordering changes
    window_spec = Window.partitionBy("actor_id").orderBy("effective_date")

    # Identify changes in quality_class or is_active
    changes = (current_actors_df
               .withColumn("effective_date", F.current_date())
               .withColumn("row_num", F.row_number().over(window_spec))
               .join(history_df.alias("hist"),
                     (F.col("actor_id") == F.col("hist.actor_id")) &
                     (F.col("quality_class") != F.col("hist.quality_class") |
                      F.col("is_active") != F.col("hist.is_active")),
                     "left_outer")
               .where("hist.actor_id is null or row_num = 1"))

    # Expire old records
    expired_records = (history_df
                       .join(changes, "actor_id", "inner")
                       .withColumn("end_date", F.current_date()))

    # Create new records
    new_records = (changes
    .select(
        "actor_id",
        "quality_class",
        "is_active",
        F.current_date().alias("effective_date"),
        F.lit(None).alias("end_date")
    ))

    return expired_records, new_records


def update_history_table(spark, expired_records, new_records):
    # Update existing records
    expired_records.write.mode("overwrite").saveAsTable("actors_history_scd_temp")

    # Insert new records
    new_records.write.mode("append").saveAsTable("actors_history_scd")

    # Clean up
    spark.sql("DROP TABLE IF EXISTS actors_history_scd_temp")


def main():
    spark = create_spark_session()

    # Load current data
    current_actors = load_current_actors(spark)
    history = load_actors_history(spark)

    # Process SCD updates
    expired_records, new_records = process_scd_updates(current_actors, history)

    # Update history table
    update_history_table(spark, expired_records, new_records)

    spark.stop()


if __name__ == "__main__":
    main()