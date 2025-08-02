#!/usr/bin/env bash

set -euo pipefail

VENV_NAME="$1"
REPO_ROOT="${REPO_ROOT:-$HOME/repos}"
VENV_DIR="$HOME/venvs/$VENV_NAME"
BUILD_VENV_DIR="$HOME/venvs/build"
CONFIG_DIR="${CONFIG_DIR:-config}"
PROJECTS_FILE="$CONFIG_DIR/editable_projects.txt"
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

[[ -f "$PROJECTS_FILE" ]] || { echo "❌ Missing $PROJECTS_FILE"; exit 1; }
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

echo
echo "Phase 2.4: Setting up build venv with required tools"

# Setup build venv (needed for both poetry exports and pip-compile)
if [[ ! -d "$BUILD_VENV_DIR" ]]; then
  echo "Creating build venv at: $BUILD_VENV_DIR"
  $PYTHON -m venv "$BUILD_VENV_DIR" --clear
  source "$BUILD_VENV_DIR/bin/activate"
  python -m ensurepip --upgrade
  pip install --quiet poetry pip-tools
  poetry self remove poetry-plugin-export
  poetry self add poetry-plugin-export
  deactivate
elif [[ ! -f "$BUILD_VENV_DIR/bin/pip-compile" ]]; then
  echo "Installing pip-tools in existing build venv"
  "$BUILD_VENV_DIR/bin/pip" install --quiet pip-tools
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
    echo "Exporting poetry project $poetry_project to: $sanitized_poetry_req"
    "$BUILD_VENV_DIR/bin/poetry" export --without-hashes -f requirements.txt -o "$(pwd)/$sanitized_poetry_req" -C "$poetry_project_path"
  done < "$POETRY_PROJECTS_FILE"
fi

echo
echo "Phase 2.6: Generating requirements files from editable projects using pip-compile"

# For each editable project, generate a requirements file with its dependencies
for path in "${PROJECT_PATHS[@]}"; do
  project_name=$(basename "$path")
  temp_req_file="$SANITIZED_DIR/temp_${project_name}.txt"
  sanitized_editable_req="$SANITIZED_DIR/editable_${project_name}.txt"
  
  echo "Generating requirements for editable project: $path"
  
  # Find the setup file algorithmically
  setup_file=""
  if [[ -f "$path/pyproject.toml" ]]; then
    setup_file="$path/pyproject.toml"
  elif [[ -f "$path/setup.py" ]]; then
    setup_file="$path/setup.py"
  elif [[ -f "$path/setup.cfg" ]]; then
    setup_file="$path/setup.cfg"
  else
    echo "  Error: No setup file found (pyproject.toml, setup.py, or setup.cfg) in $path"
    exit 1
  fi
  
  echo "  Using setup file: $setup_file"
  
  # Build pip-compile command with extras if needed
  pip_compile_cmd=("$BUILD_VENV_DIR/bin/pip-compile" --resolver=backtracking --no-strip-extras -o "$temp_req_file" "$setup_file" --quiet)
  
  if [[ -n "${EXTRAS_MAP[$path]+x}" ]]; then
    extras="${EXTRAS_MAP[$path]}"
    echo "  Processing with extras [$extras]"
    # Split extras by comma and add --extra for each
    IFS=',' read -ra EXTRA_ARRAY <<< "$extras"
    for extra in "${EXTRA_ARRAY[@]}"; do
      # Trim whitespace
      extra=$(echo "$extra" | xargs)
      pip_compile_cmd+=(--extra "$extra")
    done
  fi
  
  # Use pip-compile to generate requirements
  echo "  Running pip-compile command: ${pip_compile_cmd[*]}"
  "${pip_compile_cmd[@]}"
  
  # Remove the editable project line and apply sanitization rules
  echo "  Applying sanitization rules..."
  grep -v "^-e " "$temp_req_file" | grep -v "^# " | grep -vFf "$EXCLUDE_FILE" > "$sanitized_editable_req" 2>/dev/null || {
    # If no dependencies remain after filtering, create empty file
    touch "$sanitized_editable_req"
  }
  
  echo "  Generated requirements file: $sanitized_editable_req"
  
  # Clean up temporary files
  rm -f "$temp_req_file"
done

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
echo "Phase 4: Installing all projects in editable mode without dependencies"
for path in "${PROJECT_PATHS[@]}"; do
  if [[ -n "${EXTRAS_MAP[$path]+x}" ]]; then
    extras="${EXTRAS_MAP[$path]}"
    echo "Installing as editable with extras [$extras] (no-deps): $path"
    "${PIP_INSTALL_CMD[@]}" -e "$path[$extras]" -c "$CONSTRAINTS_FILE" --no-deps
  else
    echo "Installing as editable (no-deps): $path"
    "${PIP_INSTALL_CMD[@]}" -e "$path" -c "$CONSTRAINTS_FILE" --no-deps
  fi
done

echo "Venv setup complete: $VENV_DIR"
echo "Run this to activate it:"
echo "source $VENV_DIR/bin/activate"
