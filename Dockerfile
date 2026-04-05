FROM oven/bun:1 AS frontend

ARG VOICEBOX_REF=75abbb02c3bec49f1aebebc9776ef601f38a43bc

WORKDIR /src

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    git \
    && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/jamiepine/voicebox.git /src/voicebox && \
    cd /src/voicebox && \
    git checkout "${VOICEBOX_REF}"

WORKDIR /src/voicebox

RUN sed -i '/"tauri"/d; /"landing"/d' package.json && \
    sed -i -z 's/,\n  ]/\n  ]/' package.json && \
    bun install --no-save && \
    cd web && bunx --bun vite build


FROM python:3.11-slim AS backend-builder

ARG VOICEBOX_REF=75abbb02c3bec49f1aebebc9776ef601f38a43bc

WORKDIR /src

RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    ca-certificates \
    git \
    && rm -rf /var/lib/apt/lists/*

RUN git clone https://github.com/jamiepine/voicebox.git /src/voicebox && \
    cd /src/voicebox && \
    git checkout "${VOICEBOX_REF}"

WORKDIR /src/voicebox/backend

RUN pip install --no-cache-dir --upgrade pip "setuptools<81" wheel && \
    pip install --no-cache-dir \
      torch==2.9.1 \
      torchvision==0.24.1 \
      torchaudio==2.9.1 \
      --index-url https://download.pytorch.org/whl/cu130 && \
    pip install --no-cache-dir -r requirements.txt && \
    pip install --no-cache-dir --no-deps chatterbox-tts hume-tada && \
    pip install --no-cache-dir git+https://github.com/QwenLM/Qwen3-TTS.git


FROM python:3.11-slim

ENV PYTHONUNBUFFERED=1
ENV VOICEBOX_MODELS_DIR=/models

RUN groupadd -r voicebox && \
    useradd -r -g voicebox -m -s /bin/bash voicebox

WORKDIR /app

RUN apt-get update && apt-get install -y --no-install-recommends \
    ca-certificates \
    curl \
    ffmpeg \
    && rm -rf /var/lib/apt/lists/*

COPY --from=backend-builder /usr/local /usr/local
COPY --from=backend-builder --chown=voicebox:voicebox /src/voicebox/backend /app/backend
COPY --from=frontend --chown=voicebox:voicebox /src/voicebox/web/dist /app/frontend

RUN mkdir -p /data /models && \
    chown -R voicebox:voicebox /app /data /models

USER voicebox

EXPOSE 17493

HEALTHCHECK --interval=30s --timeout=10s --retries=3 --start-period=60s \
    CMD curl -f http://localhost:17493/health || exit 1

CMD ["python", "-m", "backend.main", "--host", "0.0.0.0", "--port", "17493", "--data-dir", "/data"]
