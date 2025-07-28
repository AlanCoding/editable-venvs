#!/usr/bin/env bash

set -euo pipefail

VENV_NAME="$1"
REPO_ROOT="${REPO_ROOT:-$HOME/repos}"
VENV_DIR="$HOME/venvs/$VENV_NAME"
PROJECTS_FILE="projects.txt"
EXTRA_REQUIREMENTS_FILE="extra.txt"
EXCLUDE_FILE="exclude.txt"
SANITIZED_DIR="sanitized"
PYTHON="/usr/bin/python"

# Set verbosity control (export PIP_QUIET=1 to enable)
PIP_QUIET="${PIP_QUIET:-1}"
PIP_INSTALL_CMD=(pip install)
if [[ "$PIP_QUIET" == "1" ]]; then
  PIP_INSTALL_CMD+=(--quiet --disable-pip-version-check)
fi

mkdir -p "$SANITIZED_DIR"

[[ -f "$PROJECTS_FILE" ]] || { echo "❌ Missing $PROJECTS_FILE"; exit 1; }
[[ -f "$EXCLUDE_FILE" ]] || { echo "❌ Missing $EXCLUDE_FILE"; exit 1; }
[[ -f "$EXTRA_REQUIREMENTS_FILE" ]] || { echo "❌ Missing $EXTRA_REQUIREMENTS_FILE"; exit 1; }

if [[ -d "$VENV_DIR" ]]; then
  echo "🧹 Deleting venv at: $VENV_DIR"
  rm -rf "$VENV_DIR"
fi

echo "📦 Creating clean venv at: $VENV_DIR"
$PYTHON -m venv "$VENV_DIR" --clear
source "$VENV_DIR/bin/activate"
python -m ensurepip --upgrade
# Verify pip is correct
VENV_BIN_DIR=$(dirname "$(which python)")
EXPECTED_PIP="$VENV_BIN_DIR/pip"
ACTUAL_PIP=$(which pip)
if [[ "$ACTUAL_PIP" != "$EXPECTED_PIP" ]]; then
  echo "🚨 pip is not from venv! Got: $ACTUAL_PIP"
  exit 1
fi

echo "📚 Parsing projects.txt (with optional extras)"
PROJECT_PATHS=()
declare -A EXTRAS_MAP

while IFS= read -r line; do
  [[ -z "$line" || "$line" =~ ^# ]] && continue
  path_part="${line%%:*}"
  extras_part="${line#*:}"
  full_path="$REPO_ROOT/$path_part"
  [[ -d "$full_path" ]] || { echo "❌ Missing project directory: $full_path"; exit 1; }
  PROJECT_PATHS+=("$full_path")
  if [[ "$extras_part" != "$path_part" ]]; then
    EXTRAS_MAP["$full_path"]="$extras_part"
  fi
done < "$PROJECTS_FILE"

echo "📄 Installing extra requirements from sanitized files"
while IFS= read -r extra_file; do
  [[ -z "$extra_file" || "$extra_file" =~ ^# ]] && continue
  full_req_path="$REPO_ROOT/$extra_file"
  if [[ ! -f "$full_req_path" ]]; then
    echo "⚠️  Skipping missing extra requirements: $full_req_path"
    continue
  fi
  sanitized_req="$SANITIZED_DIR/$(basename "$extra_file")"
  grep -vFf "$EXCLUDE_FILE" "$full_req_path" > "$sanitized_req"
  echo "📄 Installing sanitized requirements: $sanitized_req"
  "${PIP_INSTALL_CMD[@]}" -r "$sanitized_req"
done < "$EXTRA_REQUIREMENTS_FILE"

echo "🔄 Pass 1: Install all projects to resolve dependencies"
for path in "${PROJECT_PATHS[@]}"; do
  echo "➡️ Installing (non-editable): $path"
  "${PIP_INSTALL_CMD[@]}" "$path"
done

echo "🛠 Pass 2: Re-install all projects in editable mode"
for path in "${PROJECT_PATHS[@]}"; do
  if [[ -n "${EXTRAS_MAP[$path]+x}" ]]; then
    extras="${EXTRAS_MAP[$path]}"
    echo "🔁 Reinstalling as editable with extras [$extras]: $path"
    "${PIP_INSTALL_CMD[@]}" -e "$path[$extras]"
  else
    echo "🔁 Reinstalling as editable: $path"
    "${PIP_INSTALL_CMD[@]}" -e "$path"
  fi
done

echo "✅ Venv setup complete: $VENV_DIR"
echo "👉 Run this to activate it:"
echo "source \"$VENV_DIR/bin/activate\""
