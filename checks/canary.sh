#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/repos}"
CHECK_FILTER="${1:-}"  # Optional arg: awx, dab, eda

echo "🐤 Running canary tests..."

run_awx() {
  echo
  echo "🔎 AWX"
  (cd "$REPO_ROOT/awx" && pytest awx/main/tests/functional/test_instances.py)
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
    docker-compose -p eda \
      -f tools/docker/docker-compose-dev.yaml \
      up --detach postgres redis &&
    DJANGO_SETTINGS_MODULE=aap_eda.settings.default EDA_SECRET_KEY=insecure EDA_DB_PASSWORD=secret \
      pytest tests/integration/api/test_eda_credential.py
  )
}

case "$CHECK_FILTER" in
  "" )
    run_awx
    run_dab
    run_eda
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
  * )
    echo "❌ Unknown check: $CHECK_FILTER"
    echo "   Expected one of: awx, dab, eda"
    exit 1
    ;;
esac

echo
echo "✅ Canary tests complete"
