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
GALAXY_PG_PORT="${GALAXY_PG_PORT:-5433}"

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

run_awx_plugins() {
  echo
  echo "🔎 awx-plugins"
  echo "Using repository: $REPO_ROOT/awx-plugins"
  (
    cd "$REPO_ROOT/awx-plugins" &&
    pytest tests/github_app_test.py::test_github_app_invalid_args
  )
}

run_awx_plugins_interfaces() {
  echo
  echo "🔎 awx_plugins.interfaces"
  echo "Using repository: $REPO_ROOT/awx_plugins.interfaces"
  (
    cd "$REPO_ROOT/awx_plugins.interfaces" &&
    pytest tests/smoke_test.py::test_smoke
  )
}

run_runner() {
  echo
  echo "🔎 ansible-runner"
  echo "Using repository: $REPO_ROOT/ansible-runner"
  (
    cd "$REPO_ROOT/ansible-runner" &&
    pytest test/unit/test_utils.py::test_artifact_permissions
  )
}

run_dispatcherd() {
  echo
  echo "🔎 dispatcherd"
  echo "Using repository: $REPO_ROOT/dispatcherd"
  (
    cd "$REPO_ROOT/dispatcherd" &&
    pytest tests/test_noop_broker.py::test_noop_broker_publish_message
  )
}

run_galaxy_ng() {
  echo
  echo "🔎 galaxy_ng"
  echo "Using repository: $REPO_ROOT/galaxy_ng"
  (
    set -euo pipefail
    cd "$REPO_ROOT/galaxy_ng"
    export DJANGO_SETTINGS_MODULE="pulpcore.app.settings"
    export PULP_DATABASES__default__ENGINE="django.db.backends.postgresql"
    export PULP_DATABASES__default__NAME="galaxy_ng"
    export PULP_DATABASES__default__USER="galaxy_ng"
    export PULP_DATABASES__default__PASSWORD="galaxy_ng"
    export PULP_DATABASES__default__HOST="localhost"
    export PULP_DATABASES__default__PORT="$GALAXY_PG_PORT"
    export PULP_DB_ENCRYPTION_KEY="/tmp/database_fields.symmetric.key"
    export PULP_DEPLOY_ROOT="/tmp/pulp"
    export PULP_STATIC_ROOT="/tmp/pulp"
    export PULP_WORKING_DIRECTORY="/tmp/pulp/tmp"
    export PULP_MEDIA_ROOT="/tmp/pulp/media"
    export PULP_FILE_UPLOAD_TEMP_DIR="/tmp/pulp/artifact-tmp"

    compose_file="dev/compose/aap.yaml"
    trap 'docker compose -f "$compose_file" down --remove-orphans' EXIT
    docker compose -f "$compose_file" up --force-recreate -d postgres
    docker compose -f "$compose_file" exec postgres bash -c "while ! pg_isready -U galaxy_ng; do sleep 1; done"

    rm -rf /tmp/pulp
    mkdir -p /tmp/pulp/tmp /tmp/pulp/artifact-tmp /tmp/pulp/media /tmp/pulp/assets
    if [[ ! -f /tmp/database_fields.symmetric.key ]]; then
      openssl rand -base64 32 > /tmp/database_fields.symmetric.key
    fi

    pytest galaxy_ng/tests/unit/test_models.py::TestSetting::test_get_settings_as_dict
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
    run_awx_plugins
    run_awx_plugins_interfaces
    run_runner
    run_dispatcherd
    run_galaxy_ng
    run_gateway
    ;;
  awx )
    run_awx
    ;;
  dab | django-ansible-base )
    run_dab
    ;;
  eda | eda-server )
    run_eda
    ;;
  awx-plugins )
    run_awx_plugins
    ;;
  awx_plugins.interfaces )
    run_awx_plugins_interfaces
    ;;
  ansible-runner )
    run_runner
    ;;
  dispatcherd )
    run_dispatcherd
    ;;
  galaxy_ng )
    run_galaxy_ng
    ;;
  gateway )
    run_gateway
    ;;
  * )
    echo "❌ Unknown check: $CHECK_FILTER"
    echo "   Expected one of: awx, dab, django-ansible-base, eda, eda-server, awx-plugins, awx_plugins.interfaces, ansible-runner, dispatcherd, galaxy_ng, gateway"
    exit 1
    ;;
esac

echo
echo "✅ Canary tests complete"
