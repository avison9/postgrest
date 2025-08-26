#!/bin/sh

# Validate API_SECRET_ARN
if [ -z "$API_SECRET_ARN" ]; then
  echo "Error: API_SECRET_ARN is not set"
  exit 1
fi

# Fetch secrets
API_KEY_JSON=$(aws secretsmanager get-secret-value --secret-id "$API_SECRET_ARN" --query SecretString --output text 2>/dev/stderr)
if [ $? -ne 0 ]; then
  echo "Error: Failed to fetch secrets from $API_SECRET_ARN"
  exit 1
fi

# Validate API_SECRET_ARN
if [ -z "$RDS_SECRET_ARN" ]; then
  echo "Error: RDS_SECRET_ARN is not set"
  exit 1
fi

# Fetch secrets
SECRET_JSON=$(aws secretsmanager get-secret-value --secret-id "$RDS_SECRET_ARN" --query SecretString --output text 2>/dev/stderr)
if [ $? -ne 0 ]; then
  echo "Error: Failed to fetch secrets from $RDS_SECRET_ARN"
  exit 1
fi

# Extract secrets using jq
PGRST_JWT_SECRET=$(echo "$API_KEY_JSON" | jq -r '.api_key')
PGRST_DB_PASS=$(echo "$SECRET_JSON" | jq -r '.password')
PGRST_DB_ENDPOINT=$(echo "$SECRET_JSON" | jq -r '.host')
PGRST_DB_PORT=$(echo "$SECRET_JSON" | jq -r '.port')
PGRST_DB_USERNAME=$(echo "$SECRET_JSON" | jq -r '.username')
PGRST_DB_DATABASE=$(echo "$SECRET_JSON" | jq -r '.database')



# Validate secrets
if [ -z "$PGRST_JWT_SECRET" ] || [ -z "$PGRST_DB_PASS" ]; then
  echo "Error: Missing jwt_secret or postgrest_pass in secrets"
  exit 1
fi

# Set environment variables for PostgREST
export PGRST_DB_URI="postgresql://$PGRST_DB_USERNAME:$PGRST_DB_PASS@$PGRST_DB_ENDPOINT:$PGRST_DB_PORT/$PGRST_DB_DATABASE?sslmode=require"
export PGRST_JWT_SECRET
export PGRST_DB_SCHEMAS="*"
export PGRST_DB_ANON_ROLE="web_anon"
export PGRST_DB_POOL=5

# Start PostgREST without config file

exec /usr/local/bin/postgrest

