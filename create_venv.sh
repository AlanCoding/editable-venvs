#!/usr/bin/env bash

set -euo pipefail

VENV_NAME="$1"
REPO_ROOT="${REPO_ROOT:-$HOME/repos}"
VENV_DIR="$HOME/venvs/$VENV_NAME"
BUILD_VENV_DIR="$HOME/venvs/build"
CONFIG_DIR="${CONFIG_DIR:-config}"
PROJECTS_FILE="$CONFIG_DIR/editable_projects.txt"
NO_DEPS_PROJECTS_FILE="$CONFIG_DIR/editable_projects_no_deps.txt"
POETRY_PROJECTS_FILE="$CONFIG_DIR/poetry_projects.txt"
PRE_REQUIREMENTS_FILE="$CONFIG_DIR/pre_requirements.txt"
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

# Both PROJECTS_FILE and NO_DEPS_PROJECTS_FILE are optional, but at least one should exist
[[ -f "$EXCLUDE_FILE" ]] || { echo "❌ Missing $EXCLUDE_FILE"; exit 1; }
[[ -f "$EXTRA_REQUIREMENTS_FILE" ]] || { echo "❌ Missing $EXTRA_REQUIREMENTS_FILE"; exit 1; }
# PRE_REQUIREMENTS_FILE is optional, no validation required

