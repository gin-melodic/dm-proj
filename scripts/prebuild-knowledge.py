"""Build the RAG index during image creation and fail on an empty index."""

from app.services.knowledge_engine import KnowledgeEngine


engine = KnowledgeEngine()
for message in engine.load_knowledge_bases():
    print(message, flush=True)

stats = engine.embedding_service.get_stats()
if not stats.get("is_indexed") or not stats.get("indexed_count"):
    raise SystemExit(f"knowledge index prebuild failed: {stats}")

print(f"knowledge index ready: {stats['indexed_count']} documents", flush=True)
