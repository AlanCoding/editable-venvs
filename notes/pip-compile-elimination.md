# Eliminating pip-compile from Virtual Environment Setup

## Problem Statement

The original virtual environment creation script used pip-compile to resolve dependencies for editable projects, which created significant version conflicts by ignoring carefully pinned versions in project requirements files.

## The Problem with pip-compile

### Version Conflict Example: lxml Library

The problematic approach used pip-compile to resolve dependencies for editable projects, creating significant version conflicts:

```bash
# Original pinned versions in requirements files:
django-ansible-base/requirements/requirements_all.txt:    lxml==5.3.0
sanitized/tower_requirements_requirements.txt:            lxml==4.9.4

# pip-compile generated versions (using latest from PyPI):
sanitized/editable_django-ansible-base.txt:               lxml==6.0.0
sanitized/editable_aap-gateway.txt:                       lxml==6.0.0
```

### Why This Was Problematic

1. **Version Conflicts**: pip-compile resolved dependencies using **current versions from PyPI**, ignoring the carefully pinned versions in the project's actual requirements files.

2. **Unpredictable Environment**: The same project could get different dependency versions depending on when the virtual environment was created and what was latest on PyPI.

3. **Dependency Resolution Chaos**: Multiple versions of the same package were specified across different requirements files, leading to potential conflicts during installation.

4. **Loss of Reproducibility**: The carefully crafted version pins in `requirements_all.txt` and other requirements files were effectively ignored for editable projects.

### Technical Root Cause

The issue occurred when pip-compile was used to generate requirements files from project setup files. The `pip-compile` command resolved dependencies against the **current PyPI index**, completely bypassing the version constraints that were already established in the project's requirements files.

## Implemented Solution

### Dual Editable Projects Configuration

We have implemented a two-file approach that completely eliminates pip-compile:

1. **`config/editable_projects.txt`** - Projects that install with dependencies using normal pip behavior
2. **`config/editable_projects_no_deps.txt`** - Projects that install with `--no-deps` and provide explicit requirements files

### Two Installation Strategies

**Projects with Dependencies (`editable_projects.txt`)**:
- Installed using normal `pip install -e` behavior (with dependencies)
- Use standard Python packaging dependency resolution
- Good for projects with stable, well-defined dependencies
- No requirements files needed in `requirement_files.txt`

**No-Deps Projects (`editable_projects_no_deps.txt`)**:
- Installed with `pip install -e --no-deps`
- **Must** include their requirements files in `requirement_files.txt`
- Dependencies installed from explicit requirements files with pinned versions
- Provides precise version control and eliminates pip-compile conflicts

### Complete pip-compile Elimination

- **No pip-tools installation**: The build environment only installs Poetry if needed
- **No dependency generation**: All dependencies come from explicit requirements files or normal pip resolution
- **No version conflicts**: Projects control their dependencies through their chosen strategy

## Benefits Achieved

1. **Version Consistency**: Dependencies come from explicitly pinned requirements files (for no-deps projects) or standard pip resolution (for normal projects)
2. **Reproducible Builds**: Same dependency versions regardless of when the environment is created
3. **Explicit Control**: Project maintainers choose their dependency management strategy
4. **Conflict Elimination**: No more competing version specifications between pip-compile output and requirements files
5. **Flexibility**: Both normal pip behavior and explicit requirements approaches are supported

## Example: django-ansible-base Migration

**Before (with pip-compile)**:
- Listed in `editable_projects.txt`
- pip-compile generated `lxml==6.0.0` (latest from PyPI)
- Conflicted with `lxml==5.3.0` in `requirements_all.txt`

**After (no pip-compile)**:
- Moved to `editable_projects_no_deps.txt`
- `requirements_all.txt` listed in `requirement_files.txt`
- Uses explicit `lxml==5.3.0` pin from requirements file
- No version conflicts

## Implementation Status: ✅ Complete

The refactor has been successfully implemented:

1. ✅ **Script Updated**: `create_venv.sh` now supports dual editable project types
2. ✅ **pip-compile Eliminated**: No pip-compile usage anywhere in the script
3. ✅ **Dual Configuration**: Both `editable_projects.txt` and `editable_projects_no_deps.txt` supported
4. ✅ **Conditional Build Tools**: Only installs build tools (Poetry) when actually needed
5. ✅ **Documentation Updated**: README and notes reflect the new approach

The solution provides the flexibility to use either normal pip dependency resolution or explicit requirements files, while completely eliminating the pip-compile version conflicts that were causing reproducibility issues. 