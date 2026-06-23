#!/bin/sh
set -eu

# Docker only copies image contents into a new volume when the mount point itself
# contains them. Our immutable seed lives elsewhere, so seed explicitly and keep
# /app/data writable for later knowledge updates.
if [ ! -d /app/data/knowledge_bases/indices ]; then
  echo "Seeding prebuilt knowledge base and vector index into /app/data"
  mkdir -p /app/data
  cp -a /opt/dm-knowledge-data/. /app/data/
fi

exec "$@"
