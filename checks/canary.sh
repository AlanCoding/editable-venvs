#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/repos}"
AWX_REPO_NAME="${AWX_REPO_NAME:-tower}"  # Default to tower, can override with awx
CHECK_FILTER="${1:-}"  # Optional arg: awx, dab, eda, gateway

# Configurable ports for CI/local compatibility
# These can be overridden via environment variables (e.g., in GitHub Actions)
EDA_PG_PORT="${EDA_PG_PORT:-5432}"
EDA_REDIS_PORT="${EDA_REDIS_PORT:-6379}"
GATEWAY_REDIS_PORT="${GATEWAY_REDIS_PORT:-6379}"

echo "🐤 Running canary tests..."

run_awx() {
  echo
  echo "🔎 AWX"
  echo "Using repository: $REPO_ROOT/$AWX_REPO_NAME"
  (cd "$REPO_ROOT/$AWX_REPO_NAME" && AWX_LOGGING_MODE=stdout pytest awx/main/tests/functional/test_instances.py --create-db --disable-warnings -W ignore::DeprecationWarning)
}

run_dab() {
  echo
  echo "🔎 django-ansible-base"
  echo "Using repository: $REPO_ROOT/django-ansible-base"
  (cd "$REPO_ROOT/django-ansible-base" && make postgres && pytest test_app/tests/rbac/models/test_uniqueness.py)
}

run_eda() {
  echo
  echo "🔎 eda-server"
  echo "Using repository: $REPO_ROOT/eda-server"
  (
    cd "$REPO_ROOT/eda-server" &&
    # Use configurable ports (defaults to standard ports, can be overridden in CI)
    export EDA_PG_PORT="$EDA_PG_PORT"
    export EDA_REDIS_PORT="$EDA_REDIS_PORT"
    
    # Ensure cleanup on exit
    trap 'docker-compose -p eda -f tools/docker/docker-compose-dev.yaml down --remove-orphans' EXIT
    
    docker-compose -p eda -f tools/docker/docker-compose-dev.yaml up --detach postgres redis &&
    # Update database connection to use the configured ports
    EDA_DB_HOST=localhost EDA_DB_PORT="$EDA_PG_PORT" EDA_MQ_HOST=localhost EDA_MQ_PORT="$EDA_REDIS_PORT" \
    DJANGO_SETTINGS_MODULE=aap_eda.settings.default EDA_SECRET_KEY=insecure EDA_DB_PASSWORD=secret \
      pytest tests/integration/api/test_eda_credential.py
  )
}

run_gateway() {
    echo
    echo "🔎 aap-gateway"
    echo "Using repository: $REPO_ROOT/aap-gateway"
    (
        cd "$REPO_ROOT/aap-gateway" &&
        # Use configurable Redis port (defaults to standard port, can be overridden in CI)
        export REDIS_PORT="$GATEWAY_REDIS_PORT"
        
        # Ensure cleanup on exit
        trap 'docker compose -f tools/generated/docker-compose.yml down --remove-orphans' EXIT
        
        docker compose -f tools/generated/docker-compose.yml up -d db redis1 &&
        DATABASE_NAME=gateway DATABASE_USER=gateway DATABASE_PASSWORD=gateway DATABASE_HOST=localhost DATABASE_PORT=5440 \
        REDIS_URL=redis://localhost:$GATEWAY_REDIS_PORT REDIS_HOSTS=localhost:$GATEWAY_REDIS_PORT REDIS_MODE=standalone \
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
