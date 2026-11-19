FROM python:3.13-slim
ENV PYTHONUNBUFFERED=1 PYTHONDONTWRITEBYTECODE=1 WORKERS=1 LOG_LEVEL=info DEFAULT_TIME_BUDGET_MS=10000 LARGE_SCENARIO_TIME_BUDGET_MS=2000 DECOMPOSE_THRESHOLD=250
WORKDIR /app
RUN apt-get update && apt-get install -y --no-install-recommends libgomp1 && rm -rf /var/lib/apt/lists/* \
    && groupadd -g 10001 engine && useradd -m -u 10001 -g engine engine
COPY requirements.txt /tmp/requirements.txt
RUN python -m pip install --no-cache-dir -r /tmp/requirements.txt
COPY . /app/ai_engine/
RUN mkdir -p /app/ai_engine/models && chown engine:engine /app/ai_engine/models
USER 10001:10001
VOLUME ["/app/ai_engine/models"]
EXPOSE 8001
HEALTHCHECK --interval=30s --timeout=5s --start-period=30s CMD python -c "from urllib.request import urlopen; urlopen('http://127.0.0.1:8001/health', timeout=4).close()"
CMD ["sh","-c","exec python -m uvicorn ai_engine.main:app --host 0.0.0.0 --port 8001 --workers \"$WORKERS\" --log-level \"$LOG_LEVEL\""]
