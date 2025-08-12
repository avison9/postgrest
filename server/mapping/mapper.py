# from fastapi import FastAPI, Request, HTTPException, Response
# import httpx
# import os
# import boto3
# import json

# app = FastAPI()

# # Initialize AWS Secrets Manager client
# session = boto3.session.Session()
# secrets_client = session.client("secretsmanager")

# # Get ALB DNS from environment variable
# POSTGREST_ALB_URL = os.getenv("POSTGREST_INTERNAL_ALB", "http://internal-alb.example.com")
# RDS_HOST = os.getenv("RDS_HOST", "rds-host")
# API_SECRET_ARN = os.getenv("API_SECRET_ARN")
# RDS_SECRET_ARN = os.getenv("RDS_SECRET_ARN")


# # ----------------------------
# # Utilities
# # ----------------------------

# def get_secret(secret_arn: str) -> dict:
#     try:
#         response = secrets_client.get_secret_value(SecretId=secret_arn)
#         return json.loads(response["SecretString"])
#     except Exception as e:
#         raise HTTPException(status_code=500, detail=f"Failed to fetch secret: {str(e)}")


# def authenticate_request(request: Request, api_key: str) -> bool:
#     auth_header = request.headers.get("Authorization")
#     return auth_header == f"Bearer {api_key}"


# # ----------------------------
# # Health Check (No Auth)
# # ----------------------------

# @app.get("/health")
# async def health():
#     return {"status": "ok"}


# # ----------------------------
# # Config Endpoint (Protected)
# # ----------------------------

# @app.get("/config")
# async def get_config(request: Request):
#     api_secret = get_secret(API_SECRET_ARN)
#     api_key = api_secret.get("api_key", "default-key")

#     if not authenticate_request(request, api_key):
#         raise HTTPException(status_code=401, detail="Unauthorized")

#     # You can replace with tenant-specific logic
#     return {"db_name": "app_db", "schema_name": "public"}


# # ----------------------------
# # DB URL Generator (Protected)
# # ----------------------------

# @app.get("/db-url")
# async def get_db_url(request: Request, db_name: str, schema_name: str):
#     api_secret = get_secret(API_SECRET_ARN)
#     api_key = api_secret.get("api_key", "default-key")

#     if not authenticate_request(request, api_key):
#         raise HTTPException(status_code=401, detail="Unauthorized")

#     rds_secret = get_secret(RDS_SECRET_ARN)
#     rds_user = rds_secret.get("username", "user")
#     rds_password = rds_secret.get("password", "password")
#     rds_port = rds_secret.get("port", "5432")

#     db_url = f"postgresql://{rds_user}:{rds_password}@{RDS_HOST}:{rds_port}/{db_name}"
#     return {"db_url": db_url, "schema_name": schema_name}


# # ----------------------------
# # Proxy to PostgREST (Protected)
# # ----------------------------

# @app.api_route("/proxy/{table_name}", methods=["GET", "POST", "PATCH", "DELETE", "PUT", "OPTIONS"])
# async def proxy_to_postgrest(request: Request, table_name: str):
#     api_secret = get_secret(API_SECRET_ARN)
#     api_key = api_secret.get("api_key", "default-key")

#     if not authenticate_request(request, api_key):
#         raise HTTPException(status_code=401, detail="Unauthorized")

#     # Extract query params
#     db_name = request.query_params.get("db_name")
#     schema = request.query_params.get("schema_name")

#     if not db_name or not schema or not table_name:
#         raise HTTPException(status_code=400, detail="Missing db_name, schema_name, or table_name")

#     # RDS credentials
#     rds_secret = get_secret(RDS_SECRET_ARN)
#     rds_user = rds_secret.get("username", "user")
#     rds_password = rds_secret.get("password", "password")
#     rds_port = rds_secret.get("port", "5432")

#     db_url = f"postgresql://{rds_user}:{rds_password}@{RDS_HOST}:{rds_port}/{db_name}"

