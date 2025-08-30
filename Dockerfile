# syntax=docker/dockerfile:1
# Initialize device type args
# use build args in the docker build command with --build-arg="BUILDARG=true"
ARG USE_CUDA=false
ARG USE_OLLAMA=false
ARG USE_SLIM=true
# Tested with cu117 for CUDA 11 and cu121 for CUDA 12 (default)
ARG USE_CUDA_VER=cu128
# any sentence transformer model; models to use can be found at https://huggingface.co/models?library=sentence-transformers
# Leaderboard: https://huggingface.co/spaces/mteb/leaderboard 
# for better performance and multilangauge support use "intfloat/multilingual-e5-large" (~2.5GB) or "intfloat/multilingual-e5-base" (~1.5GB)
# IMPORTANT: If you change the embedding model (sentence-transformers/all-MiniLM-L6-v2) and vice versa, you aren't able to use RAG Chat with your previous documents loaded in the WebUI! You need to re-embed them.
ARG USE_EMBEDDING_MODEL=sentence-transformers/all-MiniLM-L6-v2
ARG USE_RERANKING_MODEL=""

# Tiktoken encoding name; models to use can be found at https://huggingface.co/models?library=tiktoken
ARG USE_TIKTOKEN_ENCODING_NAME="cl100k_base"

ARG BUILD_HASH=dev-build
# Override at your own risk - non-root configurations are untested
ARG UID=0
ARG GID=0

######## WebUI frontend ########
FROM --platform=$BUILDPLATFORM node:22-alpine3.20 AS frontend-build
ARG BUILD_HASH

WORKDIR /app

# to store git revision in build
RUN apk add --no-cache git

COPY package.json package-lock.json ./
RUN npm ci --force

COPY . .
ENV APP_BUILD_HASH=${BUILD_HASH}

# Set Node.js memory limits to prevent heap out of memory
ENV NODE_OPTIONS="--max-old-space-size=5120"
RUN npm run build

######## Python dependencies ########
FROM python:3.11-slim-bookworm AS deps

# Use args
ARG USE_CUDA
ARG USE_OLLAMA
ARG USE_CUDA_VER
ARG USE_SLIM
ARG USE_EMBEDDING_MODEL
ARG USE_RERANKING_MODEL
ARG UID
ARG GID

## Basis ##
ENV ENV=prod \
    PORT=8080 \
    # pass build args to the build
    USE_OLLAMA_DOCKER=${USE_OLLAMA} \
    USE_CUDA_DOCKER=${USE_CUDA} \
    USE_SLIM_DOCKER=${USE_SLIM} \
    USE_CUDA_DOCKER_VER=${USE_CUDA_VER} \
    USE_EMBEDDING_MODEL_DOCKER=${USE_EMBEDDING_MODEL} \
    USE_RERANKING_MODEL_DOCKER=${USE_RERANKING_MODEL}

## Basis URL Config ##
ENV OPENAI_API_BASE_URL="https://openai.inference.de-txl.ionos.com/v1"

## API Key and Security Config ##
ENV OPENAI_API_KEY="" \
    WEBUI_SECRET_KEY="f7ccfc96-088b-428a-955d-ac9040fbaa94" \
    ENABLE_SIGNUP=true \
    ENABLE_LOGIN_FORM=true \
    ENABLE_SIGNUP_PASSWORD_CONFIRMATION=false \
    DEFAULT_USER_ROLE=admin \
    ENABLE_OLLAMA_API=false \
    USE_OLLAMA_DOCKER=false \
    USE_CUDA_DOCKER=false \
    USE_SLIM_DOCKER=true \
    # PROXY TRUST CONFIGURATION
    FORWARDED_ALLOW_IPS="*" \
    UVICORN_WORKERS=1

