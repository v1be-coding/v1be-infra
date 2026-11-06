#!/usr/bin/env bash
# ci/check-pr-text.sh
# Reads the PR as text. Never runs terraform.
# Usage: check-pr-text.sh <folder with the PR's files> <file listing changed paths>
set -u
pr=$1; list=$2; here=$(cd "$(dirname "$0")" && pwd); block=0; out=$(mktemp)
say() { [ "$1" = error ] && block=1; m=${4//$'\r'/}; printf '::%s file=%s,line=%s::%s\n' "$1" "$2" "$3" "${m//::/: :}" >> "$out"; }
scan() { # level, regex, message, file, path
  while IFS=: read -r n t; do say "$1" "$5" "$n" "$3: ${t:0:80}"; done < <(grep -nE -- "$2" "$4")
}
hard='^[[:space:]]*data[[:space:]]+"?external"?|provisioner[[:space:]]+"?(local-exec|remote-exec)"?|provider::'
soft='^[[:space:]]*(data|resource)[[:space:]]+"?(http|local_file|local_sensitive_file|terraform_remote_state)"?'
soft+='|(^|[^[:alnum:]_])(file|fileset|filebase64|filesha256|filemd5|templatefile|abspath|pathexpand)[[:space:]]*\('
soft+='|/proc/|trivy:ignore|tflint-ignore|checkov:skip|nosemgrep|gitleaks:allow'
while IFS= read -r f; do
  p="$pr/$f"
  [ -L "$p" ] && say error "$f" 1 "Symlink. file() could read through it."
  case "$f" in
    *.tf.json|*.tfvars.json|.terraformrc|terraform.rc|.terraform/*) say error "$f" 1 "File type not allowed here." ;;
    .github/*|ci/*|.devcontainer/*|.claude/*|CLAUDE.md|CODEOWNERS|.mcp.json|.tflint.hcl|trivy.yaml|.trivyignore)
      say warning "$f" 1 "This file controls the gates. Read it closely." ;;
  esac
  [ -f "$p" ] || continue
  case "$f" in
    *.terraform.lock.hcl)
      while IFS= read -r src; do grep -qxF "$src" "$here/allowed-providers.txt" || say error "$f" 1 "Provider not on the allowed list: $src"
      done < <(sed -nE 's/^provider "([^"]+)".*/\1/p' "$p") ;;
    *.tf|*.tfvars|*.tftest.hcl)
      scan error "$hard" "Runs code" "$p" "$f"
      scan warning "$soft" "Look at this" "$p" "$f"
      while IFS=: read -r n t; do say error "$f" "$n" "Remote module: ${t:0:80}"; done < <(awk '
        /^[[:space:]]*module[[:space:]]/ {m=1}
        m && /source[[:space:]]*=/ { if ($0 !~ /"\.\.?\//) print NR ":" $0; m=0 }' "$p") ;;
  esac
done < "$list"
cat "$out"; exit $block
