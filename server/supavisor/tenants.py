import psycopg2
import base64
import re
import os
from cryptography.fernet import Fernet
from cryptography.hazmat.primitives import hashes
from cryptography.hazmat.primitives.kdf.pbkdf2 import PBKDF2HMAC

# Configuration
DB_HOST = "database-run.cpci0uk42i4s.eu-north-1.rds.amazonaws.com"
DB_PORT = 5432
DB_NAME = "supavisor_meta"
DB_USER = "postgres"
DB_PASSWORD = "MasterTest123$"  # Replace with actual password from var.rds_secret_arn
PEM_FILE_PATH = "eu-north-1-bundle.pem"  # Replace with actual path to PEM file
VAULT_ENC_KEY = "bf10423129eaf3a5531176087054b8c8"  # Replace with actual key from var.meta_hash_arn
USE_SSL = True  # Set to False to bypass SSL for testing

# Derive encryption key from VAULT_ENC_KEY
def derive_encryption_key(vault_key):
    if vault_key == "<VAULT_ENC_KEY>":
        raise ValueError("VAULT_ENC_KEY placeholder must be replaced with actual key")
    vault_key_bytes = vault_key.encode('utf-8')
    kdf = PBKDF2HMAC(
        algorithm=hashes.SHA256(),
        length=32,
        salt=b'supavisor_salt',
        iterations=100000,
    )
    key = base64.urlsafe_b64encode(kdf.derive(vault_key_bytes))
    return key

# Encrypt password
def encrypt_password(password, vault_key):
    try:
        key = derive_encryption_key(vault_key)
        fernet = Fernet(key)
        encrypted_password = fernet.encrypt(password.encode('utf-8'))
        return encrypted_password.decode('utf-8')
    except Exception as e:
        print(f"Error encrypting password: {e}")
        raise

# Read and process the PEM certificate
def read_pem_file(pem_file_path):
    try:
        with open(pem_file_path, "r") as f:
            content = f.read()
            certificates = re.split(r"-----END CERTIFICATE-----", content)
            for cert in certificates:
                cert = cert.strip()
                if not cert:
                    continue
                cert_content = re.sub(r"-----BEGIN CERTIFICATE-----|\n|\r", "", cert).strip()
                if cert_content:
                    try:
                        print(f"Processing certificate content: {cert_content[:50]}...")
                        base64.b64decode(cert_content, validate=True)
                        return cert_content
                    except base64.binascii.Error as e:
                        print(f"Error: Invalid base64 content in certificate: {e}")
                        raise
            raise ValueError("No valid certificate found in PEM file")
    except FileNotFoundError:
        print(f"Error: PEM file not found at {pem_file_path}")
        raise
    except Exception as e:
        print(f"Error reading PEM file: {e}")
        raise

# SQL statements
TENANTS_SQL = """
INSERT INTO _supavisor.tenants (
    id,
    external_id,
    db_host,
    db_port,
    db_database,
    inserted_at,
    updated_at,
    default_parameter_status,
    ip_version,
    upstream_ssl,
    upstream_verify,
    upstream_tls_ca,
    enforce_ssl,
    require_user,
    auth_query,
    default_pool_size,
    sni_hostname,
    default_max_clients,
    client_idle_timeout,
    default_pool_strategy,
    client_heartbeat_interval,
    allow_list,
    availability_zone
) VALUES (
    gen_random_uuid(),
    %s,
    %s,
    %s,
    %s,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    %s,
    %s,
    %s,
    %s,
    decode(%s, 'base64'),
    %s,
    %s,
    %s,
    %s,
    %s,
    %s,
    %s,
    %s,
    %s,
    %s,
    %s
) ON CONFLICT (external_id) DO UPDATE
SET db_host = EXCLUDED.db_host,
    db_port = EXCLUDED.db_port,
    db_database = EXCLUDED.db_database,
    updated_at = CURRENT_TIMESTAMP
RETURNING id;
"""

USERS_SQL = """
INSERT INTO _supavisor.users (
    id,
    db_user_alias,
    db_user,
    db_pass_encrypted,
    pool_size,
    mode_type,
    is_manager,
    tenant_external_id,
    inserted_at,
    updated_at,
    pool_checkout_timeout,
    max_clients
) VALUES (
    gen_random_uuid(),
    %s,
    %s,
    %s,
    %s,
    %s,
    %s,
    %s,
    CURRENT_TIMESTAMP,
    CURRENT_TIMESTAMP,
    %s,
    %s
) RETURNING id;
"""

CHECK_USER_SQL = """
SELECT id FROM _supavisor.users WHERE db_user = %s AND tenant_external_id = %s;
"""

