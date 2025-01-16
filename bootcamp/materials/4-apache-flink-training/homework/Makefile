# Makefile
.PHONY: sessionization_job setup clean

setup:
	python -m pip install apache-flink psycopg2-binary

sessionization_job:
	docker-compose up -d
	python web_session_analysis.py

clean:
	docker-compose down
	rm -rf __pycache__