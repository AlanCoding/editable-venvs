#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/repos}"
AWX_REPO_NAME="${AWX_REPO_NAME:-tower}"  # Default to tower, can override with awx
CHECK_FILTER="${1:-}"  # Optional arg: awx, dab, eda, gateway

echo "🐤 Running canary tests..."
echo "Using AWX repo: $REPO_ROOT/$AWX_REPO_NAME"

run_awx() {
  echo
  echo "🔎 AWX"
  (cd "$REPO_ROOT/$AWX_REPO_NAME" && AWX_LOGGING_MODE=stdout pytest awx/main/tests/functional/test_instances.py --create-db --disable-warnings -W ignore::DeprecationWarning)
}

run_dab() {
  echo
  echo "🔎 django-ansible-base"
  (cd "$REPO_ROOT/django-ansible-base" && make postgres && pytest test_app/tests/rbac/models/test_uniqueness.py)
}

run_eda() {
  echo
  echo "🔎 eda-server"
  (
    cd "$REPO_ROOT/eda-server" &&
    docker-compose -p eda -f tools/docker/docker-compose-dev.yaml up --detach postgres redis &&
    DJANGO_SETTINGS_MODULE=aap_eda.settings.default EDA_SECRET_KEY=insecure EDA_DB_PASSWORD=secret \
      pytest tests/integration/api/test_eda_credential.py
  )
}

run_gateway() {
    echo
    echo "🔎 aap-gateway"
    (
        cd "$REPO_ROOT/aap-gateway" &&
        docker compose -f tools/generated/docker-compose.yml up -d db redis1 &&
        DATABASE_NAME=gateway DATABASE_USER=gateway DATABASE_PASSWORD=gateway DATABASE_HOST=localhost DATABASE_PORT=5440 \
        REDIS_URL=redis://localhost:6379 REDIS_HOSTS=localhost:6379 REDIS_MODE=standalone \
        GATEWAY_SECRET_KEY_FILE=tools/configs/dev_secret_key DJANGO_SETTINGS_MODULE=aap_gateway_api.settings \
        pytest aap_gateway_api/tests/views/api/test_api_root.py
    )
}

case "$CHECK_FILTER" in
  "" )
    run_awx
    run_dab
    run_eda
    run_gateway
    ;;
  awx )
    run_awx
    ;;
  dab )
    run_dab
    ;;
  eda )
    run_eda
    ;;
  gateway )
    run_gateway
    ;;
  * )
    echo "❌ Unknown check: $CHECK_FILTER"
    echo "   Expected one of: awx, dab, eda, gateway"
    exit 1
    ;;
esac

echo
echo "✅ Canary tests complete"
