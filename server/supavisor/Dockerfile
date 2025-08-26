FROM supabase/supavisor:2.6.1

USER root

# Install CA certificates (Debian way)
RUN apt-get update && \
    apt-get install -y --no-install-recommends ca-certificates lsof iproute2 net-tools tcpdump netcat-openbsd && \
    rm -rf /var/lib/apt/lists/*

# Override limits.sh to skip ulimit
RUN echo '#!/bin/bash\nexec "$@"' > /app/limits.sh && chmod +x /app/limits.sh

# Copy RDS CA certificate
COPY eu-north-1-bundle.pem /etc/ssl/certs/rds-ca.pem

RUN chmod 644 /etc/ssl/certs/rds-ca.pem

# Ensure config directory exists
RUN mkdir -p /app/config

# # # Copy runtime.exs with SSL config for meta & tenant DBs
COPY runtime.exs /app/releases/2.6.1/runtime.exs

# Copy start script
COPY start.sh /start.sh
RUN chmod +x /start.sh
COPY connection_logger.sh /connection_logger.sh
RUN chmod +x /connection_logger.sh

ENTRYPOINT ["/start.sh"]
