FROM python:3.11-slim AS dependencies

ARG EMBEDDING_MODEL=richinfoai/ritrieve_zh_v1

ENV PYTHONPATH=/app \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1 \
    TOKENIZERS_PARALLELISM=false \
    OMP_NUM_THREADS=1 \
    MKL_NUM_THREADS=1 \
    NUMEXPR_NUM_THREADS=1 \
    TZ=Asia/Shanghai \
    HF_HOME=/opt/huggingface \
    SENTENCE_TRANSFORMERS_HOME=/opt/huggingface \
    EMBEDDING_MODEL=${EMBEDDING_MODEL}

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
      ca-certificates curl libgomp1 \
    && rm -rf /var/lib/apt/lists/*

COPY dm-knowledge-service/requirements.txt /tmp/requirements.txt

# The CPU index publishes 2.2.2+cpu for amd64 but 2.2.2 for arm64.
# Matching the public version works on both architectures and still avoids CUDA wheels.
RUN python -m pip install --no-cache-dir --upgrade pip \
    && python -m pip install --no-cache-dir "numpy<2" "torch==2.2.2" --index-url https://download.pytorch.org/whl/cpu \
    && python -m pip install --no-cache-dir -r /tmp/requirements.txt

FROM dependencies AS runtime

COPY dm-knowledge-service/app/ /app/app/
COPY dm-knowledge-service/data/ /opt/dm-knowledge-data/
COPY scripts/prebuild-knowledge.py /opt/prebuild-knowledge.py
COPY scripts/rag-entrypoint.sh /usr/local/bin/rag-entrypoint

# Download the model and generate TxtAI/FAISS indices during the local image build.
RUN mkdir -p /app/logs /app/data \
    && KNOWLEDGE_BASE_DIR=/opt/dm-knowledge-data/knowledge_bases \
       KNOWLEDGE_CACHE_DB_PATH=/opt/dm-knowledge-data/knowledge.db \
       APP_ENV=production LOG_FILE= \
       python /opt/prebuild-knowledge.py \
    && chmod +x /usr/local/bin/rag-entrypoint \
    && rm /opt/prebuild-knowledge.py

EXPOSE 8000
HEALTHCHECK --interval=30s --timeout=10s --start-period=90s --retries=5 \
  CMD curl -fsS http://localhost:8000/health || exit 1

ENTRYPOINT ["rag-entrypoint"]
CMD ["python", "-m", "uvicorn", "app.main:app", "--host", "0.0.0.0", "--port", "8000"]
