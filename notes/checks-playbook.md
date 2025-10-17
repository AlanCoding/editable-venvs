# Project Check Playbook

This guide summarizes the minimum manual steps required to reproduce the canary checks run by this repository for each supported project. Unless otherwise noted, run the commands from the root of the corresponding project repository.

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
2. Clone the target repository locally if it is not already present.
3. Create a fresh Python virtual environment (for example `python3 -m venv .venv`) before installing project-specific dependencies.

## AWX

### Prepare a project virtual environment
1. Create and activate a virtual environment:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   python -m pip install --upgrade pip
   ```
2. Install the AWX dependency sets:
   ```bash
   pip install \
     -r requirements/requirements.txt \
     -r requirements/requirements_dev.txt \
     -r requirements/requirements_git.txt
   ```
3. Install AWX in editable mode so `pytest` can import the package:
   ```bash
   pip install -e .
   ```

### Run the smoke test
```bash
AWX_LOGGING_MODE=stdout pytest \
  awx/main/tests/functional/test_instances.py \
  --create-db \
  --disable-warnings \
  -W ignore::DeprecationWarning
```

## django-ansible-base

### Prepare a project virtual environment
1. Create and activate a virtual environment:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   python -m pip install --upgrade pip
   ```
2. Install the development requirements that mirror the CI environment:
   ```bash
   pip install \
     -r requirements/requirements_dev.txt \
     -r requirements/requirements_all.txt
   ```
3. Install the package with the extras expected by the smoke test while avoiding a second dependency resolution pass:
   ```bash
   pip install -e .[authentication,rest-filters,jwt_consumer,resource-registry,rbac,feature-flags,api-documentation,oauth2-provider] --no-deps
   ```

### Run the smoke test
```bash
make postgres
pytest test_app/tests/rbac/models/test_uniqueness.py
```

## eda-server

### Prepare a project virtual environment
1. Create and activate a virtual environment:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   python -m pip install --upgrade pip poetry
   ```
2. Export the Poetry-managed dependencies that power the integration test and install them into the active environment:
   ```bash
   poetry export --without-hashes --with test -f requirements.txt -o /tmp/eda-test-requirements.txt
   pip install -r /tmp/eda-test-requirements.txt
   ```
3. Install the repository itself in editable mode:
   ```bash
   pip install -e .
   ```

### Start supporting services
```bash
EDA_PG_PORT=5432 EDA_REDIS_PORT=6379 \
  docker compose -p eda -f tools/docker/docker-compose-dev.yaml up --detach postgres redis
```
Wait for both services to report healthy status (the compose file configures health checks).

### Run the smoke test
```bash
EDA_DB_HOST=localhost EDA_DB_PORT=5432 \
EDA_MQ_HOST=localhost EDA_MQ_PORT=6379 \
DJANGO_SETTINGS_MODULE=aap_eda.settings.default \
EDA_SECRET_KEY=insecure \
EDA_DB_PASSWORD=secret \
pytest tests/integration/api/test_eda_credential.py
```

## galaxy_ng

### Prepare a project virtual environment
1. Create and activate a virtual environment:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   python -m pip install --upgrade pip
   ```
2. Install the unit-test dependency lockfile and the package under test:
   ```bash
   pip install -r unittest_requirements.txt
   pip install -e .
   ```
3. (Optional) If sibling repositories such as `django-ansible-base`, `pulpcore`, `pulp_ansible`, `galaxy-importer`, `dynaconf`, `django`, or `django-rest-framework` are checked out alongside `galaxy_ng`, install them in editable mode to mirror CI's behavior:
   ```bash
   for project in ../django-ansible-base ../pulpcore ../pulp_ansible ../galaxy-importer ../dynaconf ../django ../django-rest-framework; do
     if [[ -d "$project" ]]; then
       pip install -e "$project"
     fi
   done
   ```

### Start PostgreSQL via docker compose
```bash
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

## aap-gateway (reference)

While this private repository is not exercised by automated checks here, the shared tooling reveals how to bootstrap its environment:

1. Create and activate a virtual environment:
   ```bash
   python3 -m venv .venv
   source .venv/bin/activate
   python -m pip install --upgrade pip
   ```
2. Install the pinned requirements used across the fleet:
   ```bash
   pip install -r requirements/requirements.txt
   ```
3. Install the gateway in editable mode without re-resolving dependencies:
   ```bash
   pip install -e . --no-deps
   ```
4. Execute the repository's targeted validation command (for example `pytest` or a tox environment) as documented in the project README.

## Cross-project template

Use this template to capture new project smoke tests in a consistent format.

1. **System dependencies**
   - Install platform packages and command-line tools required by the project (database clients, Docker, build headers). See [Common prerequisites](#common-prerequisites) for baseline packages.
   - Export any project-specific environment variables required before provisioning services.
2. **Virtual environment creation**
   - Create an isolated environment with `python3 -m venv .venv` (or an equivalent tool) and activate it.
   - Upgrade pip and install the repository's requirement files or Poetry exports that correspond to the desired test target.
3. **Project installation**
   - Install the repository itself in editable mode, optionally including extras, for example: `pip install -e .[extra-a,extra-b]`.
   - Add neighboring editable checkouts when the project autodetects them (for instance sibling Django or pulpcore packages).
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

Populate each placeholder with concrete values from the target repository to produce a reproducible check recipe.
