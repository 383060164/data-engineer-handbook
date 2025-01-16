-- init.sql
CREATE TABLE IF NOT EXISTS web_sessions (
    session_id SERIAL PRIMARY KEY,
    ip_address VARCHAR(45),
    host VARCHAR(255),
    session_start TIMESTAMP,
    session_end TIMESTAMP,
    event_count INTEGER,
    UNIQUE (ip_address, host, session_start)
);

CREATE INDEX idx_host ON web_sessions(host);
CREATE INDEX idx_session_time ON web_sessions(session_start, session_end);
