FROM debian:bookworm-slim

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl jq awscli ca-certificates xz-utils && \
    rm -rf /var/lib/apt/lists/*

# Download and verify PostgREST
ARG POSTGREST_VERSION=v12.2.3
RUN curl -L -o /usr/local/bin/postgrest.tar.xz https://github.com/PostgREST/postgrest/releases/download/${POSTGREST_VERSION}/postgrest-${POSTGREST_VERSION}-linux-static-x64.tar.xz \
    && tar -xJf /usr/local/bin/postgrest.tar.xz -C /usr/local/bin \
    && rm /usr/local/bin/postgrest.tar.xz \
    && chmod +x /usr/local/bin/postgrest \
    && /usr/local/bin/postgrest --version

# Copy and register RDS CA certificate
COPY eu-north-1-bundle.pem /usr/local/share/ca-certificates/rds-ca.pem
RUN update-ca-certificates

# Copy entrypoint
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Expose PostgREST port
EXPOSE 3000

# Set entrypoint
ENTRYPOINT ["/start.sh"]
CMD ["postgrest"]
