# FROM alpine:latest

# # Install dependencies
# RUN apk add --no-cache curl jq aws-cli

# # (Optional) Install bash if you're keeping #!/bin/bash
# # RUN apk add --no-cache bash

# # Install PostgREST binary
# RUN curl -L -o /usr/local/bin/postgrest https://github.com/PostgREST/postgrest/releases/latest/download/postgrest.x86_64 \
#     && chmod +x /usr/local/bin/postgrest

# # Copy and prepare entrypoint
# COPY entrypoint.sh /entrypoint.sh
# RUN chmod +x /entrypoint.sh

# ENTRYPOINT ["/entrypoint.sh"]

FROM debian:bookworm-slim

# Install dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends curl jq awscli ca-certificates && \
    rm -rf /var/lib/apt/lists/*

# Download PostgREST (use specific version for stability)
ARG POSTGREST_VERSION=v12.2.3
RUN curl -L -o /usr/local/bin/postgrest https://github.com/PostgREST/postgrest/releases/download/${POSTGREST_VERSION}/postgrest-${POSTGREST_VERSION}-linux-static-x64 \
    && chmod +x /usr/local/bin/postgrest

# Copy entrypoint
COPY start.sh /start.sh
RUN chmod +x /start.sh

# Expose PostgREST port
EXPOSE 3000

# Set entrypoint
ENTRYPOINT ["/start.sh"]
CMD ["postgrest"]