## Admin Permissions Config - Full Access ##
# ENV USER_PERMISSIONS_WORKSPACE_MODELS_ACCESS=true \
#     USER_PERMISSIONS_WORKSPACE_KNOWLEDGE_ACCESS=true \
#     USER_PERMISSIONS_WORKSPACE_PROMPTS_ACCESS=true \
#     USER_PERMISSIONS_WORKSPACE_TOOLS_ACCESS=true \
#     USER_PERMISSIONS_WORKSPACE_MODELS_ALLOW_PUBLIC_SHARING=true \
#     USER_PERMISSIONS_WORKSPACE_KNOWLEDGE_ALLOW_PUBLIC_SHARING=true \
#     USER_PERMISSIONS_WORKSPACE_PROMPTS_ALLOW_PUBLIC_SHARING=true \
#     USER_PERMISSIONS_WORKSPACE_TOOLS_ALLOW_PUBLIC_SHARING=true \
#     USER_PERMISSIONS_CHAT_CONTROLS=true \
#     USER_PERMISSIONS_CHAT_VALVES=true \
#     USER_PERMISSIONS_CHAT_SYSTEM_PROMPT=true \
#     USER_PERMISSIONS_CHAT_PARAMS=true \
#     USER_PERMISSIONS_CHAT_FILE_UPLOAD=true \
#     USER_PERMISSIONS_CHAT_DELETE=true \
#     USER_PERMISSIONS_CHAT_DELETE_MESSAGE=true \
#     USER_PERMISSIONS_CHAT_CONTINUE_RESPONSE=true \
#     USER_PERMISSIONS_CHAT_REGENERATE_RESPONSE=true \
#     USER_PERMISSIONS_CHAT_RATE_RESPONSE=true \
#     USER_PERMISSIONS_CHAT_EDIT=true \
#     USER_PERMISSIONS_CHAT_SHARE=true \
#     USER_PERMISSIONS_CHAT_EXPORT=true \
#     USER_PERMISSIONS_CHAT_STT=true \
#     USER_PERMISSIONS_CHAT_TTS=true \
#     USER_PERMISSIONS_CHAT_CALL=true \
#     USER_PERMISSIONS_CHAT_MULTIPLE_MODELS=true \
#     USER_PERMISSIONS_CHAT_TEMPORARY=true \
#     USER_PERMISSIONS_CHAT_TEMPORARY_ENFORCED=false \
#     USER_PERMISSIONS_FEATURES_DIRECT_TOOL_SERVERS=true \
#     USER_PERMISSIONS_FEATURES_WEB_SEARCH=true \
#     USER_PERMISSIONS_FEATURES_IMAGE_GENERATION=true \
#     USER_PERMISSIONS_FEATURES_CODE_INTERPRETER=true \
#     USER_PERMISSIONS_FEATURES_NOTES=true \
#     ENABLE_ADMIN_EXPORT=true \
#     ENABLE_ADMIN_WORKSPACE_CONTENT_ACCESS=true \
#     BYPASS_ADMIN_ACCESS_CONTROL=true \
#     ENABLE_ADMIN_CHAT_ACCESS=true \
#     ENABLE_CHANNELS=true \
#     ENABLE_NOTES=true \
#     ENABLE_COMMUNITY_SHARING=true \
#     ENABLE_MESSAGE_RATING=true \
#     ENABLE_USER_WEBHOOKS=true \
#     ENABLE_WEB_SEARCH=true \
#     ENABLE_CODE_EXECUTION=true \
#     ENABLE_CODE_INTERPRETER=true \
#     ENABLE_IMAGE_GENERATION=true \
#     ENABLE_AUTOCOMPLETE_GENERATION=true

#### Other models #########################################################
## whisper TTS model settings ##
ENV WHISPER_MODEL="base" \
    WHISPER_MODEL_DIR="/app/backend/data/cache/whisper/models"

## RAG Embedding model settings ##
ENV RAG_EMBEDDING_MODEL="$USE_EMBEDDING_MODEL_DOCKER" \
    RAG_RERANKING_MODEL="$USE_RERANKING_MODEL_DOCKER" \
    SENTENCE_TRANSFORMERS_HOME="/app/backend/data/cache/embedding/models"

## Tiktoken model settings ##
ENV TIKTOKEN_ENCODING_NAME="cl100k_base" \
    TIKTOKEN_CACHE_DIR="/app/backend/data/cache/tiktoken"

## Hugging Face download cache ##
ENV HF_HOME="/app/backend/data/cache/embedding/models"

#### Other models ##########################################################

WORKDIR /app/backend

ENV HOME=/root
# Create user and group if not root
RUN if [ $UID -ne 0 ]; then \
    if [ $GID -ne 0 ]; then \
    addgroup --gid $GID app; \
    fi; \
    adduser --uid $UID --gid $GID --home $HOME --disabled-password --no-create-home app; \
    fi

