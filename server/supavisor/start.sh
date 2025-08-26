#!/bin/bash
set -e

# /connection_logger.sh &

SCHEMA_NAME="_supavisor"

echo "Starting Supavisor with DATABASE_URL: $DATABASE_URL"

if [ -z "$DATABASE_URL" ]; then
  echo "DATABASE_URL is not set"
  exit 1
fi

# Ensure RDS CA cert is present
if [ -f /etc/ssl/certs/rds-ca.pem ]; then
  echo "RDS CA cert found at /etc/ssl/certs/rds-ca.pem"
else
  echo "ERROR: RDS CA cert not found at /etc/ssl/certs/rds-ca.pem"
  exit 1
fi

# Ensure runtime.exs config is present
if [ -f /app/releases/2.6.1/runtime.exs ]; then
  echo "runtime.exs config found at /app/releases/2.6.1/runtime.exs"
else
  echo "ERROR: runtime.exs config not found at /app/releases/2.6.1/runtime.exs"
  exit 1
fi

ls -l /etc/ssl/certs/rds-ca.pem

# psql "$DATABASE_URL" -c "SELECT 1" \
#   && echo "SSL connection successful" \
#   || { echo "SSL connection failed"; exit 1; }


psql "$DATABASE_URL" -c "SELECT 1" \
  && {
    echo "SSL connection successful"

    # Create schema if not exists
    psql "$DATABASE_URL" -c "CREATE SCHEMA IF NOT EXISTS $SCHEMA_NAME;" \
      && echo "Schema '$SCHEMA_NAME' created or already exists." \
      || { echo "Failed to create schema '$SCHEMA_NAME'"; exit 1; }
  } \
  || {
    echo "SSL connection failed"
    exit 1
  }

# Optional extra checks
psql "$DATABASE_URL" -c "SHOW ssl" || { echo "SSL verification failed"; exit 1; }

echo "API_JWT_SECRET: $API_JWT_SECRET"
echo "VAULT_ENC_KEY: $VAULT_ENC_KEY"
echo "SECRET_KEY_BASE: $SECRET_KEY_BASE"
echo "METRICS_JWT_SECRET: $METRICS_JWT_SECRET"

# Run migration (idempotent, will skip if schema exists)
echo "Running migration..."
/app/bin/supavisor eval "Supavisor.Release.migrate()" || { echo "Migration failed"; exit 1; }
echo "Migration completed successfully"

# Start Supavisor (SSL is now handled via /app/config/runtime.exs)
exec /app/bin/supavisor start --debug
