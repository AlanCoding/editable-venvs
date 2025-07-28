# editable-venvs
Editable virtual environment maker for Ansible repos

Set up clean, isolated virtual environments for multi-repo Python projects.

## 📦 What It Does

- Deletes and recreates a fresh virtual environment at `~/venvs/<venv-name>`
- Activates the venv and ensures `pip` is available
- Runs a **pre-install pass** that:
  - For each project listed in `projects.txt`, looks for `<project>/requirements/requirements.in`
  - If found, filters out blacklisted packages using `exclude.txt`
  - Writes a cleaned version to `sanitized/<project>.txt` for debugging
  - Installs remaining dependencies from that sanitized file
- Runs a **first-pass install** of each project (non-editable, no dependency resolution)
- Runs a **second-pass install** of each project in editable mode with `pip install -e`
- Leaves you with a reproducible dev environment with clean, isolated dependencies

## Usage

```bash
PYTHON=python3.11 ./setup-venv.sh awx
```

