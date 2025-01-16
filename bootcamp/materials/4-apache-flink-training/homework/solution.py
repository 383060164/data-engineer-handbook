# web_session_analysis.py
from pyflink.datastream import StreamExecutionEnvironment
from pyflink.table import StreamTableEnvironment, EnvironmentSettings
from pyflink.common.time import Time
from pyflink.common.watermark_strategy import WatermarkStrategy
from pyflink.datastream.functions import MapFunction, KeySelector, AggregateFunction
from pyflink.datastream.window import EventTimeSessionWindows
from pyflink.datastream.connectors.jdbc import JdbcSink, JdbcConnectionOptions
from datetime import datetime
import json
import logging

# Configure logging
logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


class WebEvent:
    """Represents a single web event with IP address, host, and timestamp."""

    def __init__(self, ip_address: str, host: str, timestamp: int):
        self.ip_address = ip_address
        self.host = host
        self.timestamp = timestamp


class SessionStats:
    """Maintains statistics for a web session."""

    def __init__(self, host="", start_time=None, end_time=None, event_count=0):
        self.host = host
        self.start_time = start_time
        self.end_time = end_time
        self.event_count = event_count


class WebEventAggregator(AggregateFunction):
    """Aggregates web events into sessions with statistics."""

    def create_accumulator(self):
        return SessionStats()

    def add(self, event, accumulator):
        accumulator.host = event.host
        if accumulator.start_time is None:
            accumulator.start_time = event.timestamp
        accumulator.end_time = max(accumulator.end_time or 0, event.timestamp)
        accumulator.event_count += 1
        return accumulator

    def get_result(self, accumulator):
        return accumulator


def create_jdbc_sink():
    """Creates a JDBC sink for writing session data to PostgreSQL."""
    return JdbcSink.sink(
        """
        INSERT INTO web_sessions 
        (ip_address, host, session_start, session_end, event_count)
        VALUES (?, ?, ?, ?, ?)
        ON CONFLICT (ip_address, host, session_start)
        DO UPDATE SET 
            session_end = EXCLUDED.session_end,
            event_count = EXCLUDED.event_count
        """,
        lambda stats: (
            stats.ip_address,
            stats.host,
            datetime.fromtimestamp(stats.start_time / 1000),
            datetime.fromtimestamp(stats.end_time / 1000),
            stats.event_count
        ),
        JdbcConnectionOptions.JdbcConnectionOptionsBuilder()
        .with_url("jdbc:postgresql://localhost:5432/sessions")
        .with_driver_name("org.postgresql.Driver")
        .with_user_name("flink")
        .with_password("flink123")
        .build()
    )


def main():
    """Main function to run the Flink job."""
    try:
        # Set up the execution environment
        env = StreamExecutionEnvironment.get_execution_environment()
        env.add_jars("file:///path/to/postgresql-42.2.27.jar")  # Add PostgreSQL JDBC driver

        # Configure checkpointing
        env.enable_checkpointing(60000)  # Checkpoint every minute

        # Read and parse input data
        input_stream = env.read_text_file("/path/to/input/data")
        web_events = (input_stream
        .map(lambda line: WebEvent(**json.loads(line)))
        .assign_timestamps_and_watermarks(
            WatermarkStrategy
            .for_monotonous_timestamps()
            .with_timestamp_assigner(lambda event, _: event.timestamp)
        ))

        # Process sessions
        session_stats = (web_events
                         .key_by(lambda event: (event.ip_address, event.host))
                         .window(EventTimeSessionWindows.with_gap(Time.minutes(5)))
                         .aggregate(WebEventAggregator()))

        # Write to PostgreSQL
        session_stats.add_sink(create_jdbc_sink())

        # Execute the job
        env.execute("Web Session Analysis")

    except Exception as e:
        logger.error(f"Error running Flink job: {str(e)}")
        raise


if __name__ == '__main__':
    main()