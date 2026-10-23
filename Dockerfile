FROM python:3.10-slim
RUN apt-get update && apt-get install -y --no-install-recommends postgresql-client make && rm -rf /var/lib/apt/lists/*
WORKDIR /app
COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt
COPY . .
ENV DBT_PROFILES_DIR=/app/dbt DBT_ENGINE_MANAGE_STATE=0
CMD ["make", "demo"]
