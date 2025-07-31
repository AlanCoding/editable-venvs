# editable-venvs

**Multi-Repository Python Development Environment Manager for Ansible Projects**

A tool for creating unified virtual environments that span multiple related Python repositories. Designed for multi-repo development workflows in the Ansible ecosystem where running unit tests across projects requires consistent dependency management.

## Purpose

This tool addresses the challenge of running unit tests across multiple interdependent Python projects. Instead of managing separate virtual environments for each repository, it creates a single unified environment where all projects are installed in editable mode, allowing tests to run against live code changes across the entire ecosystem.

## What It Does

Creates a clean, isolated virtual environment at `~/venvs/<venv-name>` containing:
- **Editable installations** of all specified projects (allowing live code editing)
- **Poetry-exported dependencies** from projects using Poetry
- **Sanitized dependencies** from additional requirements files
- **Proper dependency resolution** across multiple repositories
- **Reproducible environment** for consistent test execution

## How create_venv.sh Works (Step-by-Step)

### Phase 1: Environment Preparation
1. **Input Validation**: Takes a virtual environment name as argument
2. **Configuration Setup**: Sets up directory paths and validates required configuration files exist
3. **Poetry Environment Setup**: Creates a dedicated poetry venv at `~/venvs/poetry` if it doesn't exist
4. **Clean Slate Creation**: Completely removes any existing virtual environment and creates a fresh one
5. **Environment Activation**: Activates the new virtual environment and verifies pip is correctly configured

### Phase 2: Project Discovery
6. **Project Parsing**: Reads `config/editable_projects.txt` and extracts:
   - Project directory paths (relative to `$REPO_ROOT`)
   - Optional package extras (e.g., `project:extra1,extra2`)
   - Validates all project directories exist

### Phase 2.5: Poetry Export
7. **Poetry Requirements Export**: For each project listed in `config/poetry_projects.txt`:
   - Validates the project directory exists and contains `pyproject.toml`
   - Uses the dedicated poetry venv to export dependencies
   - Creates requirements files in `sanitized/` directory using `poetry export`

### Phase 3: Dependency Installation
8. **Requirements Sanitization**: For each file listed in `config/requirement_files.txt`:
   - Reads the requirements file
   - Filters out blacklisted packages using `config/exclude_for_files.txt`
   - Creates cleaned versions in `sanitized/` directory
   - Installs the sanitized requirements
9. **Poetry Dependencies Installation**: Installs all poetry-exported requirements files

### Phase 4: Editable Project Installation
10. **Editable Installation**: Installs each project from `config/editable_projects.txt` in editable mode:
    - Uses `pip install -e` for live code editing
    - Applies any specified package extras
    - Enforces version constraints from `config/constraints_for_editable.txt`
    - Processes projects in dependency order (dependencies last to override PyPI versions)

## Usage

```bash
# Create environment for AWX development
PYTHON=python3.11 ./create_venv.sh awx

# With custom repo location
REPO_ROOT=/custom/path ./create_venv.sh my-env

# With custom config directory
CONFIG_DIR=/path/to/configs ./create_venv.sh awx

# Multiple config environments
CONFIG_DIR=config/production ./create_venv.sh prod-env
CONFIG_DIR=config/development ./create_venv.sh dev-env

# Loud installation
PIP_QUIET=0 ./create_venv.sh awx
```

After completion, activate the environment:
```bash
source ~/venvs/awx/bin/activate
```

## Project Structure

```
editable-venvs/
├── create_venv.sh                    # Main script
├── config/                           # Configuration files
│   ├── editable_projects.txt         # Projects to install in editable mode
│   ├── poetry_projects.txt           # Projects using Poetry (for export)
│   ├── requirement_files.txt         # Additional requirements files to install
│   ├── exclude_for_files.txt         # Packages to exclude during installation
│   └── constraints_for_editable.txt  # Version constraints for editable installs
├── checks/                           # Verification tools
├── sanitized/                        # Generated filtered requirements files
└── README.md
```

## Configuration Files

- **`config/editable_projects.txt`**: Ordered list of project directories to install in editable mode
- **`config/poetry_projects.txt`**: Projects using Poetry whose dependencies should be exported via `poetry export`
- **`config/requirement_files.txt`**: Additional requirements files to install before projects
- **`config/exclude_for_files.txt`**: Packages to exclude during requirements installation
- **`config/constraints_for_editable.txt`**: Version constraints to apply during installation

## Environment Variables

- **`CONFIG_DIR`**: Directory containing configuration files (default: `config`)
- **`REPO_ROOT`**: Root directory containing all project repositories (default: `$HOME/repos`)
- **`PYTHON`**: Python interpreter to use (default: `python3`)
- **`PIP_QUIET`**: Enable quiet pip installation (default: `1`)

## Poetry Support

The tool automatically handles projects that use Poetry for dependency management:

1. **Dedicated Poetry Environment**: Creates `~/venvs/poetry` with Poetry installed
2. **Automatic Export**: Uses `poetry export` to generate requirements.txt files
3. **Seamless Integration**: Poetry-exported dependencies are installed alongside other requirements

Poetry projects are listed in `config/poetry_projects.txt` (one per line) and must contain a `pyproject.toml` file.

## Verification Tools

- **`checks/canary.sh`**: Runs quick smoke tests to verify environment health
- **`checks/staleness.sh`**: Checks if local repositories are behind their remote counterparts

## Key Considerations

### Dependency Order Matters
Projects in `config/editable_projects.txt` are listed in reverse dependency order. The most fundamental projects (that others depend on) come last. This ensures that when projects are installed in editable mode, the final editable installation overwrites any PyPI versions that may have been pulled in as dependencies.

### Two-Phase Installation Strategy
The script uses a multi-phase approach:
1. **Poetry Export Phase**: Export dependencies from Poetry projects
2. **Requirements Phase**: Install base dependencies from sanitized requirements files
3. **Editable Phase**: Install all projects in editable mode with proper constraints

This approach ensures clean dependency resolution while maintaining the ability to edit code and run tests across all projects simultaneously.

## Generated Artifacts

- **`sanitized/`**: Contains filtered requirements files for debugging
- **`~/venvs/<venv-name>/`**: The created virtual environment
- **`~/venvs/poetry/`**: Dedicated Poetry environment for exporting dependencies
- **`freezes/`**: Historical snapshots of installed packages
- **`snapshots/`**: Project-specific package snapshots
