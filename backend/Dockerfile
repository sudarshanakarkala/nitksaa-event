# NITKSAA Event API image for Google Cloud Run.
#
# Build context is this directory (backend/): Cloud Run's Dockerfile build type
# with source location /backend/Dockerfile uses the Dockerfile's directory.
#
# Nothing environment-specific belongs here. APP_ENV, database URLs, Razorpay
# and SMTP credentials are set on the Cloud Run service (env vars / Secret
# Manager). Firebase Admin uses Application Default Credentials, i.e. the
# Cloud Run service account, so no key file is baked in.

FROM python:3.11-slim

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_ROOT_USER_ACTION=ignore

WORKDIR /app

RUN useradd --create-home --uid 10001 appuser

# Dependencies first so this layer stays cached across code-only changes.
COPY requirements.txt .
RUN pip install -r requirements.txt

# Only the application package is needed at runtime. Migrations are applied
# out-of-band and are never read by the running app.
COPY app ./app

USER appuser

# Cloud Run injects PORT (8080 by default); fall back to 8080 elsewhere.
EXPOSE 8080

# exec makes uvicorn PID 1 so it receives Cloud Run's SIGTERM directly.
CMD ["sh", "-c", "exec python -m uvicorn app.main:app --host 0.0.0.0 --port ${PORT:-8080}"]
