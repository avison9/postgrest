-- Connect to supavisor_meta database
\c supavisor_meta

-- Create schema for Supavisor tables
CREATE SCHEMA IF NOT EXISTS _supavisor;

-- Create tenants table (from CreateTenants.exs)
CREATE TABLE _supavisor.tenants (
    id UUID PRIMARY KEY,
    external_id TEXT NOT NULL,
    db_host TEXT NOT NULL,
    db_port INTEGER NOT NULL,
    db_database TEXT NOT NULL,
    inserted_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX tenants_external_id_idx ON _supavisor.tenants (external_id);

-- Create users table (from CreateUsers.exs)
CREATE TABLE _supavisor.users (
    id UUID PRIMARY KEY,
    db_user_alias TEXT NOT NULL,
    db_user TEXT NOT NULL,
    db_pass_encrypted BYTEA NOT NULL,
    pool_size INTEGER NOT NULL,
    mode_type TEXT NOT NULL,
    is_manager BOOLEAN NOT NULL DEFAULT FALSE,
    tenant_external_id TEXT REFERENCES _supavisor.tenants (external_id) ON DELETE CASCADE,
    inserted_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW(),
    updated_at TIMESTAMP WITHOUT TIME ZONE NOT NULL DEFAULT NOW()
);

CREATE UNIQUE INDEX users_db_user_alias_tenant_mode_idx ON _supavisor.users (db_user_alias, tenant_external_id, mode_type);

-- Additional migrations (from other .exs files you listed)
ALTER TABLE _supavisor.users ADD COLUMN timeout INTEGER; -- From 20230502101623_add_timeout_to_users.exs
ALTER TABLE _supavisor.tenants ADD COLUMN pg_version TEXT; -- From 20230601125553_add_tenant_pg_version.exs
ALTER TABLE _supavisor.tenants ADD COLUMN ip_version TEXT; -- From 20230619091028_add_tenant_ip_version.exs
ALTER TABLE _supavisor.tenants ADD COLUMN upstream_ssl JSONB; -- From 20230705154938_add_upstream_ssl_opts.exs
ALTER TABLE _supavisor.tenants ADD COLUMN enforce_ssl BOOLEAN DEFAULT FALSE; -- From 20230711142028_add_enforce_ssl.exs



ALTER DATABASE supavisor_meta SET idle_in_transaction_session_timeout = '5min';
