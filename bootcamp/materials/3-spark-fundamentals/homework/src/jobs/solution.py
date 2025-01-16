from pyspark.sql import SparkSession
from pyspark.sql import functions as F
from pyspark.sql.window import Window


def create_spark_session():
    """Create and configure Spark session with required settings."""
    spark = SparkSession.builder \
        .appName("Game Analysis") \
        .config("spark.sql.autoBroadcastJoinThreshold", "-1") \
        .getOrCreate()

    return spark


def prepare_bucketed_tables(spark, match_details_df, matches_df, medal_matches_players_df):
    """Prepare bucketed tables for efficient joins."""

    # Create temporary bucketed tables
    match_details_df.write \
        .bucketBy(16, "match_id") \
        .mode("overwrite") \
        .saveAsTable("bucketed_match_details")

    matches_df.write \
        .bucketBy(16, "match_id") \
        .mode("overwrite") \
        .saveAsTable("bucketed_matches")

    medal_matches_players_df.write \
        .bucketBy(16, "match_id") \
        .mode("overwrite") \
        .saveAsTable("bucketed_medal_matches_players")

    return (spark.table("bucketed_match_details"),
            spark.table("bucketed_matches"),
            spark.table("bucketed_medal_matches_players"))


def analyze_game_data(spark, match_details_df, matches_df, medal_matches_players_df, medals_df, maps_df):
    """Main analysis function to process and aggregate game data."""

    # Broadcast smaller dimension tables
    broadcast_medals = F.broadcast(medals_df)
    broadcast_maps = F.broadcast(maps_df)

    # Prepare bucketed tables for large tables
    bucketed_match_details, bucketed_matches, bucketed_medal_matches_players = \
        prepare_bucketed_tables(spark, match_details_df, matches_df, medal_matches_players_df)

    # Join all tables
    joined_df = bucketed_match_details \
        .join(bucketed_matches, "match_id") \
        .join(bucketed_medal_matches_players, ["match_id", "player_id"]) \
        .join(broadcast_medals, "medal_id") \
        .join(broadcast_maps, "map_id")

    # 4a. Find player with highest average kills (minimum 10 matches)
    top_killer = joined_df \
        .groupBy("player_id") \
        .agg(
        F.avg("kills").alias("avg_kills"),
        F.count("match_id").alias("total_matches")
    ) \
        .filter("total_matches >= 10") \
        .orderBy(F.col("avg_kills").desc()) \
        .limit(1)

    # 4b. Find most played playlist - try different sorting strategies
    # Strategy 1: Sort by count only
    playlist_count_1 = joined_df \
        .groupBy("playlist") \
        .agg(F.count("match_id").alias("match_count")) \
        .sortWithinPartitions("match_count", ascending=False)

    # Strategy 2: Sort by playlist name then count
    playlist_count_2 = joined_df \
        .groupBy("playlist") \
        .agg(F.count("match_id").alias("match_count")) \
        .sortWithinPartitions(["playlist", "match_count"], ascending=[True, False])

    # Strategy 3: Sort with null handling
    playlist_count_3 = joined_df \
        .groupBy("playlist") \
        .agg(F.count("match_id").alias("match_count")) \
        .sortWithinPartitions(F.col("match_count").desc_nulls_last())

    # Get the most played playlist
    top_playlist = playlist_count_1.limit(1)

    # 4c. Find most played map - try different sorting strategies
    # Strategy 1: Sort by count only
    map_count_1 = joined_df \
        .groupBy("map_name") \
        .agg(F.count("match_id").alias("match_count")) \
        .sortWithinPartitions("match_count", ascending=False)

    # Strategy 2: Sort by map name then count
    map_count_2 = joined_df \
        .groupBy("map_name") \
        .agg(F.count("match_id").alias("match_count")) \
        .sortWithinPartitions(["map_name", "match_count"], ascending=[True, False])

    # Get the most played map
    top_map = map_count_1.limit(1)

    # 4d. Find map with most Killing Spree medals
    top_spree_map = joined_df \
        .filter(F.col("medal_name") == "Killing Spree") \
        .groupBy("map_name") \
        .agg(F.count("medal_id").alias("spree_count")) \
        .sortWithinPartitions("spree_count", ascending=False) \
        .limit(1)

    # Compare sizes of different sorting strategies
    def get_size(df):
        return df.select(F.sum(F.length(F.to_json(F.struct(*df.columns)))).alias("size")).collect()[0]["size"]

    size_comparison = {
        'playlist_count_1_size': get_size(playlist_count_1),
        'playlist_count_2_size': get_size(playlist_count_2),
        'playlist_count_3_size': get_size(playlist_count_3),
        'map_count_1_size': get_size(map_count_1),
        'map_count_2_size': get_size(map_count_2)
    }

    return {
        'top_killer': top_killer,
        'top_playlist': top_playlist,
        'top_map': top_map,
        'top_spree_map': top_spree_map,
        'size_comparison': size_comparison,
        # Store all versions for comparison
        'playlist_counts': {
            'by_count': playlist_count_1,
            'by_name_count': playlist_count_2,
            'with_nulls': playlist_count_3
        },
        'map_counts': {
            'by_count': map_count_1,
            'by_name_count': map_count_2
        }
    }


def main():
    """Main function to execute the Spark job."""

    spark = create_spark_session()

    # Read input data
    match_details_df = spark.read.table("match_details")
    matches_df = spark.read.table("matches")
    medal_matches_players_df = spark.read.table("medals_matches_players")
    medals_df = spark.read.table("medals")
    maps_df = spark.read.table("maps")

    # Perform analysis
    results = analyze_game_data(
        spark,
        match_details_df,
        matches_df,
        medal_matches_players_df,
        medals_df,
        maps_df
    )

    # Print results
    print("\nAnalysis Results:")
    print("-----------------")

    print("\nTop Killer:")
    results['top_killer'].show()

    print("\nMost Played Playlist:")
    results['top_playlist'].show()

    print("\nMost Played Map:")
    results['top_map'].show()

    print("\nMap with Most Killing Sprees:")
    results['top_spree_map'].show()

    print("\nSize Comparison of Different Sorting Strategies:")
    for name, size in results['size_comparison'].items():
        print(f"{name}: {size}")

    # Save results
    for name, df in results.items():
        if isinstance(df, dict):
            for sub_name, sub_df in df.items():
                sub_df.write \
                    .mode("overwrite") \
                    .parquet(f"output/{name}_{sub_name}")
        elif hasattr(df, 'write'):
            df.write \
                .mode("overwrite") \
                .parquet(f"output/{name}")

    spark.stop()


if __name__ == "__main__":
    main()