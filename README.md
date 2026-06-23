# dm-proj

Dream Master 的父级工程，统一管理 Go API、RAG 知识服务和 React Native 客户端，并提供后端生产部署入口。

## 项目组成

| 目录 | 技术栈 | 职责 |
| --- | --- | --- |
| `dm-server` | Go 1.25 / GoFrame / PostgreSQL | 用户、鉴权、梦境记录、WebSocket 流式分析及 AI Provider 调用 |
| `dm-knowledge-service` | Python 3.11 / FastAPI / TxtAI | 梦境知识检索、意象抽取和缓存 |
| `dream-rn-expo` | Expo 56 / React Native | iOS、Android 客户端 |

生产链路为：`React Native → dm-server → dm-knowledge-service`，两个后端服务共享 PostgreSQL。

默认宿主机端口：Go API `8080`、RAG API `8000`、PostgreSQL `5432`。容器内部通过 `dm-knowledge-service:8000` 和 `postgres:5432` 通信。

## 获取源码

三个子项目使用 Git submodule 固定到父仓库记录的提交：

```bash
git clone --recurse-submodules <dm-proj-repository-url>
cd dm-proj
```

已有父仓库副本可执行：

```bash
git submodule update --init --recursive
```

更新某个子项目时，在子目录正常拉取并提交业务改动，再回到父目录提交新的 submodule 指针。父仓库不会自动跟随子项目分支。

## Docker 部署

要求 Docker Engine 与 Docker Compose v2+。根层 RAG Dockerfile 固定使用 CPU-only Torch，构建时会下载嵌入模型并生成 TxtAI/FAISS 索引。先创建本地配置：

```bash
cp .env.example .env
```

至少设置 `POSTGRES_PASSWORD`、`JWT_SECRET`、Supabase/登录配置，以及当前 `AI_SERVICE` 对应的 API Key。数据库密码会进入 PostgreSQL DSN，请使用 URL-safe 字符。

启动完整后端：

```bash
docker compose up -d --build
docker compose ps
```

常用运维命令：

```bash
docker compose logs -f dm-server dm-knowledge-service
docker compose restart dm-server
docker compose build --no-cache dm-server
docker compose up -d dm-server
docker compose down
```

`docker compose down` 会保留 named volumes。只有明确需要清空数据库、知识数据和日志时才使用 `docker compose down -v`。

## macOS 构建，VPS 离线部署

低配 VPS 不需要编译 Go/Python 依赖、下载模型或重新嵌入知识文本。`scripts/build-vps-bundle.sh` 会在 macOS 本地完成以下工作：

1. 按 VPS 架构构建 Go 和 RAG 镜像；
2. 将 Hugging Face 模型、原始知识文件和预生成向量索引烘焙进 RAG 镜像；
3. 拉取同架构 PostgreSQL 镜像；
4. 将三个镜像、VPS Compose、初始化 SQL、环境模板和部署脚本打成一个压缩包。

常见的 Intel/AMD VPS 使用默认目标：

```bash
./scripts/build-vps-bundle.sh
```

Apple Silicon Mac 会通过 Buildx/QEMU 构建 `linux/amd64` 镜像，RAG 首次构建耗时较长，但这正是把重活留在本机。ARM64 VPS 可改为：

```bash
PLATFORM=linux/arm64 ./scripts/build-vps-bundle.sh
```

产物位于 `dist/dm-proj-vps-<架构>.tar.gz`。上传并在 VPS 执行：

```bash
tar -xzf dm-proj-vps-amd64.tar.gz
cd dm-proj-vps
./deploy.sh
# 首次运行会生成 .env 并退出；填写必填项后再次执行
vi .env
./deploy.sh
```

VPS 部署脚本会从 `images.tar.gz` 执行 `docker load`，随后校验 Compose 并启动服务，全程无需访问镜像仓库。RAG 运行时设置为 Hugging Face/Transformers 离线模式；首次创建 `knowledge_data` volume 时，入口脚本直接复制镜像内的知识库和向量索引。

发布了新版知识内容时，已有 VPS volume 不会被默认覆盖。确认需要用新镜像中的缓存替换现有知识数据后执行：

```bash
./deploy.sh --refresh-knowledge
```

该参数只删除并重建 `dm-proj_knowledge_data`，不会删除 PostgreSQL 和日志 volumes。默认 `./deploy.sh` 始终保留所有数据卷。

服务启动后可访问：

- Go Swagger：`http://localhost:8080/swagger`
- Go OpenAPI：`http://localhost:8080/api.json`
- RAG 健康检查：`http://localhost:8000/health`
- RAG API 文档：`http://localhost:8000/docs`

PostgreSQL 初始化脚本只会在数据卷首次创建时运行。新增或修改 SQL 后，已有环境应使用正式迁移流程，不能依赖重启容器重复执行初始化脚本。

## 本地开发

各项目仍可独立启动，具体命令以子项目 README 和 `AGENTS.md` 为准：

```bash
cd dm-server && go run main.go
cd dm-knowledge-service && conda activate dm && python app/main.py
cd dream-rn-expo && npm install && npm start
```

Expo 使用 `dream-rn-expo/.env` 中的公开变量：

```dotenv
EXPO_PUBLIC_API_BASE_URL_DEV=http://<开发机局域网IP>:8080
EXPO_PUBLIC_API_BASE_URL_PROD=https://<生产API域名>
EXPO_PUBLIC_SUPABASE_URL=https://<project>.supabase.co
EXPO_PUBLIC_SUPABASE_PUBLISHABLE_KEY=<publishable-key>
```

真机或模拟器中的 `localhost` 指向设备自身，不能代表运行后端的开发机；真机调试请使用开发机局域网 IP。所有 `EXPO_PUBLIC_*` 值都会进入客户端包，只能放公开配置，禁止填写 Supabase secret key、JWT secret 或 AI API Key。

## 目录结构

```text
dm-proj/
├── docker/                    # 父层生产镜像及 Go 生产配置
├── scripts/                   # 本地打包、RAG 预热及 VPS 部署脚本
├── dm-server/                 # Go submodule
├── dm-knowledge-service/      # Python submodule
├── dream-rn-expo/             # Expo submodule
├── .env.example               # 后端统一环境变量模板
├── docker-compose.yml         # 后端统一编排
├── docker-compose.vps.yml     # 无源码、无构建步骤的 VPS 编排
├── LICENCE                    # MIT License
└── README.md
```

运行数据由 `postgres_data`、`knowledge_data`、`knowledge_logs` 和 `server_logs` named volumes 持久化，不提交到 Git。

本父项目采用 MIT License，详见 `LICENCE`。
