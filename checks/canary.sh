#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/repos}"
AWX_REPO_NAME="${AWX_REPO_NAME:-tower}"  # Default to tower, can override with awx
CHECK_FILTER="${1:-}"  # Optional arg: awx, dab, eda, galaxy_ng

# Configurable ports for CI/local compatibility
# These can be overridden via environment variables (e.g., in GitHub Actions)
EDA_PG_PORT="${EDA_PG_PORT:-5432}"
EDA_REDIS_PORT="${EDA_REDIS_PORT:-6379}"
GALAXY_PG_PORT="${GALAXY_PG_PORT:-5433}"

compose() {
  if command -v docker >/dev/null 2>&1 && docker compose version >/dev/null 2>&1; then
    docker compose "$@"
    return
  fi

  if command -v docker-compose >/dev/null 2>&1; then
    docker-compose "$@"
    return
  fi

  echo "❌ docker compose/docker-compose is required but not installed" >&2
  return 1
}

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
    trap 'compose -p eda -f tools/docker/docker-compose-dev.yaml down --remove-orphans' EXIT

    compose -p eda -f tools/docker/docker-compose-dev.yaml up --detach postgres redis &&
    # Update database connection to use the configured ports
    EDA_DB_HOST=localhost EDA_DB_PORT="$EDA_PG_PORT" EDA_MQ_HOST=localhost EDA_MQ_PORT="$EDA_REDIS_PORT" \
      DJANGO_SETTINGS_MODULE=aap_eda.settings.default EDA_SECRET_KEY=insecure EDA_DB_PASSWORD=secret \
      pytest tests/integration/api/test_eda_credential.py
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

    if ! command -v docker >/dev/null 2>&1; then
      echo "❌ docker is required to run the galaxy_ng check" >&2
      exit 1
    fi

    compose -p galaxy_ng -f dev/compose/aap.yaml down --remove-orphans --volumes >/dev/null 2>&1 || true

    compose_args=(-p galaxy_ng -f dev/compose/aap.yaml)
    override_file=""

    if [[ -n "${GALAXY_PG_PORT:-}" ]]; then
      override_file="$(mktemp)"
      printf 'services:\n  postgres:\n    ports:\n      - "%s:5432"\n' "$GALAXY_PG_PORT" >"$override_file"
      compose_args+=(-f "$override_file")
    fi

    cleanup() {
      compose "${compose_args[@]}" down --remove-orphans --volumes >/dev/null 2>&1 || true
      if [[ -n "$override_file" && -f "$override_file" ]]; then
        rm -f "$override_file"
      fi
    }

    trap cleanup EXIT

    compose "${compose_args[@]}" up --force-recreate -d postgres >/dev/null
    compose "${compose_args[@]}" exec postgres bash -c 'while ! pg_isready -U galaxy_ng; do sleep 1; done'
    sleep 10

    rm -rf /tmp/pulp
    mkdir -p /tmp/pulp/tmp /tmp/pulp/artifact-tmp /tmp/pulp/media /tmp/pulp/assets
    if [[ ! -f /tmp/database_fields.symmetric.key ]]; then
      openssl rand -base64 32 > /tmp/database_fields.symmetric.key
    fi

    pytest galaxy_ng/tests/unit/test_models.py::TestSetting::test_get_settings_as_dict
  )
}

case "$CHECK_FILTER" in
  "" )
    run_awx
    run_dab
    run_eda
    run_galaxy_ng
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
  galaxy_ng )
    run_galaxy_ng
    ;;
  * )
    echo "❌ Unknown check: $CHECK_FILTER"
    echo "   Expected one of: awx, dab, django-ansible-base, eda, eda-server, galaxy_ng"
    exit 1
    ;;
esac

echo
echo "✅ Canary tests complete"
