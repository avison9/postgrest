#!/bin/bash

# Fetch secrets from AWS Secrets Manager
SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id $RDS_SECRET_ARN --query SecretString --output text)
API_KEY_JSON=$(aws secretsmanager get-secret-value --secret-id $API_SECRET_ARN --query SecretString --output text)

# Extract secrets using jq
PGRST_JWT_SECRET=$(echo "$API_KEY_JSON" | jq -r '.api_key')
PGRST_DB_PASS=$(echo "$SECRET_JSON" | jq -r '.password')

# Set environment variables for PostgREST
export PGRST_DB_URI="postgresql://postgrest:$PGRST_DB_PASS@127.0.0.1:6543/postgres"
export PGRST_JWT_SECRET
export PGRST_DB_SCHEMAS="*"
export PGRST_DB_ANON_ROLE="web_anon"

# Start PostgREST
exec postgrest "$@"