if [[ -d "$VENV_DIR" ]]; then
  echo "Phase 1: Deleting existing venv at: $VENV_DIR"
  rm -rf "$VENV_DIR"
  echo "  deleting contents of sanitized/ folder"
  rm -rf sanitized/*
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
echo "Phase 2: Parsing editable projects files"

# Parse projects that install with dependencies (normal pip behavior)
PROJECT_PATHS=()
declare -A EXTRAS_MAP

if [[ -f "$PROJECTS_FILE" ]]; then
  echo "  Parsing $PROJECTS_FILE (install with dependencies)"
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
fi

# Parse projects that install with --no-deps (must provide explicit requirements files)
NO_DEPS_PROJECT_PATHS=()
declare -A NO_DEPS_EXTRAS_MAP

if [[ -f "$NO_DEPS_PROJECTS_FILE" ]]; then
  echo "  Parsing $NO_DEPS_PROJECTS_FILE (install with --no-deps, explicit requirements)"
  while IFS= read -r line; do
    [[ -z "$line" || "$line" =~ ^# ]] && continue
    path_part="${line%%:*}"
    extras_part="${line#*:}"
    full_path="$REPO_ROOT/$path_part"
    [[ -d "$full_path" ]] || { echo "❌ Missing project directory: $full_path"; exit 1; }
    NO_DEPS_PROJECT_PATHS+=("$full_path")
    if [[ "$extras_part" != "$path_part" ]]; then
      NO_DEPS_EXTRAS_MAP["$full_path"]="$extras_part"
    fi
  done < "$NO_DEPS_PROJECTS_FILE"
fi

echo
echo "Phase 2.4: Setting up build venv with required tools"

# Setup build venv (only for poetry exports if needed)
if [[ -f "$POETRY_PROJECTS_FILE" ]] && [[ $(grep -v '^#' "$POETRY_PROJECTS_FILE" | grep -v '^[[:space:]]*$' | wc -l) -gt 0 ]]; then
  if [[ ! -d "$BUILD_VENV_DIR" ]]; then
    echo "Creating build venv for poetry exports at: $BUILD_VENV_DIR"
    $PYTHON -m venv "$BUILD_VENV_DIR" --clear
    source "$BUILD_VENV_DIR/bin/activate"
    echo "  Installing pip in build venv..."
    python -m ensurepip --upgrade
    echo "  Installing poetry in build venv..."
    pip install --quiet poetry
    echo "  Configuring poetry plugin..."
    # Try to remove plugin first (ignore errors if not installed)
    echo "    Attempting to remove existing poetry-plugin-export..."
    poetry self remove poetry-plugin-export 2>/dev/null || echo "    (plugin not previously installed, continuing)"
    # Add the plugin (this should always work)
    echo "    Installing poetry-plugin-export..."
    poetry self add poetry-plugin-export
    echo "  Poetry setup complete"
    deactivate
  fi
else
  echo "No poetry projects configured, skipping build venv setup"
fi

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
    echo "  Exporting poetry project $poetry_project to: $sanitized_poetry_req"
    echo "    Running: poetry export --without-hashes -f requirements.txt -C $poetry_project_path"
    "$BUILD_VENV_DIR/bin/poetry" export --without-hashes -f requirements.txt -o "$(pwd)/$sanitized_poetry_req" -C "$poetry_project_path"
    echo "    Export completed successfully"
  done < "$POETRY_PROJECTS_FILE"
fi

# Phase 2.6: pip-compile generation completely eliminated
# All editable projects now use explicit requirements files from requirement_files.txt
echo
echo "Phase 2.6: pip-compile dependency resolution eliminated"
echo "  All dependencies will be installed from explicit requirements files"

echo
echo "Phase 2.75: Installing pre-requirements (direct, no exclusions)"

# Install pre-requirements directly without exclusions
if [[ -f "$PRE_REQUIREMENTS_FILE" ]]; then
  echo "Installing pre-requirements (direct): $PRE_REQUIREMENTS_FILE"
  "${PIP_INSTALL_CMD[@]}" -r "$PRE_REQUIREMENTS_FILE"
else
  echo "No pre-requirements file found ($PRE_REQUIREMENTS_FILE), skipping..."
fi

echo
echo "Phase 3: Installing requirement files (sanitized)"

# First, sanitize traditional requirements files
echo "Processing requirements files from: $EXTRA_REQUIREMENTS_FILE"
while IFS= read -r extra_file; do
  [[ -z "$extra_file" || "$extra_file" =~ ^# ]] && continue
  echo "  Processing entry: $extra_file"
  full_req_path="$REPO_ROOT/$extra_file"
  if [[ ! -f "$full_req_path" ]]; then
    echo "    Skipping missing requirements file: $full_req_path"
    continue
  fi
  sanitized_req="$SANITIZED_DIR/$(echo "$extra_file" | tr '/' '__')"
  echo "    Sanitizing requirements file: $full_req_path -> $sanitized_req"
  grep -vFf "$EXCLUDE_FILE" "$full_req_path" > "$sanitized_req"
done < "$EXTRA_REQUIREMENTS_FILE"

# Then install all sanitized requirements files (includes both traditional and poetry-exported)
# find command used to get some ordering to this
for req_file in $(find "$SANITIZED_DIR" -maxdepth 1 -type f | sort); do
# for req_file in "$SANITIZED_DIR"/*; do
  if [[ -f "$req_file" ]]; then
    if [[ "$req_file" == *"_dev.txt" ]]; then
      echo "Installing requirements (with deps): $req_file"
      "${PIP_INSTALL_CMD[@]}" -r "$req_file"
    else
      echo "Installing requirements (no deps): $req_file"
      "${PIP_INSTALL_CMD[@]}" -r "$req_file" --no-deps
    fi
  fi
done

echo
echo "Phase 4: Installing all projects in editable mode"

# Install projects with dependencies (normal pip behavior)
if [[ ${#PROJECT_PATHS[@]} -gt 0 ]]; then
  echo "  Installing projects with dependencies:"
  for path in "${PROJECT_PATHS[@]}"; do
    if [[ -n "${EXTRAS_MAP[$path]+x}" ]]; then
      extras="${EXTRAS_MAP[$path]}"
      echo "    Installing as editable with extras [$extras] (with deps): $path"
      "${PIP_INSTALL_CMD[@]}" -e "$path[$extras]" -c "$CONSTRAINTS_FILE"
    else
      echo "    Installing as editable (with deps): $path"
      "${PIP_INSTALL_CMD[@]}" -e "$path" -c "$CONSTRAINTS_FILE"
    fi
  done
fi

# Install no-deps projects (dependencies already installed from requirements files)
if [[ ${#NO_DEPS_PROJECT_PATHS[@]} -gt 0 ]]; then
  echo "  Installing no-deps projects (dependencies from explicit requirements files):"
  for path in "${NO_DEPS_PROJECT_PATHS[@]}"; do
    if [[ -n "${NO_DEPS_EXTRAS_MAP[$path]+x}" ]]; then
      extras="${NO_DEPS_EXTRAS_MAP[$path]}"
      echo "    Installing as editable with extras [$extras] (no-deps): $path"
      "${PIP_INSTALL_CMD[@]}" -e "$path[$extras]" -c "$CONSTRAINTS_FILE" --no-deps
    else
      echo "    Installing as editable (no-deps): $path"
      "${PIP_INSTALL_CMD[@]}" -e "$path" -c "$CONSTRAINTS_FILE" --no-deps
    fi
  done
fi

echo "Venv setup complete: $VENV_DIR"
echo "Run this to activate it:"
echo "source $VENV_DIR/bin/activate"
