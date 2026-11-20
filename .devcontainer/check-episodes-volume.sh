#!/usr/bin/env bash
# .devcontainer/check-episodes-volume.sh
# Episode sessions can read every folder in the episodes volume, so it should
# hold only episode repos: episode-template and each episode in episodes.tfvars.
# series sat there until 2026-11-17 and sessions kept reading it.
# Usage: check-episodes-volume.sh <episodes.tfvars> <episodes folder>
# Prints each other folder and exits 1, or exits 0. Changes nothing.
set -u
tfvars=$1
volume=$2
# Each episode's repo: its `repo = "..."` when set, else its name.
allowed=$(awk '
  /^episodes[[:space:]]*=[[:space:]]*\{/ { inside = 1; next }
  inside && /^\}/ { inside = 0 }
  inside && /^[[:space:]]*[a-z0-9][a-z0-9-]*[[:space:]]*=[[:space:]]*\{/ {
    name = $1
    repo = name
    if (match($0, /repo[[:space:]]*=[[:space:]]*"[^"]+"/)) {
      repo = substr($0, RSTART, RLENGTH)
      sub(/^repo[[:space:]]*=[[:space:]]*"/, "", repo)
      sub(/"$/, "", repo)
    }
    print repo
  }
' "$tfvars")
allowed=$(printf 'episode-template\n%s\n' "$allowed")
extra=0
for dir in "$volume"/*/; do
  [ -d "$dir" ] || continue
  name=$(basename "$dir")
  if ! grep -qxF "$name" <<<"$allowed"; then
    echo "Not an episode repo: $volume/$name"
    extra=1
  fi
done
if [ "$extra" = 1 ]; then
  echo "Episode sessions can read these. Move or delete them from the workspace session."
fi
exit "$extra"
