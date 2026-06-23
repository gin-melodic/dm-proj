#!/bin/sh
set -eu

# Seed source documents only for a new volume. The service writes its generated
# index under this persistent /app/data tree and reuses it on later starts.
if [ ! -d /app/data/knowledge_bases ]; then
  echo "Seeding knowledge base into /app/data"
  mkdir -p /app/data
  cp -a /opt/dm-knowledge-data/. /app/data/
fi

exec "$@"
