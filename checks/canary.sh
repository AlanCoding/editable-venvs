#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/repos}"

echo "🐤 Running canary tests..."

echo
echo "🔎 AWX"
(cd "$REPO_ROOT/awx" && pytest awx/main/tests/functional/test_instances.py)

echo
echo "🔎 django-ansible-base"
(cd "$REPO_ROOT/django-ansible-base" && pytest test_app/tests/rbac/models/test_uniqueness.py)

# Add more below as needed

echo "✅ Canary tests complete"
