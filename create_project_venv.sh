#!/usr/bin/env bash

set -euo pipefail

if [[ $# -lt 2 || $# -gt 2 ]]; then
  echo "Usage: $0 <venv-name> <project-key>" >&2
  exit 1
fi

VENV_NAME="$1"
PROJECT_KEY="$2"

REPO_ROOT="${REPO_ROOT:-$HOME/repos}"
CONFIG_DIR="${CONFIG_DIR:-config}"
PROJECT_SETTINGS_FILE="$CONFIG_DIR/project_settings.json"

if [[ ! -f "$PROJECT_SETTINGS_FILE" ]]; then
  echo "❌ Missing project configuration file: $PROJECT_SETTINGS_FILE" >&2
  exit 1
fi

TEMP_CONFIG_DIR=$(mktemp -d)
trap 'rm -rf "$TEMP_CONFIG_DIR"' EXIT

# Ensure the temp config contains copies of baseline files expected by create_venv.sh
for base_file in constraints_for_editable.txt exclude_for_files.txt pre_requirements.txt; do
  src="$CONFIG_DIR/$base_file"
  dest="$TEMP_CONFIG_DIR/$base_file"
  if [[ -f "$src" ]]; then
    cp "$src" "$dest"
  else
    # create empty file to satisfy create_venv.sh checks when optional
    : > "$dest"
  fi
done

python <<'PY' "$PROJECT_SETTINGS_FILE" "$PROJECT_KEY" "$TEMP_CONFIG_DIR"
import json
import sys
from pathlib import Path

config_path, project_key, dest_dir = sys.argv[1:]
dest = Path(dest_dir)

data = json.load(open(config_path, "r", encoding="utf-8"))
if project_key not in data:
    available = ", ".join(sorted(data))
    raise SystemExit(f"❌ Unknown project '{project_key}'. Available projects: {available}")

info = data[project_key]

install_type = info.get("install_type", "editable")
repo = info.get("repo", project_key)
extras = info.get("extras", [])
requirements = info.get("requirements", [])
poetry = bool(info.get("poetry", False))
post_requirements = info.get("post_requirements", [])

editable_lines = []
no_deps_lines = []
if extras:
    extras_str = ",".join(extras)
else:
    extras_str = ""

line = repo if not extras_str else f"{repo}:{extras_str}"

if install_type == "editable":
    editable_lines.append(line)
elif install_type == "editable_no_deps":
    no_deps_lines.append(line)
else:
    raise SystemExit(f"❌ Unsupported install_type '{install_type}' for project '{project_key}'")

files_to_write = {
    "editable_projects.txt": editable_lines,
    "editable_projects_no_deps.txt": no_deps_lines,
    "requirement_files.txt": requirements,
    "poetry_projects.txt": [repo] if poetry else [],
    "post_requirements.txt": post_requirements,
}

for filename, entries in files_to_write.items():
    target = dest / filename
    content = "\n".join(entries)
    target.write_text(content + ("\n" if content else ""), encoding="utf-8")
PY

CONFIG_DIR="$TEMP_CONFIG_DIR" "$(dirname "$0")/create_venv.sh" "$VENV_NAME"

POST_REQ_FILE="$TEMP_CONFIG_DIR/post_requirements.txt"
if [[ -s "$POST_REQ_FILE" ]]; then
  echo
  echo "Phase 5: Installing additional project-specific requirement files"
  source "$HOME/venvs/$VENV_NAME/bin/activate"
  PIP_QUIET="${PIP_QUIET:-1}"
  PIP_INSTALL_CMD=(pip install)
  if [[ "$PIP_QUIET" == "1" ]]; then
    PIP_INSTALL_CMD+=(--quiet --disable-pip-version-check)
  fi
  while IFS= read -r requirement_path; do
    [[ -z "$requirement_path" ]] && continue
    full_path="$REPO_ROOT/$requirement_path"
    if [[ ! -f "$full_path" ]]; then
      echo "Skipping missing requirement file: $full_path"
      continue
    fi
    echo "  Installing extra requirements: $full_path"
    "${PIP_INSTALL_CMD[@]}" -r "$full_path"
  done < "$POST_REQ_FILE"
fi

echo
VENV_DIR="$HOME/venvs/$VENV_NAME"
echo "Project-specific venv setup complete: $VENV_DIR"
echo "Run this to activate it:"
echo "source $VENV_DIR/bin/activate"