RUN mkdir -p $HOME/.cache/chroma
RUN echo -n 00000000-0000-0000-0000-000000000000 > $HOME/.cache/chroma/telemetry_user_id

# Make sure the user has access to the app and root directory
RUN chown -R $UID:$GID /app $HOME

# Install common system dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
    git build-essential pandoc gcc netcat-openbsd curl jq \
    python3-dev \
    ffmpeg libsm6 libxext6 \
    && rm -rf /var/lib/apt/lists/*

# install python dependencies
COPY --chown=$UID:$GID ./backend/requirements.txt ./requirements.txt

RUN pip3 install --no-cache-dir uv && \
    if [ "$USE_SLIM" != "true" ]; then \
    if [ "$USE_CUDA" = "true" ]; then \
    # If you use CUDA the whisper and embedding model will be downloaded on first use
    pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/$USE_CUDA_DOCKER_VER --no-cache-dir && \
    uv pip install --system -r requirements.txt --no-cache-dir && \
    python -c "import os; from sentence_transformers import SentenceTransformer; SentenceTransformer(os.environ['RAG_EMBEDDING_MODEL'], device='cpu')" && \
    python -c "import os; from faster_whisper import WhisperModel; WhisperModel(os.environ['WHISPER_MODEL'], device='cpu', compute_type='int8', download_root=os.environ['WHISPER_MODEL_DIR'])"; \
    python -c "import os; import tiktoken; tiktoken.get_encoding(os.environ['TIKTOKEN_ENCODING_NAME'])"; \
    else \
    pip3 install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu --no-cache-dir && \
    uv pip install --system -r requirements.txt --no-cache-dir && \
    python -c "import os; from sentence_transformers import SentenceTransformer; SentenceTransformer(os.environ['RAG_EMBEDDING_MODEL'], device='cpu')" && \
    python -c "import os; from faster_whisper import WhisperModel; WhisperModel(os.environ['WHISPER_MODEL'], device='cpu', compute_type='int8', download_root=os.environ['WHISPER_MODEL_DIR'])"; \
    python -c "import os; import tiktoken; tiktoken.get_encoding(os.environ['TIKTOKEN_ENCODING_NAME'])"; \
    fi; \
    else \
    uv pip install --system -r requirements.txt --no-cache-dir; \
    fi; \
    mkdir -p /app/backend/data && chown -R $UID:$GID /app/backend/data/

######## Final stage ########
FROM deps AS final

# copy built frontend files
COPY --chown=$UID:$GID --from=frontend-build /app/build /app/build
COPY --chown=$UID:$GID --from=frontend-build /app/CHANGELOG.md /app/CHANGELOG.md
COPY --chown=$UID:$GID --from=frontend-build /app/package.json /app/package.json

# copy backend files
COPY --chown=$UID:$GID ./backend .

# Create a script to load environment variables (fail-safe)
RUN echo '#!/bin/bash\n\
# Load environment variables from .env files (fail-safe)\n\
if [ -f ".env.prod" ]; then\n\
    echo "Loading .env.prod"\n\
    export $(cat .env.prod | grep -v "^#" | xargs) 2>/dev/null || true\n\
elif [ -f ".env" ]; then\n\
    echo "Loading .env"\n\
    export $(cat .env | grep -v "^#" | xargs) 2>/dev/null || true\n\
else\n\
    echo "No environment files found, using defaults"\n\
fi\n\
\n\
# Execute the original command\n\
exec "$@"' > /app/backend/load-env.sh && chmod +x /app/backend/load-env.sh

EXPOSE 8080

HEALTHCHECK CMD curl --silent --fail http://localhost:${PORT:-8080}/health | jq -ne 'input.status == true' || exit 1

# Minimal, atomic permission hardening for OpenShift (arbitrary UID):
# - Group 0 owns /app and /root
# - Directories are group-writable and have SGID so new files inherit GID 0
RUN set -eux; \
    chgrp -R 0 /app /root || true; \
    chmod -R g+rwX /app /root || true; \
    find /app -type d -exec chmod g+s {} + || true; \
    find /root -type d -exec chmod g+s {} + || true

USER $UID:$GID

ARG BUILD_HASH
ENV WEBUI_BUILD_VERSION=${BUILD_HASH}
ENV DOCKER=true

# Use the environment loading script to load .env files before starting
CMD [ "bash", "load-env.sh", "bash", "start.sh"]
