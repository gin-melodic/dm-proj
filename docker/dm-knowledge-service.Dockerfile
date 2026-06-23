# syntax=docker/dockerfile:1.7

FROM python:3.11-slim AS dependencies

ENV PYTHONPATH=/app \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    TOKENIZERS_PARALLELISM=false \
    OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 \
    TZ=Asia/Shanghai \
    HF_HOME=/opt/huggingface \
    SENTENCE_TRANSFORMERS_HOME=/opt/huggingface

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl libgomp1 \
    && rm -rf /var/lib/apt/lists/*

COPY dm-knowledge-service/requirements.txt /tmp/requirements.txt

# The CPU index publishes 2.2.2+cpu for amd64 but 2.2.2 for arm64.
# Matching the public version works on both architectures and still avoids CUDA wheels.
RUN --mount=type=cache,target=/root/.cache/pip,sharing=locked \
    python -m pip install --upgrade pip \
    && python -m pip install "numpy<2" "torch==2.2.2" --index-url https://download.pytorch.org/whl/cpu \
    && python -m pip install -r /tmp/requirements.txt

# Runtime embedding settings deliberately come after dependency installation so
# changing .env/build arguments does not invalidate the large Python wheel layer.
ARG EMBEDDING_MODEL=richinfoai/ritrieve_zh_v1
ARG EMBEDDING_PROVIDER=local
ARG GEMINI_EMBEDDING_MODEL=gemini-embedding-001
ARG GEMINI_EMBEDDING_DIMENSIONS=768
ARG GEMINI_EMBEDDING_BATCH_SIZE=100
ARG GEMINI_EMBEDDING_TIMEOUT_SECONDS=60
ARG GEMINI_EMBEDDING_MAX_RETRIES=3
ARG LMSTUDIO_EMBEDDING_BASE_URL=http://host.docker.internal:1234/v1
ARG LMSTUDIO_EMBEDDING_MODEL=text-embedding-model
ARG LMSTUDIO_EMBEDDING_DIMENSIONS=0
ARG LMSTUDIO_EMBEDDING_BATCH_SIZE=32
ARG LMSTUDIO_EMBEDDING_TIMEOUT_SECONDS=60
ARG LMSTUDIO_EMBEDDING_MAX_RETRIES=3

ENV EMBEDDING_PROVIDER=${EMBEDDING_PROVIDER} \
    EMBEDDING_MODEL=${EMBEDDING_MODEL} \
    GEMINI_EMBEDDING_MODEL=${GEMINI_EMBEDDING_MODEL} \
    GEMINI_EMBEDDING_DIMENSIONS=${GEMINI_EMBEDDING_DIMENSIONS} \
    GEMINI_EMBEDDING_BATCH_SIZE=${GEMINI_EMBEDDING_BATCH_SIZE} \
    GEMINI_EMBEDDING_TIMEOUT_SECONDS=${GEMINI_EMBEDDING_TIMEOUT_SECONDS} \
    GEMINI_EMBEDDING_MAX_RETRIES=${GEMINI_EMBEDDING_MAX_RETRIES} \
    LMSTUDIO_EMBEDDING_BASE_URL=${LMSTUDIO_EMBEDDING_BASE_URL} \
    LMSTUDIO_EMBEDDING_MODEL=${LMSTUDIO_EMBEDDING_MODEL} \
    LMSTUDIO_EMBEDDING_DIMENSIONS=${LMSTUDIO_EMBEDDING_DIMENSIONS} \
    LMSTUDIO_EMBEDDING_BATCH_SIZE=${LMSTUDIO_EMBEDDING_BATCH_SIZE} \
    LMSTUDIO_EMBEDDING_TIMEOUT_SECONDS=${LMSTUDIO_EMBEDDING_TIMEOUT_SECONDS} \
    LMSTUDIO_EMBEDDING_MAX_RETRIES=${LMSTUDIO_EMBEDDING_MAX_RETRIES}

FROM dependencies AS app

COPY dm-knowledge-service/app/ /app/app/
COPY dm-knowledge-service/data/ /opt/dm-knowledge-data/
COPY scripts/rag-entrypoint.sh /usr/local/bin/rag-entrypoint

RUN mkdir -p /app/logs /app/data \
    && chmod +x /usr/local/bin/rag-entrypoint

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=5 \
  CMD curl -fsS http://localhost:8000/health || exit 1

ENTRYPOINT ["rag-entrypoint"]
CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]

# Offline VPS images keep the model and vector index baked in.
FROM app AS offline

COPY scripts/prebuild-knowledge.py /opt/prebuild-knowledge.py

RUN --mount=type=secret,id=gemini_api_key \
    if [ "$EMBEDDING_PROVIDER" = "gemini" ]; then \
      GEMINI_API_KEY="$(cat /run/secrets/gemini_api_key)"; \
      export GEMINI_API_KEY; \
    fi; \
    KNOWLEDGE_BASE_DIR=/opt/dm-knowledge-data/knowledge_bases \
       KNOWLEDGE_CACHE_DB_PATH=/opt/dm-knowledge-data/knowledge.db \
       APP_ENV=production LOG_FILE= \
       python /opt/prebuild-knowledge.py \
    && rm /opt/prebuild-knowledge.py

# Local Compose builds only package source documents. The first container run
# creates an index in the persistent /app/data volume; later runs load it.
FROM app AS runtime
