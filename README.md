# editable-venvs
Editable virtual environment maker for Ansible repos

Set up clean, isolated virtual environments for multi-repo Python projects.

## What it does

- Creates a new virtual environment in `~/venvs/<name>`
- Installs local projects from `~/repos/<project>/` in editable mode
- Installs dependencies for each project
- Keeps your global Python environment untouched

## Usage

```bash
./setup-venv.sh awx
```

