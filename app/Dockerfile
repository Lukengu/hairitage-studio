###########
# BUILDER #
###########

FROM python:3.11.4-slim-bookworm as builder

WORKDIR /usr/src/app

ENV PYTHONDONTWRITEBYTECODE=1
ENV PYTHONUNBUFFERED=1
ENV PIP_DEFAULT_TIMEOUT=300
ENV PIP_RETRIES=10

# Install build dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends \
        build-essential \
        gcc \
        libffi-dev \
        libssl-dev \
        python3-dev \
        curl \
    && rm -rf /var/lib/apt/lists/*

# Upgrade pip and install lint/format tools
RUN pip install --upgrade pip && \
    pip install --no-cache-dir black isort flake8 autopep8


# Copy project files for linting
COPY . /usr/src/app/

# Run auto-formatters
RUN isort .
RUN black .
RUN autopep8 --in-place --recursive .

RUN flake8 --ignore=E501,F401,E241,W292,F811 .

# Copy requirements and build wheels (long timeout for slow PyPI downloads)
COPY ./requirements.txt .
RUN pip wheel --no-cache-dir --no-deps --wheel-dir /usr/src/app/wheels -r requirements.txt

#########
# FINAL #
#########

FROM python:3.11.4-slim-bookworm

WORKDIR /home/app/web

ENV HOME=/home/app
ENV APP_HOME=/home/app/web
ENV PIP_DEFAULT_TIMEOUT=300
ENV PIP_RETRIES=10

# Create app user
RUN addgroup --system app && adduser --system --group app

# Install runtime dependencies
RUN apt-get update && \
    apt-get install -y --no-install-recommends netcat-openbsd && \
    rm -rf /var/lib/apt/lists/*

# Copy wheels and install Python dependencies
COPY --from=builder /usr/src/app/wheels /wheels
COPY --from=builder /usr/src/app/requirements.txt .
RUN pip install --upgrade pip && pip install --no-cache /wheels/*

# Copy project
COPY . $APP_HOME

# Set permissions
RUN chown -R app:app $APP_HOME

# Switch to app user
USER app

# Entrypoint (replace with your script)
ENTRYPOINT ["/home/app/web/entrypoint.sh"]
