from fastapi import FastAPI, Request, HTTPException, Response
import httpx
import os
import boto3
import json
import asyncpg
import base64
import aiohttp
import logging

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)


app = FastAPI()

# Initialize AWS Secrets Manager client
session = boto3.session.Session()
secrets_client = session.client("secretsmanager")

# Environment variables
RDS_HOST = os.getenv("RDS_HOST", "rds-host")
API_SECRET_ARN = os.getenv("API_SECRET_ARN")
RDS_SECRET_ARN = os.getenv("RDS_SECRET_ARN")
META_SECRET_ARN = os.getenv("META_SECRET_ARN")
META_HOST = os.getenv("META_HOST")
SUPAVISOR_HOST = os.getenv("SUPAVISOR_HOST")
SUPAVISOR_JWT  = os.getenv("SUPA_KEY_ARN")


# Utilities
def get_secret(secret_arn: str) -> dict:
  try:
    response = secrets_client.get_secret_value(SecretId=secret_arn)
    return json.loads(response["SecretString"])
  except Exception as e:
    raise HTTPException(status_code=500, detail=f"Failed to fetch secret: {str(e)}")

def authenticate_request(request: Request, api_key: str) -> bool:
  auth_header = request.headers.get("Authorization")
  return auth_header == f"Bearer {api_key}"

async def ensure_tenant(db_name: str):
    # Retrieve secrets and configuration
    meta_secret = get_secret(META_SECRET_ARN)
    meta_user = meta_secret.get("username")
    meta_pass = meta_secret.get("password")
    meta_host = META_HOST
    meta_port = "5432"
    meta_db = "supavisor_meta"

    rds_secret = get_secret(RDS_SECRET_ARN)
    rds_user = rds_secret.get("username")
    rds_pass = rds_secret.get("password")
    rds_host = RDS_HOST
    rds_port = "5432"
    bearer_token = get_secret(SUPAVISOR_JWT).get("jwt_key")

    # Check if tenant exists
    conn = await asyncpg.connect(f"postgresql://{meta_user}:{meta_pass}@{meta_host}:{meta_port}/{meta_db}")
    print(bearer_token)
    try:
        tenant_id = db_name
        exists = await conn.fetchval("SELECT COUNT(*) FROM _supavisor.tenants WHERE external_id = $1", tenant_id)
        if exists == 0:
            # Step 1: Register tenant via Supavisor API
            async with aiohttp.ClientSession() as session:
                payload = {
                    "tenant": {
                        "external_id": db_name,
                        "db_host": rds_host,
                        "db_port": rds_port,
                        "db_database": db_name,
                        "ip_version": "auto",
                        "enforce_ssl": False,
                        "require_user": True,
                        "auth_query": "SELECT username, password FROM auth_credentials WHERE username = $1",
                        "users": [
                            {
                                "db_user": rds_user,
                                "db_password": rds_pass,
                                "pool_size": 20,
                                "mode_type": "transaction",
                                "is_manager": False
                            }
                        ]
                    }
                }
                headers = {
                    "Accept": "*/*",
                    "Authorization": f"Bearer {bearer_token}",
                    "Content-Type": "application/json"
                }
                async with session.put(f"http://{SUPAVISOR_HOST}/api/tenants/{db_name}", json=payload, headers=headers) as response:
                    if response.status not in (200, 201):
                        raise Exception(f"Failed to register tenant {db_name}: {await response.text()}")

            # Step 2: Set up auth_credentials table
            try:
                rds_conn = await asyncpg.connect(f"postgresql://{rds_user}:{rds_pass}@{rds_host}:{rds_port}/{db_name}")
                try:
                    # Create table
                    await rds_conn.execute("""
                        CREATE TABLE IF NOT EXISTS auth_credentials (
                            username text PRIMARY KEY,
                            password text NOT NULL,
                            external_id text NOT NULL
                        )
                    """)
                    # Insert credentials
                    await rds_conn.execute("""
                        INSERT INTO auth_credentials (username, password, external_id)
                        VALUES ($1, $2, $3)
                        ON CONFLICT (username) DO UPDATE SET password = EXCLUDED.password, external_id = EXCLUDED.external_id
                    """, rds_user, rds_pass, db_name)
                    # Grant permissions
                    await rds_conn.execute("GRANT ALL ON auth_credentials TO postgres")
                    logger.info(f"auth_credentials table created and populated successfully in database {db_name}")
                finally:
                    await rds_conn.close()
            except asyncpg.PostgresError as e:
                raise Exception(f"Failed to set up auth_credentials for {db_name}: {str(e)}")

    finally:
        await conn.close()

