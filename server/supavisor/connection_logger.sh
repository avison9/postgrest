#!/bin/bash
# connection_logger.sh

while true; do
  echo "------ $(date) ------"
  ss -tnp | grep ':5432'
  sleep 1
done
