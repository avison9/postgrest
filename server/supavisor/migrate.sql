CREATE TABLE _supavisor.tenants (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  external_id TEXT NOT NULL UNIQUE,
  db_host TEXT NOT NULL,
  db_port INTEGER NOT NULL,
  db_database TEXT NOT NULL,
  inserted_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  default_parameter_status JSONB NOT NULL DEFAULT '{}',
  ip_version TEXT NOT NULL DEFAULT 'auto',
  upstream_ssl BOOLEAN NOT NULL DEFAULT false,
  enforce_ssl BOOLEAN NOT NULL DEFAULT false,
  require_user BOOLEAN NOT NULL DEFAULT true,
  default_pool_size INTEGER NOT NULL DEFAULT 20,
  default_max_clients INTEGER NOT NULL DEFAULT 100,
  client_idle_timeout INTEGER NOT NULL DEFAULT 0,
  default_pool_strategy TEXT NOT NULL DEFAULT 'fifo',
  client_heartbeat_interval INTEGER NOT NULL DEFAULT 60,
  allow_list INET[] NOT NULL DEFAULT ARRAY['0.0.0.0/0', '::/0']
);




CREATE TABLE _supavisor.users (
  id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
  db_user_alias TEXT NOT NULL,
  db_user TEXT NOT NULL,
  db_pass_encrypted BYTEA NOT NULL,
  pool_size INTEGER NOT NULL DEFAULT 20,
  mode_type TEXT NOT NULL DEFAULT 'transaction',
  is_manager BOOLEAN NOT NULL DEFAULT false,
  tenant_external_id TEXT NOT NULL REFERENCES _supavisor.tenants(external_id) ON DELETE CASCADE,
  inserted_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  updated_at TIMESTAMP WITHOUT TIME ZONE DEFAULT CURRENT_TIMESTAMP,
  pool_checkout_timeout INTEGER NOT NULL DEFAULT 60000
);
