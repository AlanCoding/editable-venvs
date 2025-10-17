# Project Check Playbook

This guide summarizes the minimum manual steps required to reproduce the canary checks run by this repository for each supported project. All commands assume repositories live under `$REPO_ROOT` (default: `$HOME/repos`) and virtual environments are created in `$HOME/venvs`.

## Common prerequisites

1. Install the system packages that the checks expect. The GitHub runners use the following sets:
   - **Fedora/RHEL:**
     ```bash
     sudo dnf install -y \
       postgresql postgresql-server postgresql-contrib redis \
       docker-compose-plugin docker \
       libxml2-devel libxmlsec1-devel libxmlsec1-openssl \
       openldap-devel cyrus-sasl-devel openssl-devel \
       python3-devel gcc gcc-c++ make pkgconfig libtool
     ```
   - **Debian/Ubuntu:**
     ```bash
     sudo apt-get update
     sudo apt-get install -y \
       postgresql postgresql-contrib redis-server docker-compose \
       libxml2-dev libxmlsec1-dev libxmlsec1-openssl \
       libldap2-dev libsasl2-dev libssl-dev \
       python3-dev build-essential pkg-config \
       libtool-bin
     ```
   Ensure the Docker daemon is running (e.g., `sudo systemctl start docker`) so compose commands can launch services.
2. Create the repositories directory and clone the projects under `$REPO_ROOT` if they are not already present.
3. When using Poetry-backed projects, keep the shared configuration files in `config/` or `config-public/` available so the helper scripts can resolve groups and post-install requirements.

## AWX

### Prepare a project virtual environment
1. Ensure the repository is cloned at `$REPO_ROOT/awx`.
2. Create a split virtual environment with the public configuration:
   ```bash
   CONFIG_DIR=config-public ./create_project_venv.sh awx-canary awx
   ```
3. Activate the environment:
   ```bash
   source ~/venvs/awx-canary/bin/activate
   ```

### Run the smoke test
```bash
cd "$REPO_ROOT/awx"
AWX_LOGGING_MODE=stdout pytest \
  awx/main/tests/functional/test_instances.py \
  --create-db \
  --disable-warnings \
  -W ignore::DeprecationWarning
```

## django-ansible-base

### Prepare a project virtual environment
1. Confirm the repository is available at `$REPO_ROOT/django-ansible-base`.
2. Create the environment with Poetry extras defined in `config/project_settings.json`:
   ```bash
   CONFIG_DIR=config-public ./create_project_venv.sh dab-canary django-ansible-base
   ```
3. Activate the environment:
   ```bash
   source ~/venvs/dab-canary/bin/activate
   ```

### Run the smoke test
```bash
cd "$REPO_ROOT/django-ansible-base"
make postgres
pytest test_app/tests/rbac/models/test_uniqueness.py
```

Stop the temporary PostgreSQL container with:
```bash
cd "$REPO_ROOT/django-ansible-base"
make postgres-down
```

## eda-server

