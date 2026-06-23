#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
PLATFORM=${PLATFORM:-linux/amd64}
OUTPUT_DIR=${OUTPUT_DIR:-"$ROOT/dist"}
STAGE="$OUTPUT_DIR/dm-proj-vps"
ARCHIVE="$OUTPUT_DIR/dm-proj-vps-${PLATFORM#linux/}.tar.gz"

command -v docker >/dev/null 2>&1 || { echo "docker is required" >&2; exit 1; }
docker buildx version >/dev/null 2>&1 || { echo "docker buildx is required" >&2; exit 1; }

rm -rf "$STAGE"
mkdir -p "$STAGE/initdb" "$OUTPUT_DIR"

echo "Building VPS images for $PLATFORM (RAG model and index are baked in)..."
docker pull --platform "$PLATFORM" postgres:18.4
docker buildx build --platform "$PLATFORM" --load \
  -f "$ROOT/docker/dm-server.Dockerfile" \
  -t dm-server:vps "$ROOT"
docker buildx build --platform "$PLATFORM" --load \
  -f "$ROOT/docker/dm-knowledge-service.Dockerfile" \
  --build-arg "USE_CHINA_MIRRORS=${USE_CHINA_MIRRORS:-true}" \
  --build-arg "TUNA_PYPI_MIRROR=${TUNA_PYPI_MIRROR:-https://mirrors.aliyun.com/pypi/simple/}" \
  --build-arg "HF_MIRROR_ENDPOINT=${HF_MIRROR_ENDPOINT:-https://hf-mirror.com}" \
  --build-arg "EMBEDDING_MODEL=${EMBEDDING_MODEL:-richinfoai/ritrieve_zh_v1}" \
  -t dm-knowledge-service:vps "$ROOT"

echo "Exporting images..."
docker save dm-server:vps dm-knowledge-service:vps postgres:18.4 | gzip -1 > "$STAGE/images.tar.gz"
cp "$ROOT/docker-compose.vps.yml" "$STAGE/docker-compose.yml"
cp "$ROOT/.env.example" "$STAGE/.env.example"
cp "$ROOT/LICENCE" "$STAGE/LICENCE"
cp "$ROOT/README.md" "$STAGE/README.md"
cp "$ROOT/scripts/deploy-vps.sh" "$STAGE/deploy.sh"
cp "$ROOT/dm-server/resource/database/0-create-tables.sql" "$STAGE/initdb/00-create-tables.sql"
cp "$ROOT/dm-knowledge-service/scripts/migrate_knowledge_cache_schema.sql" "$STAGE/initdb/10-migrate-knowledge-cache-schema.sql"
cp "$ROOT/dm-knowledge-service/scripts/migrate_symbol_cache.sql" "$STAGE/initdb/20-migrate-symbol-cache.sql"
chmod +x "$STAGE/deploy.sh"

tar -C "$OUTPUT_DIR" -czf "$ARCHIVE" "$(basename "$STAGE")"
echo "Offline bundle ready: $ARCHIVE"
