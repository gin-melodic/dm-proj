# dm-proj

Parent project for Dream Master, centrally managing the Go API, RAG knowledge service, and React Native client, with production deployment entry points for the backend.

## Project Structure

| Directory | Tech Stack | Responsibility |
| --- | --- | --- |
| `dm-server` | Go 1.25 / GoFrame / PostgreSQL | Users, authentication, dream journaling, WebSocket streaming analysis, and AI Provider invocation |
| `dm-knowledge-service` | Python 3.11 / FastAPI / TxtAI | Dream knowledge retrieval, imagery extraction, and caching |
| `dream-rn-expo` | Expo 56 / React Native | iOS and Android client |

Production pipeline: `React Native → dm-server → dm-knowledge-service`. Both backend services share a PostgreSQL database.

Default host ports: Go API `8080`, RAG API `8000`, PostgreSQL `5432`. Internally within containers, communication happens through `dm-knowledge-service:8000` and `postgres:5432`.

## Getting the Source Code

The three subprojects use Git submodules pinned to commits recorded in the parent repository:

```bash
git clone --recurse-submodules <dm-proj-repository-url>
cd dm-proj
```

For an existing copy of the parent repo:

```bash
git submodule update --init --recursive
```

To update a subproject, pull and commit changes normally inside its directory, then return to the parent directory to commit the new submodule pointer. The parent repository does not automatically follow subproject branches.

## Docker Deployment

Requires Docker Engine and Docker Compose v2+. The root-level RAG Dockerfile uses CPU-only Torch; during build it downloads embedding models and generates the TxtAI/FAISS index. Create local configuration first:

```bash
cp .env.example .env
```

At minimum, set `POSTGRES_PASSWORD`, `JWT_SECRET`, Supabase/auth configuration, and the API key for your chosen `AI_SERVICE`. The database password is used in the PostgreSQL DSN — use URL-safe characters only.

Start the full backend:

```bash
docker compose up -d --build
docker compose ps
```

Common maintenance commands:

```bash
docker compose logs -f dm-server dm-knowledge-service
docker compose restart dm-server
docker compose build --no-cache dm-server
docker compose up -d dm-server
docker compose down
```

`docker compose down` preserves named volumes. Only use `docker compose down -v` when you explicitly need to wipe the database, knowledge data, and logs.

## Build on macOS, Deploy Offline on VPS

A low-spec VPS doesn't need to compile Go/Python dependencies, download models, or re-embed knowledge text. `scripts/build-vps-bundle.sh` performs all of the following locally on macOS:

1. Build Go and RAG images for the VPS architecture;
2. Bake Hugging Face models, raw knowledge files, and pre-built vector indexes into the RAG image;
3. Pull a matching-architecture PostgreSQL image;
4. Package the three images, VPS Compose file, init SQL, environment template, and deployment script into a single archive.

For common Intel/AMD VPS, use the default target:

```bash
./scripts/build-vps-bundle.sh
```

Apple Silicon Macs will build `linux/amd64` images via Buildx/QEMU. The first RAG build takes longer — this is intentional, keeping heavy work on the local machine. For ARM64 VPS:

```bash
PLATFORM=linux/arm64 ./scripts/build-vps-bundle.sh
```

Output is at `dist/dm-proj-vps-<arch>.tar.gz`. Upload to the VPS and run:

```bash
tar -xzf dm-proj-vps-amd64.tar.gz
cd dm-proj-vps
./deploy.sh
# First run generates .env and exits; fill in required fields, then run again
vi .env
./deploy.sh
```

The VPS deployment script loads images from `images.tar.gz` via `docker load`, validates Compose, and starts services — no registry access required. RAG runs in Hugging Face/Transformers offline mode. On first creation of the `knowledge_data` volume, the entrypoint copies the knowledge base and vector index directly from inside the image.

When new knowledge content is published, existing VPS volumes are not overwritten by default. To confirm replacement with cached data from the new image:

```bash
./deploy.sh --refresh-knowledge
```

This only removes and recreates `dm-proj_knowledge_data`; PostgreSQL and log volumes are preserved. A normal `./deploy.sh` always keeps all data volumes intact.

Once services are running, visit:

- Go Swagger: `http://localhost:8080/swagger`
- Go OpenAPI: `http://localhost:8080/api.json`
- RAG health check: `http://localhost:8000/health`
- RAG API docs: `http://localhost:8000/docs`

PostgreSQL initialization scripts only run when the data volume is created for the first time. After adding or modifying SQL, existing environments should use a formal migration workflow rather than relying on container restarts to re-run init scripts.

## Local Development

Each subproject can still be started independently; see the individual README and `AGENTS.md` for specific commands:

```bash
cd dm-server && go run main.go
cd dm-knowledge-service && conda activate dm && python app/main.py
cd dream-rn-expo && npm install && npm start
```

Expo uses public variables from `dream-rn-expo/.env`:

```dotenv
EXPO_PUBLIC_API_BASE_URL_DEV=http://<dev-machine-lan-ip>:8080
EXPO_PUBLIC_API_BASE_URL_PROD=https://<production-api-domain>
EXPO_PUBLIC_SUPABASE_URL=https://<project>.supabase.co
EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY=<publishable-key>
```

`localhost` inside a physical device or emulator refers to the device itself, not the development machine running the backend. Use your dev machine's LAN IP for physical-device debugging. All `EXPO_PUBLIC_*` values are bundled into the client package — only public configuration is allowed. Never put Supabase secret keys, JWT secrets, or AI API keys here.

## Directory Structure

```text
dm-proj/
├── docker/                    # Root-level production images and Go production config
├── scripts/                   # Local packaging, RAG prewarming, and VPS deployment scripts
├── dm-server/                 # Go submodule
├── dm-knowledge-service/      # Python submodule
├── dream-rn-expo/             # Expo submodule
├── .env.example               # Unified backend environment variable template
├── docker-compose.yml         # Unified backend orchestration
├── docker-compose.vps.yml     # VPS orchestration without source code or build steps
├── LICENCE                    # MIT License
└── README.md
```

Runtime data is persisted via `postgres_data`, `knowledge_data`, `knowledge_logs`, and `server_logs` named volumes — not committed to Git.

This parent project is under the MIT License; see `LICENCE`.