# Health Check
@app.get("/health")
async def health():
  return {"status": "ok"}

# Config Endpoint
@app.get("/config")
async def get_config(request: Request):
  api_secret = get_secret(API_SECRET_ARN)
  api_key = api_secret.get("api_key", "default-key")
  if not authenticate_request(request, api_key):
    raise HTTPException(status_code=401, detail="Unauthorized")
  return {"db_name": "postgres", "schema_name": "public"}  # Dummy response

# Proxy to Supavisor with SQL execution
@app.api_route("/oraion/{table_name}", methods=["GET", "POST", "PATCH", "DELETE"])
async def oraion_to_supavisor(request: Request, table_name: str):
  api_secret = get_secret(API_SECRET_ARN)
  api_key = api_secret.get("api_key", "default-key")
  if not authenticate_request(request, api_key):
    raise HTTPException(status_code=401, detail="Unauthorized")

  db_name = request.query_params.get("db_name")
  schema = request.query_params.get("schema_name")
  if not db_name or not schema or not table_name:
    raise HTTPException(status_code=400, detail="Missing db_name, schema_name, or table_name")

  # Ensure tenant exists in Supavisor meta DB
  await ensure_tenant(db_name)

  rds_secret = get_secret(RDS_SECRET_ARN)
  db_pass = rds_secret.get("password")
  rds_user = get_secret(META_SECRET_ARN).get("username")

  rds_direct =  f"postgresql://{rds_user}:{db_pass}@{RDS_HOST}:5432/{db_name}?sslmode=require"
  dsn = f"postgresql://{rds_user}.{db_name}:{db_pass}@{SUPAVISOR_HOST}:6543/{db_name}?sslmode=disable"

  conn = await asyncpg.connect(dsn)
  print(f"Connecting with DSN: {dsn}")
  try:
    if request.method == "GET":
      select_param = request.query_params.get("select", "*")
      where = []
      where_params = []
      param_index = 1
      order_clause = ""
      limit_clause = ""
      offset_clause = ""

      # Handle select/aggregation parsing (PostgREST-style)
      select_parts = []
      group_by_fields = []

      for part in select_param.split(","):
          if "(" in part and ")" in part:
              # Aggregate function, e.g. count(id)
              func_call = part.strip()
              func_name = func_call.split("(")[0].lower()
              arg = func_call[func_call.find("(")+1 : func_call.find(")")]

              if func_name not in ["count", "sum", "avg", "min", "max"]:
                  raise HTTPException(status_code=400, detail=f"Unsupported aggregation function: {func_name}")

              alias = f"{func_name}_{arg.replace('.', '_')}"
              select_parts.append(f"{func_name.upper()}({arg}) AS {alias}")
          else:
              # Regular field
              select_parts.append(part)
              group_by_fields.append(part)

      select_clause = ", ".join(select_parts)
      group_by_clause = f" GROUP BY {', '.join(group_by_fields)}" if any("(" not in s for s in select_parts) and any("(" in s for s in select_parts) else ""

      # Filter support
      for k, v in request.query_params.items():
          if '.' in k:
              op, col = k.split('.', 1)
              if op == "eq":
                  where.append(f"{col} = ${param_index}")
              elif op == "gt":
                  where.append(f"{col} > ${param_index}")
              elif op == "lt":
                  where.append(f"{col} < ${param_index}")
              elif op == "gte":
                  where.append(f"{col} >= ${param_index}")
              elif op == "lte":
                  where.append(f"{col} <= ${param_index}")
              elif op == "neq":
                  where.append(f"{col} != ${param_index}")
              elif op == "like":
                  where.append(f"{col} LIKE ${param_index}")
              elif op == "ilike":
                  where.append(f"{col} ILIKE ${param_index}")
              elif op == "in":
                  items = v.split(",")
                  placeholders = ", ".join(f"${param_index + i}" for i in range(len(items)))

                  # Try to cast each item to int or float
                  casted_items = []
                  for item in items:
                      try:
                          casted_items.append(int(item))
                      except ValueError:
                          try:
                              casted_items.append(float(item))
                          except ValueError:
                              casted_items.append(item)

                  where.append(f"{col} IN ({placeholders})")
                  where_params.extend(casted_items)
                  param_index += len(casted_items)
                  continue
              else:
                  continue  # unsupported operator

              # Attempt cast to int/float
              try:
                  val_casted = int(v)
              except ValueError:
                  try:
                      val_casted = float(v)
                  except ValueError:
                      val_casted = v
              where_params.append(val_casted)
              param_index += 1

      where_str = " WHERE " + " AND ".join(where) if where else ""

      # Sorting
      order = request.query_params.get("order")
      if order:
          parts = []
          for clause in order.split(","):
              if "." in clause:
                  col, direction = clause.rsplit(".", 1)
                  if direction.lower() in ["asc", "desc"]:
                      parts.append(f"{col} {direction.upper()}")
          if parts:
              order_clause = " ORDER BY " + ", ".join(parts)

      # Pagination
      limit = request.query_params.get("limit")
      offset = request.query_params.get("offset")
      if limit:
          limit_clause += f" LIMIT {limit}"
      if offset:
          offset_clause += f" OFFSET {offset}"

      # Final SQL
      sql = f"""
          SELECT {select_clause}
          FROM {schema}.{table_name}
          {where_str}
          {group_by_clause}
          {order_clause}
          {limit_clause}
          {offset_clause}
      """

      try:
          result = await conn.fetch(sql, *where_params)
          return [{"row": dict(r)} for r in result]
      except Exception as e:
          raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")

    elif request.method == "POST":
      body = await request.json()
      cols = ", ".join(body.keys())
      placeholders = ", ".join(f"${i+1}" for i in range(len(body)))
      sql = f"INSERT INTO {schema}.{table_name} ({cols}) VALUES ({placeholders}) RETURNING *"
      result = await conn.fetch(sql, *body.values())
      return [dict(r) for r in result]

    elif request.method == "PATCH":
      body = await request.json()
      set_clause = ", ".join(f"{k} = ${i+1}" for i, k in enumerate(body.keys()))
      where = []
      where_params = list(body.values())
      for k, v in request.query_params.items():
        if '.' in k:
          op, col = k.split('.')
          if op == "eq":
            where.append(f"{col} = ${len(where_params)+1}")
            where_params.append(v)
      where_str = " WHERE " + " AND ".join(where) if where else ""
      sql = f"UPDATE {schema}.{table_name} SET {set_clause}{where_str} RETURNING *"
      result = await conn.fetch(sql, *where_params)
      return [dict(r) for r in result]

    elif request.method == "DELETE":
      where = []
      where_params = []
      for k, v in request.query_params.items():
        if '.' in k:
          op, col = k.split('.')
          if op == "eq":
            where.append(f"{col} = ${len(where_params)+1}")
            where_params.append(v)
      where_str = " WHERE " + " AND ".join(where) if where else ""
      sql = f"DELETE FROM {schema}.{table_name}{where_str} RETURNING *"
      result = await conn.fetch(sql, *where_params)
      return [dict(r) for r in result]

  except Exception as e:
    raise HTTPException(status_code=500, detail=f"Database error: {str(e)}")
  finally:
    await conn.close()