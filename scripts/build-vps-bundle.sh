#!/bin/sh
set -eu

ROOT=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)

# Build settings live in the repository-level .env. Export them so Docker
# build arguments and BuildKit secrets can consume them. ENV_FILE can point to
# an alternative file; already-exported variables may still be overridden by
# putting the desired value in that file.
ENV_FILE=${ENV_FILE:-"$ROOT/.env"}
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090
  . "$ENV_FILE"
  set +a
fi

PLATFORM=${PLATFORM:-linux/amd64}
OUTPUT_DIR=${OUTPUT_DIR:-"$ROOT/dist"}
STAGE="$OUTPUT_DIR/dm-proj-vps"
ARCHIVE="$OUTPUT_DIR/dm-proj-vps-${PLATFORM#linux/}.tar.gz"
EMBEDDING_PROVIDER=${EMBEDDING_PROVIDER:-local}

case "$EMBEDDING_PROVIDER" in
  local|gemini|lmstudio) ;;
  *) echo "EMBEDDING_PROVIDER must be 'local', 'gemini', or 'lmstudio'" >&2; exit 1 ;;
esac

if [ "$EMBEDDING_PROVIDER" = "gemini" ] && [ -z "${GEMINI_API_KEY:-}" ]; then
  echo "GEMINI_API_KEY must be set when EMBEDDING_PROVIDER=gemini" >&2
  exit 1
fi

command -v docker >/dev/null 2>&1 || { echo "docker is required" >&2; exit 1; }
docker buildx version >/dev/null 2>&1 || { echo "docker buildx is required" >&2; exit 1; }

rm -rf "$STAGE"
mkdir -p "$STAGE/initdb" "$OUTPUT_DIR"

echo "Building VPS images for $PLATFORM (RAG model and index are baked in)..."
docker pull --platform "$PLATFORM" postgres:18.4
docker buildx build --platform "$PLATFORM" --load \
  -f "$ROOT/docker/dm-server.Dockerfile" \
  -t dm-server:vps "$ROOT"
set -- docker buildx build --platform "$PLATFORM" --load \
  -f "$ROOT/docker/dm-knowledge-service.Dockerfile" \
  --target offline \
  --build-arg "EMBEDDING_PROVIDER=$EMBEDDING_PROVIDER" \
  --build-arg "EMBEDDING_MODEL=${EMBEDDING_MODEL:-richinfoai/ritrieve_zh_v1}" \
  --build-arg "GEMINI_EMBEDDING_MODEL=${GEMINI_EMBEDDING_MODEL:-gemini-embedding-001}" \
  --build-arg "GEMINI_EMBEDDING_DIMENSIONS=${GEMINI_EMBEDDING_DIMENSIONS:-768}" \
  --build-arg "GEMINI_EMBEDDING_BATCH_SIZE=${GEMINI_EMBEDDING_BATCH_SIZE:-100}" \
  --build-arg "GEMINI_EMBEDDING_TIMEOUT_SECONDS=${GEMINI_EMBEDDING_TIMEOUT_SECONDS:-60}" \
  --build-arg "GEMINI_EMBEDDING_MAX_RETRIES=${GEMINI_EMBEDDING_MAX_RETRIES:-3}" \
  --build-arg "LMSTUDIO_EMBEDDING_BASE_URL=${LMSTUDIO_EMBEDDING_BASE_URL:-http://host.docker.internal:1234/v1}" \
  --build-arg "LMSTUDIO_EMBEDDING_MODEL=${LMSTUDIO_EMBEDDING_MODEL:-text-embedding-model}" \
  --build-arg "LMSTUDIO_EMBEDDING_DIMENSIONS=${LMSTUDIO_EMBEDDING_DIMENSIONS:-0}" \
  --build-arg "LMSTUDIO_EMBEDDING_BATCH_SIZE=${LMSTUDIO_EMBEDDING_BATCH_SIZE:-32}" \
  --build-arg "LMSTUDIO_EMBEDDING_TIMEOUT_SECONDS=${LMSTUDIO_EMBEDDING_TIMEOUT_SECONDS:-60}" \
  --build-arg "LMSTUDIO_EMBEDDING_MAX_RETRIES=${LMSTUDIO_EMBEDDING_MAX_RETRIES:-3}" \
  -t dm-knowledge-service:vps
if [ "$EMBEDDING_PROVIDER" = "gemini" ]; then
  set -- "$@" --secret id=gemini_api_key,env=GEMINI_API_KEY
fi
if [ "$EMBEDDING_PROVIDER" = "lmstudio" ]; then
  set -- "$@" --add-host host.docker.internal=host-gateway
fi
set -- "$@" "$ROOT"
"$@"

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
