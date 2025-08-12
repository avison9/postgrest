#!/bin/sh
set -ex



# Fetch API key from Secrets Manager
API_SECRET_ARN="$API_SECRET_ARN"
if [ -z "$API_SECRET_ARN" ]; then
  echo "Error: API_SECRET_ARN not set"
  exit 1
fi

API_KEY=$(aws secretsmanager get-secret-value --secret-id "$API_SECRET_ARN" --region eu-north-1 | jq -r '.SecretString | fromjson | .api_key')
if [ -z "$API_KEY" ]; then
  echo "Error: Failed to fetch API key"
  exit 1
fi

# Fetch configuration (db_name, schema_name) from CONFIG_URL
CONFIG_URL="$CONFIG_URL"
if [ -z "$CONFIG_URL" ]; then
  echo "Error: CONFIG_URL not set"
  exit 1
fi

CONFIG=$(curl -s -H "Authorization: Bearer $API_KEY" "$CONFIG_URL")
if [ $? -ne 0 ]; then
  echo "Error: Failed to fetch config"
  exit 1
fi

# echo "Calling CONFIG_URL: $CONFIG_URL"
# HTTP_RESPONSE=$(curl -s -w "HTTPSTATUS:%{http_code}" -H "Authorization: Bearer $API_KEY" "$CONFIG_URL")

# # Extract body and status
# CONFIG=$(echo "$HTTP_RESPONSE" | sed -e 's/HTTPSTATUS\:.*//g')
# HTTP_STATUS=$(echo "$HTTP_RESPONSE" | tr -d '\n' | sed -e 's/.*HTTPSTATUS://')

# echo "HTTP_STATUS: $HTTP_STATUS"
# echo "CONFIG: $CONFIG"

# if [ "$HTTP_STATUS" -ne 200 ]; then
#   echo "Error: Failed to fetch config, status code: $HTTP_STATUS"
#   exit 1
# fi

# if [ -z "$CONFIG" ]; then
#   echo "Error: Config response body is empty"
#   exit 1
# fi

DB_NAME=$(echo "$CONFIG" | jq -r '.db_name')
SCHEMA_NAME=$(echo "$CONFIG" | jq -r '.schema_name')
if [ -z "$DB_NAME" ] || [ -z "$SCHEMA_NAME" ]; then
  echo "Error: Invalid config response"
  exit 1
fi

# Query mapper for DB URL and schema
MAPPER_API_URL="$MAPPER_API_URL"
RESPONSE=$(curl -s -H "Authorization: Bearer $API_KEY" "$MAPPER_API_URL?db_name=$DB_NAME&schema_name=$SCHEMA_NAME")
if [ $? -ne 0 ]; then
  echo "Error: Failed to query mapper"
  exit 1
fi

DB_URL=$(echo "$RESPONSE" | jq -r '.db_url')
SCHEMA_NAME=$(echo "$RESPONSE" | jq -r '.schema_name')
if [ -z "$DB_URL" ] || [ -z "$SCHEMA_NAME" ]; then
  echo "Error: Invalid response from mapper"
  exit 1
fi

# Set PostgREST environment variables
export PGRST_DB_URI="$DB_URL"
export PGRST_DB_SCHEMA="$SCHEMA_NAME"
export PGRST_DB_ANON_ROLE="web_anon"

echo "DB_URI: $PGRST_DB_URI"
echo "SCHEMA: $PGRST_DB_SCHEMA"
echo "ANON_ROLE: $PGRST_DB_ANON_ROLE"


env | grep PGRST_

# Start PostgREST
exec /usr/local/bin/postgrest