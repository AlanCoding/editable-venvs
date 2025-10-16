# editable-venvs

**Multi-Repository Python Development Environment Manager for Ansible Projects**

A tool for creating unified virtual environments that span multiple related Python repositories. Designed for multi-repo development workflows in the Ansible ecosystem where running unit tests across projects requires consistent dependency management.

## Purpose

This tool addresses the challenge of running unit tests across multiple interdependent Python projects. Instead of managing separate virtual environments for each repository, it creates a single unified environment where all projects are installed in editable mode, allowing tests to run against live code changes across the entire ecosystem.

## What It Does

Creates a clean, isolated virtual environment at `~/venvs/<venv-name>` containing:
- **Two types of editable installations**:
  - Projects with dependencies (normal pip behavior)
  - Projects with explicit requirements files (installed with --no-deps)
- **Poetry-exported dependencies** from projects using Poetry
- **Sanitized dependencies** from additional requirements files
- **Proper dependency resolution** without pip-compile conflicts
- **Reproducible environment** for consistent test execution

## How create_venv.sh Works (Step-by-Step)

### Phase 1: Environment Preparation
1. **Input Validation**: Takes a virtual environment name as argument
2. **Configuration Setup**: Sets up directory paths and validates required configuration files exist
3. **Clean Slate Creation**: Completely removes any existing virtual environment and creates a fresh one
4. **Environment Activation**: Activates the new virtual environment and verifies pip is correctly configured

### Phase 2: Project Discovery
5. **Dual Project Parsing**: Reads both editable project configuration files:
   - `config/editable_projects.txt`: Projects installed with dependencies (normal pip behavior)
   - `config/editable_projects_no_deps.txt`: Projects installed with --no-deps (must provide requirements files)
   - Extracts project directory paths and optional package extras
   - Validates all project directories exist

### Phase 2.4: Tool Environment Setup
6. **Conditional Build Environment**: Creates build venv only if needed:
   - Installs `poetry` only if there are Poetry projects to export
   - **No pip-tools installation** - pip-compile has been completely eliminated
   - Skips build environment entirely if no build tools are needed

### Phase 2.5: Poetry Export
7. **Poetry Requirements Export**: For each project listed in `config/poetry_projects.txt`:
   - Validates the project directory exists and contains `pyproject.toml`
   - Uses the dedicated build venv to export dependencies
   - Creates requirements files in `sanitized/` directory using `poetry export`

### Phase 2.6: pip-compile Elimination
8. **No Dependency Generation**: pip-compile has been completely eliminated
   - No automatic dependency resolution from project setup files
   - All dependencies come from explicit requirements files or normal pip resolution
   - Eliminates version conflicts between pip-compile output and explicit requirements

### Phase 2.75: Pre-Requirements Installation
9. **Direct Requirements Installation**: Installs packages listed in `config/pre_requirements.txt`:
   - Installs requirements directly without any filtering or exclusions
   - Runs before sanitized requirements to ensure early availability
   - Bypasses the exclusion list in `config/exclude_for_files.txt`

### Phase 3: Dependency Installation
10. **Requirements Sanitization**: For each file listed in `config/requirement_files.txt`:
    - Reads the requirements file
    - Filters out blacklisted packages using `config/exclude_for_files.txt`
    - Creates cleaned versions in `sanitized/` directory
11. **Sanitized Requirements Installation**: Installs all sanitized requirements files:
    - **Development files** (`*_dev.txt`): Installed with dependencies
    - **Other files**: Installed with `--no-deps` to prevent conflicts
    - **Poetry-exported files**: Installed with `--no-deps` as dependencies are pre-resolved

### Phase 4: Editable Project Installation
12. **Dual Installation Strategy**: 
    - **Projects with dependencies**: Installed from `config/editable_projects.txt` using normal pip behavior (with dependencies)
    - **No-deps projects**: Installed from `config/editable_projects_no_deps.txt` with `--no-deps` (dependencies already installed from explicit requirements files)
    - Both types support package extras and apply version constraints from `config/constraints_for_editable.txt`

## Usage

### Unified environment

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

### Project-specific environments

Use `create_project_venv.sh` to build an isolated virtual environment for a single repository. The script reads project metadata from `config/project_settings.json` (or another `CONFIG_DIR`) and reuses the existing installer while limiting the scope to the requested project.

```bash
# Create a venv only for awx
PYTHON=python3.11 ./create_project_venv.sh awx-dev awx

# Create a venv for galaxy_ng using the new split configuration
CONFIG_DIR=config-public ./create_project_venv.sh galaxy-demo galaxy_ng
```

Project entries include optional extra requirement files that install after the base environment has been created, which is useful for test-only dependencies.

