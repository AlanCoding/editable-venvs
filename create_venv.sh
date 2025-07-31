#!/usr/bin/env bash

set -euo pipefail

VENV_NAME="$1"
REPO_ROOT="${REPO_ROOT:-$HOME/repos}"
VENV_DIR="$HOME/venvs/$VENV_NAME"
POETRY_VENV_DIR="$HOME/venvs/poetry"
CONFIG_DIR="${CONFIG_DIR:-config}"
PROJECTS_FILE="$CONFIG_DIR/editable_projects.txt"
POETRY_PROJECTS_FILE="$CONFIG_DIR/poetry_projects.txt"
EXTRA_REQUIREMENTS_FILE="$CONFIG_DIR/requirement_files.txt"
EXCLUDE_FILE="$CONFIG_DIR/exclude_for_files.txt"
CONSTRAINTS_FILE="$CONFIG_DIR/constraints_for_editable.txt"
SANITIZED_DIR="sanitized"
PYTHON="${PYTHON:-python3}"

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
  echo "Phase 1: Deleting existing venv at: $VENV_DIR"
  rm -rf "$VENV_DIR"
  echo "  deleting contents of sanitized/ folder"
  rm -rf sanitized/*
fi

# Setup poetry venv if it doesn't exist
if [[ ! -d "$POETRY_VENV_DIR" ]]; then
  echo "Phase 1: Creating poetry venv at: $POETRY_VENV_DIR"
  $PYTHON -m venv "$POETRY_VENV_DIR" --clear
  source "$POETRY_VENV_DIR/bin/activate"
  python -m ensurepip --upgrade
  pip install --quiet poetry
  poetry self remove poetry-plugin-export
  poetry self add poetry-plugin-export
  deactivate
fi

echo
echo "Phase 1: Creating clean venv at: $VENV_DIR"
$PYTHON -m venv "$VENV_DIR" --clear
source "$VENV_DIR/bin/activate"
python -m ensurepip --upgrade
# Verify pip is correct
VENV_BIN_DIR=$(dirname "$(which python)")
EXPECTED_PIP="$VENV_BIN_DIR/pip"
ACTUAL_PIP=$(which pip)
if [[ "$ACTUAL_PIP" != "$EXPECTED_PIP" ]]; then
  echo "pip is not from venv! Got: $ACTUAL_PIP"
  exit 1
fi

echo
echo "Phase 2: Parsing $PROJECTS_FILE (with optional extras)"
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

# Phase 2.5: Export poetry projects to requirements files
if [[ -f "$POETRY_PROJECTS_FILE" ]]; then
  echo
  echo "Phase 2.5: Exporting poetry projects to requirements files"
  while IFS= read -r poetry_project; do
    [[ -z "$poetry_project" || "$poetry_project" =~ ^# ]] && continue
    poetry_project_path="$REPO_ROOT/$poetry_project"
    if [[ ! -d "$poetry_project_path" ]]; then
      echo "Skipping missing poetry project: $poetry_project_path"
      continue
    fi
    if [[ ! -f "$poetry_project_path/pyproject.toml" ]]; then
      echo "Skipping $poetry_project_path - no pyproject.toml found"
      continue
    fi

    sanitized_poetry_req="$SANITIZED_DIR/$(basename "$poetry_project").txt"
    echo "Exporting poetry project $poetry_project to: $sanitized_poetry_req"
    "$POETRY_VENV_DIR/bin/poetry" export --without-hashes -f requirements.txt -o "$(pwd)/$sanitized_poetry_req" -C "$poetry_project_path"
  done < "$POETRY_PROJECTS_FILE"
fi

echo
echo "Phase 3: Installing requirement files (sanitized)"

# First, sanitize traditional requirements files
while IFS= read -r extra_file; do
  [[ -z "$extra_file" || "$extra_file" =~ ^# ]] && continue
  full_req_path="$REPO_ROOT/$extra_file"
  if [[ ! -f "$full_req_path" ]]; then
    echo "Skipping missing requirements file: $full_req_path"
    continue
  fi
  sanitized_req="$SANITIZED_DIR/$(echo "$extra_file" | tr '/' '__')"
  echo "Sanitizing requirements file: $full_req_path -> $sanitized_req"
  grep -vFf "$EXCLUDE_FILE" "$full_req_path" > "$sanitized_req"
done < "$EXTRA_REQUIREMENTS_FILE"

# Then install all sanitized requirements files (includes both traditional and poetry-exported)
for req_file in "$SANITIZED_DIR"/*; do
  if [[ -f "$req_file" ]]; then
    echo "Installing requirements: $req_file"
    "${PIP_INSTALL_CMD[@]}" -r "$req_file"
  fi
done

echo
echo "Phase 4: Installing all projects in editable mode"
for path in "${PROJECT_PATHS[@]}"; do
  if [[ -n "${EXTRAS_MAP[$path]+x}" ]]; then
    extras="${EXTRAS_MAP[$path]}"
    echo "Installing as editable with extras [$extras]: $path"
    "${PIP_INSTALL_CMD[@]}" -e "$path[$extras]" -c "$CONSTRAINTS_FILE"
  else
    echo "Installing as editable: $path"
    "${PIP_INSTALL_CMD[@]}" -e "$path" -c "$CONSTRAINTS_FILE"
  fi
done

echo "Venv setup complete: $VENV_DIR"
echo "Run this to activate it:"
echo "source $VENV_DIR/bin/activate"
