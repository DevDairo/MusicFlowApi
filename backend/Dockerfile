# syntax=docker/dockerfile:1.7

ARG PYTHON_IMAGE=python:3.14.6-slim-bookworm

FROM ${PYTHON_IMAGE} AS runtime-base

ENV PYTHONDONTWRITEBYTECODE=1 \
    PYTHONUNBUFFERED=1 \
    PIP_DISABLE_PIP_VERSION_CHECK=1 \
    PIP_NO_CACHE_DIR=1 \
    PIP_ROOT_USER_ACTION=ignore \
    PYTHONPATH=/app/src

RUN groupadd --gid 10001 musicflow \
    && useradd --uid 10001 --gid musicflow --no-create-home \
        --home-dir /nonexistent --shell /usr/sbin/nologin musicflow

WORKDIR /app

COPY requirements/runtime.lock.txt /tmp/requirements/runtime.lock.txt
RUN python -m pip install --no-deps --requirement /tmp/requirements/runtime.lock.txt

COPY src /app/src

FROM runtime-base AS api

USER 10001:10001
EXPOSE 8000

CMD ["uvicorn", "musicflow.api.main:app", "--host", "0.0.0.0", "--port", "8000", "--no-access-log"]

FROM runtime-base AS worker

USER 10001:10001

CMD ["python", "-m", "musicflow.worker.main"]

FROM runtime-base AS migrations

COPY alembic.ini /app/alembic.ini
COPY migrations /app/migrations

USER 10001:10001

CMD ["alembic", "-c", "/app/alembic.ini", "upgrade", "head"]

FROM runtime-base AS tests

USER root
COPY requirements/dev.lock.txt /tmp/requirements/dev.lock.txt
RUN python -m pip install --no-deps --requirement /tmp/requirements/dev.lock.txt

COPY pyproject.toml /app/pyproject.toml
COPY alembic.ini /app/alembic.ini
COPY migrations /app/migrations
COPY tests /app/tests

USER 10001:10001

CMD ["pytest", "-q"]