## Project Structure

```
editable-venvs/
├── create_venv.sh                    # Main script
├── create_project_venv.sh            # Project-scoped environment helper
├── config/                           # Configuration files
│   ├── editable_projects.txt         # Projects to install with dependencies
│   ├── editable_projects_no_deps.txt # Projects to install with --no-deps
│   ├── poetry_projects.txt           # Projects using Poetry (for export)
│   ├── pre_requirements.txt          # Requirements to install directly (no exclusions)
│   ├── requirement_files.txt         # Additional requirements files to install
│   ├── exclude_for_files.txt         # Packages to exclude during installation
│   ├── constraints_for_editable.txt  # Version constraints for editable installs
│   └── project_settings.json         # Metadata for per-project environments
├── checks/                           # Verification tools
├── sanitized/                        # Generated filtered requirements files
├── notes/                            # Documentation and migration notes
└── README.md
```

## Configuration Files

### Editable Projects Configuration

- **`config/editable_projects.txt`**: Projects installed with dependencies using normal pip behavior
  - Use for projects that work well with standard Python packaging dependency resolution
  - Dependencies are resolved automatically by pip during installation

- **`config/editable_projects_no_deps.txt`**: Projects installed with `--no-deps` 
  - Use for projects that need explicit version control via requirements files
  - **Must** include their requirements files in `config/requirement_files.txt`
  - Dependencies installed from explicit requirements files with pinned versions

### Other Configuration Files

- **`config/poetry_projects.txt`**: Projects using Poetry whose dependencies should be exported via `poetry export`
- **`config/requirement_files.txt`**: Additional requirements files to install before projects
- **`config/exclude_for_files.txt`**: Packages to exclude during requirements installation
- **`config/constraints_for_editable.txt`**: Version constraints to apply during installation
- **`config/project_settings.json`**: Describes how each individual project should be installed when using `create_project_venv.sh`, including extras, requirement files, and optional Poetry export flags. Public automation uses `config-public/project_settings.json`, which includes the `galaxy_ng` split environment while keeping it out of the unified environment.

## Environment Variables

- **`CONFIG_DIR`**: Directory containing configuration files (default: `config`)
- **`REPO_ROOT`**: Root directory containing all project repositories (default: `$HOME/repos`)
- **`PYTHON`**: Python interpreter to use (default: `python3`)
- **`PIP_QUIET`**: Enable quiet pip installation (default: `1`)

## Poetry Support

The tool automatically handles projects that use Poetry for dependency management:

1. **Conditional Poetry Environment**: Creates `~/venvs/build` only if Poetry projects exist
2. **Automatic Export**: Uses `poetry export` to generate requirements.txt files
3. **Seamless Integration**: Poetry-exported dependencies are installed alongside other requirements

Poetry projects are listed in `config/poetry_projects.txt` (one per line) and must contain a `pyproject.toml` file.

## Verification Tools

- **`checks/canary.sh`**: Runs quick smoke tests to verify environment health
- **`checks/staleness.sh`**: Checks if local repositories are behind their remote counterparts

## Key Considerations

### Two Installation Strategies

**Projects with Dependencies (`editable_projects.txt`)**:
- Use standard Python packaging dependency resolution
- Good for projects with stable, well-defined dependencies
- Dependencies resolved automatically during installation

**No-Deps Projects (`editable_projects_no_deps.txt`)**:
- Require explicit requirements files for dependency management
- Provide precise version control through pinned requirements
- Prevent pip-compile style conflicts with carefully maintained version pins
- Must include requirements files in `config/requirement_files.txt`

### Dependency Order Matters
Projects in configuration files should be listed considering dependency relationships. More fundamental projects (that others depend on) should be considered when determining installation order.

### Multi-Phase Installation Strategy
The script uses a sophisticated multi-phase approach:
1. **Conditional Tool Setup**: Create build environment only if Poetry projects exist
2. **Requirements Generation**: Export dependencies from Poetry projects only
3. **Dependency Resolution**: Install all dependencies from explicit requirements files
4. **Dual Editable Installation**: Install projects using appropriate strategy (with or without deps)

This approach ensures clean dependency resolution by separating dependency discovery from installation, while providing flexibility in how dependencies are managed per project.

## Generated Artifacts

- **`sanitized/`**: Contains filtered requirements files for debugging including:
  - Poetry-exported requirements files
  - Sanitized traditional requirements files  
- **`~/venvs/<venv-name>/`**: The created virtual environment
- **`~/venvs/build/`**: Conditional build environment (only if Poetry projects exist)
- **`freezes/`**: Historical snapshots of installed packages
- **`snapshots/`**: Project-specific package snapshots
