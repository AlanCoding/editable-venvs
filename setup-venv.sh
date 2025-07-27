#!/usr/bin/env bash
set -euo pipefail

VENV_NAME="${1:?Usage: $0 <venv-name>}"
PYTHON="${PYTHON_BIN:-/usr/bin/python}"
VENV_DIR="$HOME/venvs/$VENV_NAME"

REPO_ROOT="${REPO_ROOT:-$HOME/repos}"
PROJECTS_FILE="projects.txt"
EXCLUDE_FILE="${EXCLUDE_FILE:-exclude.txt}"
EXTRA_REQS_FILE="${EXTRA_REQS_FILE:-extra.txt}"
SANITIZED_DIR="${SANITIZED_DIR:-sanitized}"

mkdir -p "$SANITIZED_DIR"

echo "📦 Creating clean venv at: $VENV_DIR"
rm -rf "$VENV_DIR"
"$PYTHON" -m venv --clear "$VENV_DIR"

echo "🐍 Activating venv"
source "$VENV_DIR/bin/activate"

if ! command -v pip >/dev/null; then
  echo "📥 Bootstrapping pip..."
  curl -sS https://bootstrap.pypa.io/get-pip.py | python
fi

# Load exclusions
if [[ ! -f "$EXCLUDE_FILE" ]]; then
  echo "❌ Exclude list file '$EXCLUDE_FILE' not found"
  exit 1
fi
mapfile -t EXCLUDES < "$EXCLUDE_FILE"

# Step 0: Install extra requirements from extra.txt
if [[ ! -f "$EXTRA_REQS_FILE" ]]; then
  echo "❌ Extra requirements file '$EXTRA_REQS_FILE' not found"
  exit 1
fi

echo
echo "📥 Pass 0: Installing sanitized requirements from extra.txt"
while IFS= read -r rel_path; do
  [[ -z "$rel_path" || "$rel_path" =~ ^# ]] && continue

  full_path="$REPO_ROOT/$rel_path"
  project_name=$(basename "$(dirname "$rel_path")")

  if [[ ! -f "$full_path" ]]; then
    echo "⚠️  Skipping — requirements file not found: $full_path"
    continue
  fi

  sanitized_file="$SANITIZED_DIR/${project_name}.txt"
  echo "🔎 Sanitizing: $rel_path → $sanitized_file"

  exclude_regex="^($(printf '%s\n' "${EXCLUDES[@]}" | paste -sd '|' -))"
  grep -v -i -E "$exclude_regex" "$full_path" > "$sanitized_file"

  echo "📦 Installing sanitized requirements for $project_name"
  pip install -r "$sanitized_file"
done < "$EXTRA_REQS_FILE"

# Load projects
if [[ ! -f "$PROJECTS_FILE" ]]; then
  echo "❌ Projects file '$PROJECTS_FILE' not found"
  exit 1
fi

PROJECT_PATHS=()
while IFS= read -r project; do
  [[ -z "$project" || "$project" =~ ^# ]] && continue
  path="$REPO_ROOT/$project"
  if [[ ! -d "$path" ]]; then
    echo "❌ Missing project directory: $path"
    exit 1
  fi
  PROJECT_PATHS+=("$path")
done < "$PROJECTS_FILE"

# Step 1: Non-editable pre-install to satisfy dependencies
echo
echo "🚧 Pass 1: Pre-install all projects (non-editable, no-deps)"
for path in "${PROJECT_PATHS[@]}"; do
  echo "📄 Installing (no-deps): $path"
  pip install --no-deps "$path"
done

# Step 2: Editable install of all projects
echo
echo "🛠 Pass 2: Re-install all projects in editable mode"
for path in "${PROJECT_PATHS[@]}"; do
  echo "🔁 Reinstalling as editable: $path"
  pip install -e "$path"
done

echo
echo "✅ Done. To activate your environment:"
echo "   source $VENV_DIR/bin/activate"