UPDATE_USER_SQL = """
UPDATE _supavisor.users
SET db_user_alias = %s,
    db_pass_encrypted = %s,
    updated_at = CURRENT_TIMESTAMP
WHERE db_user = %s AND tenant_external_id = %s
RETURNING id;
"""

def main():
    # Read PEM file (if SSL is enabled)
    cert_content = None
    if USE_SSL:
        cert_content = read_pem_file(PEM_FILE_PATH)
    else:
        print("SSL disabled for testing; using NULL for upstream_tls_ca")

    # Encrypt the password
    encrypted_password = encrypt_password(DB_PASSWORD, VAULT_ENC_KEY)

    # Database connection
    try:
        print(f"Connecting to {DB_HOST}:{DB_PORT}/{DB_NAME} as {DB_USER}")
        conn = psycopg2.connect(
            host=DB_HOST,
            port=DB_PORT,
            dbname=DB_NAME,
            user=DB_USER,
            password=DB_PASSWORD,
            sslmode='require',
            sslrootcert=PEM_FILE_PATH
        )
        cursor = conn.cursor()

        # Insert or update tenant
        placeholder_count = TENANTS_SQL.count('%s')
        tenants_params = (
            'postgrest',  # external_id
            DB_HOST,      # db_host
            5432,         # db_port
            'supavisor_meta',  # db_database
            '{}',         # default_parameter_status
            'auto',       # ip_version
            USE_SSL,      # upstream_ssl
            'peer' if USE_SSL else 'none',  # upstream_verify
            cert_content if USE_SSL else None,  # upstream_tls_ca
            False,        # enforce_ssl
            True,         # require_user
            '',           # auth_query
            20,           # default_pool_size
            'postgrest',  # sni_hostname
            100,          # default_max_clients
            0,            # client_idle_timeout
            'fifo',       # default_pool_strategy
            60,           # client_heartbeat_interval
            ['0.0.0.0/0', '::/0'],  # allow_list
            'eu-north-1'  # availability_zone
        )
        print(f"Number of placeholders in TENANTS_SQL: {placeholder_count}")
        print(f"Number of parameters in tenants_params: {len(tenants_params)}")
        if placeholder_count != len(tenants_params):
            raise ValueError(f"Placeholder count ({placeholder_count}) does not match parameter count ({len(tenants_params)})")

        cursor.execute(TENANTS_SQL, tenants_params)
        tenant_id = cursor.fetchone()[0]
        print(f"Inserted/Updated tenant with ID: {tenant_id}")

        # Check if user exists
        check_user_params = ('postgrest', 'postgrest')
        cursor.execute(CHECK_USER_SQL, check_user_params)
        existing_user = cursor.fetchone()

        # Insert or update user
        users_params = (
            'postgrest.postgrest',  # db_user_alias
            'postgrest',            # db_user
            encrypted_password,     # db_pass_encrypted
            20,                     # pool_size
            'transaction',          # mode_type
            False,                  # is_manager
            'postgrest',            # tenant_external_id
            60000,                  # pool_checkout_timeout
            100                     # max_clients
        )
        if existing_user:
            print("User already exists; updating...")
            update_params = (
                users_params[0],  # db_user_alias
                users_params[2],  # db_pass_encrypted
                users_params[1],  # db_user
                users_params[6]   # tenant_external_id
            )
            cursor.execute(UPDATE_USER_SQL, update_params)
            user_id = cursor.fetchone()[0]
            print(f"Updated user with ID: {user_id}")
        else:
            cursor.execute(USERS_SQL, users_params)
            user_id = cursor.fetchone()[0]
            print(f"Inserted user with ID: {user_id}")

        # Verify insertions
        cursor.execute("SELECT * FROM _supavisor.tenants WHERE external_id = %s", ('postgrest',))
        tenant = cursor.fetchone()
        if tenant:
            print("Tenant inserted successfully:", tenant)
        else:
            print("Error: Tenant not found after insertion")

        cursor.execute("SELECT * FROM _supavisor.users WHERE db_user = %s AND tenant_external_id = %s", ('postgrest', 'postgrest'))
        user = cursor.fetchone()
        if user:
            print("User inserted successfully:", user)
        else:
            print("Error: User not found after insertion")

        # Commit transaction
        conn.commit()

    except psycopg2.Error as e:
        print(f"Database error: {e}")
        conn.rollback()
        raise
    except Exception as e:
        print(f"Error: {e}")
        raise
    finally:
        cursor.close()
        conn.close()

if __name__ == "__main__":
    main()