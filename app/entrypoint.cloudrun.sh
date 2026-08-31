#!/bin/sh
set -e

echo "==> Cloud Run startup (PORT=${PORT:-8080})"

if [ -z "${SECRET_KEY:-}" ]; then
    echo "ERROR: SECRET_KEY is not set"
    exit 1
fi

echo "==> Running database migrations"
attempt=1
until python manage.py migrate --noinput; do
    if [ "$attempt" -ge 15 ]; then
        echo "ERROR: migrations failed after ${attempt} attempts"
        exit 1
    fi
    echo "Migration attempt ${attempt} failed, retrying in 3s..."
    attempt=$((attempt + 1))
    sleep 3
done

if [ "$COLLECT_STATIC" = "1" ]; then
    echo "==> Collecting static files"
    python manage.py collectstatic --noinput
fi

echo "==> Starting Gunicorn"
exec gunicorn hairitage.wsgi:application \
    --bind "0.0.0.0:${PORT:-8080}" \
    --workers "${GUNICORN_WORKERS:-1}" \
    --threads "${GUNICORN_THREADS:-4}" \
    --timeout "${GUNICORN_TIMEOUT:-120}"
