# editable-venvs

**Multi-Repository Python Development Environment Manager for Ansible Projects**

A tool for creating unified virtual environments that span multiple related Python repositories. Designed for multi-repo development workflows in the Ansible ecosystem where running unit tests across projects requires consistent dependency management.

## Purpose

This tool addresses the challenge of running unit tests across multiple interdependent Python projects. Instead of managing separate virtual environments for each repository, it creates a single unified environment where all projects are installed in editable mode, allowing tests to run against live code changes across the entire ecosystem.

## What It Does

Creates a clean, isolated virtual environment at `~/venvs/<venv-name>` containing:
- **Editable installations** of all specified projects (allowing live code editing)
- **pip-compile generated requirements** from each editable project with proper extras support
- **Poetry-exported dependencies** from projects using Poetry
- **Sanitized dependencies** from additional requirements files
- **Proper dependency resolution** across multiple repositories
- **Isolated dependency installation** using --no-deps to avoid conflicts
- **Reproducible environment** for consistent test execution

## How create_venv.sh Works (Step-by-Step)

### Phase 1: Environment Preparation
1. **Input Validation**: Takes a virtual environment name as argument
2. **Configuration Setup**: Sets up directory paths and validates required configuration files exist
3. **Clean Slate Creation**: Completely removes any existing virtual environment and creates a fresh one
4. **Environment Activation**: Activates the new virtual environment and verifies pip is correctly configured

### Phase 2: Project Discovery
5. **Project Parsing**: Reads `config/editable_projects.txt` and extracts:
   - Project directory paths (relative to `$REPO_ROOT`)
   - Optional package extras (e.g., `project:extra1,extra2`)
   - Validates all project directories exist

### Phase 2.4: Tool Environment Setup
6. **Poetry Environment Setup**: Creates a dedicated poetry venv at `~/venvs/poetry` if it doesn't exist
   - Installs both `poetry` and `pip-tools` for dependency management
   - Sets up poetry plugin for exporting requirements

### Phase 2.5: Poetry Export
7. **Poetry Requirements Export**: For each project listed in `config/poetry_projects.txt`:
   - Validates the project directory exists and contains `pyproject.toml`
   - Uses the dedicated poetry venv to export dependencies
   - Creates requirements files in `sanitized/` directory using `poetry export`

### Phase 2.6: Editable Project Requirements Generation
8. **pip-compile Requirements Generation**: For each editable project:
   - Detects the appropriate setup file (`pyproject.toml`, `setup.py`, or `setup.cfg`)
   - Uses `pip-compile` with `--resolver=backtracking` to resolve all dependencies
   - Applies any configured extras using `--extra` flags
   - Filters out the editable project itself and applies sanitization rules
   - Creates sanitized requirements files in `sanitized/` directory

### Phase 2.75: Pre-Requirements Installation
9. **Direct Requirements Installation**: Installs packages listed in `config/pre_requirements.txt`:
   - Installs requirements directly without any filtering or exclusions
   - Runs before sanitized requirements to ensure early availability
   - Bypasses the exclusion list in `config/exclude_for_files.txt`
   - Useful for critical dependencies that must not be filtered
   - Uses standard pip requirements format (package names and versions)

### Phase 3: Dependency Installation
10. **Requirements Sanitization**: For each file listed in `config/requirement_files.txt`:
    - Reads the requirements file
    - Filters out blacklisted packages using `config/exclude_for_files.txt`
    - Creates cleaned versions in `sanitized/` directory
11. **Sanitized Requirements Installation**: Installs all sanitized requirements files:
    - **Development files** (`*_dev.txt`): Installed with dependencies to support dev tools
    - **Other files**: Installed with `--no-deps` to prevent dependency conflicts
    - **Poetry-exported files**: Installed with `--no-deps` as dependencies are pre-resolved
    - **pip-compile generated files**: Installed with `--no-deps` as dependencies are pre-resolved

### Phase 4: Editable Project Installation
12. **Editable Installation**: Installs each project from `config/editable_projects.txt` in editable mode:
    - Uses `pip install -e` with `--no-deps` for live code editing
    - Applies any specified package extras during installation
    - Enforces version constraints from `config/constraints_for_editable.txt`
    - Dependencies already installed in Phase 3, so no conflicts occur

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
│   ├── pre_requirements.txt          # Requirements to install directly (no exclusions)
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

### Multi-Phase Installation Strategy
The script uses a sophisticated multi-phase approach:
1. **Tool Setup Phase**: Create dedicated environment with Poetry and pip-tools
2. **Requirements Generation Phase**: 
   - Export dependencies from Poetry projects using `poetry export`
   - Generate requirements from editable projects using `pip-compile` with proper extras support
3. **Dependency Resolution Phase**: Install all dependencies using `--no-deps` to prevent conflicts
4. **Editable Installation Phase**: Install projects in editable mode without dependencies

This approach ensures clean dependency resolution by separating dependency discovery from installation, while maintaining the ability to edit code and run tests across all projects simultaneously. The use of `--no-deps` prevents pip from second-guessing the carefully resolved dependency tree.

## Generated Artifacts

- **`sanitized/`**: Contains filtered requirements files for debugging including:
  - Poetry-exported requirements files
  - pip-compile generated requirements files from editable projects
  - Sanitized traditional requirements files
- **`~/venvs/<venv-name>/`**: The created virtual environment
- **`~/venvs/poetry/`**: Dedicated environment with Poetry and pip-tools
- **`freezes/`**: Historical snapshots of installed packages
- **`snapshots/`**: Project-specific package snapshots
