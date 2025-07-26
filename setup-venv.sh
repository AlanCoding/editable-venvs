#!/usr/bin/env bash
set -euo pipefail

VENV_NAME="${1:?Usage: $0 <venv-name>}"
PYTHON="${PYTHON_BIN:-/usr/bin/python}"
VENV_DIR="$HOME/venvs/$VENV_NAME"
PROJECTS_FILE="${2:-projects.txt}"
REPO_ROOT="${REPO_ROOT:-$HOME/repos}"

echo "Deleting venv at: $VENV_DIR"
rm -rf "$VENV_DIR"
echo "📦 Creating clean venv at: $VENV_DIR"
"$PYTHON" -m venv --system-site-packages=false --clear "$VENV_DIR"

echo "🐍 Activating venv"
source "$VENV_DIR/bin/activate"

if ! command -v pip >/dev/null; then
  echo "📥 Bootstrapping pip..."
  curl -sS https://bootstrap.pypa.io/get-pip.py | python
fi

echo "📚 Installing editable projects from: $PROJECTS_FILE"
INSTALL_ARGS=()
while IFS= read -r project; do
  [[ -z "$project" || "$project" =~ ^# ]] && continue
  path="$REPO_ROOT/$project"
  if [[ ! -d "$path" ]]; then
    echo "❌ Missing directory: $path"
    exit 1
  fi
  echo "✔ Queued for editable install: $path"
  INSTALL_ARGS+=("-e" "$path")
done < "$PROJECTS_FILE"

echo "🚀 Installing with pip..."
pip install "${INSTALL_ARGS[@]}"

echo
echo "✅ Done. To activate:"
echo "   source $VENV_DIR/bin/activate"
