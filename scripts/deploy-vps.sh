#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
cd "$ROOT"

command -v docker >/dev/null 2>&1 || { echo "docker is required" >&2; exit 1; }
docker compose version >/dev/null 2>&1 || { echo "docker compose v2 is required" >&2; exit 1; }

if [ ! -f .env ]; then
  cp .env.example .env
  echo "Created $ROOT/.env; fill required secrets, then run ./deploy.sh again." >&2
  exit 1
fi

if [ "${1:-}" = "--refresh-knowledge" ]; then
  echo "Refreshing the knowledge volume from the index baked into the image..."
  docker compose down
  docker volume rm dm-proj_knowledge_data 2>/dev/null || true
fi

echo "Loading offline images..."
gzip -dc images.tar.gz | docker load
docker compose config --quiet
docker compose up -d
docker compose ps
