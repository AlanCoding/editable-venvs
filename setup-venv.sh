#!/usr/bin/env bash
set -euo pipefail

VENV_NAME="${1:?Usage: $0 <venv-name>}"
PYTHON="${PYTHON_BIN:-/usr/bin/python}"
VENV_DIR="$HOME/venvs/$VENV_NAME"
PROJECTS_FILE="projects.txt"
REPO_ROOT="${REPO_ROOT:-$HOME/repos}"

echo "📦 Creating clean venv at: $VENV_DIR"
rm -rf "$VENV_DIR"
"$PYTHON" -m venv --clear "$VENV_DIR"

echo "🐍 Activating venv"
source "$VENV_DIR/bin/activate"

if ! command -v pip >/dev/null; then
  echo "📥 Bootstrapping pip..."
  curl -sS https://bootstrap.pypa.io/get-pip.py | python
fi

if [[ ! -f "$PROJECTS_FILE" ]]; then
  echo "❌ Projects file '$PROJECTS_FILE' not found"
  exit 1
fi

# Collect valid project paths
PROJECT_PATHS=()
while IFS= read -r project; do
  [[ -z "$project" || "$project" =~ ^# ]] && continue
  path="$REPO_ROOT/$project"
  if [[ ! -d "$path" ]]; then
    echo "❌ Missing directory: $path"
    exit 1
  fi
  PROJECT_PATHS+=("$path")
done < "$PROJECTS_FILE"

echo
echo "🚧 Pass 1: Pre-install all projects (non-editable, no-deps)"
for path in "${PROJECT_PATHS[@]}"; do
  echo "📄 Installing: $path"
  pip install --no-deps -c constraints.txt "$path"
done

echo
echo "🛠 Pass 2: Re-install all projects in editable mode"
for path in "${PROJECT_PATHS[@]}"; do
  echo "🔁 Reinstalling as editable: $path"
  pip install -e "$path"
done

echo
echo "✅ Done. To activate your environment:"
echo "   source $VENV_DIR/bin/activate"