### Prepare a project virtual environment
1. Verify the repository resides at `$REPO_ROOT/eda-server`.
2. Build the environment (the configuration exports Poetry's `test` group so pytest is available):
   ```bash
   CONFIG_DIR=config-public ./create_project_venv.sh eda-canary eda-server
   ```
3. Activate the environment:
   ```bash
   source ~/venvs/eda-canary/bin/activate
   ```

### Start supporting services
```bash
cd "$REPO_ROOT/eda-server"
EDA_PG_PORT=5432 EDA_REDIS_PORT=6379 \
  docker compose -p eda -f tools/docker/docker-compose-dev.yaml up --detach postgres redis
```
Wait for both services to report healthy status (the compose file configures health checks).

### Run the smoke test
```bash
cd "$REPO_ROOT/eda-server"
EDA_DB_HOST=localhost EDA_DB_PORT=5432 \
EDA_MQ_HOST=localhost EDA_MQ_PORT=6379 \
DJANGO_SETTINGS_MODULE=aap_eda.settings.default \
EDA_SECRET_KEY=insecure \
EDA_DB_PASSWORD=secret \
pytest tests/integration/api/test_eda_credential.py
```

### Tear down services
```bash
cd "$REPO_ROOT/eda-server"
docker compose -p eda -f tools/docker/docker-compose-dev.yaml down --remove-orphans
```

## galaxy_ng

### Prepare a project virtual environment
1. Confirm `$REPO_ROOT/galaxy_ng` exists.
2. Build the split environment (post requirements install `unittest_requirements.txt`):
   ```bash
   CONFIG_DIR=config-public ./create_project_venv.sh galaxy-canary galaxy_ng
   ```
3. Activate the environment:
   ```bash
   source ~/venvs/galaxy-canary/bin/activate
   ```

### Start PostgreSQL via docker compose
```bash
cd "$REPO_ROOT/galaxy_ng"
docker compose -p galaxy_ng -f dev/compose/aap.yaml up --force-recreate -d postgres
```
Wait for readiness:
```bash
docker compose -p galaxy_ng -f dev/compose/aap.yaml exec postgres \
  bash -c 'while ! pg_isready -U galaxy_ng; do sleep 1; done'
```

### Prepare runtime directories
```bash
rm -rf /tmp/pulp
mkdir -p /tmp/pulp/tmp /tmp/pulp/artifact-tmp /tmp/pulp/media /tmp/pulp/assets
if [[ ! -f /tmp/database_fields.symmetric.key ]]; then
  openssl rand -base64 32 > /tmp/database_fields.symmetric.key
fi
```

### Run the smoke test
```bash
cd "$REPO_ROOT/galaxy_ng"
DJANGO_SETTINGS_MODULE=pulpcore.app.settings \
PULP_DATABASES__default__ENGINE=django.db.backends.postgresql \
PULP_DATABASES__default__NAME=galaxy_ng \
PULP_DATABASES__default__USER=galaxy_ng \
PULP_DATABASES__default__PASSWORD=galaxy_ng \
PULP_DATABASES__default__HOST=localhost \
PULP_DATABASES__default__PORT=5433 \
PULP_DB_ENCRYPTION_KEY=/tmp/database_fields.symmetric.key \
PULP_DEPLOY_ROOT=/tmp/pulp \
PULP_STATIC_ROOT=/tmp/pulp \
PULP_WORKING_DIRECTORY=/tmp/pulp/tmp \
PULP_MEDIA_ROOT=/tmp/pulp/media \
PULP_FILE_UPLOAD_TEMP_DIR=/tmp/pulp/artifact-tmp \
pytest galaxy_ng/tests/unit/test_models.py::TestSetting::test_get_settings_as_dict
```

### Tear down services
```bash
docker compose -p galaxy_ng -f dev/compose/aap.yaml down --remove-orphans --volumes
```

## aap-gateway (reference)

While this private repository is not exercised by automated checks here, the shared tooling reveals how to bootstrap its environment:

1. Include the repository in the unified environment by running:
   ```bash
   CONFIG_DIR=config ./create_venv.sh gateway-dev
   ```
   This configuration installs `aap-gateway` in editable mode without automatic dependency resolution and consumes `aap-gateway/requirements/requirements.txt` to provide its pinned dependencies.
2. Activate the environment:
   ```bash
   source ~/venvs/gateway-dev/bin/activate
   ```
3. Follow the repository's internal README to run its validation suite (commonly a targeted `pytest` or tox environment). The unified environment already aligns protobuf-related pins with the rest of the stack, as documented in `config/pre_requirements.txt`.

## Cross-project template

Use this template to capture new project smoke tests in a consistent format.

1. **System dependencies**
   - Install platform packages and command-line tools required by the project (database clients, Docker, build headers). See [Common prerequisites](#common-prerequisites) for baseline packages.
   - Export any project-specific environment variables required before provisioning services.
2. **Virtual environment creation**
   - For unified installs: `CONFIG_DIR=<config> ./create_venv.sh <venv-name>`.
   - For split installs: `CONFIG_DIR=<config> ./create_project_venv.sh <venv-name> <project-key>`.
   - Activate with `source ~/venvs/<venv-name>/bin/activate`.
3. **Optional dependency extras**
   - Install post-requirement files or editable siblings with `pip install -e ../<dependency>` if the repository detects optional neighbors.
4. **Service orchestration**
   - Start required infrastructure (databases, cache, message brokers) via Docker:
     ```bash
     docker compose -p <project> -f <path/to/compose>.yaml up --detach <services>
     ```
   - Alternatively, use helper targets such as `make postgres` when provided.
   - Wait for readiness by polling health checks, e.g.:
     ```bash
     docker compose -p <project> -f <compose>.yaml exec <service> \
       bash -c 'while ! pg_isready -U <user> -h <host> -p <port>; do sleep 1; done'
     ```
5. **Filesystem bootstrap**
   - Create or reset working directories expected by the app (for example `/tmp/pulp` trees or asset caches).
   - Generate encryption keys or secrets if they are not checked into the repository.
6. **Execute the smoke test**
   - Run the minimal high-signal command (pytest module, Django check, etc.).
   - Capture artifacts such as coverage or JUnit XML when useful for CI.
7. **Cleanup**
   - Stop auxiliary services with `docker compose ... down --remove-orphans` (add `--volumes` if the data should be discarded).
   - Deactivate the virtual environment if desired.

Populate each placeholder with concrete values from the target repository to produce a reproducible check recipe.
