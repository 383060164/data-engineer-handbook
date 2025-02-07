"""
Web Session Analysis Job
-----------------------
This PyFlink job processes web events, creates sessions based on IP and host,
and writes results to PostgreSQL for further analysis.

Dependencies:
- Apache Flink 1.15+
- PyFlink
- PostgreSQL JDBC driver
- Kafka connector
"""

from pyflink.datastream import StreamExecutionEnvironment
from pyflink.table import StreamTableEnvironment, EnvironmentSettings
from pyflink.common.time import Time
from pyflink.common import Types, Row
from pyflink.datastream.functions import KeyedProcessFunction
from pyflink.datastream.window import EventTimeSessionWindows
from datetime import datetime
from typing import Dict, Tuple
import logging

# Configure logging
logging.basicConfig(
    level=logging.INFO,
    format='%(asctime)s - %(name)s - %(levelname)s - %(message)s'
)
logger = logging.getLogger(__name__)


class SessionProcessor:
    def __init__(self):
        self.env = StreamExecutionEnvironment.get_execution_environment()
        self.t_env = StreamTableEnvironment.create(self.env)
        self._configure_environment()

    def _configure_environment(self):
        """Configure Flink environment with required dependencies and settings"""
        # Set up dependencies
        dependencies = [
            'flink-connector-jdbc-1.15.0.jar',
            'flink-connector-kafka-1.15.0.jar',
            'postgresql-42.2.27.jar'
        ]

        for dependency in dependencies:
            self.env.add_jars(f"file:///opt/flink/lib/{dependency}")

        # Configure checkpointing
        self.env.enable_checkpointing(60000)  # Checkpoint every minute

        # Set parallelism
        self.env.set_parallelism(4)  # Adjust based on your needs

    def create_source_table(self):
        """Create the source table connected to Kafka"""
        source_ddl = """
            CREATE TABLE web_events (
                ip_address STRING,
                host STRING,
                event_time TIMESTAMP(3),
                WATERMARK FOR event_time AS event_time - INTERVAL '5' SECONDS
            ) WITH (
                'connector' = 'kafka',
                'topic' = 'web_events',
                'properties.bootstrap.servers' = 'kafka:9092',
                'properties.group.id' = 'web_session_group',
                'scan.startup.mode' = 'latest',
                'format' = 'json'
            )
        """
        self.t_env.execute_sql(source_ddl)

    def create_sink_table(self):
        """Create the sink table connected to PostgreSQL"""
        sink_ddl = """
            CREATE TABLE web_sessions (
                session_id BIGINT,
                ip_address STRING,
                host STRING,
                session_start TIMESTAMP(3),
                session_end TIMESTAMP(3),
                event_count INT,
                PRIMARY KEY (session_id) NOT ENFORCED
            ) WITH (
                'connector' = 'jdbc',
                'url' = 'jdbc:postgresql://postgres:5432/webdb',
                'table-name' = 'web_sessions',
                'username' = 'webuser',
                'password' = 'webpass',
                'sink.buffer-flush.max-rows' = '1000',
                'sink.buffer-flush.interval' = '1s'
            )
        """
        self.t_env.execute_sql(sink_ddl)

    def process_sessions(self):
        """Main processing logic for session creation and analysis"""
        # Convert source table to stream
        events = self.t_env.from_path('web_events').to_data_stream()

        # Create sessions using window aggregation
        sessions = (
            events
            .key_by(lambda event: f"{event.ip_address}|{event.host}")
            .window(EventTimeSessionWindows.with_gap(Time.minutes(5)))
            .aggregate(SessionAggregator())
        )

        # Write sessions to PostgreSQL
        session_table = self.t_env.from_data_stream(
            sessions,
            'session_id BIGINT, ip_address STRING, host STRING, ' +
            'session_start TIMESTAMP(3), session_end TIMESTAMP(3), event_count INT'
        )
        session_table.execute_insert('web_sessions')

        # Calculate and output statistics
        sessions.key_by(lambda x: x[2])  # key by host
        .process(HostStatsCalculator())
        .print()

        return self.env.execute("Web Session Analysis")


class SessionAggregator:
    """Aggregates web events into sessions"""

    def create_accumulator(self) -> Dict:
        return {
            'session_id': 0,
            'ip': '',
            'host': '',
            'start_time': None,
            'end_time': None,
            'count': 0
        }

    def add(self, event: Row, accumulator: Dict) -> Dict:
        timestamp = event.event_time.timestamp() * 1000
        if not accumulator['start_time']:
            accumulator['session_id'] = int(timestamp)  # Use first event timestamp as session ID
            accumulator['ip'] = event.ip_address
            accumulator['host'] = event.host
            accumulator['start_time'] = timestamp

        accumulator['end_time'] = max(accumulator['end_time'] or timestamp, timestamp)
        accumulator['count'] += 1
        return accumulator

    def get_result(self, accumulator: Dict) -> Tuple:
        return (
            accumulator['session_id'],
            accumulator['ip'],
            accumulator['host'],
            datetime.fromtimestamp(accumulator['start_time'] / 1000),
            datetime.fromtimestamp(accumulator['end_time'] / 1000),
            accumulator['count']
        )


class HostStatsCalculator(KeyedProcessFunction):
    """Calculates running statistics for each host"""

    def __init__(self):
        self.stats = {}

    def process_element(self, session: Tuple, ctx: KeyedProcessFunction.Context):
        host = session[2]
        event_count = session[5]

        if host not in self.stats:
            self.stats[host] = {'total_events': 0, 'session_count': 0}

        self.stats[host]['total_events'] += event_count
        self.stats[host]['session_count'] += 1

        avg = self.stats[host]['total_events'] / self.stats[host]['session_count']
        yield f"Host: {host}, Average events per session: {avg:.2f}"


def main():
    """Main entry point for the Flink job"""
    try:
        processor = SessionProcessor()
        processor.create_source_table()
        processor.create_sink_table()
        processor.process_sessions()
    except Exception as e:
        logger.error(f"Error running Flink job: {str(e)}")
        raise


if __name__ == "__main__":
    main()