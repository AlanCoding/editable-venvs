#!/usr/bin/env bash
set -euo pipefail

REPO_ROOT="${REPO_ROOT:-$HOME/repos}"
PROJECTS_FILE="${1:-editable_projects.txt}"
FETCH_TIMEOUT="${FETCH_TIMEOUT:-1}"
REMOTE_NAME="${REMOTE_NAME:-ansible}"

if [[ ! -f "$PROJECTS_FILE" ]]; then
  echo "❌ Projects file '$PROJECTS_FILE' not found"
  exit 1
fi

echo "📡 Checking staleness of git repos relative to $REMOTE_NAME/HEAD"
echo "📁 Using REPO_ROOT: $REPO_ROOT"
echo "📄 Using PROJECTS_FILE: $PROJECTS_FILE"
echo "⏱  Fetch timeout per repo: ${FETCH_TIMEOUT}s"
echo "🌐 Using remote: $REMOTE_NAME"
echo

while IFS= read -r project; do
  [[ -z "$project" || "$project" =~ ^# ]] && continue

  path="$REPO_ROOT/$project"
  echo "────────────────────────────────────────────"
  echo "🔍 Checking project: $project"
  echo "📂 Full path: $path"

  if [[ ! -d "$path/.git" ]]; then
    echo "⚠️  Skipping — not a Git repository"
    continue
  fi

  pushd "$path" > /dev/null

  echo "🔄 FETCHING from $REMOTE_NAME with timeout: ${FETCH_TIMEOUT}s..."
  echo "▶ Running: timeout ${FETCH_TIMEOUT}s git fetch --quiet --prune $REMOTE_NAME"

  if ! timeout "${FETCH_TIMEOUT}"s git fetch --quiet --prune "$REMOTE_NAME"; then
    echo "   ❌ Timed out or failed to fetch from $REMOTE_NAME"
    popd > /dev/null
    continue
  fi

  echo "🔗 Resolving remote default branch ($REMOTE_NAME/HEAD)..."
  remote_head=$(git symbolic-ref --quiet --short "refs/remotes/${REMOTE_NAME}/HEAD" | cut -d/ -f2 || echo "main")
  echo "📌 Remote HEAD points to: $REMOTE_NAME/$remote_head"

  if ! git show-ref --verify --quiet "refs/remotes/${REMOTE_NAME}/${remote_head}"; then
    echo "   ❌ Could not resolve $REMOTE_NAME/$remote_head"
    popd > /dev/null
    continue
  fi

  local_commit=$(git rev-parse HEAD)
  remote_commit=$(git rev-parse "${REMOTE_NAME}/${remote_head}")
  echo "🔍 Local HEAD:  $local_commit"
  echo "🔍 Remote HEAD: $remote_commit"

  if [[ "$local_commit" == "$remote_commit" ]]; then
    echo "✅ Local branch is up to date with $REMOTE_NAME/$remote_head"
  else
    local_date=$(git show -s --format=%ct "$local_commit")
    remote_date=$(git show -s --format=%ct "$remote_commit")
    delta_days=$(( (remote_date - local_date) / 86400 ))

    local_fmt=$(date -d "@$local_date" "+%Y-%m-%d %H:%M:%S")
    remote_fmt=$(date -d "@$remote_date" "+%Y-%m-%d %H:%M:%S")

    echo "🕒 Local HEAD date:  $local_fmt"
    echo "🕒 Remote HEAD date: $remote_fmt"

    if (( delta_days < 0 )); then
      echo "🔁 Local branch is ahead of $REMOTE_NAME/$remote_head by $((-delta_days)) days"
    else
      echo "⏳ Local branch is behind $REMOTE_NAME/$remote_head by $delta_days days"
    fi
  fi

  popd > /dev/null
  echo
done < "$PROJECTS_FILE"
