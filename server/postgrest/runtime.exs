config :supavisor,
  session_proxy_ports: [5432, 4000, 4001],
  transaction_proxy_ports: [5000, 5001],
  http_port: 4000,
  metrics_port: 4001,
  prom_poll_rate: 5_000,
  proxy_port_transaction: 5433,
  proxy_port_session: 5434,
  proxy_port: 5435,
  listeners: [
    %{
      port: 5433,  # your main proxy port
      transport: :tcp,
      tls: %{
        certfile: "/etc/ssl/certs/server_cert.pem",
        keyfile: "/etc/ssl/private/server_key.pem"
      }
    }
  ]
