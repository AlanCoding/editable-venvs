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

## Hacks and Notes

The `projects.txt` is the most important file.
This contains all of the folder locations (relate to the repo root)
that should be installed as editable.

This is necessarily an ordered list, and going in reverse-order of dependencies.
That means that the most depended-on projects should come last.
This is because the dependent projects are _very very_ likely to be listed
as a pip dependency of other projects.
Each entry in the file is `pip -e install`ed in order.
Thus, the last entry will overwrite any installs of that same project
from PyPI or any other given tag, pulled in from an earlier `-e` install.