#     # Construct headers
#     headers = dict(request.headers)
#     headers["X-Db-Uri"] = db_url
#     headers["Host"] = POSTGREST_ALB_URL.split("//")[1]
#     headers["Prefer"] = f"schema={schema}"

#     async with httpx.AsyncClient() as client:
#         try:
#             response = await client.request(
#                 method=request.method,
#                 url=f"{POSTGREST_ALB_URL}/postgrest/{table_name}",
#                 headers=headers,
#                 content=await request.body(),
#                 params=request.query_params
#             )
#             return Response(
#                 content=response.content,
#                 status_code=response.status_code,
#                 headers=dict(response.headers)
#             )
#         except httpx.RequestError as e:
#             raise HTTPException(status_code=500, detail=f"Error forwarding request: {str(e)}")


from fastapi import FastAPI, Request, HTTPException, Response
import httpx
import os
import boto3
import json
import asyncpg

app = FastAPI()

# Initialize AWS Secrets Manager client
session = boto3.session.Session()
secrets_client = session.client("secretsmanager")

# Environment variables
POSTGREST_ALB_URL = os.getenv("POSTGREST_INTERNAL_ALB", "http://internal-alb.example.com")
RDS_HOST = os.getenv("RDS_HOST", "rds-host")
API_SECRET_ARN = os.getenv("API_SECRET_ARN")
RDS_SECRET_ARN = os.getenv("RDS_SECRET_ARN")
META_SECRET_ARN = os.getenv("META_SECRET_ARN")
META_HOST = os.getenv("META_HOST")

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
    rds_secret = get_secret(RDS_SECRET_ARN)
    meta_user = rds_secret.get("username")
    meta_pass = rds_secret.get("password")
    meta_host = RDS_HOST
    meta_port = "5432"
    meta_db = "supavisor_meta"

    conn = await asyncpg.connect(f"postgresql://{meta_user}:{meta_pass}@{meta_host}:{meta_port}/{meta_db}")
    try:
        tenant_id = db_name  # Use db_name as tenant_id
        exists = await conn.fetchval("SELECT COUNT(*) FROM _supavisor.tenants WHERE external_id = $1", tenant_id)
        if exists == 0:
            # Insert into tenants
            await conn.execute("""
                INSERT INTO _supavisor.tenants (id, external_id, db_host, db_port, db_database)
                VALUES (gen_random_uuid(), $1, $2, $3, $4)
            """, tenant_id, RDS_HOST, 5432, db_name)

            # Insert into users
            await conn.execute("""
                INSERT INTO _supavisor.users (id, db_user_alias, db_user, db_pass_encrypted, pool_size, mode_type, is_manager, tenant_external_id)
                VALUES (gen_random_uuid(), $1, $1, $2::bytea, $3, $4, $5, $6)
            """, f"postgrest.{tenant_id}", rds_secret.get("password").encode('utf-8'), 20, "transaction", False, tenant_id)
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

# Proxy to PostgREST
@app.api_route("/proxy/{table_name}", methods=["GET", "POST", "PATCH", "DELETE", "PUT", "OPTIONS"])
async def proxy_to_postgrest(request: Request, table_name: str):
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

  # Construct headers
  headers = dict(request.headers)
  headers.pop("X-Db-Uri", None)  # Not needed with Supavisor
  headers["Prefer"] = f"schema={schema}"
  headers["Host"] = POSTGREST_ALB_URL.split("//")[1]
  # Set tenant-specific username for Supavisor routing
  headers["Authorization"] = f"Bearer postgrest.{db_name}"

  url = f"{POSTGREST_ALB_URL}/{table_name}"

  async with httpx.AsyncClient() as client:
    try:
      response = await client.request(
        method=request.method,
        url=url,
        headers=headers,
        content=await request.body(),
        params=request.query_params
      )
      return Response(
        content=response.content,
        status_code=response.status_code,
        headers=dict(response.headers)
      )
    except httpx.RequestError as e:
      raise HTTPException(status_code=500, detail=f"Error forwarding request: {str(e)}")