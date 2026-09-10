FROM python:3.12-slim
WORKDIR /app
COPY requirements-dev.txt .
RUN pip install --no-cache-dir -r requirements-dev.txt && useradd --uid 10001 --create-home api && mkdir -p /data/attachments && chown -R 10001:10001 /data
COPY . .
USER 10001
EXPOSE 8090
CMD ["sh", "-c", "alembic upgrade head && exec uvicorn app.main:app --host 0.0.0.0 --port 8090 --no-proxy-headers"]
